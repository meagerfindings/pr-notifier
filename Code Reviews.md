# Code Reviews

## 📋 System Overview

**GitHub Code Review Monitoring System** - Automated code review task management for CompanyCam API repository.

This system automatically queries GitHub and maintains a centralized list of code review tasks, organized by priority using the Eisenhower Matrix. Tasks are displayed dynamically in your daily notes via Obsidian dataview queries.

### 🎯 Philosophy: "Pay It Forward" Leadership

Tasks are prioritized to **unblock team members first**, then handle your own work:
1. **Integration Team Reviews** - Domain expertise responsibility 
2. **Follow-up Reviews** - Complete commitments to other developers
3. **General Code Reviews** - Broader team contribution (limited to 10/day)
4. **My PRs** - Handle your own work when you can focus deeply

### 🏗️ System Architecture

- **Repository**: `/Users/mat/git/pr-notifier` (Private GitHub repo)
- **Script**: `/Users/mat/git/pr-notifier/github-review-monitor.sh`
- **Central File**: This file (`Code Reviews.md`)
- **Daily Display**: Dynamic dataview queries in daily note template
- **Automation**: 
  - **Daily reviews**: Monday-Friday at 7:50 AM MST
  - **Integration alerts**: Every 30 minutes, 8 AM - 4 PM weekdays
- **Notifications**: NTFY push alerts via `ntfy.tail001dd.ts.net/code-reviews`

### 📊 Task Categories & Tags

| Category | Tag | Priority | Description |
|----------|-----|----------|-------------|
| Integration Reviews | `#integrations-review` | #urgent-important | PRs requesting @CompanyCam/integrations-engineers review |
| Follow-up Reviews | `#follow-up-review` | #urgent-important | PRs where you've commented but aren't the author |
| General Reviews | `#general-review` | #not-urgent-important | PRs requesting @CompanyCam/backend-engineers team OR individual @meagerfindings review (max 10) |
| My PRs | `#my-pr` | #urgent-important | Your open PRs with recent activity |

All tasks include base tags: `#task #code-review`

### 🚀 Daily Workflow

**Your daily note automatically shows:**

```
#### ⚙️ Integration Team Code Reviews
(Highest priority - your domain expertise)

#### 👥 Follow-up Reviews  
(PRs you're invested in - complete the commitment)

#### 📋 General Code Reviews
(Team contribution - max 10 per day)

#### 🚀 My Pull Requests Needing Attention
(Your work - handle when you can focus)
```

### ⚙️ Commands

| Command | Purpose |
|---------|---------|
| `/Users/mat/git/pr-notifier/github-review-monitor.sh` | Manual full review run |
| `--dry-run --verbose` | Preview changes without modifying |
| `--force` | Update all task dates even if no new PRs |
| `--integration-only --notifications` | Check integration reviews with NTFY alerts |
| `--help` | Show usage information |

### 📱 Notification Features

- **Real-time alerts**: NTFY push notifications for urgent integration reviews
- **Smart filtering**: Only notifies for PRs that actually need your review  
- **Deduplication**: Prevents repeated notifications (once per PR per day)
- **Rich content**: Includes PR title, author, number, and direct link
- **Business hours**: Notifications only during work hours (8 AM - 4 PM)

### 🔄 Automation Details

- **Daily Reviews**: Monday-Friday at 7:50 AM MST  
- **Integration Alerts**: Every 30 minutes, 8 AM - 4 PM weekdays
- **LaunchAgents**: 
  - `~/Library/LaunchAgents/com.mat.github-review-monitor.plist` (daily)
  - `~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist` (alerts)
- **Smart Deduplication**: Won't add duplicate PRs or send repeat notifications
- **Date Management**: Incomplete tasks roll forward with updated dates
- **Logging**: 
  - Activity: `/tmp/github-review-monitor.log`
  - Daily runs: `/tmp/github-review-monitor.out|err`  
  - Integration alerts: `/tmp/github-review-monitor-integration.out|err`
  - Notifications: `/tmp/github-review-monitor-notifications.log`

