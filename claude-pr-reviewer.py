#!/usr/bin/env python3
"""
Claude PR Reviewer - Automated Code Review using Claude Code SDK
Integrates with the GitHub PR monitoring system to provide automated code reviews.
Author: Mat Greten
"""

import os
import sys
import json
import argparse
import subprocess
import signal
import time
import fcntl
from pathlib import Path
from datetime import datetime

# Configuration
REPO = "CompanyCam/Company-Cam-API"
OBSIDIAN_VAULT = "/Users/mat/git/Obsidian/CompanyCam Vault"
REVIEW_DIR = f"{OBSIDIAN_VAULT}/Code Reviews/automated-reviews"
LOCK_FILE = "/tmp/claude-pr-reviewer.lock"
CLAUDE_PROCESS_TIMEOUT = 120  # 2 minutes per attempt

# Exit codes
EXIT_SUCCESS = 0  # At least one review generated and saved
EXIT_OTHER_ERROR = 1  # Other errors (GitHub API, filesystem, etc.)
EXIT_TOOL_UNAVAILABLE = 2  # Claude CLI completely unavailable
EXIT_SKIPPED_SIZE = 3  # Skipped due to small PR size (below threshold)

def log(level, message):
    """Simple logging function"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [{level}] {message}")

def get_pr_diff_stats(pr_number):
    """Get PR diff statistics using GitHub CLI"""
    try:
        # Get the diff stats
        result = subprocess.run([
            "gh", "pr", "view", str(pr_number), 
            "--repo", REPO,
            "--json", "additions,deletions"
        ], capture_output=True, text=True, check=True)
        
        stats = json.loads(result.stdout)
        total_lines = stats.get("additions", 0) + stats.get("deletions", 0)
        
        log("DEBUG", f"PR #{pr_number}: {stats.get('additions', 0)} additions, {stats.get('deletions', 0)} deletions, {total_lines} total")
        return total_lines
        
    except subprocess.CalledProcessError as e:
        log("ERROR", f"Failed to get PR diff stats: {e}")
        return 0

def get_pr_details(pr_number):
    """Get PR details using GitHub CLI"""
    try:
        result = subprocess.run([
            "gh", "pr", "view", str(pr_number),
            "--repo", REPO,
            "--json", "number,title,author,url,body,reviewRequests"
        ], capture_output=True, text=True, check=True)
        
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        log("ERROR", f"Failed to get PR details: {e}")
        return None

def get_pr_files(pr_number):
    """Get PR file changes using GitHub CLI"""
    try:
        result = subprocess.run([
            "gh", "pr", "diff", str(pr_number),
            "--repo", REPO
        ], capture_output=True, text=True, check=True)
        
        return result.stdout
    except subprocess.CalledProcessError as e:
        log("ERROR", f"Failed to get PR diff: {e}")
        return None


def kill_process_group(process):
    """Kill an entire process group to ensure no orphaned children"""
    if process is None:
        return
    try:
        # Get the process group ID (same as PID when start_new_session=True)
        pgid = os.getpgid(process.pid)
        log("DEBUG", f"Killing process group {pgid}")
        os.killpg(pgid, signal.SIGTERM)
        # Give processes a moment to terminate gracefully
        time.sleep(0.5)
        # Force kill if still running
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass  # Already dead
    except ProcessLookupError:
        pass  # Process already dead
    except Exception as e:
        log("WARN", f"Error killing process group: {e}")


def call_claude_code_cli(prompt, additional_context=""):
    """Call Claude Code CLI for code review with exponential backoff retry.

    Uses process groups to ensure proper cleanup of all child processes
    on timeout or error.
    """
    max_retries = 5
    base_delay = 1  # Start with 1 second

    for attempt in range(max_retries):
        process = None
        try:
            # Check if claude is available
            subprocess.run(["claude", "--version"], capture_output=True, check=True)

            # Call claude directly with the prompt using -p flag
            # Limit tools to Read only for security - we just want analysis, not file changes
            # Use start_new_session=True to create a new process group for proper cleanup
            process = subprocess.Popen(
                [
                    "claude",
                    "-p", prompt,
                    "--allowedTools", "Read",
                    "--model", "haiku"
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True  # Creates new process group for clean termination
            )

            try:
                stdout, stderr = process.communicate(timeout=CLAUDE_PROCESS_TIMEOUT)
            except subprocess.TimeoutExpired:
                log("WARN", f"Claude process timed out after {CLAUDE_PROCESS_TIMEOUT}s, killing process group...")
                kill_process_group(process)
                process.wait()  # Reap the zombie
                raise

            if process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, "claude", stderr=stderr)

            if stdout.strip():
                if attempt > 0:
                    log("INFO", f"Claude Code CLI succeeded on attempt {attempt + 1}/{max_retries}")
                else:
                    log("DEBUG", "Claude Code CLI completed successfully")
                return stdout.strip()
            else:
                log("WARN", f"Claude Code CLI returned empty response on attempt {attempt + 1}/{max_retries}")
                if attempt == max_retries - 1:  # Last attempt
                    return None

        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            error_msg = "claude CLI not found" if isinstance(e, FileNotFoundError) else f"claude CLI failed with exit code {e.returncode}"

            # Ensure cleanup on error
            if process is not None:
                kill_process_group(process)

            if attempt == max_retries - 1:  # Last attempt
                log("ERROR", f"{error_msg}. All {max_retries} retry attempts exhausted.")
                if hasattr(e, 'stderr') and e.stderr:
                    log("ERROR", f"Final stderr: {e.stderr}")
                return None
            else:
                # Calculate exponential backoff delay: 2^attempt seconds
                delay = base_delay * (2 ** attempt)
                log("WARN", f"{error_msg}. Retrying in {delay}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(delay)

        except subprocess.TimeoutExpired:
            # Process group already killed above, just handle retry logic
            if attempt == max_retries - 1:  # Last attempt
                log("ERROR", f"Claude Code CLI timed out after {CLAUDE_PROCESS_TIMEOUT}s. All {max_retries} retry attempts exhausted.")
                return None
            else:
                delay = base_delay * (2 ** attempt)
                log("WARN", f"Claude Code CLI timed out. Retrying in {delay}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(delay)

        except Exception as e:
            # Ensure cleanup on any error
            if process is not None:
                kill_process_group(process)

            if attempt == max_retries - 1:  # Last attempt
                log("ERROR", f"Error calling Claude Code CLI: {e}. All {max_retries} retry attempts exhausted.")
                return None
            else:
                delay = base_delay * (2 ** attempt)
                log("WARN", f"Error calling Claude Code CLI: {e}. Retrying in {delay}s (attempt {attempt + 1}/{max_retries})...")
                time.sleep(delay)

    # This shouldn't be reached, but just in case
    return None

def generate_review_content(pr_details, diff_content):
    """Generate the review content using Claude

    Returns:
        tuple: (review_content, has_successful_reviews)
        - review_content: Complete markdown content if review succeeded, None otherwise
        - has_successful_reviews: True if review was generated successfully
    """
    pr_number = pr_details.get("number")
    title = pr_details.get("title", "")
    author = pr_details.get("author", {}).get("login", "")
    url = pr_details.get("url", "")
    body = pr_details.get("body", "")

    # Create the review prompt
    review_prompt = f"""Please review this Pull Request:

Title: {title}
Author: {author}
Description: {body}

Code changes:
{diff_content}

Please provide a thorough code review covering:
- Code quality and best practices
- Potential bugs or issues
- Security considerations
- Performance implications
- Suggestions for improvement

Format your response as a detailed markdown code review."""

    # Get review from Claude Code CLI
    log("INFO", f"Generating code review for PR #{pr_number}")
    review = call_claude_code_cli(review_prompt, "")

    if not review:
        log("ERROR", "Review could not be generated - Claude CLI unavailable")
        return None, False

    log("DEBUG", "Code review generated successfully")

    # Generate markdown content
    content = f"""# PR #{pr_number}: {title}

## GitHub Links
- [View PR]({url})
- [View Files]({url}/files)

## Code Review (Claude Haiku)

{review}

## Conversational Context for Claude

<details>
<summary>💬 Copy this code block to continue the review in a new Claude session</summary>

```
I'd like to continue reviewing PR #{pr_number}: {title}
Author: {author}
PR URL: {url}

PR Description:
{body if body else "No description provided"}

Please fetch the latest diff for this PR using:
gh pr diff {pr_number} --repo CompanyCam/Company-Cam-API

Then continue with the code review discussion.
```

</details>

---
*Automated review generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*
*Author: {author}*
"""

    return content, True

def save_review_to_obsidian(pr_number, content):
    """Save the review content to Obsidian vault"""
    try:
        # Ensure the review directory exists
        os.makedirs(REVIEW_DIR, exist_ok=True)
        
        # Create the review file
        review_file = f"{REVIEW_DIR}/PR-{pr_number}-review.md"
        
        with open(review_file, 'w') as f:
            f.write(content)
        
        log("INFO", f"Saved review to: {review_file}")
        return review_file
        
    except Exception as e:
        log("ERROR", f"Failed to save review: {e}")
        return None

def acquire_lock():
    """Acquire an exclusive lock to prevent concurrent runs.

    Returns the lock file handle if successful, None if another instance is running.
    """
    try:
        lock_fd = open(LOCK_FILE, 'w')
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Write PID for debugging
        lock_fd.write(str(os.getpid()))
        lock_fd.flush()
        log("DEBUG", f"Acquired lock (PID {os.getpid()})")
        return lock_fd
    except (IOError, OSError) as e:
        if e.errno in (11, 35):  # EAGAIN or EWOULDBLOCK
            log("WARN", "Another instance is already running, exiting")
            return None
        raise


def release_lock(lock_fd):
    """Release the exclusive lock"""
    if lock_fd:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            lock_fd.close()
            os.unlink(LOCK_FILE)
            log("DEBUG", "Released lock")
        except Exception as e:
            log("WARN", f"Error releasing lock: {e}")


def main():
    parser = argparse.ArgumentParser(description="Generate automated code reviews for GitHub PRs")
    parser.add_argument("pr_number", type=int, help="GitHub PR number")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without making changes")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")

    args = parser.parse_args()

    if args.verbose:
        log("DEBUG", f"Starting review for PR #{args.pr_number}")

    # Acquire lock to prevent concurrent runs
    lock_fd = acquire_lock()
    if lock_fd is None:
        return EXIT_OTHER_ERROR  # Another instance running

    try:
        return _main_impl(args)
    finally:
        release_lock(lock_fd)


def _main_impl(args):
    """Main implementation, called after lock is acquired"""
    if args.verbose:
        log("DEBUG", f"Processing review for PR #{args.pr_number}")
    
    # Get PR details
    pr_details = get_pr_details(args.pr_number)
    if not pr_details:
        log("ERROR", f"Could not retrieve PR #{args.pr_number}")
        return 1
    
    # Check line count threshold
    line_count = get_pr_diff_stats(args.pr_number)
    if line_count < 10:
        log("INFO", f"Skipping review for PR #{args.pr_number} ({line_count} lines - below threshold)")
        return EXIT_SKIPPED_SIZE

    # Get PR diff
    diff_content = get_pr_files(args.pr_number)
    if not diff_content:
        log("ERROR", f"Could not retrieve diff for PR #{args.pr_number}")
        return 1

    if args.dry_run:
        log("INFO", f"DRY RUN: Would generate review for PR #{args.pr_number}")
        log("INFO", f"DRY RUN: PR has {line_count} lines of changes")
        return 0

    # Generate review content
    log("INFO", f"Generating code review for PR #{args.pr_number}")
    review_content, has_successful_reviews = generate_review_content(pr_details, diff_content)
    
    # If no successful reviews were generated, exit with tool unavailable code
    if not has_successful_reviews:
        log("ERROR", "No automated reviews could be generated - exiting without creating files")
        return EXIT_TOOL_UNAVAILABLE
    
    # Save to Obsidian
    review_file = save_review_to_obsidian(args.pr_number, review_content)
    if review_file:
        log("INFO", f"Review completed and saved: {review_file}")
        # Output the file path for the shell script to use (backward compatibility)
        print(review_file)
        return EXIT_SUCCESS
    else:
        log("ERROR", "Failed to save review")
        return EXIT_OTHER_ERROR

if __name__ == "__main__":
    sys.exit(main())
