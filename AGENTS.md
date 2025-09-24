# PR Notifier Project - Agent Guidelines

## Build/Test/Lint Commands
- **Test scripts**: `./github-review-monitor.sh --dry-run --verbose` or `./github-mentions-monitor.sh --dry-run --verbose`
- **Setup**: `./setup.sh` (installs LaunchAgents and dependencies)
- **Prerequisites**: Requires `gh` CLI authenticated and `jq` installed
- **Test CLI failure**: `PATH="/usr/bin:/bin:/opt/homebrew/bin" ./github-review-monitor.sh --dry-run --verbose` (simulates Claude CLI unavailable)

## Architecture & Structure
- **Type**: Shell script-based GitHub automation system for macOS LaunchAgents
- **Core components**: 
  - `github-review-monitor.sh` - Main PR review fetcher/organizer
  - `github-mentions-monitor.sh` - Personal mention detector  
  - LaunchAgent plist files for automation scheduling
- **Integration**: Updates Obsidian vault markdown files and sends NTFY notifications
- **Data flow**: GitHub API → Shell processing → Obsidian tasks + NTFY alerts
- **External dependencies**: GitHub CLI (`gh`), `jq`, macOS LaunchAgents, NTFY server

## Code Style & Conventions  
- **Shell style**: Bash with `set -euo pipefail`, readonly vars, proper quoting
- **Error handling**: Log levels (ERROR/WARN/INFO/DEBUG), color-coded output
- **Configuration**: Hardcoded at top of scripts (REPO, OBSIDIAN_VAULT, etc)
- **Functions**: Modular design with clear single responsibilities
- **Logging**: All actions logged to `/tmp/` files with timestamps
- **Testing**: Use `--dry-run --verbose` flags for safe testing without side effects

## Automated Review Exit Code Contract
- **Exit 0**: At least one review successfully generated and saved; Obsidian file created with review link
- **Exit 2**: Claude CLI completely unavailable after retries; no Obsidian files created; regular tasks without review links
- **Exit 1**: Other errors (GitHub API, filesystem, invalid args); preserves existing error handling
- **Exponential backoff**: 5 retry attempts with delays of 1s, 2s, 4s, 8s when Claude CLI fails
