#!/bin/bash

#
# GitHub Code Review Monitor
# Automatically fetches and organizes code review tasks from GitHub
# Author: Mat Greten
# Usage: ./github-review-monitor.sh [--dry-run] [--verbose] [--force]
#

set -euo pipefail

# Script directory (determined before loading config)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from .env file
load_config() {
    local env_file="$SCRIPT_DIR/.env"

    if [[ ! -f "$env_file" ]]; then
        echo "ERROR: Configuration file not found: $env_file" >&2
        echo "Please copy .env.example to .env and configure it." >&2
        exit 1
    fi

    # Source the .env file
    # shellcheck disable=SC1090
    source "$env_file"

    # Validate required configuration
    if [[ -z "${GITHUB_REPO:-}" ]]; then
        echo "ERROR: GITHUB_REPO is not set in .env" >&2
        exit 1
    fi
    if [[ -z "${GITHUB_USER:-}" ]]; then
        echo "ERROR: GITHUB_USER is not set in .env" >&2
        exit 1
    fi
    if [[ -z "${OBSIDIAN_VAULT:-}" ]]; then
        echo "ERROR: OBSIDIAN_VAULT is not set in .env" >&2
        exit 1
    fi
}

# Load config before setting readonly variables
load_config

# Configuration from .env
readonly REPO="${GITHUB_REPO}"
readonly OBSIDIAN_VAULT="${OBSIDIAN_VAULT}"
readonly CODE_REVIEWS_FILE="$OBSIDIAN_VAULT/Code Reviews.md"
readonly LOG_FILE="/tmp/github-review-monitor.log"
readonly GITHUB_USER="${GITHUB_USER}"
readonly NTFY_SERVER="${NTFY_SERVER:-}"
readonly NTFY_TOPIC="${NTFY_TOPIC:-code-reviews}"

# Parse team members from comma-separated string
IFS=',' read -ra INTEGRATION_TEAM_MEMBERS <<< "${TEAM_MEMBERS:-}"

# Parse Riftwalkers team members from comma-separated string
IFS=',' read -ra RIFTWALKERS_TEAM_MEMBERS <<< "${RIFTWALKERS_TEAM_MEMBERS:-}"

# Team slugs for review detection
readonly INTEGRATION_TEAM_SLUG="${INTEGRATION_TEAM_SLUG:-}"
readonly RIFTWALKERS_TEAM_SLUG="${RIFTWALKERS_TEAM_SLUG:-}"
readonly BACKEND_TEAM_SLUG="${BACKEND_TEAM_SLUG:-}"

# Advanced settings with defaults
readonly PR_SIZE_THRESHOLD="${PR_SIZE_THRESHOLD:-10}"
readonly MAX_GENERAL_REVIEWS="${MAX_GENERAL_REVIEWS:-10}"
readonly BUSINESS_HOURS_START="${BUSINESS_HOURS_START:-8}"
readonly BUSINESS_HOURS_END="${BUSINESS_HOURS_END:-16}"

# Options
DRY_RUN=false
VERBOSE=false
FORCE_UPDATE=false
INTEGRATION_ONLY=false
SEND_NOTIFICATIONS=false
TODAY=$(date +%Y-%m-%d)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Show what would be done without making changes"
    echo "  --verbose              Enable detailed logging"
    echo "  --force                Update all task dates even if no new PRs"
    echo "  --integration-only     Only check for integration team reviews"
    echo "  --notifications        Send NTFY notifications for new integration PRs"
    echo "  --help                 Show this help message"
    echo ""
    echo "This script queries GitHub for code review tasks and updates"
    echo "your Obsidian Code Reviews.md file with new tasks."
    echo ""
    echo "Integration-only mode is designed for frequent checks (every 30 minutes)"
    echo "and will send notifications for new integration PRs requiring review."
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" != "DEBUG" ]]; then
        case "$level" in
            "ERROR") echo -e "${RED}[$level]${NC} $message" >&2 ;;
            "WARN")  echo -e "${YELLOW}[$level]${NC} $message" >&2 ;;
            "INFO")  echo -e "${GREEN}[$level]${NC} $message" >&2 ;;
            "DEBUG") echo -e "${BLUE}[$level]${NC} $message" >&2 ;;
            *)       echo "[$level] $message" >&2 ;;
        esac
    fi
}

# Send NTFY notification
send_ntfy_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    local tags="${4:-review,github}"

    # Skip if NTFY is not configured
    if [[ -z "$NTFY_SERVER" ]]; then
        log "DEBUG" "NTFY not configured, skipping notification: $title"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would send notification: $title - $message"
        return 0
    fi

    log "DEBUG" "Sending NTFY notification: $title"

    curl -s \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$message" \
        "https://$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        log "INFO" "NTFY notification sent: $title"
    else
        log "WARN" "Failed to send NTFY notification: $title"
    fi
}

# Get PR line counts in formatted string
get_pr_line_counts() {
    local pr_number="$1"

    # Get PR diff statistics
    local pr_stats
    pr_stats=$(gh pr view "$pr_number" --repo "$REPO" --json additions,deletions 2>/dev/null || echo '{"additions":0,"deletions":0}')

    local additions deletions
    additions=$(echo "$pr_stats" | jq -r '.additions // 0' 2>/dev/null || echo "0")
    deletions=$(echo "$pr_stats" | jq -r '.deletions // 0' 2>/dev/null || echo "0")

    echo "(+$additions |-$deletions)"
}

# Check if PR has enough lines to warrant automated review
pr_meets_size_threshold() {
    local pr_number="$1"

    # Get PR diff statistics
    local pr_stats
    pr_stats=$(gh pr view "$pr_number" --repo "$REPO" --json additions,deletions 2>/dev/null || echo '{"additions":0,"deletions":0}')

    local additions deletions total_lines
    additions=$(echo "$pr_stats" | jq -r '.additions // 0' 2>/dev/null || echo "0")
    deletions=$(echo "$pr_stats" | jq -r '.deletions // 0' 2>/dev/null || echo "0")
    total_lines=$((additions + deletions))

    log "DEBUG" "PR #$pr_number: $additions additions, $deletions deletions, $total_lines total lines"

    # Return 0 (true) if PR meets threshold, 1 (false) if it doesn't
    if [[ $total_lines -ge $PR_SIZE_THRESHOLD ]]; then
        return 0
    else
        log "DEBUG" "PR #$pr_number below size threshold ($total_lines lines < $PR_SIZE_THRESHOLD)"
        return 1
    fi
}

