#!/bin/bash

#
# GitHub Mentions Monitor
# Automatically detects personal @mentions in GitHub and sends NTFY notifications
# Author: Mat Greten
# Usage: ./github-mentions-monitor.sh [--dry-run] [--verbose]
#

set -euo pipefail

# Configuration
readonly REPO="CompanyCam/Company-Cam-API"
readonly NTFY_SERVER="ntfy.tail001dd.ts.net"
readonly NTFY_TOPIC="code-reviews"
readonly LOG_FILE="/tmp/github-mentions-monitor.log"
readonly GITHUB_USER="meagerfindings"
readonly NOTIFICATIONS_FILE="/tmp/github-mentions-notifications.log"

# Options
DRY_RUN=false
VERBOSE=false
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
    echo "  --help                 Show this help message"
    echo ""
    echo "This script monitors GitHub for personal @mentions and sends"
    echo "NTFY notifications. Excludes team mentions like @CompanyCam/backend-engineers."
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
    local priority="${3:-high}"
    local tags="${4:-mention,urgent,github}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would send notification: $title"
        log "DEBUG" "Message: $message"
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

# Check if notification was already sent for this mention
notification_already_sent() {
    local notification_id="$1"
    local today="$2"
    
    if [[ -f "$NOTIFICATIONS_FILE" ]]; then
        grep -q "^$today:$notification_id$" "$NOTIFICATIONS_FILE" 2>/dev/null
    else
        return 1  # File doesn't exist, so notification not sent
    fi
}

# Record that notification was sent for this mention
record_notification_sent() {
    local notification_id="$1"
    local today="$2"
    
    echo "$today:$notification_id" >> "$NOTIFICATIONS_FILE"
    
    # Clean up old entries (keep only today's entries)
    if [[ -f "$NOTIFICATIONS_FILE" ]]; then
        grep "^$today:" "$NOTIFICATIONS_FILE" > "${NOTIFICATIONS_FILE}.tmp" 2>/dev/null || true
        mv "${NOTIFICATIONS_FILE}.tmp" "$NOTIFICATIONS_FILE" 2>/dev/null || true
    fi
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
    
    log "DEBUG" "Prerequisites check passed"
}

# Get personal mentions from GitHub notifications
get_personal_mentions() {
    log "DEBUG" "Fetching personal mentions from GitHub notifications..."
    
    # Get all notifications with reason "mention" for our repo
    local mentions_json
    mentions_json=$(gh api /notifications 2>/dev/null || echo "[]")
    
    local mentions
    mentions=$(echo "$mentions_json" | jq ".[] | select(.reason == \"mention\" and .repository.full_name == \"$REPO\" and .unread == true)")
    
    if [[ -z "$mentions" ]]; then
        log "DEBUG" "No unread mentions found"
        echo "[]"
        return
    fi
    
    log "DEBUG" "Found potential mentions, filtering for personal mentions..."
    
    # Process each mention to check if it's a personal mention
    local personal_mentions="[]"
    while IFS= read -r mention; do
        if [[ -n "$mention" ]]; then
            local id subject_url subject_type
            id=$(echo "$mention" | jq -r '.id')
            subject_url=$(echo "$mention" | jq -r '.subject.url')
            subject_type=$(echo "$mention" | jq -r '.subject.type')
            
            log "DEBUG" "Processing mention ID: $id, Type: $subject_type"
            
            # Convert GitHub API URL to comments API URL based on type
            local comments_url=""
            if [[ "$subject_type" == "PullRequest" ]]; then
                # For PRs, we need to check both issue comments and review comments
                local pr_number
                pr_number=$(echo "$subject_url" | grep -oE '[0-9]+$')
                
                # Check issue comments (general PR comments)
                local issue_comments
                issue_comments=$(gh api "/repos/$REPO/issues/$pr_number/comments" --jq '.[]' 2>/dev/null || echo "")
                
                # Check review comments (code review comments)
                local review_comments
                review_comments=$(gh api "/repos/$REPO/pulls/$pr_number/comments" --jq '.[]' 2>/dev/null || echo "")
                
                # Combine both types of comments
                local all_comments="$issue_comments"$'\n'"$review_comments"
                
                # Check each comment for personal mention
                while IFS= read -r comment; do
                    if [[ -n "$comment" ]]; then
                        local comment_body user_login html_url created_at
                        comment_body=$(echo "$comment" | jq -r '.body // empty')
                        user_login=$(echo "$comment" | jq -r '.user.login // empty')
                        html_url=$(echo "$comment" | jq -r '.html_url // empty')
                        created_at=$(echo "$comment" | jq -r '.created_at // empty')
                        
                        # Check if comment contains personal mention but not team mention
                        if [[ "$comment_body" =~ @$GITHUB_USER ]] && ! [[ "$comment_body" =~ @CompanyCam/backend-engineers ]]; then
                            log "DEBUG" "Found personal mention from $user_login"
                            
                            # Create mention object with comment details
                            local mention_with_comment subject_title
                            subject_title=$(echo "$mention" | jq -r '.subject.title')
                            mention_with_comment=$(echo "$mention" | jq --arg body "$comment_body" --arg author "$user_login" --arg url "$html_url" --arg created "$created_at" --arg title "$subject_title" '. + {
                                comment_body: $body,
                                comment_author: $author,
                                comment_url: $url,
                                comment_created: $created,
                                subject_title: $title
                            }')
                            
                            personal_mentions=$(echo "$personal_mentions" | jq --argjson new_mention "$mention_with_comment" '. + [$new_mention]')
                            break  # Found mention in this PR, no need to check more comments
                        fi
                    fi
                done <<< "$all_comments"
            fi
        fi
    done <<< "$(echo "$mentions_json" | jq -c ".[] | select(.reason == \"mention\" and .repository.full_name == \"$REPO\" and .unread == true)" 2>/dev/null || true)"
    
    echo "$personal_mentions"
}

