#!/bin/bash

#
# GitHub PR Review Notifier Setup Script
# Sets up automated code review monitoring and notifications
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        *)       echo "[$level] $message" ;;
    esac
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        log "ERROR" "GitHub CLI (gh) is not installed. Please install it first:"
        log "INFO" "  brew install gh"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq is not installed. Please install it first:"
        log "INFO" "  brew install jq"
        exit 1
    fi
    
    # Check if gh is authenticated
    if ! gh auth status &> /dev/null; then
        log "ERROR" "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    log "INFO" "Prerequisites check passed"
}

setup_launchagents() {
    log "INFO" "Setting up LaunchAgents..."
    
    # Unload existing agents if they exist
    if launchctl list | grep -q "com.mat.github-review-monitor"; then
        log "INFO" "Unloading existing LaunchAgents..."
        launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor.plist 2>/dev/null || true
        launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist 2>/dev/null || true
    fi
    
    # Copy LaunchAgent files
    cp "$SCRIPT_DIR/com.mat.github-review-monitor.plist" ~/Library/LaunchAgents/
    cp "$SCRIPT_DIR/com.mat.github-review-monitor-integration.plist" ~/Library/LaunchAgents/
    
    # Load LaunchAgents
    launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
    launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist
    
    log "INFO" "LaunchAgents installed and loaded"
}

make_executable() {
    log "INFO" "Making script executable..."
    chmod +x "$SCRIPT_DIR/github-review-monitor.sh"
}

test_installation() {
    log "INFO" "Testing installation..."
    
    # Test the script
    if "$SCRIPT_DIR/github-review-monitor.sh" --help > /dev/null; then
        log "INFO" "Script test passed"
    else
        log "ERROR" "Script test failed"
        exit 1
    fi
    
    # Check LaunchAgents are loaded
    if launchctl list | grep -q "com.mat.github-review-monitor"; then
        log "INFO" "LaunchAgents test passed"
    else
        log "ERROR" "LaunchAgents test failed"
        exit 1
    fi
}

show_status() {
    log "INFO" "Installation complete! Status:"
    echo ""
    echo "📁 Script location: $SCRIPT_DIR/github-review-monitor.sh"
    echo "⚙️  LaunchAgents:"
    launchctl list | grep github-review-monitor | while read -r line; do
        echo "   $line"
    done
    echo ""
    echo "🚀 Next steps:"
    echo "   1. Review and update configuration in github-review-monitor.sh"
    echo "   2. Set up Obsidian dataview queries in your daily note template"
    echo "   3. Test notifications: $SCRIPT_DIR/github-review-monitor.sh --integration-only --notifications --dry-run"
    echo ""
    echo "📖 Full documentation: $SCRIPT_DIR/README.md"
}

main() {
    log "INFO" "Starting GitHub PR Review Notifier setup..."
    
    check_prerequisites
    make_executable
    setup_launchagents
    test_installation
    show_status
    
    log "INFO" "Setup completed successfully!"
}

# Run main function
main "$@"