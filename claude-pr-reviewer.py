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
from pathlib import Path
from datetime import datetime

# Configuration
REPO = "CompanyCam/Company-Cam-API"
OBSIDIAN_VAULT = "/Users/mat/Documents/Obsidian/CompanyCam Vault"
REVIEW_DIR = f"{OBSIDIAN_VAULT}/Code Reviews/automated-reviews"
INTEGRATION_TEAM_MEMBERS = ["groovestation31785", "xrgloria", "rotondozer", "jarhartman"]

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
            "--json", "title,author,url,body,reviewRequests"
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

def is_integration_pr(pr_details):
    """Determine if PR is an integration PR based on existing logic"""
    title = pr_details.get("title", "")
    author = pr_details.get("author", {}).get("login", "")
    
    # Check integration criteria
    if "INT-" in title:
        return True
    if "integration" in title.lower():
        return True
    if author in INTEGRATION_TEAM_MEMBERS:
        return True
    
    # Check for integration team review request
    review_requests = pr_details.get("reviewRequests", [])
    for request in review_requests:
        if (request.get("__typename") == "Team" and 
            request.get("slug") == "CompanyCam/integrations-engineers"):
            return True
    
    return False

def call_claude_code_cli(prompt, additional_context=""):
    """Call Claude Code CLI for code review"""
    try:
        # Check if claude is available
        subprocess.run(["claude", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        log("ERROR", "claude CLI not found. Please install Claude Code.")
        return None
    
    try:
        # Call claude directly with the prompt using -p flag
        # Limit tools to Read only for security - we just want analysis, not file changes
        result = subprocess.run([
            "claude", 
            "-p", prompt,
            "--allowedTools", "Read"
        ], capture_output=True, text=True, check=True, timeout=120)  # 2 minute timeout
        
        if result.stdout.strip():
            log("DEBUG", "Claude Code CLI completed successfully")
            return result.stdout.strip()
        else:
            log("WARN", "Claude Code CLI returned empty response")
            return None
        
    except subprocess.TimeoutExpired:
        log("ERROR", "Claude Code CLI timed out after 2 minutes")
        return None
    except subprocess.CalledProcessError as e:
        log("ERROR", f"Claude Code CLI failed with exit code {e.returncode}")
        if e.stderr:
            log("ERROR", f"Stderr: {e.stderr}")
        return None
    except Exception as e:
        log("ERROR", f"Error calling Claude Code CLI: {e}")
        return None

def generate_review_content(pr_details, diff_content, is_integration):
    """Generate the review content using Claude"""
    pr_number = pr_details.get("number")
    title = pr_details.get("title", "")
    author = pr_details.get("author", {}).get("login", "")
    url = pr_details.get("url", "")
    body = pr_details.get("body", "")
    
    # Create the general review prompt
    general_prompt = f"""Please review this Pull Request:

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

    # Get general review from Claude Code CLI
    log("INFO", f"Generating general review for PR #{pr_number}")
    general_review = call_claude_code_cli(general_prompt, "")
    if not general_review:
        general_review = "Review generation failed - Claude Code CLI unavailable"
    
    # If integration PR, get specialized review
    integration_review = None
    if is_integration:
        integration_prompt = f"""Please review this Pull Request with a focus on integration expertise:

Title: {title}
Author: {author}
Description: {body}

Code changes:
{diff_content}

Please provide an integration-specific analysis covering:
- Integration patterns and practices
- API design considerations
- Data flow and transformation logic
- Third-party service interactions
- Error handling for external dependencies
- Monitoring and observability considerations
- Compatibility with existing integrations

Format your response as a detailed markdown integration analysis."""

        log("INFO", f"Generating integration review for PR #{pr_number}")
        integration_review = call_claude_code_cli(integration_prompt, "")
        if not integration_review:
            integration_review = "Integration review generation failed - Claude Code CLI unavailable"
    
    # Generate markdown content
    content = f"""# PR #{pr_number}: {title}

## GitHub Links
- [View PR]({url})
- [View Files]({url}/files)

## General Code Review (Claude Sonnet)

{general_review}

"""
    
    if integration_review:
        content += f"""## Integration Expert Analysis

{integration_review}

## Combined Assessment

This PR requires both general code review and integration expertise. Please review both analyses above when making your decision.

"""
    
    content += f"""---
*Automated review generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*
*Author: {author}*
"""
    
    return content

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

def main():
    parser = argparse.ArgumentParser(description="Generate automated code reviews for GitHub PRs")
    parser.add_argument("pr_number", type=int, help="GitHub PR number")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without making changes")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    
    args = parser.parse_args()
    
    if args.verbose:
        log("DEBUG", f"Starting review for PR #{args.pr_number}")
    
    # Get PR details
    pr_details = get_pr_details(args.pr_number)
    if not pr_details:
        log("ERROR", f"Could not retrieve PR #{args.pr_number}")
        return 1
    
    # Check line count threshold
    line_count = get_pr_diff_stats(args.pr_number)
    if line_count < 10:
        log("INFO", f"Skipping review for PR #{args.pr_number} ({line_count} lines - below threshold)")
        return 0
    
    # Check if integration PR
    is_integration = is_integration_pr(pr_details)
    log("INFO", f"PR #{args.pr_number} - Integration PR: {is_integration}")
    
    # Get PR diff
    diff_content = get_pr_files(args.pr_number)
    if not diff_content:
        log("ERROR", f"Could not retrieve diff for PR #{args.pr_number}")
        return 1
    
    if args.dry_run:
        log("INFO", f"DRY RUN: Would generate {'dual' if is_integration else 'single'} review for PR #{args.pr_number}")
        log("INFO", f"DRY RUN: PR has {line_count} lines of changes")
        return 0
    
    # Generate review content
    log("INFO", f"Generating {'dual' if is_integration else 'single'} review for PR #{args.pr_number}")
    review_content = generate_review_content(pr_details, diff_content, is_integration)
    
    # Save to Obsidian
    review_file = save_review_to_obsidian(args.pr_number, review_content)
    if review_file:
        log("INFO", f"Review completed and saved: {review_file}")
        return 0
    else:
        log("ERROR", "Failed to save review")
        return 1

if __name__ == "__main__":
    sys.exit(main())
