# GitHub Issues Tracker Guide

The GitHub Issues tracker uses **labels as pipeline states** and **issue comments as artifacts**.
Instead of renaming files, agents transition tasks by swapping labels. Instead of appending to markdown files, agents post structured comments on the issue.

A single `gh issue list --label "..."` command replaces `ls tracker/*.state.md`.

---

## Project Board

All issues are tracked on the GitHub Project board:
**https://github.com/users/<your-github-user>/projects/<your-project-number>**

When creating issues, link them to the project with `--project "<your-github-user>/<your-project-number>"`.

---

## Label System

Labels encode three dimensions: **pipeline state**, **priority**, and **current role**.

### Pipeline State Labels

| Pipeline State | Label Name | Color | Description |
|---|---|---|---|
| Dormant backlog | `backlog` | `#CCCCCC` | Captured idea, not in active pipeline — human must promote before work starts |
| Raw task | `needs-grooming` | `#D93F0B` | Task waiting for PM to write spec |
| PM groomed | `ready-for-dev` | `#0E8A16` | Spec written, ready for SWE |
| SWE working | `in-progress` | `#1D76DB` | SWE implementing |
| Ready for QA | `ready-for-qa` | `#FBCA04` | Implementation done, waiting for QA |
| QA passed | `ready-for-acceptance` | `#BFD4F2` | QA verified, waiting for PM acceptance |
| Ready for docs | `ready-for-docs` | `#C5DEF5` | PM accepted, waiting for Technical Writer |
| Docs done | `docs-done` | `#0E8A16` | Theory doc written, ready to commit and close |
| Rework needed | `rework-needed` | `#E4E669` | QA failed or PM rejected, back to SWE |
| Blocked | `blocked` | `#B60205` | Waiting for human input (check Agent Questions) |
| Accepted | *(issue closed)* | — | Code committed and issue closed |

**`backlog` is not a state the orchestrator processes.** Issues with this label are dormant — visible in GitHub but invisible to the main pipeline queue. They become active only when a human swaps `backlog,role-human` → `needs-grooming,role-pm`.

### Priority Labels

| Label | Color | Description |
|---|---|---|
| `priority-high` | `#B60205` | High priority |
| `priority-medium` | `#FEF2C0` | Medium priority |
| `priority-low` | `#0E8A16` | Low priority |

### Role Labels (who is currently responsible)

Exactly **one role label** should be active per issue.

| Label | Color | Description |
|---|---|---|
| `role-pm` | `#D4C5F9` | Currently with Product Manager |
| `role-swe` | `#BFD4F2` | Currently with Software Engineer |
| `role-qa` | `#FEF2C0` | Currently with QA / Tester |
| `role-techwriter` | `#C5DEF5` | Currently with Technical Writer |
| `role-oncall` | `#E6E6E6` | Currently with On-Call Engineer |
| `role-human` | `#F9D0C4` | Waiting for the ideator (human) |

### Type Labels

One type label per issue (informational, does not affect pipeline logic).

| Label | Color | Description |
|---|---|---|
| `type-feature` | `#A2EEEF` | New feature or capability |
| `type-bugfix` | `#D93F0B` | Bug fix |
| `type-refactor` | `#C5DEF5` | Code refactoring (no behavior change) |
| `type-infra` | `#E6E6E6` | Infrastructure or CI/CD change |

### QA Cycle Labels

Tracks rework cycles. The orchestrator enforces the 3-cycle limit.

| Label | Description |
|---|---|
| `qa-cycle-1` | First QA pass |
| `qa-cycle-2` | Second QA pass (after first rework) |
| `qa-cycle-3` | Third QA pass — escalate to human if fails |

### Blocked State

When any agent is blocked by ambiguity, it sets `blocked` + `role-human`. The ideator answers the
question on the issue and restores the previous role label.

The **block / unblock contract** is documented in `process/PROCESS.md` §5: `tracker_unblock_issue`
restores the role only — the caller must follow with `tracker_transition --to-state <next>` to
land the issue on a real pipeline state. Same rule applies in Azure mode.

---

## GitHub Project Board Fields

If a GitHub Project is configured (`CLAUDE.md` → `github_project_number`), the orchestrator and agents
also update Project fields alongside labels:

| Field | Type | Values | Purpose |
|---|---|---|---|
| **Pipeline** | Single-select | Backlog, Development, QA, Acceptance, Documentation, Done, Blocked | Kanban column |
| **Priority** | Single-select | High, Medium, Low | Sort order for pickup |
| **Agent** | Single-select | PM, SWE, QA, TechWriter, On-Call, Human | Who currently owns it |
| **Status** | Single-select | Backlog, Ready, In progress, In review, In documentation, Done | Fine-grained state within a Pipeline column |
| **QA Cycle** | Number | 1, 2, 3 | Rework count |

Create these fields by running:
```bash
bash scripts/init-github-tracker.sh <your-github-user>/<your-repo> <your-project-number>
```

### Label Transitions Matrix

| Pipeline Step | Remove Labels | Add Labels | Project Fields |
|---|---|---|---|
| **Create issue** | — | `needs-grooming`, `priority-*`, `role-pm` | Pipeline=Backlog, Agent=PM |
| **PM captures backlog item** (during grooming, from Out of Scope) | — | `backlog`, `role-human` | Pipeline=Backlog, Agent=Human |
| **Human promotes backlog item** | `backlog`, `role-human` | `needs-grooming`, `priority-*`, `role-pm` | Pipeline=Backlog, Agent=PM |
| **PM grooms** | `needs-grooming`, `role-pm` | `ready-for-dev`, `role-swe` | Pipeline=Development, Agent=SWE |
| **SWE starts** | `ready-for-dev` | `in-progress` | — |
| **SWE done** | `in-progress`, `role-swe` | `ready-for-qa`, `role-qa`, `qa-cycle-1` | Pipeline=QA, Agent=QA, QA Cycle=1 |
| **QA passes** | `ready-for-qa`, `role-qa` | `ready-for-acceptance`, `role-pm` | Pipeline=Acceptance, Agent=PM |
| **QA fails** | `ready-for-qa`, `role-qa` | `rework-needed`, `role-swe` | Agent=SWE |
| **SWE reworks** | `rework-needed`, `qa-cycle-(N-1)` | `ready-for-qa`, `role-qa`, `qa-cycle-N` | QA Cycle=N |
| **PM accepts** | `ready-for-acceptance`, `role-pm` | *(close issue)* | Pipeline=Done |
| **PM rejects** | `ready-for-acceptance`, `role-pm` | `rework-needed`, `role-swe` | Agent=SWE |
| **Blocked** | current role | `blocked`, `role-human` | Pipeline=Blocked, Agent=Human |
| **Unblocked** | `blocked`, `role-human` | previous role | Restore previous Pipeline |

---

## Priority-Aware Pickup (used by orchestrator)

The orchestrator picks issues **in priority order within each state**:

```bash
# All issues needing grooming, high priority first
gh issue list --repo <your-github-user>/<your-repo> \
  --label "needs-grooming" \
  --json number,title,labels \
  --jq 'sort_by(
    if (.labels | map(.name) | index("priority-high")) then 0
    elif (.labels | map(.name) | index("priority-medium")) then 1
    else 2 end
  ) | .[] | "\(.number)\t\(.title)"'
```

---

## Setup (Run Once Per Repo)

Run the init script to create all labels:

```bash
bash agent-playbook/scripts/init-github-tracker.sh <your-github-user>/<your-repo>
```

Or create labels manually:

```bash
# Pipeline state labels
gh label create "backlog" --color "CCCCCC" --description "Dormant backlog item — human must promote to activate"
gh label create "needs-grooming" --color "D93F0B" --description "Task waiting for PM to write spec"
gh label create "ready-for-dev" --color "0E8A16" --description "Spec written, ready for SWE"
gh label create "in-progress" --color "1D76DB" --description "SWE implementing"
gh label create "ready-for-qa" --color "FBCA04" --description "Implementation done, waiting for QA"
gh label create "ready-for-acceptance" --color "BFD4F2" --description "QA verified, waiting for PM acceptance"
gh label create "rework-needed" --color "E4E669" --description "QA failed or PM rejected"

# Priority labels
gh label create "priority-high" --color "B60205" --description "High priority"
gh label create "priority-medium" --color "FEF2C0" --description "Medium priority"
gh label create "priority-low" --color "0E8A16" --description "Low priority"

# Role labels
gh label create "role-pm" --color "C5DEF5" --description "Currently with PM"
gh label create "role-swe" --color "C5DEF5" --description "Currently with SWE"
gh label create "role-qa" --color "C5DEF5" --description "Currently with QA"
gh label create "role-oncall" --color "C5DEF5" --description "Currently with On-Call"
```

---