# Check if PR needs review (not already reviewed by user)
pr_needs_review() {
    local pr_number="$1"

    # Check if user is explicitly requested as a reviewer (by name, not just team)
    local user_requested
    user_requested=$(gh pr view "$pr_number" --repo "$REPO" --json reviewRequests 2>/dev/null | \
        jq --arg user "$GITHUB_USER" '[.reviewRequests[] | select(.__typename == "User" and .login == $user)] | length' 2>/dev/null || echo "0")

    if [[ "$user_requested" -gt 0 ]]; then
        log "DEBUG" "User explicitly requested as reviewer for PR #$pr_number - needs review"
        return 0  # Needs review - explicit request overrides everything
    fi

    # Check if user has already submitted a review for this PR
    local user_reviews
    user_reviews=$(gh pr view "$pr_number" --repo "$REPO" --json reviews 2>/dev/null | \
        jq --arg user "$GITHUB_USER" '[.reviews[] | select(.author.login == $user)] | length' 2>/dev/null || echo "0")

    # If user has already reviewed, check if there are new commits since last review
    if [[ "$user_reviews" -gt 0 ]]; then
        log "DEBUG" "User has already reviewed PR #$pr_number ($user_reviews reviews)"

        # Get timestamp of user's last review
        local last_review_date
        last_review_date=$(gh pr view "$pr_number" --repo "$REPO" --json reviews 2>/dev/null | \
            jq -r --arg user "$GITHUB_USER" '[.reviews[] | select(.author.login == $user) | .submittedAt] | sort | last' 2>/dev/null || echo "")

        if [[ -n "$last_review_date" ]]; then
            # Check if PR was updated after last review
            local pr_updated
            pr_updated=$(gh pr view "$pr_number" --repo "$REPO" --json updatedAt 2>/dev/null | \
                jq -r '.updatedAt' 2>/dev/null || echo "")

            if [[ -n "$pr_updated" && "$pr_updated" > "$last_review_date" ]]; then
                log "DEBUG" "PR #$pr_number updated after last review - needs re-review"
                return 0  # Needs review
            else
                log "DEBUG" "PR #$pr_number not updated since last review - skipping"
                return 1  # Doesn't need review
            fi
        fi
    fi

    # Check if there are unresolved review comments addressing the user
    local addressing_comments
    addressing_comments=$(gh pr view "$pr_number" --repo "$REPO" --json comments 2>/dev/null | \
        jq --arg user "@$GITHUB_USER" '[.comments[] | select(.body | contains($user))] | length' 2>/dev/null || echo "0")

    if [[ "$addressing_comments" -gt 0 ]]; then
        log "DEBUG" "PR #$pr_number has comments addressing user - needs review"
        return 0  # Needs review
    fi

    # If no previous review, definitely needs review
    if [[ "$user_reviews" -eq 0 ]]; then
        log "DEBUG" "PR #$pr_number not yet reviewed by user - needs review"
        return 0  # Needs review
    fi

    return 1  # Doesn't need review
}

# Get integration reviews that need notification
get_integration_reviews_for_notification() {
    log "DEBUG" "Fetching integration reviews for notification..." >&2
    
    local integration_prs
    integration_prs=$(get_integration_reviews)
    
    if [[ "$integration_prs" == "[]" || -z "$integration_prs" ]]; then
        echo "[]"
        return
    fi
    
    # Filter PRs that actually need review/notification
    local notification_prs="[]"
    while IFS= read -r pr; do
        local number title author url
        number=$(echo "$pr" | jq -r '.number')
        title=$(echo "$pr" | jq -r '.title')
        author=$(echo "$pr" | jq -r '.author')
        url=$(echo "$pr" | jq -r '.url')
        
        if pr_needs_review "$number"; then
            log "DEBUG" "Integration PR #$number needs notification: $title" >&2
            notification_prs=$(echo "$notification_prs" | jq --argjson new_pr "$pr" '. + [$new_pr]')
        else
            log "DEBUG" "Integration PR #$number already handled: $title" >&2
        fi
    done <<< "$(echo "$integration_prs" | jq -c '.[]' 2>/dev/null || true)"
    
    echo "$notification_prs"
}

# Check prerequisites
check_prerequisites() {
    log "DEBUG" "Checking prerequisites..."
    
    # Check if gh CLI is installed and authenticated
    if ! command -v gh &> /dev/null; then
        log "ERROR" "GitHub CLI (gh) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log "ERROR" "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    # Check if Obsidian vault exists
    if [[ ! -d "$OBSIDIAN_VAULT" ]]; then
        log "ERROR" "Obsidian vault not found at: $OBSIDIAN_VAULT"
        exit 1
    fi

    # Create Code Reviews file if it doesn't exist
    if [[ ! -f "$CODE_REVIEWS_FILE" ]]; then
        log "WARN" "Code Reviews.md not found, creating it..."
        create_initial_code_reviews_file
    fi
    
    log "DEBUG" "Prerequisites check passed"
}

# Create initial Code Reviews.md file
create_initial_code_reviews_file() {
    cat > "$CODE_REVIEWS_FILE" << 'EOF'
# Code Reviews

## Active Reviews

<!-- Tasks are automatically added here by github-review-monitor.sh -->
<!-- Format: - [ ] #task #code-review #[category] #[priority] [PR Title](URL) 📅 YYYY-MM-DD -->

## Completed Reviews

<!-- Completed tasks can be moved here manually or they'll disappear from daily queries when marked done -->
EOF
    log "INFO" "Created initial Code Reviews.md file"
}

# Get existing PR URLs from Code Reviews.md to avoid duplicates
get_existing_pr_urls() {
    if [[ -f "$CODE_REVIEWS_FILE" ]]; then
        grep -oE 'https://github\.com/[^)]+' "$CODE_REVIEWS_FILE" 2>/dev/null || true
    fi
}

# Extract PR number from GitHub URL
extract_pr_number() {
    local url="$1"
    echo "$url" | grep -oE '[0-9]+$'
}

