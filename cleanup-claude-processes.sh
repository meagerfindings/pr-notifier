#!/bin/bash
#
# Cleanup Orphaned Claude Processes
# Kills claude processes that have been running longer than a threshold
# Author: Mat Greten
# Usage: ./cleanup-claude-processes.sh [--dry-run] [--max-age MINUTES]
#

set -euo pipefail

# Configuration
DEFAULT_MAX_AGE_MINUTES=10  # Kill processes older than this
LOG_FILE="/tmp/claude-cleanup.log"

# Options
DRY_RUN=false
MAX_AGE_MINUTES=$DEFAULT_MAX_AGE_MINUTES
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    case "$level" in
        "ERROR") echo -e "${RED}[$level]${NC} $message" >&2 ;;
        "WARN")  echo -e "${YELLOW}[$level]${NC} $message" >&2 ;;
        "INFO")  echo -e "${GREEN}[$level]${NC} $message" ;;
        "DEBUG") [[ "$VERBOSE" == "true" ]] && echo "[$level] $message" ;;
        *)       echo "[$level] $message" ;;
    esac
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Show what would be killed without actually killing"
    echo "  --max-age MINUTES      Kill processes older than this (default: $DEFAULT_MAX_AGE_MINUTES)"
    echo "  --verbose              Enable verbose logging"
    echo "  --help                 Show this help message"
    echo ""
    echo "This script finds and kills orphaned claude processes that have been"
    echo "running longer than the specified threshold."
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --max-age)
                MAX_AGE_MINUTES="$2"
                shift 2
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

get_process_age_minutes() {
    local pid="$1"
    # Get elapsed time using ps (macOS format: [[DD-]HH:]MM:SS)
    local etime
    etime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0:00")

    # Parse the elapsed time format
    local days=0 hours=0 minutes=0 seconds=0

    if [[ "$etime" =~ ^([0-9]+)-(.+)$ ]]; then
        # Format: DD-HH:MM:SS
        days="${BASH_REMATCH[1]}"
        etime="${BASH_REMATCH[2]}"
    fi

    # Count colons to determine format
    local colons="${etime//[^:]/}"
    if [[ ${#colons} -eq 2 ]]; then
        # Format: HH:MM:SS
        IFS=':' read -r hours minutes seconds <<< "$etime"
    else
        # Format: MM:SS
        IFS=':' read -r minutes seconds <<< "$etime"
    fi

    # Calculate total minutes
    local total_minutes=$(( days * 24 * 60 + hours * 60 + minutes ))
    echo "$total_minutes"
}

kill_process_tree() {
    local pid="$1"
    local signal="${2:-TERM}"

    # Get all child processes
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)

    # Kill children first (depth-first)
    for child in $children; do
        kill_process_tree "$child" "$signal"
    done

    # Kill the process itself
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would kill PID $pid with SIG$signal"
    else
        log "DEBUG" "Sending SIG$signal to PID $pid"
        kill -s "$signal" "$pid" 2>/dev/null || true
    fi
}

cleanup_orphaned_processes() {
    log "INFO" "Starting cleanup (max age: ${MAX_AGE_MINUTES} minutes)..."

    local killed_count=0
    local found_count=0

    # Find all claude processes
    # Look for: claude CLI, node processes spawned by claude, etc.
    local claude_pids
    claude_pids=$(pgrep -f "claude" 2>/dev/null || true)

    if [[ -z "$claude_pids" ]]; then
        log "INFO" "No claude processes found"
        return 0
    fi

    log "DEBUG" "Found claude-related PIDs: $(echo $claude_pids | tr '\n' ' ')"

    for pid in $claude_pids; do
        # Skip if process no longer exists
        if ! kill -0 "$pid" 2>/dev/null; then
            continue
        fi

        # Get process info
        local cmd age_minutes
        cmd=$(ps -o command= -p "$pid" 2>/dev/null | head -c 80 || echo "unknown")
        age_minutes=$(get_process_age_minutes "$pid")

        ((found_count++))

        log "DEBUG" "PID $pid: age=${age_minutes}m cmd='$cmd'"

        # Check if process is older than threshold
        if [[ $age_minutes -ge $MAX_AGE_MINUTES ]]; then
            log "WARN" "Found stale claude process: PID $pid (age: ${age_minutes}m)"
            log "DEBUG" "  Command: $cmd"

            # Try graceful termination first
            kill_process_tree "$pid" "TERM"

            if [[ "$DRY_RUN" != "true" ]]; then
                # Wait a moment for graceful shutdown
                sleep 1

                # Force kill if still running
                if kill -0 "$pid" 2>/dev/null; then
                    log "WARN" "Process $pid didn't terminate gracefully, force killing..."
                    kill_process_tree "$pid" "KILL"
                fi
            fi

            ((killed_count++))
        fi
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN: Would have killed $killed_count of $found_count claude processes"
    else
        log "INFO" "Cleanup complete: killed $killed_count of $found_count claude processes"
    fi

    return 0
}

# Also clean up stale lock files
cleanup_stale_locks() {
    local lock_file="/tmp/claude-pr-reviewer.lock"

    if [[ ! -f "$lock_file" ]]; then
        log "DEBUG" "No lock file found"
        return 0
    fi

    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

    if [[ -z "$lock_pid" ]]; then
        log "DEBUG" "Lock file empty, removing"
        [[ "$DRY_RUN" != "true" ]] && rm -f "$lock_file"
        return 0
    fi

    # Check if the process holding the lock is still running
    if ! kill -0 "$lock_pid" 2>/dev/null; then
        log "WARN" "Found stale lock file (PID $lock_pid no longer running)"
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "DRY RUN: Would remove stale lock file"
        else
            rm -f "$lock_file"
            log "INFO" "Removed stale lock file"
        fi
    else
        log "DEBUG" "Lock file held by active process $lock_pid"
    fi
}

main() {
    echo "=== Claude Process Cleanup Started at $(date) ===" >> "$LOG_FILE"

    parse_args "$@"

    cleanup_stale_locks
    cleanup_orphaned_processes

    log "INFO" "Cleanup script finished"
}

main "$@"
