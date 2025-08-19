# GitHub PR Review Notifier

Automated GitHub pull request review monitoring and notification system for CompanyCam API repository.

## Overview

This system automatically queries GitHub for code review tasks and provides:
- **Centralized task management** in Obsidian with priority-based organization
- **Real-time NTFY notifications** for urgent integration reviews
- **Smart deduplication** to prevent notification fatigue
- **Enhanced integration detection** using multiple criteria

## Philosophy: "Pay It Forward" Leadership

Tasks are prioritized to **unblock team members first**, then handle your own work:
1. **Integration Team Reviews** - Domain expertise responsibility 
2. **Follow-up Reviews** - Complete commitments to other developers
3. **General Code Reviews** - Broader team contribution (limited to 10/day)
4. **My PRs** - Handle your own work when you can focus deeply

## Features

### 🔄 Automated Scheduling
- **Daily full processing**: Monday-Friday at 7:50 AM MST
- **Half-hourly integration alerts**: Every 30 minutes, 8 AM - 4 PM weekdays

### 📱 Smart Notifications
- **NTFY push notifications** to `ntfy.tail001dd.ts.net/code-reviews`
- **Priority levels**: Integration reviews marked as "high" priority
- **Rich content**: Includes PR title, author, number, and direct link
- **Deduplication**: Only notifies once per PR per day

### 🎯 Enhanced Integration Detection
- PRs requesting `@CompanyCam/integrations-engineers` team review
- PRs with `INT-` JIRA tickets in title (case insensitive)
- PRs with "Integration" anywhere in title
- PRs authored by integration team members

### 📋 Task Categories & Tags
| Category | Tag | Priority | Description |
|----------|-----|----------|-------------|
| Integration Reviews | `#integrations-review` | #urgent-important | Integration team PRs |
| Follow-up Reviews | `#follow-up-review` | #urgent-important | PRs where you're mentioned |
| General Reviews | `#general-review` | #not-urgent-important | Backend team PRs (max 10) |
| My PRs | `#my-pr` | #urgent-important | Your open PRs needing attention |

## Installation

### Prerequisites
- GitHub CLI (`gh`) installed and authenticated
- `jq` for JSON processing
- Access to `ntfy.tail001dd.ts.net` for notifications
- Obsidian with dataview plugin

### Setup
1. Clone this repository to `~/git/pr-notifier`
2. Make the script executable: `chmod +x github-review-monitor.sh`
3. Install LaunchAgents: `cp *.plist ~/Library/LaunchAgents/`
4. Load the automation: 
   ```bash
   launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
   launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist
   ```

### Configuration
Update the following variables in `github-review-monitor.sh`:
- `REPO`: GitHub repository (default: "CompanyCam/Company-Cam-API")
- `OBSIDIAN_VAULT`: Path to your Obsidian vault
- `GITHUB_USER`: Your GitHub username
- `INTEGRATION_TEAM_MEMBERS`: Array of integration team GitHub usernames
- `NTFY_SERVER`: NTFY server URL (default: "ntfy.tail001dd.ts.net")
- `NTFY_TOPIC`: NTFY topic (default: "code-reviews")

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

# Show help
./github-review-monitor.sh --help
```

### LaunchAgent Management
```bash
# Check status
launchctl list | grep github-review-monitor

# Stop automation
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist

# Start automation
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist
```

## File Structure

```
pr-notifier/
├── github-review-monitor.sh                      # Main script
├── com.mat.github-review-monitor.plist          # Daily review LaunchAgent
├── com.mat.github-review-monitor-integration.plist # Integration alerts LaunchAgent
├── README.md                                     # This file
└── setup.sh                                     # Installation script (optional)
```

## Integration with Obsidian

### Central File
Tasks are managed in: `{OBSIDIAN_VAULT}/Code Reviews.md`

### Daily Note Template
Add these dataview queries to your daily note template:

```markdown
#### ⚙️ Integration Team Code Reviews
\`\`\`tasks
not done
description includes #code-review
description includes #integrations-review
description does not include #sensitive
hide tags
short mode
sort by created
\`\`\`

#### 👥 Follow-up Reviews
\`\`\`tasks
not done  
description includes #code-review
description includes #follow-up-review
description does not include #sensitive
hide tags
short mode
sort by created
\`\`\`

#### 📋 General Code Reviews
\`\`\`tasks
not done
description includes #code-review
description includes #not-urgent-important
description does not include #follow-up-review
description does not include #integrations-review
description does not include #my-pr
description does not include #sensitive
hide tags
short mode
sort by created
limit 10
\`\`\`

#### 🚀 My Pull Requests Needing Attention
\`\`\`tasks
not done
description includes #code-review
description includes #my-pr
description does not include #sensitive
hide tags
short mode
sort by created
\`\`\`
```

## Logging

- **Activity logs**: `/tmp/github-review-monitor.log`
- **Daily execution**: `/tmp/github-review-monitor.out` and `.err`
- **Integration checks**: `/tmp/github-review-monitor-integration.out` and `.err`
- **Notification tracking**: `/tmp/github-review-monitor-notifications.log`

## Troubleshooting

### Common Issues
1. **GitHub CLI not authenticated**: Run `gh auth login`
2. **LaunchAgent not running**: Check with `launchctl list | grep github-review-monitor`
3. **Notifications not working**: Verify NTFY server accessibility
4. **Tasks not appearing**: Check Obsidian dataview plugin is enabled

### Debug Mode
Run with `--verbose` flag for detailed logging:
```bash
./github-review-monitor.sh --integration-only --notifications --verbose
```

## Architecture

### Core Components
1. **GitHub Queries**: Uses `gh` CLI to fetch PRs from GitHub
2. **Categorization**: Sorts PRs by team assignments and involvement
3. **Task Creation**: Formats as Obsidian tasks with proper tags and dates
4. **Notification System**: NTFY integration for real-time alerts
5. **Deduplication**: Prevents duplicate tasks and notifications

### Smart Review Detection
The system determines if a PR needs your review by checking:
- Whether you've already reviewed it
- If the PR was updated since your last review
- If there are unresolved comments mentioning you
- Integration team assignment and involvement criteria

## Contributing

This is a personal productivity tool. Contributions welcome via:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

## License

Private repository - internal use only.