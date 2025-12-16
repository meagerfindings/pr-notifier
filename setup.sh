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

setup_config() {
    log "INFO" "Setting up configuration..."

    local env_file="$SCRIPT_DIR/.env"
    local example_file="$SCRIPT_DIR/.env.example"

    if [[ -f "$env_file" ]]; then
        log "WARN" "Configuration file already exists: $env_file"
        read -p "Do you want to overwrite it? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "INFO" "Keeping existing configuration"
            return
        fi
    fi

    if [[ ! -f "$example_file" ]]; then
        log "ERROR" "Example configuration file not found: $example_file"
        exit 1
    fi

    cp "$example_file" "$env_file"
    log "INFO" "Created configuration file: $env_file"

    echo ""
    log "INFO" "Please edit $env_file with your settings:"
    echo "   - GITHUB_REPO: Your GitHub repository (e.g., your-org/your-repo)"
    echo "   - GITHUB_USER: Your GitHub username"
    echo "   - OBSIDIAN_VAULT: Path to your Obsidian vault"
    echo ""
    log "INFO" "Optional settings:"
    echo "   - NTFY_SERVER: Your NTFY server for push notifications"
    echo "   - TEAM_MEMBERS: Comma-separated list of team member usernames"
    echo ""

    read -p "Would you like to edit the configuration now? (Y/n): " response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        ${EDITOR:-nano} "$env_file"
    fi
}

make_executable() {
    log "INFO" "Making scripts executable..."
    chmod +x "$SCRIPT_DIR/github-review-monitor.sh"
    chmod +x "$SCRIPT_DIR/github-mentions-monitor.sh"
}

generate_launchagent_plists() {
    log "INFO" "Generating LaunchAgent plist files..."

    # Source the .env to get user's HOME
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        source "$SCRIPT_DIR/.env"
    fi

    local user_home="${HOME}"
    local username="${USER}"

    # Generate daily review monitor plist
    cat > "$SCRIPT_DIR/com.user.github-review-monitor.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.github-review-monitor</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/github-review-monitor.sh</string>
    </array>

    <!-- Schedule for daily at 7:51 AM -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>51</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/github-review-monitor.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/github-review-monitor.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$user_home</string>
        <key>USER</key>
        <string>$username</string>
    </dict>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    # Generate integration monitor plist (runs every 30 min during business hours)
    cat > "$SCRIPT_DIR/com.user.github-review-monitor-integration.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.github-review-monitor-integration</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/github-review-monitor.sh</string>
        <string>--integration-only</string>
        <string>--notifications</string>
    </array>

    <!-- Run every 30 minutes during business hours -->
    <key>StartInterval</key>
    <integer>1800</integer>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$user_home</string>
        <key>USER</key>
        <string>$username</string>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/github-review-monitor-integration.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/github-review-monitor-integration.err</string>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    # Generate mentions monitor plist (runs every 10 min during business hours)
    cat > "$SCRIPT_DIR/com.user.github-mentions-monitor.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.github-mentions-monitor</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/github-mentions-monitor.sh</string>
    </array>

    <!-- Run every 10 minutes -->
    <key>StartInterval</key>
    <integer>600</integer>

    <key>StandardOutPath</key>
    <string>/tmp/github-mentions-monitor.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/github-mentions-monitor.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$user_home</string>
        <key>USER</key>
        <string>$username</string>
    </dict>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    log "INFO" "Generated LaunchAgent plist files"
}

setup_launchagents() {
    log "INFO" "Setting up LaunchAgents..."

    # Unload existing agents if they exist
    for agent in "github-review-monitor" "github-review-monitor-integration" "github-mentions-monitor"; do
        if launchctl list 2>/dev/null | grep -q "com.user.$agent"; then
            log "INFO" "Unloading existing $agent..."
            launchctl unload ~/Library/LaunchAgents/com.user.$agent.plist 2>/dev/null || true
        fi
        # Also check for old com.mat.* agents
        if launchctl list 2>/dev/null | grep -q "com.mat.$agent"; then
            log "INFO" "Unloading old com.mat.$agent..."
            launchctl unload ~/Library/LaunchAgents/com.mat.$agent.plist 2>/dev/null || true
        fi
    done

    # Copy LaunchAgent files
    cp "$SCRIPT_DIR/com.user.github-review-monitor.plist" ~/Library/LaunchAgents/
    cp "$SCRIPT_DIR/com.user.github-review-monitor-integration.plist" ~/Library/LaunchAgents/
    cp "$SCRIPT_DIR/com.user.github-mentions-monitor.plist" ~/Library/LaunchAgents/

    # Load LaunchAgents
    launchctl load ~/Library/LaunchAgents/com.user.github-review-monitor.plist
    launchctl load ~/Library/LaunchAgents/com.user.github-review-monitor-integration.plist
    launchctl load ~/Library/LaunchAgents/com.user.github-mentions-monitor.plist

    log "INFO" "LaunchAgents installed and loaded"
}

test_installation() {
    log "INFO" "Testing installation..."

    # Check if .env exists
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log "ERROR" "Configuration file not found. Please run setup again."
        exit 1
    fi

    # Test the script
    if "$SCRIPT_DIR/github-review-monitor.sh" --help > /dev/null 2>&1; then
        log "INFO" "Review monitor script test passed"
    else
        log "ERROR" "Review monitor script test failed"
        exit 1
    fi

    if "$SCRIPT_DIR/github-mentions-monitor.sh" --help > /dev/null 2>&1; then
        log "INFO" "Mentions monitor script test passed"
    else
        log "ERROR" "Mentions monitor script test failed"
        exit 1
    fi

    # Check LaunchAgents are loaded
    if launchctl list 2>/dev/null | grep -q "com.user.github-review-monitor"; then
        log "INFO" "LaunchAgents test passed"
    else
        log "WARN" "LaunchAgents may not be loaded (this is normal if you skipped that step)"
    fi
}

show_status() {
    log "INFO" "Installation complete! Status:"
    echo ""
    echo "Configuration: $SCRIPT_DIR/.env"
    echo "Scripts:"
    echo "   $SCRIPT_DIR/github-review-monitor.sh"
    echo "   $SCRIPT_DIR/github-mentions-monitor.sh"
    echo ""
    echo "LaunchAgents:"
    launchctl list 2>/dev/null | grep "github-" | while read -r line; do
        echo "   $line"
    done || echo "   (none loaded)"
    echo ""
    echo "Next steps:"
    echo "   1. Edit $SCRIPT_DIR/.env with your configuration"
    echo "   2. Test manually: $SCRIPT_DIR/github-review-monitor.sh --dry-run --verbose"
    echo "   3. Set up Obsidian dataview queries (see README.md)"
    echo ""
    echo "For push notifications, configure NTFY_SERVER in .env"
    echo ""
    echo "Full documentation: $SCRIPT_DIR/README.md"
}

main() {
    log "INFO" "Starting GitHub PR Review Notifier setup..."

    check_prerequisites
    setup_config
    make_executable
    generate_launchagent_plists

    echo ""
    read -p "Would you like to install and load LaunchAgents for automated scheduling? (Y/n): " response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        setup_launchagents
    else
        log "INFO" "Skipping LaunchAgent installation. You can run scripts manually."
    fi

    test_installation
    show_status

    log "INFO" "Setup completed successfully!"
}

# Run main function
main "$@"