# Process mentions and send notifications
process_mentions() {
    log "INFO" "Starting GitHub mentions monitoring for $TODAY..."
    
    local mentions
    mentions=$(get_personal_mentions)
    
    if [[ "$mentions" == "[]" || -z "$mentions" ]]; then
        log "INFO" "No new personal mentions requiring notification"
        return 0
    fi
    
    local mention_count
    mention_count=$(echo "$mentions" | jq 'length' 2>/dev/null || echo "0")
    log "INFO" "Found $mention_count personal mention(s) requiring notification"
    
    local notifications_sent=0
    
    # Process each mention
    while IFS= read -r mention; do
        local id subject_title comment_author comment_body comment_url repository
        id=$(echo "$mention" | jq -r '.id')
        subject_title=$(echo "$mention" | jq -r '.subject_title // .subject.title')
        comment_author=$(echo "$mention" | jq -r '.comment_author')
        comment_body=$(echo "$mention" | jq -r '.comment_body')
        comment_url=$(echo "$mention" | jq -r '.comment_url')
        repository=$(echo "$mention" | jq -r '.repository.full_name // .repository')
        
        # Check if we already sent a notification for this mention today
        if notification_already_sent "$id" "$TODAY"; then
            log "DEBUG" "Notification already sent today for mention ID: $id - skipping"
            continue
        fi
        
        # Truncate comment body for notification
        local comment_preview
        if [[ ${#comment_body} -gt 100 ]]; then
            comment_preview="${comment_body:0:100}..."
        else
            comment_preview="$comment_body"
        fi
        
        # Create notification
        local notification_title="🔔 You were mentioned"
        local notification_message="$comment_author mentioned you in: $subject_title

'$comment_preview'

View: $comment_url"
        
        send_ntfy_notification "$notification_title" "$notification_message" "high" "mention,urgent"
        record_notification_sent "$id" "$TODAY"
        ((notifications_sent++))
        
        log "INFO" "Personal mention notification sent: $comment_author mentioned you in '$subject_title'"
        
    done <<< "$(echo "$mentions" | jq -c '.[]' 2>/dev/null || true)"
    
    if [[ $notifications_sent -gt 0 ]]; then
        log "INFO" "Sent $notifications_sent new mention notification(s)"
    else
        log "INFO" "No new notifications sent (all mentions already notified today)"
    fi
    
    log "INFO" "GitHub mentions monitoring completed"
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

# Check if current time is during business hours
is_business_hours() {
    local current_hour=$(date +%H)
    local current_day=$(date +%u)  # 1-7 (Monday-Sunday)
    
    # Only run Monday-Friday (1-5) between 8 AM and 4 PM (08-15)
    if [[ $current_day -ge 1 && $current_day -le 5 && $((10#$current_hour)) -ge 8 && $((10#$current_hour)) -lt 16 ]]; then
        return 0  # Business hours
    else
        return 1  # Outside business hours
    fi
}

# Main function
main() {
    # Initialize log file
    echo "=== GitHub Mentions Monitor Session Started at $(date) ===" >> "$LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    
    # Check if we're in business hours (unless dry-run)
    if [[ "$DRY_RUN" == "false" ]] && ! is_business_hours; then
        log "INFO" "Outside business hours - skipping mentions monitoring"
        exit 0
    fi
    
    process_mentions
    
    log "INFO" "GitHub mentions monitoring completed successfully"
}

# Run main function with all arguments
main "$@"