### 🎛️ Manual Operations

**Start/Stop Automation:**
```bash
# Load (start) both automations
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl load ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist

# Unload (stop) both automations  
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor.plist
launchctl unload ~/Library/LaunchAgents/com.mat.github-review-monitor-integration.plist
```

**Check Status:**
```bash
launchctl list | grep github-review-monitor
```

**Repository Management:**
```bash
# View repository status
cd /Users/mat/git/pr-notifier && git status

# Create/update private GitHub repository
gh repo create pr-notifier --private --source=. --push
```

### 🔍 How It Works

1. **GitHub Queries**: Uses `gh` CLI to fetch PRs from CompanyCam/Company-Cam-API
2. **Categorization**: Sorts PRs by team assignments, individual review requests, and your involvement
3. **Deduplication**: Checks existing URLs to avoid duplicates
4. **Task Creation**: Formats as Obsidian tasks with proper tags and dates
5. **File Update**: Appends new tasks to this file under "Active Reviews"
6. **Daily Display**: Dataview queries in your daily notes show relevant tasks

### 📈 Benefits

- **No missed reviews**: Automated discovery of PRs needing your attention (team assignments + individual requests)
- **Priority-driven**: Focus on highest impact work first
- **Persistent tracking**: Tasks remain visible until completed
- **Team-first approach**: Embodies servant leadership principles
- **Scalable**: Handles varying workloads without overwhelming you

---

## Active Reviews

- [ ] #task #code-review #general-review #not-urgent-important [Chad Wilken's Update rexml for CVE-2025-58767](https://github.com/CompanyCam/Company-Cam-API/pull/16580) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Derik Olsson's [PLAT-632] Prevail Dashboard](https://github.com/CompanyCam/Company-Cam-API/pull/16575) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Flora Saramago's Seed data for Payments](https://github.com/CompanyCam/Company-Cam-API/pull/16570) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Courtney White's Plat-592 adds statsd implementation for all queues](https://github.com/CompanyCam/Company-Cam-API/pull/16569) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Shaun Garwood's Integrate analytics context with TrackedEvent](https://github.com/CompanyCam/Company-Cam-API/pull/16568) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Shaun Garwood's Analytics context HTTP header injection](https://github.com/CompanyCam/Company-Cam-API/pull/16567) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Derik Olsson's DB Migration: New tables for Prevail (LLM Evaluation)](https://github.com/CompanyCam/Company-Cam-API/pull/16563) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Alison Chan's maintenance(ff): remove `document-signing` feature flag](https://github.com/CompanyCam/Company-Cam-API/pull/16554) 📅 2025-09-23
- [ ] #task #code-review #general-review #not-urgent-important [Steve's [FIX] Asset Generation for Ended Collaborations](https://github.com/CompanyCam/Company-Cam-API/pull/16550) 📅 2025-09-23