## Pipeline Transitions — `gh` Commands

### Task Creation (Ideator)

```bash
gh issue create \
  --title "Brief task title" \
  --body "Raw description of what needs to be done" \
  --label "needs-grooming,priority-medium,role-pm" \
  --project "<your-github-user>/<your-project-number>"
```

### PM Grooming (Job 1)

```bash
# Read the issue
gh issue view {NUMBER} --comments

# Post groomed spec as a comment
gh issue comment {NUMBER} --body "## Groomed Specification
### Summary
...
### User Story
As a [user], I want [feature] so that [benefit].
### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
### Test Scenarios
1. ...
### Dependencies
- ...
### Out of Scope
- ..."

# Transition labels
gh issue edit {NUMBER} \
  --remove-label "needs-grooming,role-pm" \
  --add-label "ready-for-dev,role-swe"
```

### PM Backlog Capture (during grooming)

After posting the groomed spec, the PM iterates over the `### Out of Scope` bullets and captures any that describe **concrete, actionable work** (concrete verb + object) as dormant backlog issues. Vague aspirations are skipped. See the PM agent prompt (Step 4.5) for the qualification rules.

```bash
# Dedupe against existing open issues first
gh issue list --state open --search "<2-4 keywords from the bullet>" --json number,title,labels

# If a match exists, link back instead of creating
gh issue comment <MATCH_NUMBER> --body "Raised again during grooming of #{PARENT} as an out-of-scope item: \"[bullet]\""

# If no match, create a dormant backlog issue
gh issue create \
  --title "<concise verb + object>" \
  --body "Spun out of #{PARENT} during grooming.

**Original out-of-scope bullet:** [bullet verbatim]
**Context:** [why it came up]" \
  --label "backlog,role-human"
```

**Dormant by design:** captured items get `backlog,role-human` — NOT `needs-grooming`. The orchestrator does not pick them up. They sit in the backlog until a human promotes them.

### Promoting a Backlog Item

When a human decides a dormant backlog item is worth working on:

```bash
gh issue edit {NUMBER} \
  --remove-label "backlog,role-human" \
  --add-label "needs-grooming,priority-medium,role-pm"
```

From that point on, it flows through the normal PM→SWE→QA pipeline like any other task.

### SWE Implementation

```bash
# Pick up the task
gh issue edit {NUMBER} \
  --remove-label "ready-for-dev" \
  --add-label "in-progress"

# Post implementation report as a comment
gh issue comment {NUMBER} --body "## Implementation Report
### Files Changed
- ...
### Approach
...
### Tests Written
- ...
### Test Results
All X tests passing.
### Decisions Made
- ..."

# Transition to QA
gh issue edit {NUMBER} \
  --remove-label "in-progress,role-swe" \
  --add-label "ready-for-qa,role-qa"
```

### QA Verification

```bash
# Post test report as a comment
gh issue comment {NUMBER} --body "## QA Report
### Test Suite Results
\`\`\`
pytest output here
\`\`\`
### Acceptance Criteria Verification
- [x] Criterion 1 — PASS (evidence: ...)
- [ ] Criterion 2 — FAIL (reason: ...)
### Domain-Specific Checks
...
### Overall Verdict: PASS / FAIL"

# If PASS:
gh issue edit {NUMBER} \
  --remove-label "ready-for-qa,role-qa" \
  --add-label "ready-for-acceptance,role-pm"

# If FAIL:
gh issue edit {NUMBER} \
  --remove-label "ready-for-qa,role-qa" \
  --add-label "rework-needed,role-swe"
```

### PM Acceptance (Job 2)

```bash
# Read all comments (spec + implementation report + QA report)
gh issue view {NUMBER} --comments

# If ACCEPT:
gh issue comment {NUMBER} --body "## PM Acceptance: APPROVED
Task meets all acceptance criteria from a user perspective.
Approved for commit."
gh issue close {NUMBER} --comment "Accepted and committed."

# If REJECT:
gh issue comment {NUMBER} --body "## PM Acceptance: REJECTED
### Reasons
- ...
### Required Changes
- ..."
gh issue edit {NUMBER} \
  --remove-label "ready-for-acceptance,role-pm" \
  --add-label "rework-needed,role-swe"
```

---

## Orchestrator Status Checks

