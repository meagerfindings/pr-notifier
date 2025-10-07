# LaunchAgent Configuration Summary

## Overview
All three GitHub monitoring scripts are configured and running as macOS LaunchAgents with the correct PATH environment.

## Configured Services

### 1. Main Review Monitor (`com.mat.github-review-monitor`)
**Script:** `github-review-monitor.sh`  
**Schedule:** Daily at 7:51 AM  
**Purpose:** Fetch all code reviews (integration, general, follow-ups, my PRs) and update Code Reviews.md  
**Dependencies:**
- ✅ `gh` (GitHub CLI) - `/opt/homebrew/bin/gh`
- ✅ `jq` - `/opt/homebrew/bin/jq`
- ✅ `curl` - `/usr/bin/curl`
- ✅ `claude` (Claude CLI) - `/Users/mat/.npm-global/bin/claude` ⚠️ **Required in PATH**
- ✅ `python3` - `/opt/homebrew/bin/python3`

**Logs:**
- Stdout: `/tmp/github-review-monitor.out`
- Stderr: `/tmp/github-review-monitor.err`
- Script log: `/tmp/github-review-monitor.log`

**PATH:** `/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` ✅

---

### 2. Integration Review Monitor (`com.mat.github-review-monitor-integration`)
**Script:** `github-review-monitor.sh --integration-only`  
**Schedule:** Every 30 minutes, 8 AM - 4 PM, Monday-Friday  
**Purpose:** Quick check for new integration team PRs requiring review, sends NTFY notifications  
**Dependencies:**
- ✅ `gh` (GitHub CLI) - `/opt/homebrew/bin/gh`
- ✅ `jq` - `/opt/homebrew/bin/jq`
- ✅ `curl` - `/usr/bin/curl`
- ✅ `claude` (Claude CLI) - `/Users/mat/.npm-global/bin/claude` ⚠️ **Required in PATH**

**Logs:**
- Stdout: `/tmp/github-review-monitor-integration.out`
- Stderr: `/tmp/github-review-monitor-integration.err`
- Script log: `/tmp/github-review-monitor.log` (shared with main monitor)

**PATH:** `/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` ✅

**Scheduled Times (Weekdays):**
- 8:00, 8:30, 9:00, 9:30, 10:00, 10:30, 11:00, 11:30
- 12:00, 12:30, 13:00, 13:30, 14:00, 14:30, 15:00, 15:30, 16:00

---

### 3. Mentions Monitor (`com.mat.github-mentions-monitor`)
**Script:** `github-mentions-monitor.sh`  
**Schedule:** Every 10 minutes, 8 AM - 4 PM, Monday-Friday  
**Purpose:** Detect personal @mentions in GitHub and send NTFY notifications  
**Dependencies:**
- ✅ `gh` (GitHub CLI) - `/opt/homebrew/bin/gh`
- ✅ `jq` - `/opt/homebrew/bin/jq`
- ✅ `curl` - `/usr/bin/curl`
- ❌ Does NOT need `claude` CLI

**Logs:**
- Stdout: `/tmp/github-mentions-monitor.out`
- Stderr: `/tmp/github-mentions-monitor.err`
- Script log: `/tmp/github-mentions-monitor.log`
- Notifications tracking: `/tmp/github-mentions-notifications.log`

**PATH:** `/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` ✅

**Scheduled Times (Weekdays):**
- Every 10 minutes from 8:00 AM to 4:00 PM

---

## Critical PATH Configuration

All three services now include `/Users/mat/.npm-global/bin` in their PATH to ensure Claude CLI is accessible:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/mat</string>
    <key>USER</key>
    <string>mat</string>
</dict>
```

### Why This Matters
- Main & Integration monitors use Claude CLI for automated code reviews
- Claude CLI is installed in `~/.npm-global/bin`
- LaunchAgents don't inherit your shell's PATH
- Without this PATH configuration, the scripts would fail with "claude CLI not found"

---

## Testing Commands

### Test with LaunchAgent Environment
```bash
# Test Mentions Monitor
PATH="/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
HOME="/Users/mat" \
USER="mat" \
./github-mentions-monitor.sh --dry-run --verbose

# Test Integration Monitor
PATH="/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
HOME="/Users/mat" \
USER="mat" \
./github-review-monitor.sh --integration-only --dry-run --verbose

# Test Main Review Monitor
PATH="/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
HOME="/Users/mat" \
USER="mat" \
./github-review-monitor.sh --dry-run --verbose
```

### Check Service Status
```bash
# List all running services
launchctl list | grep com.mat.github

# Check service details
launchctl list com.mat.github-review-monitor
launchctl list com.mat.github-review-monitor-integration
launchctl list com.mat.github-mentions-monitor
```

### Reload Services After Changes
```bash
# Reload main review monitor
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist

# Reload integration monitor
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist

# Reload mentions monitor
launchctl unload ~/Library/LaunchAgents/com.mat.github-mentions-monitor.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-mentions-monitor.plist
```

---

## Monitoring & Debugging

### Real-time Log Monitoring
```bash
# Watch main review monitor
tail -f /tmp/github-review-monitor.log

# Watch integration monitor (same log file)
tail -f /tmp/github-review-monitor.log

# Watch mentions monitor
tail -f /tmp/github-mentions-monitor.log

# Watch all errors
tail -f /tmp/github-*-monitor.err
```

### Check Recent Runs
```bash
# Last 50 lines of main review monitor
tail -50 /tmp/github-review-monitor.log

# Check for errors
grep -i error /tmp/github-review-monitor.err

# Check for Claude CLI issues
grep -i "claude" /tmp/github-review-monitor.log | tail -20
```

---

## Verification Checklist

- ✅ All three plist files have correct PATH including `/Users/mat/.npm-global/bin`
- ✅ All three services are loaded in launchctl
- ✅ All dependencies are in the configured PATH
- ✅ Claude CLI accessible at `/Users/mat/.npm-global/bin/claude`
- ✅ Scripts tested successfully with LaunchAgent environment
- ✅ Log files created and writable

---

## Next Monitoring Points

### Tomorrow Morning (Oct 8, 7:51 AM)
Watch for the main review monitor's automated run:
```bash
tail -f /tmp/github-review-monitor.log
```

**Expected success indicators:**
- No "claude CLI not found" errors
- "Claude Code CLI completed successfully" messages
- "Added X new tasks to Code Reviews.md"
- No "Code Reviews file not readable" errors

### Throughout Today
Integration & mentions monitors are running every 30 and 10 minutes respectively:
```bash
# Watch for activity
tail -f /tmp/github-review-monitor.log /tmp/github-mentions-monitor.log
```

---

## Common Issues & Solutions

### Issue: "command not found" errors
**Solution:** Check that the command is in one of the PATH directories and update the plist if needed.

### Issue: Service not running
**Solution:** 
```bash
launchctl list | grep com.mat.github-review-monitor
# If not listed, reload:
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
```

### Issue: Permission denied
**Solution:** Check file permissions:
```bash
ls -la /Users/mat/git/pr-notifier/*.sh
chmod +x /Users/mat/git/pr-notifier/*.sh
```

### Issue: New dependency needed
**Solution:**
1. Find where the tool is installed: `which <toolname>`
2. If it's not in the current PATH, add its directory to the plist
3. Reload the service