- [-] #task #code-review #general-review #not-urgent-important [Matthew Melnick's cancel/discard account subscriptions and trials with a deletion request](https://github.com/CompanyCam/Company-Cam-API/pull/16557) 📅 2025-09-22 ❌ 2025-09-22
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-795 Creating Checkist from a Template creates TrackedEvents on backend](https://github.com/CompanyCam/Company-Cam-API/pull/16556) 📅 2025-09-22 ✅ 2025-09-22
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-792 Update RubyLLM to 1.8.0](https://github.com/CompanyCam/Company-Cam-API/pull/16551) 📅 2025-09-22 ✅ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-791 Enhancing a Proposal creates TrackedEvents](https://github.com/CompanyCam/Company-Cam-API/pull/16542) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Josephine's Bil 430/payment events](https://github.com/CompanyCam/Company-Cam-API/pull/16539) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Matthew Melnick's Maintenance task to migrate paid monthly accounts to new billing](https://github.com/CompanyCam/Company-Cam-API/pull/16528) 📅 2025-09-22 ❌ 2025-09-22
- [ ] #task #code-review #my-pr #urgent-important [Flexible field mapping system for Integrations](https://github.com/CompanyCam/Company-Cam-API/pull/16379) 📅 2025-09-23



- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] JobNimbus Updates Continued...](https://github.com/CompanyCam/Company-Cam-API/pull/16536) 📅 2025-09-22 ✅ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Josephine's Bil 430/track product changed](https://github.com/CompanyCam/Company-Cam-API/pull/16535) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Steve's [Mid-343] Current Company Context from Session](https://github.com/CompanyCam/Company-Cam-API/pull/16519) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Alison Chan's maintenance(ff): remove `collab-remove-perms` ff](https://github.com/CompanyCam/Company-Cam-API/pull/16503) 📅 2025-09-22 ❌ 2025-09-22



- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-785 TrackedEventable can detect touch updates](https://github.com/CompanyCam/Company-Cam-API/pull/16498) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Jordan Godwin's MID-344: v3 endpoint to switch `current_company` session](https://github.com/CompanyCam/Company-Cam-API/pull/16485) 📅 2025-09-22 ❌ 2025-09-22



- [-] #task #code-review #general-review #not-urgent-important [Raj Mirpuri's [ML-232] Mute CCML Timeout](https://github.com/CompanyCam/Company-Cam-API/pull/16513) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-782 Checklist models track events on the server](https://github.com/CompanyCam/Company-Cam-API/pull/16477) 📅 2025-09-22 ❌ 2025-09-22



- [x] #task #code-review #general-review #not-urgent-important [Stephane Liu's Revert Project Groups Implementation](https://github.com/CompanyCam/Company-Cam-API/pull/16495) 📅 2025-09-17 ✅ 2025-09-17
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-784 Add Snowplow AIContext for tracking AI-related events](https://github.com/CompanyCam/Company-Cam-API/pull/16488) 📅 2025-09-17 ✅ 2025-09-17
- [x] #task #code-review #general-review #not-urgent-important [Flora Saramago's V3 endpoint to import Product Catalog CSV](https://github.com/CompanyCam/Company-Cam-API/pull/16487) 📅 2025-09-17 ✅ 2025-09-17
- [x] #task #code-review #general-review #not-urgent-important [Derik Olsson's [PLAT-480] Fivetran Rake task updates](https://github.com/CompanyCam/Company-Cam-API/pull/16484) 📅 2025-09-17 ✅ 2025-09-17
- [x] #task #code-review #general-review #not-urgent-important [Salvador Olocco Gorla's [payments] Reminder notification of unfinished onboarding](https://github.com/CompanyCam/Company-Cam-API/pull/16479) 📅 2025-09-17 ✅ 2025-09-17
- [-] #task #code-review #general-review #not-urgent-important [Matt Sell's move page template CRUD events to the server](https://github.com/CompanyCam/Company-Cam-API/pull/16465) 📅 2025-09-17 ❌ 2025-09-17



- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-581 Integrate AIActionable with TrackedEventabled](https://github.com/CompanyCam/Company-Cam-API/pull/16473) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Tim Ross's Move SF tracking out of transactions](https://github.com/CompanyCam/Company-Cam-API/pull/16471) 📅 2025-09-22 ❌ 2025-09-22
- [-] #task #code-review #general-review #not-urgent-important [Flora Saramago's AI Tool to import CSV data into Product Catalog](https://github.com/CompanyCam/Company-Cam-API/pull/16466) 📅 2025-09-17 ❌ 2025-09-17
- [-] #task #code-review #general-review #not-urgent-important [Kim Crowder's Move Project Template Created Event to Backend](https://github.com/CompanyCam/Company-Cam-API/pull/16457) 📅 2025-09-17 ❌ 2025-09-17
- [ ] #task #code-review #my-pr #urgent-important [[Part 2/4] Implement BatchAssetSyncWorker for processing asset sync batches](https://github.com/CompanyCam/Company-Cam-API/pull/16472) 📅 2025-09-23



- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] Validate integration records with required settings](https://github.com/CompanyCam/Company-Cam-API/pull/16450) 📅 2025-09-16 ✅ 2025-09-16
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-781 - Enhance TrackedEventable company resolution logic](https://github.com/CompanyCam/Company-Cam-API/pull/16470) 📅 2025-09-16 ✅ 2025-09-16
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-769 Remove deprecated TaskList create method](https://github.com/CompanyCam/Company-Cam-API/pull/16461) 📅 2025-09-16 ✅ 2025-09-16
- [ ] #task #code-review #my-pr #urgent-important [INT-439: Asset Sync Foundation with Critical Fixes](https://github.com/CompanyCam/Company-Cam-API/pull/16469) 📅 2025-09-23



- [x] #task #code-review #general-review #not-urgent-important [Shaun Garwood's Update AmplitudeProvider to use better method](https://github.com/CompanyCam/Company-Cam-API/pull/16444) 📅 2025-09-15 ✅ 2025-09-15
- [x] #task #code-review #general-review #not-urgent-important [Courtney White's Update ReadMe to include Access Not Granted workaround](https://github.com/CompanyCam/Company-Cam-API/pull/16437) 📅 2025-09-15 ✅ 2025-09-15
- [x] #task #code-review #general-review #not-urgent-important [Ali Schlereth's Outputs 561 refactor MarkdownToTipTapConverter](https://github.com/CompanyCam/Company-Cam-API/pull/16400) 📅 2025-09-16 ✅ 2025-09-15



- [x] #task #code-review #general-review #not-urgent-important [Katie Shaffer's Grant Fivetran access to proposals tables](https://github.com/CompanyCam/Company-Cam-API/pull/16428) 📅 2025-09-12 ✅ 2025-09-12
- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Generate and store video transcripts](https://github.com/CompanyCam/Company-Cam-API/pull/16424) 📅 2025-09-12 ❌ 2025-09-12
- [-] #task #code-review #general-review #not-urgent-important [Tyler Deboer's Add ability to include photo descriptions on galleries](https://github.com/CompanyCam/Company-Cam-API/pull/16410) 📅 2025-09-12 ❌ 2025-09-12



- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] Remove HCP User Assignment FF](https://github.com/CompanyCam/Company-Cam-API/pull/16402) 📅 2025-09-11 ✅ 2025-09-11
- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] Update scope for refreshing oauth token worker](https://github.com/CompanyCam/Company-Cam-API/pull/16388) 📅 2025-09-11 ✅ 2025-09-11
- [x] #task #code-review #general-review #not-urgent-important [Drew Mitchell's Added function with formatted warning message and displayed it prior …](https://github.com/CompanyCam/Company-Cam-API/pull/16403) 📅 2025-09-11 ✅ 2025-09-11
- [x] #task #code-review #general-review #not-urgent-important [Josephine's Bil 427/itunes fix](https://github.com/CompanyCam/Company-Cam-API/pull/16401) 📅 2025-09-11 ✅ 2025-09-11
- [-] #task #code-review #general-review #not-urgent-important [Josephine's Add v2 subscription schema](https://github.com/CompanyCam/Company-Cam-API/pull/16395) 📅 2025-09-11 ❌ 2025-09-11
- [x] #task #code-review #general-review #not-urgent-important [Tim Ross's [Billing Rearchitecture] Salesforce tracking update trial](https://github.com/CompanyCam/Company-Cam-API/pull/16386) 📅 2025-09-11 ✅ 2025-09-11



- [ ] #task #code-review #my-pr #urgent-important [feat(integrations): implement flexible field mapping system](https://github.com/CompanyCam/Company-Cam-API/pull/16377) 📅 2025-09-23



- [x] #task #code-review #general-review #not-urgent-important [Chad Wilken's Searchable Project lookup](https://github.com/CompanyCam/Company-Cam-API/pull/16360) 📅 2025-09-10 ✅ 2025-09-10
- [-] #task #code-review #general-review #not-urgent-important [Steve's [Mid-346] Update GQL mutations and resolvers for current_company functionality](https://github.com/CompanyCam/Company-Cam-API/pull/16349) 📅 2025-09-10 ❌ 2025-09-10



- [x] #task #code-review #integrations-review #urgent-important [Hartman's [Bug] Handle teamup dash errors properly](https://github.com/CompanyCam/Company-Cam-API/pull/16330) 📅 2025-09-08 ✅ 2025-09-08
- [x] #task #code-review #general-review #not-urgent-important [Chad Wilken's Papercuts/paper 63 annotate model](https://github.com/CompanyCam/Company-Cam-API/pull/16340) 📅 2025-09-08 ✅ 2025-09-08
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-756 Adjust SubTaskActionable spec to not flake](https://github.com/CompanyCam/Company-Cam-API/pull/16338) 📅 2025-09-08 ✅ 2025-09-08
- [x] #task #code-review #general-review #not-urgent-important [Stephane Liu's Fix: Guard translations to companies with translation_pro product fea…](https://github.com/CompanyCam/Company-Cam-API/pull/16336) 📅 2025-09-08 ✅ 2025-09-08
- [x] #task #code-review #general-review #not-urgent-important [Matthew Melnick's migrate subscriptions where stripe_subscription_id is an empty string](https://github.com/CompanyCam/Company-Cam-API/pull/16333) 📅 2025-09-08 ✅ 2025-09-08



- [x] #task #code-review #integrations-review #urgent-important [Gloria Ngo's INT-457/wire up get integration actions](https://github.com/CompanyCam/Company-Cam-API/pull/16296) 📅 2025-09-05 ✅ 2025-09-05
- [x] #task #code-review #integrations-review #urgent-important [Chad Wilken's Pass first error so it correctly generates a message](https://github.com/CompanyCam/Company-Cam-API/pull/16287) 📅 2025-09-05 ✅ 2025-09-05
- [x] #task #code-review #general-review #not-urgent-important [Tim Ross's [Remodel] Add archived info to project show](https://github.com/CompanyCam/Company-Cam-API/pull/16311) 📅 2025-09-08 ✅ 2025-09-08
- [-] #task #code-review #general-review #not-urgent-important [Steve's [MID-332] GQL UserType Updates for Company Switcher](https://github.com/CompanyCam/Company-Cam-API/pull/16290) 📅 2025-09-10 ❌ 2025-09-10
- [x] #task #code-review #general-review #not-urgent-important [Shaun Garwood's [PLAT-367] Amplitude feature flag provider](https://github.com/CompanyCam/Company-Cam-API/pull/16274) 📅 2025-09-10 ✅ 2025-09-10
- [ ] #task #code-review #my-pr #urgent-important [fix(integrations): resolve QuickBooks Projects to parent Customer for invoices](https://github.com/CompanyCam/Company-Cam-API/pull/16266) 📅 2025-09-23



- [-] #task #code-review #general-review #not-urgent-important [Josephine's Add coupon code index](https://github.com/CompanyCam/Company-Cam-API/pull/16269) 📅 2025-09-03 ❌ 2025-09-04
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-687 AI::Actionable calls utilize GenerativeAIPrompts](https://github.com/CompanyCam/Company-Cam-API/pull/16267) 📅 2025-09-03 ✅ 2025-09-04
- [x] #task #code-review #general-review #not-urgent-important [Chad Wilken's Add tool to manage a project's timeline status](https://github.com/CompanyCam/Company-Cam-API/pull/16265) 📅 2025-09-03 ✅ 2025-09-04
- [-] #task #code-review #general-review #not-urgent-important [Jason Grosz's Feature - add timeout arg to asset feed measurement task](https://github.com/CompanyCam/Company-Cam-API/pull/16264) 📅 2025-09-03 ❌ 2025-09-04
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's Add Lidar plan feature](https://github.com/CompanyCam/Company-Cam-API/pull/16246) 📅 2025-09-10 ❌ 2025-09-10
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-670 data migration to populate ai actionable generative ai prompts](https://github.com/CompanyCam/Company-Cam-API/pull/16244) 📅 2025-09-10 ❌ 2025-09-10
- [-] #task #code-review #general-review #not-urgent-important [Alison Chan's Feature/checklistify all kinds of documents](https://github.com/CompanyCam/Company-Cam-API/pull/16237) 📅 2025-09-10 ❌ 2025-09-10
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-669 Seed data for AI::Actionable GenerativeAIPrompts](https://github.com/CompanyCam/Company-Cam-API/pull/16231) 📅 2025-09-10 ❌ 2025-09-10



- [x] #task #code-review #integrations-review #urgent-important [Nick Rotondo's Update the hook used when connecting 'custom' integrations to V3 ](https://github.com/CompanyCam/Company-Cam-API/pull/16241) 📅 2025-09-03 ✅ 2025-09-03
- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Update BaseTool to always initialize with a current user](https://github.com/CompanyCam/Company-Cam-API/pull/16247) 📅 2025-09-10 ❌ 2025-09-10
- [x] #task #code-review #general-review #not-urgent-important [Matthew Melnick's Address CMCN022 - url access to groups](https://github.com/CompanyCam/Company-Cam-API/pull/16238) 📅 2025-09-03 ✅ 2025-09-04
- [-] #task #code-review #general-review #not-urgent-important [Derik Olsson's [PLAT-358] Fivetran Logical Replication](https://github.com/CompanyCam/Company-Cam-API/pull/16236) 📅 2025-09-10 ❌ 2025-09-10
- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Gallery create tool](https://github.com/CompanyCam/Company-Cam-API/pull/16235) 📅 2025-09-03 ❌ 2025-09-04



- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Set new max as temporary work around for map embed showcase projects](https://github.com/CompanyCam/Company-Cam-API/pull/16234) 📅 2025-08-29 ❌ 2025-08-29
- [x] #task #code-review #general-review #not-urgent-important [Salvador Olocco Gorla's [payments] add description to proposal items](https://github.com/CompanyCam/Company-Cam-API/pull/16225) 📅 2025-08-29 ✅ 2025-08-29
- [x] #task #code-review #general-review #not-urgent-important [Tim Ross's [Remodel] Move manual opt in to feature flag evaluation column](https://github.com/CompanyCam/Company-Cam-API/pull/16224) 📅 2025-08-29 ✅ 2025-08-29
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-573 Migrations to associate AIActionable/GenerativeAIPrompts](https://github.com/CompanyCam/Company-Cam-API/pull/16184) 📅 2025-08-29 ✅ 2025-08-29



- [-] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] Return interactor context if the integration is inactive](https://github.com/CompanyCam/Company-Cam-API/pull/16116) 📅 2025-08-29 ❌ 2025-08-29
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's Update RubyLLM to 1.6.4](https://github.com/CompanyCam/Company-Cam-API/pull/16204) 📅 2025-08-28 ❌ 2025-08-28
- [-] #task #code-review #general-review #not-urgent-important ['s chore(*): remove unused workflow](https://github.com/CompanyCam/Company-Cam-API/pull/16200) 📅 2025-08-28 ❌ 2025-08-28
- [-] #task #code-review #general-review #not-urgent-important [Alison Chan's feat(tasklist actions): Use document_content for docx files](https://github.com/CompanyCam/Company-Cam-API/pull/16187) 📅 2025-08-28 ❌ 2025-08-28
- [-] #task #code-review #general-review #not-urgent-important [Derik Olsson's [PLAT-428] Move to Sidekiq's CurrentAttributes middleware](https://github.com/CompanyCam/Company-Cam-API/pull/16143) 📅 2025-08-28 ❌ 2025-08-28



- [-] #task #code-review #integrations-review #urgent-important [allyse's DO NOT MERGE - Test Jobber Refresh Token Rotation](https://github.com/CompanyCam/Company-Cam-API/pull/16136) 📅 2025-08-27 ❌ 2025-08-27
- [-] #task #code-review #integrations-review #urgent-important [Gloria Ngo's INT-395/wire up connect agave button](https://github.com/CompanyCam/Company-Cam-API/pull/16131) 📅 2025-08-27 ❌ 2025-08-27
- [-] #task #code-review #integrations-review #urgent-important [Gloria Ngo's INT-458/wire up action links](https://github.com/CompanyCam/Company-Cam-API/pull/16128) 📅 2025-08-27 ❌ 2025-08-27
- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Make example prompts clickable](https://github.com/CompanyCam/Company-Cam-API/pull/16181) 📅 2025-08-27 ❌ 2025-08-27
- [-] #task #code-review #general-review #not-urgent-important [Raj Mirpuri's [RND-203] - Route CCML Backfill Jobs to new Queue](https://github.com/CompanyCam/Company-Cam-API/pull/16173) 📅 2025-08-27 ❌ 2025-08-27
- [x] #task #code-review #general-review #not-urgent-important [Flora Saramago's No longer require contact info for Proposal creation](https://github.com/CompanyCam/Company-Cam-API/pull/16159) 📅 2025-08-27 ✅ 2025-08-27
- [-] #task #code-review #general-review #not-urgent-important [Shaun Garwood's [PLAT-417] Request queue timing to Cloudwatch](https://github.com/CompanyCam/Company-Cam-API/pull/16146) 📅 2025-08-27 ❌ 2025-08-27
- [x] #task #code-review #general-review #not-urgent-important [Tim Ross's Add beta opt in status to dash](https://github.com/CompanyCam/Company-Cam-API/pull/16140) 📅 2025-08-27 ✅ 2025-08-27
- [-] #task #code-review #general-review #not-urgent-important [Tim Ross's Add manual opt in to remodel beta data](https://github.com/CompanyCam/Company-Cam-API/pull/16139) 📅 2025-08-27 ❌ 2025-08-27
- [ ] #task #code-review #my-pr #urgent-important [feat(INT-477):  Normalized field mapping system with template inheritance](https://github.com/CompanyCam/Company-Cam-API/pull/16134) 📅 2025-09-23



- [-] #task #code-review #general-review #not-urgent-important [Jason Grosz's Feature - Add a model for Postgres asset view](https://github.com/CompanyCam/Company-Cam-API/pull/16107) 📅 2025-08-25 ❌ 2025-08-25



- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integraton] Update project name from Hover Job](https://github.com/CompanyCam/Company-Cam-API/pull/16101) 📅 2025-08-22 ✅ 2025-08-22
- [x] #task #code-review #integrations-review #urgent-important [allyse's [Integrations] Remove integration soft delete Feature Flag](https://github.com/CompanyCam/Company-Cam-API/pull/16078) 📅 2025-08-22 ✅ 2025-08-22
- [x] #task #code-review #integrations-review #urgent-important [Nick Rotondo's [Integrations] Migrate client to use V3 OAuth `new` endpoint ](https://github.com/CompanyCam/Company-Cam-API/pull/16070) 📅 2025-08-22 ✅ 2025-08-22
- [x] #task #code-review #integrations-review #urgent-important [Gloria Ngo's INT-397/wire v3 endpoint to use update integration](https://github.com/CompanyCam/Company-Cam-API/pull/16068) 📅 2025-08-22 ✅ 2025-08-22
- [-] #task #code-review #general-review #not-urgent-important [Salvador Olocco Gorla's [payments] add proposal id to payment_requests](https://github.com/CompanyCam/Company-Cam-API/pull/16102) 📅 2025-08-22 ❌ 2025-08-22
- [-] #task #code-review #general-review #not-urgent-important [Chad Wilken's Update showcase_projects_controller to allow dynamic pagination items with a max...](https://github.com/CompanyCam/Company-Cam-API/pull/16100) 📅 2025-08-22 ❌ 2025-08-22
- [-] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-646 Update TaskList creation prompt to add subtasks](https://github.com/CompanyCam/Company-Cam-API/pull/16093) 📅 2025-08-22 ❌ 2025-08-22
- [x] #task #code-review #general-review #not-urgent-important [Chad Wilken's Setup worker to generate description and hook into flow](https://github.com/CompanyCam/Company-Cam-API/pull/16089) 📅 2025-08-22 ✅ 2025-08-22
- [-] #task #code-review #general-review #not-urgent-important [Michael Mosher's Feature/fix pr cleanup workflow](https://github.com/CompanyCam/Company-Cam-API/pull/16084) 📅 2025-08-22 ❌ 2025-08-22
- [-] #task #code-review #general-review #not-urgent-important [Shaun Garwood's Refactor Fivetran rake task to use centralized permissions class](https://github.com/CompanyCam/Company-Cam-API/pull/16082) 📅 2025-08-22 ❌ 2025-08-22
- [ ] #task #code-review #my-pr #urgent-important [Add stripe_card_brand column to payment_requests table](https://github.com/CompanyCam/Company-Cam-API/pull/16098) 📅 2025-09-23



- [x] #task #code-review #general-review #not-urgent-important [Chad Wilken's Model changes for AI Photo Descriptions](https://github.com/CompanyCam/Company-Cam-API/pull/16064) 📅 2025-08-21 ✅ 2025-08-21



- [x] #task #code-review #general-review #not-urgent-important [Salvador Olocco Gorla's [payments] remove onboarding url from v1 serializer, create its own controller](https://github.com/CompanyCam/Company-Cam-API/pull/16052) 📅 2025-08-20 ✅ 2025-08-20



- [ ] #task #code-review #my-pr #urgent-important [Implement QuickBooks payment method service with caching and fallback](https://github.com/CompanyCam/Company-Cam-API/pull/16051) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [[INT-476] Add card brand extraction infrastructure for Stripe payments](https://github.com/CompanyCam/Company-Cam-API/pull/16048) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [[Part 1/3] Security and reliability fixes for QuickBooks customer operations](https://github.com/CompanyCam/Company-Cam-API/pull/16035) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [feat(INT-439): QuickBooks customer search and deduplication system](https://github.com/CompanyCam/Company-Cam-API/pull/16034) 📅 2025-09-23



- [x] #task #code-review #integrations-review #urgent-important [allyse's [Hover API] Update Document Processing](https://github.com/CompanyCam/Company-Cam-API/pull/15984) 📅 2025-08-19 ✅ 2025-08-19
- [x] #task #code-review #general-review #not-urgent-important [Salvador Olocco Gorla's [payments] Proposals, deposit percentage migration](https://github.com/CompanyCam/Company-Cam-API/pull/16028) 📅 2025-08-19 ✅ 2025-08-19
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's RND-192 Refactor LidarData permitted params](https://github.com/CompanyCam/Company-Cam-API/pull/16006) 📅 2025-08-19 ✅ 2025-08-19
- [-] #task #code-review #general-review #not-urgent-important [Matt Sell's Move Page created entity CRUD events to the server](https://github.com/CompanyCam/Company-Cam-API/pull/16005) 📅 2025-08-19 ❌ 2025-08-19
- [x] #task #code-review #general-review #not-urgent-important [Nicholas Seemiller's INPUT-583 AIActionable provides context for tracked events](https://github.com/CompanyCam/Company-Cam-API/pull/16004) 📅 2025-08-20 ✅ 2025-08-20
- [ ] #task #code-review #my-pr #urgent-important [[INT-463] Implement payment sync idempotency using Sidekiq Enterprise unique job...](https://github.com/CompanyCam/Company-Cam-API/pull/16010) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [feat(INT-456): add QuickBooks payment method mapping](https://github.com/CompanyCam/Company-Cam-API/pull/15898) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [feat(INT-453): auto-create QuickBooks customers during payment sync](https://github.com/CompanyCam/Company-Cam-API/pull/15837) 📅 2025-09-23
- [ ] #task #code-review #my-pr #urgent-important [feat(INT-433): add payment sync status monitoring to Dash pages](https://github.com/CompanyCam/Company-Cam-API/pull/15829) 📅 2025-09-23









<!-- Tasks are automatically added here by github-review-monitor.sh -->
<!-- Format: - [ ] #task #code-review #[category] #[priority] [PR Title](URL) 📅 YYYY-MM-DD -->

## Completed Reviews

<!-- Completed tasks can be moved here manually or they'll disappear from daily queries when marked done -->