```bash
# See the kanban at a glance
gh issue list --label "backlog"       # Dormant backlog (human-curated)
gh issue list --label "needs-grooming"       # Grooming queue (active pipeline)
gh issue list --label "ready-for-dev"        # Ready
gh issue list --label "in-progress"          # In Progress
gh issue list --label "ready-for-qa"         # QA Queue
gh issue list --label "ready-for-acceptance" # Acceptance Queue
gh issue list --label "rework-needed"        # Blocked / Rework

# Issues assigned to a specific role
gh issue list --label "role-pm"
gh issue list --label "role-swe"
gh issue list --label "role-qa"
gh issue list --label "role-oncall"

# High-priority items across all states
gh issue list --label "priority-high"
```

---

## Batch-Creating Issues from a Requirements File

If you have a file with one task per line (e.g., `requirements.txt`):

```bash
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  gh issue create \
    --title "$line" \
    --body "Raw task from requirements import." \
    --label "needs-grooming,priority-medium,role-pm" \
    --project "<your-github-user>/<your-project-number>"
done < requirements.txt
```

---

## Linking Issues to the Project Board

Every `gh issue create` command should include `--project "<your-github-user>/<your-project-number>"` to automatically add the issue to the project board. For existing issues not yet on the board:

```bash
# Add an existing issue to the project (requires the issue node ID)
ISSUE_ID=$(gh issue view {NUMBER} --json id --jq '.id')
gh project item-add <your-project-number> --owner <your-github-user> --url "https://github.com/<your-github-user>/<your-repo>/issues/{NUMBER}"
```

---

## Querying Issues by Role

```bash
# What does the PM need to do?
gh issue list --label "role-pm" --json number,title,labels --jq '.[] | "\(.number) \(.title)"'

# What does the SWE need to do?
gh issue list --label "role-swe" --json number,title,labels --jq '.[] | "\(.number) \(.title)"'

# What does QA need to do?
gh issue list --label "role-qa" --json number,title,labels --jq '.[] | "\(.number) \(.title)"'
```

---

## Discovery Issues (Agent-Created Backlog Items)

During implementation or testing, agents may discover problems **outside the scope of their current task**.
Instead of expanding scope, they create a new issue in the backlog.

### Who Creates Discovery Issues

- **SWE** — bugs, tech debt, edge cases found during implementation
- **QA** — test gaps, security concerns, bugs found during verification
- **Refactoring Reviewer** — each proposed refactoring task from a code review

### Command Template

```bash
gh issue create --repo <your-github-user>/<your-repo> \
  --title "[DISCOVERY] Brief description of the problem" \
  --body "$(cat <<'EOF'
## Discovered During
Issue #CURRENT_NUMBER — [current task title]

## Description
[What was found, where, and why it matters]

## Evidence
[File path, line number, test name, or command that revealed the issue]

## Suggested Type
[bugfix / refactor / feature]

---
*Created by [agent-name] agent during [implementation/QA/review] of #CURRENT_NUMBER.*
EOF
)" \
  --label "needs-grooming,priority-medium,role-pm,type-bugfix" \
  --project "<your-github-user>/<your-project-number>"
```

### Label Rules

| Scenario | Labels |
|---|---|
| Default discovery | `needs-grooming`, `priority-medium`, `role-pm`, `type-bugfix` |
| Security or data-loss risk | `needs-grooming`, `priority-high`, `role-pm`, `type-bugfix` |
| Tech debt / refactoring | `needs-grooming`, `priority-medium`, `role-pm`, `type-refactor` |
| Missing functionality | `needs-grooming`, `priority-medium`, `role-pm`, `type-feature` |

### Constraints

- Always `needs-grooming` + `role-pm` — PM must groom before anyone acts
- Always reference the originating issue number in the body
- The agent must log the created issue in their report (Implementation Report, QA Report, or Review Report)
- **Agents never self-assign discovery issues** — they go through PM grooming

---

## Comparison with File-Based Tracking

| Aspect | File-Based | GitHub Issues |
|---|---|---|
| Status at a glance | `ls tracker/` | `gh issue list --label "..."` |
| State transition | File rename | Label swap |
| Spec / report storage | Appended to task file | Posted as issue comments |
| Audit trail | File content + git history | Issue timeline + comments |
| Scalability | ~20–30 tasks | Unlimited |
| Multi-repo | One tracker per repo | One project board across repos |
| Human visibility | Must read files | GitHub web UI + notifications |
| CI integration | Manual | Native (PR links, actions) |

Use **file-based** for small, experimental, or single-repo projects.
Use **GitHub Issues** for multi-repo, team, or long-running projects.
