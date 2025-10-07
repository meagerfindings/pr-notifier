# LaunchAgent Failure Investigation - Oct 7, 2025

## Problem Summary
Main review monitor (com.mat.github-review-monitor) was failing during automated runs at 7:51 AM, but worked perfectly when run manually.

## Root Cause: Missing Claude CLI in LaunchAgent PATH

**NOT** a file locking issue as suspected. The actual problem was:
1. Claude CLI installed in `/Users/mat/.npm-global/bin`
2. LaunchAgent PATH only included: `/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin`
3. Script couldn't find `claude` command → automated reviews failed
4. File write operations then failed cascading from the Claude CLI failure

## Evidence from Logs

### Failed Automated Runs (Sept 25 - Oct 6)
```
[2025-09-25 08:01:10] [WARN] claude CLI not found. Retrying in 1s (attempt 1/5)...
[2025-09-25 08:01:11] [WARN] claude CLI not found. Retrying in 2s (attempt 2/5)...
...
[2025-09-25 08:01:26] [ERROR] claude CLI not found. All 5 retry attempts exhausted.
[2025-09-25 08:01:26] [WARN] Automated review tool unavailable for PR #16588
...
[ERROR] Code Reviews file not readable after 10 attempts; aborting add
```

### Pattern
- **Every** automated run from Sept 25-Oct 6: Claude CLI not found
- **No** FolderSync conflicts detected
- **No** file locking issues detected
- Integration & Mentions monitors ran successfully (no Claude dependency)

## Solution Applied

### 1. Located Claude CLI
```bash
which claude
# → /Users/mat/.npm-global/bin/claude
```

### 2. Updated All Three LaunchAgent Plists
**Files updated:**
- `com.mat.github-review-monitor.plist`
- `com.mat.github-review-monitor-integration.plist`
- `com.mat.github-mentions-monitor.plist`

**New PATH:**
```xml
<string>/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
```

### 3. Reloaded LaunchAgents
```bash
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
# (repeated for integration and mentions monitors)
```

### 4. Verified
```bash
# Test with LaunchAgent's exact PATH
PATH="/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" which claude
# ✅ /Users/mat/.npm-global/bin/claude

# Verify services loaded
launchctl list | grep com.mat.github
# ✅ All three services showing as loaded
```

## File Permissions Analysis (No Issues Found)

### Code Reviews File
```bash
-rw-------@ mat:staff /Users/mat/Documents/Obsidian/CompanyCam Vault/Code Reviews.md
lrwxr-xr-x@ mat:staff /Users/mat/git/pr-notifier/Code Reviews.md → [Obsidian file]
```
- ✅ Correct ownership (mat:staff)
- ✅ Correct permissions (600)
- ✅ Symlink working properly
- ✅ Extended attributes present (com.apple.macl, com.apple.provenance)

## Schedule Confirmation

| Service | Schedule | Status |
|---------|----------|--------|
| Main Review Monitor | Daily at 7:51 AM | ✅ Fixed |
| Integration Monitor | Every 30 min, 8 AM-4 PM weekdays | ✅ Fixed |
| Mentions Monitor | Every 10 min, 8 AM-4 PM weekdays | ✅ Fixed |

## Testing Recommendations

### Wait for Tomorrow's Automated Run
Monitor `/tmp/github-review-monitor.log` at 7:51 AM on Oct 8, 2025:
```bash
tail -f /tmp/github-review-monitor.log
```

Look for:
- ✅ No "claude CLI not found" errors
- ✅ "Claude Code CLI completed successfully"
- ✅ "Added X new tasks to Code Reviews.md"

### Manual Test with LaunchAgent Environment
```bash
PATH="/Users/mat/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
HOME="/Users/mat" \
USER="mat" \
./github-review-monitor.sh --dry-run --verbose
```

## Lessons Learned

1. **PATH differences**: Interactive shell vs LaunchAgent environments have different PATHs
2. **Cascading failures**: Claude CLI failure → file write failure (misleading error message)
3. **Log analysis**: The real error was buried before the file access errors
4. **Testing approach**: Always test with the exact LaunchAgent environment variables

## Files Modified
- ✅ `/Users/mat/git/pr-notifier/com.mat.github-review-monitor.plist`
- ✅ `/Users/mat/git/pr-notifier/com.mat.github-review-monitor-integration.plist`
- ✅ `/Users/mat/git/pr-notifier/com.mat.github-mentions-monitor.plist`
- ✅ All copied to `~/Library/LaunchAgents/`
- ✅ All services reloaded

## Next Steps
1. Monitor tomorrow's 7:51 AM run (Oct 8)
2. Check for successful Claude CLI execution
3. Verify automated reviews are being generated
4. Confirm no file access errors