# Format PR title for task (truncate if too long)
format_pr_title() {
    local title="$1"
    local max_length=80
    
    if [[ ${#title} -gt $max_length ]]; then
        echo "${title:0:$max_length}..."
    else
        echo "$title"
    fi
}

# Get integration team reviews
get_integration_reviews() {
    log "DEBUG" "Fetching integration team reviews..." >&2
    
    # Get all open PRs that are not authored by the current user
    local all_prs
    all_prs=$(gh pr list \
        --repo "$REPO" \
        --state open \
        --limit 1000 \
        --json number,title,author,url,updatedAt,reviewRequests,isDraft 2>/dev/null)
    
    if [[ -n "$all_prs" ]]; then
        all_prs=$(echo "$all_prs" | jq --arg user "$GITHUB_USER" 'map(select(.author.login == $user | not) | select(.isDraft == false))' 2>/dev/null || echo "[]")
    else
        all_prs="[]"
    fi
    
    if [[ "$all_prs" == "[]" || -z "$all_prs" ]]; then
        log "DEBUG" "No PRs found after filtering user's own PRs" >&2
        echo "[]"
        return
    fi
    
    log "DEBUG" "Found $(echo "$all_prs" | jq 'length' 2>/dev/null || echo "unknown") PRs for integration filtering" >&2
    
    # Create integration team members JSON array for jq
    local team_members_json
    team_members_json="["
    for member in "${INTEGRATION_TEAM_MEMBERS[@]}"; do
        team_members_json+="\"$member\","
    done
    team_members_json="${team_members_json%,}]"
    log "DEBUG" "Team members JSON: $team_members_json" >&2
    
    # Filter PRs that match integration criteria  
    log "DEBUG" "Applying integration filters to PRs..." >&2
    
    # Use a simpler approach with multiple jq calls
    local integration_prs="[]"
    
    # Check each PR individually to avoid complex jq parsing issues
    while IFS= read -r pr; do
        local number title author url updated
        number=$(echo "$pr" | jq -r '.number' 2>/dev/null || continue)
        title=$(echo "$pr" | jq -r '.title' 2>/dev/null || continue)
        author=$(echo "$pr" | jq -r '.author.name // .author.login' 2>/dev/null || continue)
        url=$(echo "$pr" | jq -r '.url' 2>/dev/null || continue)
        updated=$(echo "$pr" | jq -r '.updatedAt' 2>/dev/null || continue)
        
        # Check integration criteria
        local is_integration=false
        
        # Check for team review request (if integration team slug is configured)
        if [[ -n "$INTEGRATION_TEAM_SLUG" ]]; then
            if echo "$pr" | jq -e --arg slug "$INTEGRATION_TEAM_SLUG" '.reviewRequests[]? | select(.__typename == "Team" and .slug == $slug)' >/dev/null 2>&1; then
                is_integration=true
            fi
        fi
        
        # Check for INT- in title
        if [[ "$title" =~ INT- ]]; then
            is_integration=true
        fi
        
        # Check for "Integration" in title
        if [[ "$title" =~ [Ii]ntegration ]]; then
            is_integration=true
        fi
        
        # Check if author is integration team member
        local author_login
        author_login=$(echo "$pr" | jq -r '.author.login' 2>/dev/null || echo "")
        for member in "${INTEGRATION_TEAM_MEMBERS[@]}"; do
            if [[ "$author_login" == "$member" ]]; then
                is_integration=true
                break
            fi
        done
        
        # Add to results if it matches integration criteria
        if [[ "$is_integration" == "true" ]]; then
            local pr_object
            pr_object=$(jq -n --arg number "$number" --arg title "$title" --arg author "$author" --arg url "$url" --arg updated "$updated" '{number: ($number | tonumber), title: $title, author: $author, url: $url, updated: $updated}')
            integration_prs=$(echo "$integration_prs" | jq --argjson new_pr "$pr_object" '. + [$new_pr]')
        fi
    done <<< "$(echo "$all_prs" | jq -c '.[]' 2>/dev/null)"

    echo "$integration_prs"
}

# Get Riftwalkers team reviews
get_riftwalkers_reviews() {
    log "DEBUG" "Fetching Riftwalkers team reviews..." >&2

    # Skip if no Riftwalkers team members configured
    if [[ ${#RIFTWALKERS_TEAM_MEMBERS[@]} -eq 0 ]]; then
        log "DEBUG" "No Riftwalkers team members configured, skipping" >&2
        echo "[]"
        return
    fi

    # Get all open PRs that are not authored by the current user
    local all_prs
    all_prs=$(gh pr list \
        --repo "$REPO" \
        --state open \
        --limit 1000 \
        --json number,title,author,url,updatedAt,reviewRequests,isDraft 2>/dev/null)

    if [[ -n "$all_prs" ]]; then
        all_prs=$(echo "$all_prs" | jq --arg user "$GITHUB_USER" 'map(select(.author.login == $user | not) | select(.isDraft == false))' 2>/dev/null || echo "[]")
    else
        all_prs="[]"
    fi

    if [[ "$all_prs" == "[]" || -z "$all_prs" ]]; then
        log "DEBUG" "No PRs found after filtering user's own PRs" >&2
        echo "[]"
        return
    fi

    log "DEBUG" "Found $(echo "$all_prs" | jq 'length' 2>/dev/null || echo "unknown") PRs for Riftwalkers filtering" >&2

    # Filter PRs that match Riftwalkers criteria
    local riftwalkers_prs="[]"

    while IFS= read -r pr; do
        local number title author url updated
        number=$(echo "$pr" | jq -r '.number' 2>/dev/null || continue)
        title=$(echo "$pr" | jq -r '.title' 2>/dev/null || continue)
        author=$(echo "$pr" | jq -r '.author.name // .author.login' 2>/dev/null || continue)
        url=$(echo "$pr" | jq -r '.url' 2>/dev/null || continue)
        updated=$(echo "$pr" | jq -r '.updatedAt' 2>/dev/null || continue)

        local is_riftwalkers=false

        # Check for Riftwalkers team review request (if team slug is configured)
        if [[ -n "$RIFTWALKERS_TEAM_SLUG" ]]; then
            if echo "$pr" | jq -e --arg slug "$RIFTWALKERS_TEAM_SLUG" '.reviewRequests[]? | select(.__typename == "Team" and .slug == $slug)' >/dev/null 2>&1; then
                is_riftwalkers=true
            fi
        fi

        # Check if author is Riftwalkers team member
        local author_login
        author_login=$(echo "$pr" | jq -r '.author.login' 2>/dev/null || echo "")
        for member in "${RIFTWALKERS_TEAM_MEMBERS[@]}"; do
            if [[ "$author_login" == "$member" ]]; then
                is_riftwalkers=true
                break
            fi
        done

        # Add to results if it matches Riftwalkers criteria
        if [[ "$is_riftwalkers" == "true" ]]; then
            local pr_object
            pr_object=$(jq -n --arg number "$number" --arg title "$title" --arg author "$author" --arg url "$url" --arg updated "$updated" '{number: ($number | tonumber), title: $title, author: $author, url: $url, updated: $updated}')
            riftwalkers_prs=$(echo "$riftwalkers_prs" | jq --argjson new_pr "$pr_object" '. + [$new_pr]')
        fi
    done <<< "$(echo "$all_prs" | jq -c '.[]' 2>/dev/null)"

    echo "$riftwalkers_prs"
}

# Get Riftwalkers reviews that need notification
get_riftwalkers_reviews_for_notification() {
    log "DEBUG" "Fetching Riftwalkers reviews for notification..." >&2

    local riftwalkers_prs
    riftwalkers_prs=$(get_riftwalkers_reviews)

    if [[ "$riftwalkers_prs" == "[]" || -z "$riftwalkers_prs" ]]; then
        echo "[]"
        return
    fi

    # Filter PRs that actually need review/notification
    local notification_prs="[]"
    while IFS= read -r pr; do
        local number title author url
        number=$(echo "$pr" | jq -r '.number')
        title=$(echo "$pr" | jq -r '.title')
        author=$(echo "$pr" | jq -r '.author')
        url=$(echo "$pr" | jq -r '.url')

        if pr_needs_review "$number"; then
            log "DEBUG" "Riftwalkers PR #$number needs notification: $title" >&2
            notification_prs=$(echo "$notification_prs" | jq --argjson new_pr "$pr" '. + [$new_pr]')
        else
            log "DEBUG" "Riftwalkers PR #$number already handled: $title" >&2
        fi
    done <<< "$(echo "$riftwalkers_prs" | jq -c '.[]' 2>/dev/null || true)"

    echo "$notification_prs"
}

# Get follow-up reviews (PRs where you've been mentioned or someone replied to your comments)
get_followup_reviews() {
    log "DEBUG" "Fetching follow-up reviews..." >&2
    
    # Search for PRs where you've been mentioned or are involved in conversations
    gh pr list \
        --repo "$REPO" \
        --state open \
        --search "mentions:$GITHUB_USER -author:$GITHUB_USER" \
        --json number,title,author,url,updatedAt,isDraft 2>/dev/null | \
        jq 'map(select(.isDraft == false) | {number, title, author: (.author.name // .author.login), url, updated: .updatedAt})' 2>/dev/null || echo "[]"
}

# Get general backend reviews
get_general_reviews() {
    log "DEBUG" "Fetching general backend reviews..." >&2
    
    local raw_response
    raw_response=$(gh pr list \
        --repo "$REPO" \
        --state open \
        --json number,title,author,url,updatedAt,reviewRequests,isDraft 2>/dev/null)
    
    # Debug: Save raw response if DEBUG_DUMP_JSON is set
    if [[ "${DEBUG_DUMP_JSON:-}" == "1" ]]; then
        echo "$raw_response" | tee "/tmp/review-monitor.fetch.general.$(date +%s).json" >&2
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log "DEBUG" "Raw general reviews count: $(echo "$raw_response" | jq 'length' 2>/dev/null || echo 'parse_error')" >&2
    fi
    
    # Build jq filter based on whether backend team slug is configured
    local jq_filter
    if [[ -n "$BACKEND_TEAM_SLUG" ]]; then
        jq_filter='map(select(.isDraft == false) | select(
            (.reviewRequests[] | select(.__typename == "Team" and .slug == $team)) or
            (.reviewRequests[] | select(.__typename == "User" and .login == $user))
        ) | select(.author.login == $user | not) | {number, title, author: (.author.name // .author.login), url, updated: .updatedAt})'
        echo "$raw_response" | jq --arg user "$GITHUB_USER" --arg team "$BACKEND_TEAM_SLUG" "$jq_filter" 2>/dev/null || echo "[]"
    else
        # If no backend team configured, only look for direct user review requests
        jq_filter='map(select(.isDraft == false) | select(
            (.reviewRequests[] | select(.__typename == "User" and .login == $user))
        ) | select(.author.login == $user | not) | {number, title, author: (.author.name // .author.login), url, updated: .updatedAt})'
        echo "$raw_response" | jq --arg user "$GITHUB_USER" "$jq_filter" 2>/dev/null || echo "[]"
    fi
}

# Get your PRs that have new activity (comments, reviews, etc)
get_my_prs_with_new_activity() {
    log "DEBUG" "Fetching my PRs with new activity..." >&2

    # Get your open PRs with detailed activity info
    local my_prs
    my_prs=$(gh pr list \
        --repo "$REPO" \
        --state open \
        --author "$GITHUB_USER" \
        --json number,title,url,updatedAt,comments,reviews,isDraft 2>/dev/null)

    if [[ -z "$my_prs" || "$my_prs" == "[]" ]]; then
        echo "[]"
        return
    fi

    # Filter for PRs with activity (comments or reviews)
    local prs_with_activity="[]"

    while IFS= read -r pr; do
        local number title url updated comment_count review_count
        number=$(echo "$pr" | jq -r '.number' 2>/dev/null || continue)
        title=$(echo "$pr" | jq -r '.title' 2>/dev/null || continue)
        url=$(echo "$pr" | jq -r '.url' 2>/dev/null || continue)
        updated=$(echo "$pr" | jq -r '.updatedAt' 2>/dev/null || continue)
        comment_count=$(echo "$pr" | jq -r '.comments | length' 2>/dev/null || echo "0")
        review_count=$(echo "$pr" | jq -r '.reviews | length' 2>/dev/null || echo "0")

        # Skip draft PRs
        local is_draft
        is_draft=$(echo "$pr" | jq -r '.isDraft' 2>/dev/null || echo "false")
        if [[ "$is_draft" == "true" ]]; then
            continue
        fi

        # Check if there's any activity (comments or reviews)
        if [[ "$comment_count" -gt 0 || "$review_count" -gt 0 ]]; then
            # Get the latest activity timestamp
            local latest_comment_time latest_review_time latest_activity_time
            latest_comment_time=$(echo "$pr" | jq -r '[.comments[].createdAt] | sort | last // empty' 2>/dev/null || echo "")
            latest_review_time=$(echo "$pr" | jq -r '[.reviews[].submittedAt] | sort | last // empty' 2>/dev/null || echo "")

            # Determine the most recent activity
            if [[ -n "$latest_comment_time" && -n "$latest_review_time" ]]; then
                if [[ "$latest_comment_time" > "$latest_review_time" ]]; then
                    latest_activity_time="$latest_comment_time"
                else
                    latest_activity_time="$latest_review_time"
                fi
            elif [[ -n "$latest_comment_time" ]]; then
                latest_activity_time="$latest_comment_time"
            else
                latest_activity_time="$latest_review_time"
            fi

            local pr_object
            pr_object=$(jq -n \
                --arg number "$number" \
                --arg title "$title" \
                --arg url "$url" \
                --arg updated "$updated" \
                --arg latest_activity "$latest_activity_time" \
                --argjson comment_count "$comment_count" \
                --argjson review_count "$review_count" \
                '{number: ($number | tonumber), title: $title, url: $url, updated: $updated, latest_activity: $latest_activity, comment_count: $comment_count, review_count: $review_count}')

            prs_with_activity=$(echo "$prs_with_activity" | jq --argjson new_pr "$pr_object" '. + [$new_pr]')

            log "DEBUG" "Found activity on my PR #$number: $comment_count comments, $review_count reviews" >&2
        fi
    done <<< "$(echo "$my_prs" | jq -c '.[]' 2>/dev/null)"

    echo "$prs_with_activity"
}

# Create a task line for a PR with automated review link
create_task_line_with_review() {
    local pr_data="$1"
    local category="$2"
    local priority="$3"

    local number title author url
    number=$(echo "$pr_data" | jq -r '.number')
    title=$(echo "$pr_data" | jq -r '.title')
    author=$(echo "$pr_data" | jq -r '.author')
    url=$(echo "$pr_data" | jq -r '.url')

    local formatted_title
    formatted_title=$(format_pr_title "$title")

    # Get line counts
    local line_counts
    line_counts=$(get_pr_line_counts "$number")

    # Link to automated review using Obsidian wiki link format
    local review_link="[[PR-${number}-review|🤖 Automated Review]]"
    echo "- [ ] #task #code-review #$category #$priority [$author's $formatted_title]($url) $line_counts $review_link 📅 $TODAY"
}

# Create a regular task line for a PR without automated review link
create_task_line_without_review() {
    local pr_data="$1"
    local category="$2"
    local priority="$3"

    local number title author url
    number=$(echo "$pr_data" | jq -r '.number')
    title=$(echo "$pr_data" | jq -r '.title')
    author=$(echo "$pr_data" | jq -r '.author')
    url=$(echo "$pr_data" | jq -r '.url')

    local formatted_title
    formatted_title=$(format_pr_title "$title")

    # Get line counts
    local line_counts
    line_counts=$(get_pr_line_counts "$number")

    echo "- [ ] #task #code-review #$category #$priority [$author's $formatted_title]($url) $line_counts 📅 $TODAY"
}

# Legacy function - maintained for backward compatibility
# Create a task line for a PR (checks if automated review exists)
create_task_line() {
    local pr_data="$1"
    local category="$2"
    local priority="$3"

    local number title author url
    number=$(echo "$pr_data" | jq -r '.number')
    title=$(echo "$pr_data" | jq -r '.title')
    author=$(echo "$pr_data" | jq -r '.author')
    url=$(echo "$pr_data" | jq -r '.url')

    local formatted_title
    formatted_title=$(format_pr_title "$title")

    # Get line counts
    local line_counts
    line_counts=$(get_pr_line_counts "$number")

    # Check if automated review exists
    local review_file="/Users/mat/git/Obsidian/CompanyCam Vault/Code Reviews/automated-reviews/PR-${number}-review.md"
    if [[ -f "$review_file" ]]; then
        # Link to automated review using Obsidian wiki link format
        local review_link="[[PR-${number}-review|🤖 Automated Review]]"
        echo "- [ ] #task #code-review #$category #$priority [$author's $formatted_title]($url) $line_counts $review_link 📅 $TODAY"
    else
        echo "- [ ] #task #code-review #$category #$priority [$author's $formatted_title]($url) $line_counts 📅 $TODAY"
    fi
}

# Trigger automated review for a PR
# Returns: 0 = review generated, 2 = tool unavailable, other = error
trigger_automated_review() {
    local pr_number="$1"
    local pr_title="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would trigger automated review for PR #$pr_number"
        return 0
    fi
    
    local python_script="$SCRIPT_DIR/claude-pr-reviewer.py"
    if [[ ! -f "$python_script" ]]; then
        log "WARN" "Claude PR reviewer script not found: $python_script"
        return 1
    fi
    
    log "INFO" "Triggering automated review for PR #$pr_number: $pr_title"
    
    # Run the Python script and capture exit code
    "$python_script" "$pr_number" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    
    case $exit_code in
        0)
            log "INFO" "Automated review completed successfully for PR #$pr_number"
            return 0
            ;;
        2)
            log "WARN" "Automated review tool unavailable for PR #$pr_number (will create regular task)"
            return 2
            ;;
        3)
            log "INFO" "Automated review skipped for PR #$pr_number (below size threshold)"
            return 3
            ;;
        *)
            log "ERROR" "Automated review failed for PR #$pr_number with exit code $exit_code (check logs)"
            return $exit_code
            ;;
    esac
}

# Add new tasks to Code Reviews.md
add_tasks_to_file() {
    local new_tasks="$1"
    
    if [[ -z "$new_tasks" ]]; then
        log "DEBUG" "No new tasks to add"
        return 0
    fi

    # Preflight diagnostics: log symlink target and current ls -l
    local link_target
    link_target=$(readlink "$CODE_REVIEWS_FILE" 2>/dev/null || echo "")
    if [[ -n "$link_target" ]]; then
        log "DEBUG" "Preparing to update Code Reviews file: $CODE_REVIEWS_FILE (symlink target: $link_target)"
    else
        log "DEBUG" "Preparing to update Code Reviews file: $CODE_REVIEWS_FILE (no symlink)"
    fi
    ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true

    # Small initial delay to reduce contention with Obsidian or other editors
    log "DEBUG" "Initial 1s delay before updating Code Reviews file to avoid contention"
    sleep 1

    # Ensure the file is readable (handles transient locks) with retries
    # Allow up to ~1 minute of retries: 1s,2s,4s,8s,8s,8s,8s,8s,8s,8s
    local max_attempts=10
    local attempt=1
    local delay=1
    while (( attempt <= max_attempts )); do
        if [[ -r "$CODE_REVIEWS_FILE" ]] && cat "$CODE_REVIEWS_FILE" >/dev/null 2>&1; then
            break
        fi
        # Log detailed error information
        log "WARN" "Code Reviews file not readable (attempt $attempt/$max_attempts); retrying in ${delay}s"
        ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true
        echo "[DEBUG] Test -r result: $([[ -r "$CODE_REVIEWS_FILE" ]] && echo 'PASS' || echo 'FAIL')" >> "$LOG_FILE"
        cat "$CODE_REVIEWS_FILE" >/dev/null 2>>"$LOG_FILE" || echo "[DEBUG] Cat failed with exit code: $?" >> "$LOG_FILE"
        sleep "$delay"
        delay=$(( delay < 8 ? delay*2 : 8 ))
        ((attempt++))
    done
    if (( attempt > max_attempts )); then
        log "ERROR" "Code Reviews file not readable after $max_attempts attempts; aborting add"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would add the following tasks:"
        echo "$new_tasks"
        return 0
    fi

    # Create a temporary file with the new content
    local temp_file
    temp_file=$(mktemp)
    
    # Write new tasks to a separate temp file first
    local new_tasks_file
    new_tasks_file=$(mktemp)
    echo "$new_tasks" > "$new_tasks_file"

    # Read the existing file and insert new tasks after "## Active Reviews" with retries (handles transient access errors)
    attempt=1
    delay=1
    local awk_ok=false
    while (( attempt <= max_attempts )); do
        awk '
            /^## Active Reviews/ {
                print $0
                print ""
                while ((getline line < "'"$new_tasks_file"'") > 0) {
                    print line
                }
                close("'"$new_tasks_file"'")
                print ""
                next
            }
            { print }
        ' "$CODE_REVIEWS_FILE" > "$temp_file" && awk_ok=true || awk_ok=false

        if $awk_ok; then
            break
        fi
        log "WARN" "Failed to open/update Code Reviews file with awk (attempt $attempt/$max_attempts); retrying in ${delay}s"
        ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true
        sleep "$delay"
        delay=$(( delay < 8 ? delay*2 : 8 ))
        ((attempt++))
    done

    # Clean up the temporary new tasks file now that awk is done
    rm -f "$new_tasks_file"

    if ! $awk_ok; then
        rm -f "$temp_file"
        log "ERROR" "Giving up updating Code Reviews file after $max_attempts attempts"
        return 1
    fi

    # IMPORTANT: Preserve symlink to Obsidian vault by copying over the target
    # Using mv here would replace the symlink itself. cp follows symlinks and writes to the target file.
    cp "$temp_file" "$CODE_REVIEWS_FILE"
    rm "$temp_file"
    
    local task_count
    task_count=$(echo "$new_tasks" | grep -c "^- \[ \]" || echo "0")
    log "INFO" "Added $task_count new tasks to Code Reviews.md"
}

# Cancel tasks for PRs that have been merged or closed
cancel_closed_merged_prs() {
    log "DEBUG" "Checking for merged/closed PRs to cancel..."

    if [[ ! -f "$CODE_REVIEWS_FILE" ]]; then
        log "DEBUG" "Code Reviews file not found, skipping merged/closed check"
        return 0
    fi

    # Read the file and find open tasks (- [ ]) with PR URLs
    local open_tasks
    open_tasks=$(grep -n "^- \[ \] #task #code-review" "$CODE_REVIEWS_FILE" 2>/dev/null || true)

    if [[ -z "$open_tasks" ]]; then
        log "DEBUG" "No open code review tasks found"
        return 0
    fi

    local canceled_count=0
    local temp_file
    temp_file=$(mktemp)
    cp "$CODE_REVIEWS_FILE" "$temp_file"

    while IFS= read -r line; do
        # Extract the PR URL from the task line
        local pr_url
        pr_url=$(echo "$line" | grep -oE 'https://github\.com/[^)]+' | head -1)

        if [[ -z "$pr_url" ]]; then
            log "DEBUG" "Could not extract PR URL from line: $line"
            continue
        fi

        # Check the PR state using GitHub CLI
        local pr_state
        pr_state=$(gh pr view "$pr_url" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")

        log "DEBUG" "PR $pr_url state: $pr_state"

        if [[ "$pr_state" == "MERGED" || "$pr_state" == "CLOSED" ]]; then
            log "INFO" "Canceling task for $pr_state PR: $pr_url"

            # Replace "- [ ]" with "- [-]" for this specific line
            # We match on the PR URL to ensure we update the correct line
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "DRY RUN: Would cancel task for $pr_state PR: $pr_url"
            else
                # Use sed to replace the checkbox on lines containing this URL
                sed -i '' "s|^\(- \)\[ \]\(.*$(echo "$pr_url" | sed 's|[&/]|\\&|g').*\)$|\1[-]\2|" "$temp_file"
                ((canceled_count++))
            fi
        fi
    done <<< "$open_tasks"

    if [[ "$DRY_RUN" != "true" && $canceled_count -gt 0 ]]; then
        cp "$temp_file" "$CODE_REVIEWS_FILE"
        log "INFO" "Canceled $canceled_count task(s) for merged/closed PRs"
    fi

    rm -f "$temp_file"

    if [[ $canceled_count -eq 0 ]]; then
        log "DEBUG" "No tasks needed to be canceled"
    fi
}

# Update dates on existing incomplete tasks
update_existing_task_dates() {
    # Preflight diagnostics and DRY RUN handling
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would update dates on existing incomplete tasks"
        return 0
    fi

    local link_target
    link_target=$(readlink "$CODE_REVIEWS_FILE" 2>/dev/null || echo "")
    if [[ -n "$link_target" ]]; then
        log "DEBUG" "Preparing to update task dates in: $CODE_REVIEWS_FILE (symlink target: $link_target)"
    else
        log "DEBUG" "Preparing to update task dates in: $CODE_REVIEWS_FILE (no symlink)"
    fi
    ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true

    # Small initial delay to reduce contention with Obsidian or other editors
    log "DEBUG" "Initial 1s delay before date update to avoid contention"
    sleep 1

    # Ensure file is readable with retries
    # Allow up to ~1 minute of retries: 1s,2s,4s,8s,8s,8s,8s,8s,8s,8s
    local max_attempts=10
    local attempt=1
    local delay=1
    while (( attempt <= max_attempts )); do
        if [[ -r "$CODE_REVIEWS_FILE" ]] && cat "$CODE_REVIEWS_FILE" >/dev/null 2>&1; then
            break
        fi
        # Log detailed error information
        log "WARN" "Code Reviews file not readable for date update (attempt $attempt/$max_attempts); retrying in ${delay}s"
        ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true
        echo "[DEBUG] Test -r result: $([[ -r "$CODE_REVIEWS_FILE" ]] && echo 'PASS' || echo 'FAIL')" >> "$LOG_FILE"
        cat "$CODE_REVIEWS_FILE" >/dev/null 2>>"$LOG_FILE" || echo "[DEBUG] Cat failed with exit code: $?" >> "$LOG_FILE"
        sleep "$delay"
        delay=$(( delay < 8 ? delay*2 : 8 ))
        ((attempt++))
    done
    if (( attempt > max_attempts )); then
        log "ERROR" "Code Reviews file not readable after $max_attempts attempts; aborting date update"
        return 1
    fi

    # Update dates on incomplete tasks (those starting with "- [ ]") with retries
    attempt=1
    delay=1
    local updated=false
    while (( attempt <= max_attempts )); do
        local tmp_update
        tmp_update=$(mktemp)
        if sed "s/\(- \[ \] #task #code-review.*\)📅 [0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}/\1📅 $TODAY/g" "$CODE_REVIEWS_FILE" > "$tmp_update" 2>>"$LOG_FILE"; then
            if cp "$tmp_update" "$CODE_REVIEWS_FILE" 2>>"$LOG_FILE"; then
                updated=true
                rm -f "$tmp_update"
                break
            fi
        fi
        rm -f "$tmp_update"
        log "WARN" "Failed to update dates (attempt $attempt/$max_attempts); retrying in ${delay}s"
        ls -l "$CODE_REVIEWS_FILE" >> "$LOG_FILE" 2>&1 || true
        sleep "$delay"
        delay=$(( delay < 8 ? delay*2 : 8 ))
        ((attempt++))
    done

    if ! $updated; then
        log "ERROR" "Giving up updating task dates after $max_attempts attempts"
        return 1
    fi

    log "DEBUG" "Updated dates on existing incomplete tasks"
}

# Main processing function
process_reviews() {
    log "INFO" "Starting GitHub review processing for $TODAY..."

    # First, cancel tasks for PRs that have been merged or closed
    cancel_closed_merged_prs

    local existing_urls new_tasks=""
    existing_urls=$(get_existing_pr_urls)
    
    # Process integration team reviews
    log "DEBUG" "Processing integration team reviews..."
    local integration_prs integration_pr_urls=""
    integration_prs=$(get_integration_reviews)
    
    if [[ "$integration_prs" != "[]" && -n "$integration_prs" ]]; then
        while IFS= read -r pr; do
            local url number title
            url=$(echo "$pr" | jq -r '.url')
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            integration_pr_urls+="$url"$'\n'
            
            # Check if this PR is already tracked
            if ! echo "$existing_urls" | grep -q "$url"; then
                # STEP 1: Try automated review first (only if meets size threshold)
                local task_line
                if pr_meets_size_threshold "$number" && trigger_automated_review "$number" "$title"; then
                    # Automated review succeeded - create task with review link
                    task_line=$(create_task_line_with_review "$pr" "integrations-review" "urgent-important")
                    log "DEBUG" "Added integration review with automated review: $title"
                else
                    local review_exit_code=$?
                    if [[ $review_exit_code -eq 2 ]]; then
                        # Tool unavailable - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (no automated review): $title"
                    elif [[ $review_exit_code -eq 3 ]] || ! pr_meets_size_threshold "$number"; then
                        # Skipped due to size or below threshold - create task without automated review
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (below size threshold, no automated review): $title"
                    else
                        # Other error - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (review failed): $title"
                    fi
                fi
                new_tasks+="$task_line"$'\n'
            fi
        done <<< "$(echo "$integration_prs" | jq -c '.[]' 2>/dev/null || true)"
    fi

    # Process Riftwalkers team reviews
    log "DEBUG" "Processing Riftwalkers team reviews..."
    local riftwalkers_prs riftwalkers_pr_urls=""
    riftwalkers_prs=$(get_riftwalkers_reviews)

    if [[ "$riftwalkers_prs" != "[]" && -n "$riftwalkers_prs" ]]; then
        while IFS= read -r pr; do
            local url number title
            url=$(echo "$pr" | jq -r '.url')
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            riftwalkers_pr_urls+="$url"$'\n'

            # Check if this PR is already tracked or is an integration PR
            if ! echo "$existing_urls" | grep -q "$url" && ! echo "$integration_pr_urls" | grep -q "$url"; then
                # STEP 1: Try automated review first (only if meets size threshold)
                local task_line
                if pr_meets_size_threshold "$number" && trigger_automated_review "$number" "$title"; then
                    # Automated review succeeded - create task with review link
                    task_line=$(create_task_line_with_review "$pr" "riftwalkers-review" "urgent-important")
                    log "DEBUG" "Added Riftwalkers review with automated review: $title"
                else
                    local review_exit_code=$?
                    if [[ $review_exit_code -eq 2 ]]; then
                        # Tool unavailable - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (no automated review): $title"
                    elif [[ $review_exit_code -eq 3 ]] || ! pr_meets_size_threshold "$number"; then
                        # Skipped due to size or below threshold - create task without automated review
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (below size threshold, no automated review): $title"
                    else
                        # Other error - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (review failed): $title"
                    fi
                fi
                new_tasks+="$task_line"$'\n'
            fi
        done <<< "$(echo "$riftwalkers_prs" | jq -c '.[]' 2>/dev/null || true)"
    fi

    # Process follow-up reviews
    log "DEBUG" "Processing follow-up reviews..."
    local followup_prs
    followup_prs=$(get_followup_reviews)

    if [[ "$followup_prs" != "[]" && -n "$followup_prs" ]]; then
        while IFS= read -r pr; do
            local url
            url=$(echo "$pr" | jq -r '.url')

            # Skip if already in existing URLs, integration PRs, or Riftwalkers PRs
            if ! echo "$existing_urls" | grep -q "$url" && ! echo "$integration_pr_urls" | grep -q "$url" && ! echo "$riftwalkers_pr_urls" | grep -q "$url"; then
                local task_line
                task_line=$(create_task_line "$pr" "follow-up-review" "urgent-important")
                new_tasks+="$task_line"$'\n'
                log "DEBUG" "Added follow-up review: $(echo "$pr" | jq -r '.title')"
            fi
        done <<< "$(echo "$followup_prs" | jq -c '.[]' 2>/dev/null || true)"
    fi
    
    # Process general reviews (limit to 10)
    log "DEBUG" "Processing general reviews..."
    local general_prs
    general_prs=$(get_general_reviews)
    
    if [[ "$general_prs" != "[]" && -n "$general_prs" ]]; then
        local total_general_count
        total_general_count=$(echo "$general_prs" | jq 'length' 2>/dev/null || echo "0")
        log "DEBUG" "Found $total_general_count general PRs before filtering" >&2
        
        local count=0
        while IFS= read -r pr && [[ $count -lt $MAX_GENERAL_REVIEWS ]]; do
            local url number title
            url=$(echo "$pr" | jq -r '.url')
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            
            log "DEBUG" "Evaluating general PR #$number: $title" >&2
            
            # Debug deduplication checks
            local existing_check integration_check new_tasks_check
            existing_check=$(echo "$existing_urls" | grep -q "$url" && echo "EXISTS" || echo "NEW")
            integration_check=$(echo "$integration_pr_urls" | grep -q "$url" && echo "INTEGRATION" || echo "NOT_INTEGRATION")
            new_tasks_check=$(echo "$new_tasks" | grep -q "$url" && echo "ALREADY_ADDED" || echo "NOT_ADDED")
            local riftwalkers_check
            riftwalkers_check=$(echo "$riftwalkers_pr_urls" | grep -q "$url" && echo "RIFTWALKERS" || echo "NOT_RIFTWALKERS")
            log "DEBUG" "PR #$number dedup status: existing=$existing_check, integration=$integration_check, riftwalkers=$riftwalkers_check, new_tasks=$new_tasks_check" >&2

            # Skip if already in existing URLs, integration PRs, Riftwalkers PRs, or new tasks
            if ! echo "$existing_urls" | grep -q "$url" && \
               ! echo "$integration_pr_urls" | grep -q "$url" && \
               ! echo "$riftwalkers_pr_urls" | grep -q "$url" && \
               ! echo "$new_tasks" | grep -q "$url"; then
                # STEP 1: Try automated review first (only if meets size threshold)
                local task_line
                if pr_meets_size_threshold "$number" && trigger_automated_review "$number" "$title"; then
                    # Automated review succeeded - create task with review link
                    task_line=$(create_task_line_with_review "$pr" "general-review" "not-urgent-important")
                    log "DEBUG" "Added general review with automated review: $title"
                else
                    local review_exit_code=$?
                    if [[ $review_exit_code -eq 2 ]]; then
                        # Tool unavailable - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "general-review" "not-urgent-important")
                        log "DEBUG" "Added general review (no automated review): $title"
                    elif [[ $review_exit_code -eq 3 ]] || ! pr_meets_size_threshold "$number"; then
                        # Skipped due to size or below threshold - create task without automated review
                        task_line=$(create_task_line_without_review "$pr" "general-review" "not-urgent-important")
                        log "DEBUG" "Added general review (below size threshold, no automated review): $title"
                    else
                        # Other error - create regular task without link
                        task_line=$(create_task_line_without_review "$pr" "general-review" "not-urgent-important")
                        log "DEBUG" "Added general review (review failed): $title"
                    fi
                fi
                new_tasks+="$task_line"$'\n'
                ((count++))
            fi
        done <<< "$(echo "$general_prs" | jq -c '.[]' 2>/dev/null || true)"
    fi
    
    # NOTE: "My PRs" section removed per user request (2025-11-17)
    # We no longer automatically add your PRs to Code Reviews.md
    # However, NTFY notifications are still sent for PR updates (comments, reviews, feedback)
    
    # Add new tasks and update existing ones
    add_tasks_to_file "$new_tasks"
    
    if [[ "$FORCE_UPDATE" == "true" ]] || [[ -n "$new_tasks" ]]; then
        update_existing_task_dates
    fi
    
    # Summary telemetry
    local new_task_count integration_count riftwalkers_count general_count incomplete_reviews
    new_task_count=$(echo "$new_tasks" | grep -c "^- \[ \]" || echo "0")
    integration_count=$(echo "$integration_prs" | jq 'length' 2>/dev/null || echo "0")
    riftwalkers_count=$(echo "$riftwalkers_prs" | jq 'length' 2>/dev/null || echo "0")
    general_count=$(echo "$general_prs" | jq 'length' 2>/dev/null || echo "0")
    incomplete_reviews=$(grep -c "^- \[ \] #task #code-review" "$CODE_REVIEWS_FILE" 2>/dev/null || echo "0")

    log "INFO" "Processing summary: Integration PRs: $integration_count, Riftwalkers PRs: $riftwalkers_count, General PRs: $general_count, Total incomplete code reviews: $incomplete_reviews, New code review tasks created: $new_task_count"
    
    log "INFO" "GitHub review processing completed"
}

# Track sent notifications to avoid duplicates
readonly NOTIFICATIONS_FILE="/tmp/github-review-monitor-notifications.log"

# Check if notification was already sent for this PR
notification_already_sent() {
    local pr_number="$1"
    local today="$2"
    
    if [[ -f "$NOTIFICATIONS_FILE" ]]; then
        grep -q "^$today:$pr_number$" "$NOTIFICATIONS_FILE" 2>/dev/null
    else
        return 1  # File doesn't exist, so notification not sent
    fi
}

# Record that notification was sent for this PR
record_notification_sent() {
    local pr_number="$1"
    local today="$2"
    
    echo "$today:$pr_number" >> "$NOTIFICATIONS_FILE"
    
    # Clean up old entries (keep only today's entries)
    if [[ -f "$NOTIFICATIONS_FILE" ]]; then
        grep "^$today:" "$NOTIFICATIONS_FILE" > "${NOTIFICATIONS_FILE}.tmp" 2>/dev/null || true
        mv "${NOTIFICATIONS_FILE}.tmp" "$NOTIFICATIONS_FILE" 2>/dev/null || true
    fi
}

# Check for new activity on your own PRs and send notifications
check_my_prs_for_activity() {
    log "INFO" "Checking my PRs for new activity on $TODAY..."

    local my_prs_with_activity
    my_prs_with_activity=$(get_my_prs_with_new_activity)

    if [[ "$my_prs_with_activity" == "[]" || -z "$my_prs_with_activity" ]]; then
        log "INFO" "No activity found on my PRs"
        return 0
    fi

    local pr_count
    pr_count=$(echo "$my_prs_with_activity" | jq 'length' 2>&1)
    if [[ $? -ne 0 ]]; then
        log "WARN" "Failed to get PR count: $pr_count" >&2
        return 1
    fi
    log "INFO" "Found $pr_count of my PR(s) with activity"

    local notifications_sent=0

    # Check each PR for new activity since last notification
    while IFS= read -r pr; do
        local number title url latest_activity comment_count review_count
        number=$(echo "$pr" | jq -r '.number')
        title=$(echo "$pr" | jq -r '.title')
        url=$(echo "$pr" | jq -r '.url')
        latest_activity=$(echo "$pr" | jq -r '.latest_activity')
        comment_count=$(echo "$pr" | jq -r '.comment_count')
        review_count=$(echo "$pr" | jq -r '.review_count')

        # Check if we already sent a notification for this PR's latest activity
        # We use the latest_activity timestamp as a key
        local notification_key="$TODAY:mypr:$number:$latest_activity"
        if grep -q "^$notification_key$" "$NOTIFICATIONS_FILE" 2>/dev/null; then
            log "DEBUG" "Notification already sent for PR #$number's latest activity - skipping"
            continue
        fi

        # Build notification message with activity details
        local activity_summary=""
        if [[ "$comment_count" -gt 0 && "$review_count" -gt 0 ]]; then
            activity_summary="$review_count review(s) and $comment_count comment(s)"
        elif [[ "$review_count" -gt 0 ]]; then
            activity_summary="$review_count review(s)"
        else
            activity_summary="$comment_count comment(s)"
        fi

        local notification_title="💬 Activity on Your PR #$number"
        local notification_message="$title

New activity: $activity_summary

View: $url"

        if [[ "$SEND_NOTIFICATIONS" == "true" ]]; then
            send_ntfy_notification "$notification_title" "$notification_message" "default" "pr,activity"
            echo "$notification_key" >> "$NOTIFICATIONS_FILE"
            ((notifications_sent++))
        else
            log "INFO" "Would notify: $notification_title - $notification_message"
        fi

        log "INFO" "Activity detected on my PR #$number: $activity_summary"
    done <<< "$(echo "$my_prs_with_activity" | jq -c '.[]' 2>/dev/null || true)"

    if [[ $notifications_sent -gt 0 ]]; then
        log "INFO" "Sent $notifications_sent notification(s) for my PRs"
    else
        log "INFO" "No new notifications sent (all activity already notified)"
    fi

    log "INFO" "My PRs activity check completed"
}

# Process integration and Riftwalkers reviews only (for frequent checks)
process_integration_reviews_only() {
    log "INFO" "Starting priority team review check for $TODAY..."

    # First, cancel tasks for PRs that have been merged or closed
    cancel_closed_merged_prs

    local existing_urls new_tasks=""
    existing_urls=$(get_existing_pr_urls)
    local notifications_sent=0

    # ========================================
    # Process Integration Team PRs
    # ========================================
    local integration_prs
    integration_prs=$(get_integration_reviews_for_notification)
    log "DEBUG" "Integration PRs result (first 100 chars): $(echo "$integration_prs" | head -c 100)" >&2

    if [[ "$integration_prs" != "[]" && -n "$integration_prs" ]]; then
        local integration_count
        integration_count=$(echo "$integration_prs" | jq 'length' 2>/dev/null || echo "0")
        log "INFO" "Found $integration_count integration PR(s) requiring notification"

        # Add new integration PRs to Code Reviews.md
        while IFS= read -r pr; do
            local url number title
            url=$(echo "$pr" | jq -r '.url')
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')

            if ! echo "$existing_urls" | grep -q "$url"; then
                local task_line
                if pr_meets_size_threshold "$number" && trigger_automated_review "$number" "$title"; then
                    task_line=$(create_task_line_with_review "$pr" "integrations-review" "urgent-important")
                    log "DEBUG" "Added integration review with automated review: $title"
                else
                    local review_exit_code=$?
                    if [[ $review_exit_code -eq 2 ]]; then
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (no automated review): $title"
                    elif [[ $review_exit_code -eq 3 ]] || ! pr_meets_size_threshold "$number"; then
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (below size threshold): $title"
                    else
                        task_line=$(create_task_line_without_review "$pr" "integrations-review" "urgent-important")
                        log "DEBUG" "Added integration review (review failed): $title"
                    fi
                fi
                new_tasks+="$task_line"$'\n'
            fi
        done <<< "$(echo "$integration_prs" | jq -c '.[]' 2>/dev/null || true)"

        # Send notifications for integration PRs
        while IFS= read -r pr; do
            local number title author url
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            author=$(echo "$pr" | jq -r '.author')
            url=$(echo "$pr" | jq -r '.url')

            if notification_already_sent "$number" "$TODAY"; then
                log "DEBUG" "Notification already sent today for integration PR #$number - skipping"
                continue
            fi

            local notification_title="🔧 Integration Review Needed"
            local notification_message="$author: $title

PR #$number requires your integration expertise.

View: $url"

            if [[ "$SEND_NOTIFICATIONS" == "true" ]]; then
                send_ntfy_notification "$notification_title" "$notification_message" "high" "integration,urgent"
                record_notification_sent "$number" "$TODAY"
                ((notifications_sent++))
            else
                log "INFO" "Would notify: $notification_title - $notification_message"
            fi

            log "INFO" "Integration review needed: PR #$number by $author"
        done <<< "$(echo "$integration_prs" | jq -c '.[]' 2>/dev/null || true)"
    else
        log "INFO" "No new integration reviews requiring notification"
    fi

    # ========================================
    # Process Riftwalkers Team PRs
    # ========================================
    local riftwalkers_prs
    riftwalkers_prs=$(get_riftwalkers_reviews_for_notification)
    log "DEBUG" "Riftwalkers PRs result (first 100 chars): $(echo "$riftwalkers_prs" | head -c 100)" >&2

    if [[ "$riftwalkers_prs" != "[]" && -n "$riftwalkers_prs" ]]; then
        local riftwalkers_count
        riftwalkers_count=$(echo "$riftwalkers_prs" | jq 'length' 2>/dev/null || echo "0")
        log "INFO" "Found $riftwalkers_count Riftwalkers PR(s) requiring notification"

        # Add new Riftwalkers PRs to Code Reviews.md
        while IFS= read -r pr; do
            local url number title
            url=$(echo "$pr" | jq -r '.url')
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')

            # Skip if already tracked or is an integration PR
            if ! echo "$existing_urls" | grep -q "$url" && ! echo "$new_tasks" | grep -q "$url"; then
                local task_line
                if pr_meets_size_threshold "$number" && trigger_automated_review "$number" "$title"; then
                    task_line=$(create_task_line_with_review "$pr" "riftwalkers-review" "urgent-important")
                    log "DEBUG" "Added Riftwalkers review with automated review: $title"
                else
                    local review_exit_code=$?
                    if [[ $review_exit_code -eq 2 ]]; then
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (no automated review): $title"
                    elif [[ $review_exit_code -eq 3 ]] || ! pr_meets_size_threshold "$number"; then
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (below size threshold): $title"
                    else
                        task_line=$(create_task_line_without_review "$pr" "riftwalkers-review" "urgent-important")
                        log "DEBUG" "Added Riftwalkers review (review failed): $title"
                    fi
                fi
                new_tasks+="$task_line"$'\n'
            fi
        done <<< "$(echo "$riftwalkers_prs" | jq -c '.[]' 2>/dev/null || true)"

        # Send notifications for Riftwalkers PRs
        while IFS= read -r pr; do
            local number title author url
            number=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title')
            author=$(echo "$pr" | jq -r '.author')
            url=$(echo "$pr" | jq -r '.url')

            if notification_already_sent "$number" "$TODAY"; then
                log "DEBUG" "Notification already sent today for Riftwalkers PR #$number - skipping"
                continue
            fi

            local notification_title="⚡ Riftwalkers Review Needed"
            local notification_message="$author: $title

PR #$number from your Riftwalkers teammate.

View: $url"

            if [[ "$SEND_NOTIFICATIONS" == "true" ]]; then
                send_ntfy_notification "$notification_title" "$notification_message" "high" "riftwalkers,urgent"
                record_notification_sent "$number" "$TODAY"
                ((notifications_sent++))
            else
                log "INFO" "Would notify: $notification_title - $notification_message"
            fi

            log "INFO" "Riftwalkers review needed: PR #$number by $author"
        done <<< "$(echo "$riftwalkers_prs" | jq -c '.[]' 2>/dev/null || true)"
    else
        log "INFO" "No new Riftwalkers reviews requiring notification"
    fi

    # ========================================
    # Add all new tasks to file
    # ========================================
    if [[ -n "$new_tasks" ]]; then
        add_tasks_to_file "$new_tasks"
        log "INFO" "Added new priority team PRs to Code Reviews.md"
    else
        log "DEBUG" "No new priority team PRs to add to Code Reviews.md" >&2
    fi

    if [[ $notifications_sent -gt 0 ]]; then
        log "INFO" "Sent $notifications_sent new priority team review notification(s)"
    else
        log "INFO" "No new notifications sent (all PRs already notified today)"
    fi

    log "INFO" "Priority team review check completed"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            --integration-only)
                INTEGRATION_ONLY=true
                shift
                ;;
            --notifications)
                SEND_NOTIFICATIONS=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Initialize log file
    echo "=== GitHub Review Monitor Session Started at $(date) ===" >> "$LOG_FILE"
    
    parse_args "$@"
    log "DEBUG" "Parsed args. INTEGRATION_ONLY=$INTEGRATION_ONLY, VERBOSE=$VERBOSE" >&2
    check_prerequisites
    
    if [[ "$INTEGRATION_ONLY" == "true" ]]; then
        log "DEBUG" "Running integration-only mode" >&2
        process_integration_reviews_only

        # Also check for activity on my PRs
        log "DEBUG" "Checking for activity on my PRs..." >&2
        check_my_prs_for_activity

        log "DEBUG" "Integration-only processing completed" >&2
        return 0
    else
        log "DEBUG" "Running full review processing" >&2
        process_reviews
    fi
}

# Run main function with all arguments
main "$@"