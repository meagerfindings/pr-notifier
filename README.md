# GitHub PR Review Notifier

Automated GitHub pull request review monitoring and notification system that integrates with Obsidian for task management.

## Overview

This system automatically queries GitHub for code review tasks and personal mentions, providing:
- **Centralized task management** in Obsidian with priority-based organization
- **Real-time push notifications** via NTFY (optional)
- **Smart deduplication** to prevent notification fatigue
- **Configurable team and integration detection**
- **Personal mention monitoring** for immediate awareness when you're needed

## Quick Start

### Prerequisites

- macOS (for LaunchAgent scheduling)
- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- [jq](https://stedolan.github.io/jq/) for JSON processing
- [Obsidian](https://obsidian.md/) with the Tasks plugin (optional but recommended)

```bash
# Install prerequisites on macOS
brew install gh jq

# Authenticate with GitHub
gh auth login
```

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/pr-notifier.git
   cd pr-notifier
   ```

2. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

   The setup script will:
   - Check prerequisites
   - Create your `.env` configuration file from the template
   - Open your editor to configure settings
   - Generate LaunchAgent plist files with your paths
   - Optionally install and load LaunchAgents for automated scheduling

3. **Configure your settings** in `.env`:
   ```bash
   # Required settings
   GITHUB_REPO="your-org/your-repo"
   GITHUB_USER="your-github-username"
   OBSIDIAN_VAULT="/path/to/your/obsidian/vault"
   ```

4. **Test the installation:**
   ```bash
   ./github-review-monitor.sh --dry-run --verbose
   ```

## Configuration

All configuration is stored in `.env` (git-ignored). Copy `.env.example` to `.env` and customize:

### Required Settings

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_REPO` | GitHub repository to monitor | `your-org/your-repo` |
| `GITHUB_USER` | Your GitHub username | `octocat` |
| `OBSIDIAN_VAULT` | Path to your Obsidian vault | `/Users/you/Documents/Obsidian` |

### Optional Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `NTFY_SERVER` | NTFY server URL for push notifications | _(disabled)_ |
| `NTFY_TOPIC` | NTFY topic name | `code-reviews` |
| `TEAM_MEMBERS` | Comma-separated GitHub usernames for Integrations team | _(empty)_ |
| `RIFTWALKERS_TEAM_MEMBERS` | Comma-separated GitHub usernames for Riftwalkers team | _(empty)_ |
| `INTEGRATION_TEAM_SLUG` | GitHub team slug for integration reviews | _(empty)_ |
| `RIFTWALKERS_TEAM_SLUG` | GitHub team slug for Riftwalkers reviews | _(empty)_ |
| `BACKEND_TEAM_SLUG` | GitHub team slug for backend reviews | _(empty)_ |
| `PR_SIZE_THRESHOLD` | Min lines changed for automated review | `10` |
| `MAX_GENERAL_REVIEWS` | Max general reviews to add per run | `10` |
| `BUSINESS_HOURS_START` | Business hours start (24h) | `8` |
| `BUSINESS_HOURS_END` | Business hours end (24h) | `16` |

### Example Configuration

```bash
# .env
GITHUB_REPO="acme/api"
GITHUB_USER="jsmith"
OBSIDIAN_VAULT="/Users/jsmith/Documents/Obsidian/Work"

# Optional: Push notifications
NTFY_SERVER="ntfy.sh"
NTFY_TOPIC="my-code-reviews"

# Optional: Team configuration
TEAM_MEMBERS="alice,bob,charlie"
INTEGRATION_TEAM_SLUG="acme/integrations-team"
BACKEND_TEAM_SLUG="acme/backend-team"
```

## Features

### Task Categories & Priorities

| Category | Tag | Priority | Description |
|----------|-----|----------|-------------|
| Integration Reviews | `#integrations-review` | `#urgent-important` | PRs from integration team or matching criteria |
| Riftwalkers Reviews | `#riftwalkers-review` | `#urgent-important` | PRs from Riftwalkers team members |
| Follow-up Reviews | `#follow-up-review` | `#urgent-important` | PRs where you're mentioned |
| General Reviews | `#general-review` | `#not-urgent-important` | Backend team PRs + direct requests |

### Integration Detection

PRs are flagged as "integration" reviews when they match any of:
- Review requested from your integration team (if `INTEGRATION_TEAM_SLUG` is set)
- PR title contains `INT-` (JIRA ticket pattern)
- PR title contains "Integration" (case insensitive)
- PR author is in your `TEAM_MEMBERS` list

### Riftwalkers Detection

PRs are flagged as "riftwalkers" reviews when they match any of:
- Review requested from your Riftwalkers team (if `RIFTWALKERS_TEAM_SLUG` is set)
- PR author is in your `RIFTWALKERS_TEAM_MEMBERS` list

### Push Notifications (Optional)

If you configure `NTFY_SERVER`, you'll receive push notifications for:
- New integration PRs requiring review
- New Riftwalkers PRs requiring review
- Personal @mentions in PR comments
- Activity on your own PRs (comments, reviews)

[NTFY](https://ntfy.sh/) is a simple pub-sub notification service. You can use the public server at `ntfy.sh` or self-host.

## Usage

### Manual Commands

```bash
# Full review processing
./github-review-monitor.sh

# Preview changes without making modifications
./github-review-monitor.sh --dry-run --verbose

# Force update all task dates
./github-review-monitor.sh --force

# Integration-only check with notifications
./github-review-monitor.sh --integration-only --notifications

# Check for personal mentions
./github-mentions-monitor.sh

# Preview mentions without sending notifications
./github-mentions-monitor.sh --dry-run --verbose
```

### Automated Scheduling

The setup script creates LaunchAgents for automated scheduling:

| Agent | Schedule | Description |
|-------|----------|-------------|
| `github-review-monitor` | Daily at 7:51 AM | Full PR review processing |
| `github-review-monitor-integration` | Every 30 min | Integration alerts during business hours |
| `github-mentions-monitor` | Every 10 min | Personal mention monitoring |

#### Managing LaunchAgents

```bash
# Check status
launchctl list | grep github

# Stop automation
launchctl unload ~/Library/LaunchAgents/com.user.github-review-monitor.plist
launchctl unload ~/Library/LaunchAgents/com.user.github-review-monitor-integration.plist
launchctl unload ~/Library/LaunchAgents/com.user.github-mentions-monitor.plist

# Start automation
launchctl load ~/Library/LaunchAgents/com.user.github-review-monitor.plist
launchctl load ~/Library/LaunchAgents/com.user.github-review-monitor-integration.plist
launchctl load ~/Library/LaunchAgents/com.user.github-mentions-monitor.plist
```

## Obsidian Integration

### Central File

Tasks are managed in: `{OBSIDIAN_VAULT}/Code Reviews.md`

### Recommended Plugins

- **Tasks** - For task management and queries
- **Dataview** - For advanced queries (optional)

### Daily Note Template

Add these queries to your daily note template:

```markdown
#### Integration Team Code Reviews
```tasks
not done
description includes #code-review
description includes #integrations-review
hide tags
short mode
sort by created
```

#### Riftwalkers Team Code Reviews
```tasks
not done
description includes #code-review
description includes #riftwalkers-review
hide tags
short mode
sort by created
```

#### Follow-up Reviews
```tasks
not done
description includes #code-review
description includes #follow-up-review
hide tags
short mode
sort by created
```

#### General Code Reviews
```tasks
not done
description includes #code-review
description includes #not-urgent-important
description does not include #follow-up-review
description does not include #integrations-review
description does not include #riftwalkers-review
hide tags
short mode
sort by created
limit 10
```
```

## File Structure

```
pr-notifier/
├── .env.example                    # Configuration template
├── .env                            # Your configuration (git-ignored)
├── .gitignore                      # Git ignore rules
├── github-review-monitor.sh        # Main PR monitoring script
├── github-mentions-monitor.sh      # Personal mentions monitor
├── setup.sh                        # Interactive setup script
├── com.user.*.plist               # Generated LaunchAgent files
└── README.md                       # This file
```

## Logging & Troubleshooting

### Log Files

| File | Description |
|------|-------------|
| `/tmp/github-review-monitor.log` | Main activity log |
| `/tmp/github-review-monitor.out` | Daily execution stdout |
| `/tmp/github-review-monitor.err` | Daily execution stderr |
| `/tmp/github-review-monitor-integration.out` | Integration check stdout |
| `/tmp/github-review-monitor-integration.err` | Integration check stderr |
| `/tmp/github-mentions-monitor.out` | Mentions monitor stdout |
| `/tmp/github-mentions-monitor.err` | Mentions monitor stderr |
| `/tmp/github-review-monitor-notifications.log` | Notification dedup tracking |
| `/tmp/github-mentions-notifications.log` | Mentions notification tracking |

### Common Issues

1. **"Configuration file not found"**
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

2. **GitHub CLI not authenticated**
   ```bash
   gh auth login
   ```

3. **LaunchAgent not running**
   ```bash
   launchctl list | grep github
   # If not listed, reload:
   launchctl load ~/Library/LaunchAgents/com.user.github-review-monitor.plist
   ```

4. **Notifications not working**
   - Check `NTFY_SERVER` is set in `.env`
   - Verify the NTFY server is accessible
   - Check `/tmp/github-review-monitor.log` for errors

5. **Tasks not appearing in Obsidian**
   - Verify `OBSIDIAN_VAULT` path is correct
   - Check that `Code Reviews.md` exists in the vault
   - Ensure the Obsidian Tasks plugin is enabled

### Debug Mode

Run with `--verbose` for detailed logging:
```bash
./github-review-monitor.sh --dry-run --verbose
```

### Example Output

```
[INFO] Starting GitHub review processing for 2024-01-15...
[INFO] Processing summary: Integration PRs: 1, Riftwalkers PRs: 2, General PRs: 5, Total incomplete code reviews: 6, New code review tasks created: 3
```

## How It Works

1. **GitHub Queries**: Uses `gh` CLI to fetch open PRs and notifications
2. **Categorization**: Sorts PRs by team assignments, mentions, and involvement
3. **Task Creation**: Formats tasks with proper tags and dates for Obsidian
4. **Notification System**: Optional NTFY integration for real-time alerts
5. **Deduplication**: Prevents duplicate tasks and notifications

### Smart Review Detection

The system determines if a PR needs your review by checking:
- Whether you've already reviewed it
- If the PR was updated since your last review
- If there are unresolved comments mentioning you
- Team assignment and involvement criteria

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with a clear description

## License

MIT License - See LICENSE file for details.
