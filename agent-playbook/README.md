# Agent Playbook — Reusable AI Development Team

A portable framework for deploying a consistent AI development team on any project.
Think of it as a consulting firm's operating manual: the methodology stays the same, only the client brief changes.

---

## Table of Contents

- [What This Is](#what-this-is)
- [The Team](#the-team)
- [The Pipeline](#the-pipeline)
- [Where You (the Ideator) Must Intervene](#where-you-the-ideator-must-intervene)
- [Quick Start](#quick-start)
- [Coding Standards](#coding-standards)
- [Portability — How the Team Stays Project-Agnostic](#portability--how-the-team-stays-project-agnostic)
- [File Structure Reference](#file-structure-reference)
- [GitHub Issues Mode](#github-issues-mode)
- [Azure DevOps Boards Mode](#azure-devops-boards-mode)
- [Discovery Issues](#discovery-issues)
- [Adding New Skills](#adding-new-skills)
- [Onboarding Checklist](#onboarding-checklist)

---

## What This Is

This playbook defines a **6-agent team** that runs inside Claude Code. Each agent has a clearly bounded role. Together they run a disciplined pipeline from raw idea to committed code — with the human ideator in control at every critical gate.

The playbook is **project-agnostic**: copy it to any project, fill in one `CLAUDE.md` file, and the team knows what to do.

---

## The Team

| Agent | File | Role |
|---|---|---|
| **Product Manager** | `agents/product-manager.md` | Grooms raw tasks into precise specs; accepts or rejects completed work |
| **Software Engineer** | `agents/software-engineer.md` | Implements code and writes tests from groomed specs |
| **Tester (QA)** | `agents/tester.md` | Independently verifies implementation against spec and domain standards |
| **Technical Writer** | `agents/technical-writer.md` | Produces theory and reference documentation in `_docs/theory/` after PM acceptance |
| **On-Call Engineer** | `agents/oncall-engineer.md` | Fixes CI/CD, infrastructure, and tooling failures; initialises new GitHub repos |
| **Refactoring Reviewer** | `agents/refactoring-reviewer.md` | Reviews existing code and produces a prioritized refactoring roadmap |

---

## The Pipeline

```
[You: Ideator]
      │
      │  Write a *.todo.md file
      ▼
┌─────────────┐
│     PM      │  Grooms task → writes spec → *.groomed.md
│  (Job 1)    │  ── Stops if spec is ambiguous → asks you ──►
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     SWE     │  Reads spec → implements → writes tests → *.in-progress.md
│             │  ── Stops if spec is unclear → asks you ──►
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     QA      │  Runs tests → verifies each criterion → appends QA report
│             │  ── FAIL: goes back to SWE (max 3 cycles) ──►
└──────┬──────┘
       │  PASS
       ▼
┌─────────────┐
│     PM      │  Reviews from user perspective → ACCEPT or REJECT
│  (Job 2)    │  ── REJECT: goes back to SWE with reasons ──►
└──────┬──────┘
       │  ACCEPT
       ▼
┌─────────────┐
│ TechWriter  │  Writes theory doc in _docs/theory/
│             │  (only when domain warrants it)
└──────┬──────┘
       │  DOCS DONE
       ▼
[You: Ideator]
      │
      │  Review commit, approve push
      ▼
   tracker/done/
```

---

## Where You (the Ideator) Must Intervene

These are the **mandatory human gates**. The pipeline will explicitly pause and wait for your input at each one.

### Gate 1 — Task Creation (always)
**When**: Before the pipeline starts.
**What you do**: Write a `*.todo.md` file describing what you want built. It can be rough — the PM will refine it.
**Why it's yours**: You define the problem. No agent invents requirements.

### Gate 2 — Ambiguous Spec (as needed)
**When**: The PM or SWE finds the spec ambiguous during grooming or implementation.
**What you do**: Answer the question(s) appended under `## Agent Questions` in the task file.
**Why it's yours**: Only you know the intent behind the requirement.
**How to recognize it**: The PM outputs `GROOMED — BLOCKED: questions in task file.` or the SWE pauses with `SWE BLOCKED: clarification needed.`

### Gate 3 — PM Acceptance Review (always)
**When**: After QA passes, the PM does a final review.
**What the PM does**: Accepts or rejects from the user's perspective.
**What you do**: After PM accepts, review the commit diff and approve the push to your repository.
**Why it's yours**: You own the repository. No agent pushes code without your explicit approval.
**How to recognize it**: The PM outputs `ACCEPTED: tracker/done/NNN-... — ready to commit.`

### Gate 4 — QA Cycle 3 Escalation (as needed)
**When**: A task has failed QA three times in a row.
**What you do**: Read the QA report, decide whether to rethink the spec or approach.
**Why it's yours**: Three cycles means the problem is likely in the spec or a fundamental constraint — human judgment needed.
**How to recognize it**: QA outputs `QA CYCLE 3 FAIL — escalate to human.`

### Gate 5 — Refactoring Scope (when using refactoring-reviewer)
**When**: Before the refactoring reviewer starts.
**What you do**: Tell it what scope to review (a file, a module, or the full project).
**Why it's yours**: Refactoring scope defines what gets touched; wrong scope = wasted work.

### Gate 6 — Refactoring Task Approval (when using refactoring-reviewer)
**When**: After the refactoring reviewer delivers its report.
**What you do**: Read the prioritized findings, decide which refactoring tasks to actually create in the tracker.
**Why it's yours**: Not all findings need to be acted on immediately; you set the priorities.

### Gate 7 — Repo Initialisation (once per project)
**When**: Before the On-Call engineer creates the GitHub repo.
**What you do**: Confirm repository visibility (public/private), default branch name, whether a `develop` branch is needed, and whether branch protection rules should be applied.
**Why it's yours**: These are permanent decisions about your repository — wrong visibility on a public repo cannot be undone quietly.
**How to trigger it**: `claude --agent .claude/agents/oncall-engineer.md "Initialise the GitHub repo for /path/to/project"`

---

## Quick Start

> **Important**: Steps must be followed in order. Each step depends on the previous one completing successfully.
>
> **Using Azure DevOps Boards instead of GitHub?** Skip steps 0–2 below and follow the [Azure DevOps Boards Mode](#azure-devops-boards-mode) section's setup block, then resume at step 3 (which is backend-agnostic — the on-call agent branches on `tracker:` automatically). Step 4 onwards uses `tracker_*` verbs that work in either mode.

### 0. Create the project and repo (once per project family)

Before bootstrapping a project, create the GitHub Project board and link the repo to it:

```bash
# Create project board + repo and link them in one step:
bash ./agent-playbook/scripts/gh-setup.sh \
  --owner <your-github-user> \
  --project <your-project-name> \
  --repo <your-repo>

# Private repo with description:
bash ./agent-playbook/scripts/gh-setup.sh \
  --owner <your-github-user> \
  --project <your-project-name> \
  --repo <your-repo> \
  --private \
  --description "<your-repo-description>"

# Repo already exists — just link it to the project:
bash ./agent-playbook/scripts/gh-setup.sh \
  --owner <your-github-user> \
  --project <your-project-name> \
  --repo <your-repo> \
  --link-only
```

> **Note:** If the script fails on the project step, refresh your gh scopes first:
> `gh auth refresh -h github.com -s project,read:project`

---

### 1. Bootstrap a new project

Run from the **repo root** (`dev-team/`), not from `agent-playbook/`:

```bash
bash ./agent-playbook/scripts/init-project.sh /path/to/your-project quant-finance
# Template options: quant-finance | web-app | cli-tool | data-pipeline

# With GitHub Issues tracking:
bash ./agent-playbook/scripts/init-project.sh /path/to/your-project quant-finance --github

# With Azure DevOps Boards tracking (org/project/repo must already exist):
bash ./agent-playbook/scripts/init-project.sh /path/to/your-project quant-finance --azure

# On Windows (PowerShell + Git Bash):
bash ./agent-playbook/scripts/init-project.sh "/c/Users/<you>/projects/your-project" quant-finance --github
```

`--github` and `--azure` are mutually exclusive. The default (no flag) is file-based mode.

**Verify** the project was created before moving on:

```powershell
# PowerShell:
Get-ChildItem -Recurse /path/to/your-project | Select-Object FullName
# You should see: CLAUDE.md, .claude/, tracker/, _docs/
```

### 2. Fill in CLAUDE.md and project.env

Open `/path/to/your-project/CLAUDE.md` and fill in:
- Project name and overview
- Tech stack
- Skills Path (must match `SUPERPOWERS_SKILLS_DIR` in `.claude/project.env`)
- Architecture notes
- Domain-specific rules
- Agent Variant (`file` or `github`)

Then open `/path/to/your-project/.claude/project.env`. `init-project.sh` already
filled in `GH_OWNER` from your `gh api user` login. Resolve and fill in:
- `GH_REPO`, `GH_PROJECT_NUMBER`, `GH_PROJECT_ID`
- The `GH_FIELD_*`, `GH_PIPELINE_*`, `GH_AGENT_*`, `GH_STATUS_*` IDs
- `SUPERPOWERS_SKILLS_DIR` if your skills don't live at the default relative path

The exact `gh project field-list` commands that produce each ID are
documented in the per-project `.claude/PORTING.md` (also seeded by
`init-project.sh`).

### 3. Initialise the project repo (On-Call)

**You must `cd` into the new project directory first.** The On-Call agent reads `CLAUDE.md` from the current directory, decides which remote-host platform to use based on the `tracker:` line, and provisions the repo accordingly.

```bash
# 1. Change into the project directory:
cd /path/to/your-project

# 2. Run the On-Call agent (single line — do NOT use backslash line-continuation):
claude --agent .claude/agents/oncall-engineer.md "Initialise the repo for $(pwd)"

# On Windows (PowerShell):
cd "C:\Users\<you>\projects\your-project"
claude --agent .claude/agents/oncall-engineer.md "Initialise the repo for $PWD"
```

The On-Call agent will:
1. Read your `CLAUDE.md` for project details and the `tracker:` mode
2. Verify the appropriate CLI is authenticated (`gh auth status` for GitHub, `az account show` + `azure-devops` extension for Azure)
3. Ask you: repo visibility (GitHub only — ADO repos inherit project visibility), branch structure, protection rules
4. Run `git init`, create `.gitignore`, make an initial commit, then either:
   - **GitHub mode**: `gh repo create`, optional Project board create/link, run `init-github-tracker.sh` to seed labels
   - **Azure mode**: verify the existing ADO project / repo, add Azure Repos as `origin`, push, run `init-azure-tracker.sh` to verify the connection
   - **File mode**: skip the remote setup entirely

### 4. Create your first task

**File-based mode:**
```bash
cp .claude/templates/task.todo.md tracker/001-my-first-feature.todo.md
# Edit the file with your task description
```

**GitHub Issues mode:**
```bash
source .claude/env.sh   # exports GH_OWNER, GH_PROJECT_NUMBER, etc.
gh issue create \
  --title "My first feature" \
  --body "Description of what needs to be done" \
  --label "needs-grooming,priority-medium,role-pm" \
  --project "${GH_OWNER}/${GH_PROJECT_NUMBER}"
```

### 5. Run the pipeline

In Claude Code, from your project directory:

```bash
# Run the full pipeline on the next batch of todo tasks:
/execute

# Or launch a specific agent manually:
claude --agent .claude/agents/product-manager.md "Groom task tracker/001-my-first-feature.todo.md"
claude --agent .claude/agents/software-engineer.md "Implement task tracker/001-my-first-feature.groomed.md"
claude --agent .claude/agents/tester.md "Verify task tracker/001-my-first-feature.in-progress.md"
```

### 6. Run a code review

```bash
claude --agent .claude/agents/refactoring-reviewer.md "Review the src/pricing/ module"
```

---

## Coding Standards

All agents follow the standards in `copilot-instructions.md` (copied to each project by `init-project.sh`).
The canonical source is in this playbook:
```
agent-playbook/copilot-instructions.md
```

Key standards:
- Python-first, frozen dataclasses, full type hints (PEP 484)
- Polars over pandas; `np.random.default_rng()` always
- pytest with Arrange–Act–Assert, `test_<unit>__<scenario>__<expected>` naming
- Google-style docstrings, `logging` module (never `print`)
- SOLID design principles

---

## Portability — How the Team Stays Project-Agnostic

The agent files in `agents/` contain **no project-specific identifiers** —
no GitHub usernames, no project IDs, no field/option IDs. Every variable
that changes between projects is exported by `.claude/env.sh`, which
auto-sources `.claude/project.env` at the start of every agent run.

**What lives in `project.env`:**
- `GH_OWNER`, `GH_REPO`, `GH_PROJECT_NUMBER`, `GH_PROJECT_ID` — repo and board identity
- `GH_FIELD_PIPELINE`, `GH_FIELD_AGENT`, `GH_FIELD_STATUS`, `GH_FIELD_QA_CYCLE` — board field IDs
- `GH_PIPELINE_*`, `GH_AGENT_*`, `GH_STATUS_*` — single-select option IDs
- `SUPERPOWERS_SKILLS_DIR` — where the obra/superpowers skills are installed

**What every agent does at startup:**

```bash
source .claude/env.sh   # toolchain (PYTEST, RUFF, …) + project.env
```

After that, agents address the GitHub board with `${GH_PROJECT_ID}`,
`${GH_FIELD_PIPELINE}`, etc. — never with literal IDs.

**What every agent references for process discipline:**

Each agent's prompt includes a "Superpowers Skills" table that maps
specific workflow steps to obra/superpowers skill files at
`${SUPERPOWERS_SKILLS_DIR}/<skill-name>/SKILL.md`. Examples:

| Agent | Skill | When |
|---|---|---|
| product-manager | `brainstorming`, `writing-plans` | grooming |
| product-manager | `verification-before-completion` | acceptance review |
| software-engineer | `test-driven-development` | implementation |
| software-engineer | `systematic-debugging` | debugging failures |
| software-engineer | `verification-before-completion` | before reporting done |
| software-engineer | `receiving-code-review` | rework after QA fail |
| tester | `verification-before-completion` | running tests / writing report |
| tester | `systematic-debugging` | investigating failures |
| refactoring-reviewer | `requesting-code-review`, `writing-plans` | review report |
| oncall-engineer | `systematic-debugging`, `verification-before-completion` | incident response |

To port the team to a new project: run `init-project.sh`, then walk through
the per-project `.claude/PORTING.md` checklist. The script auto-detects
your GitHub username via `gh api user`; everything else is documented.

---

## File Structure Reference

```
agent-playbook/
├── README.md                          ← You are here
├── copilot-instructions.md            ← Coding standards (portable)
├── agents/
│   ├── product-manager.md             ← PM agent (grooming + acceptance)
│   ├── software-engineer.md           ← SWE agent (implementation + tests)
│   ├── tester.md                      ← QA agent (independent verification)
│   ├── technical-writer.md            ← Tech-writer agent (theory docs in _docs/theory/)
│   ├── oncall-engineer.md             ← On-Call agent (CI/CD + infra)
│   └── refactoring-reviewer.md        ← Refactor agent (review + roadmap)
├── process/
│   ├── PROCESS.md                     ← Pipeline rules (single source of truth)
│   ├── TRACKER-GUIDE.md               ← File-based task tracking guide
│   ├── GITHUB-TRACKER-GUIDE.md        ← GitHub Issues tracking guide
│   └── AZURE-TRACKER-GUIDE.md         ← Azure DevOps Boards tracking guide
├── lib/
│   └── tracker/                       ← Tracker abstraction (deployed to .claude/lib/tracker/)
│       ├── tracker.sh                 ← Dispatcher; sourced by .claude/env.sh
│       ├── _common.sh                 ← Shared logging/helpers
│       ├── tracker_file.sh            ← File-based backend (full implementation)
│       ├── tracker_github.sh          ← GitHub Issues backend (full implementation)
│       └── tracker_azure.sh           ← Azure Boards backend (verbs implemented; bootstrap scripts not yet shipped)
├── skills/                            ← Source library (NOT read by Claude Code directly)
│   └── execute/
│       └── SKILL.md                   ← /execute skill: GitHub Issues pipeline
├── templates/
│   ├── task.todo.md                   ← Blank task template
│   ├── CLAUDE.md.template             ← Per-project CLAUDE.md skeleton
│   ├── env.sh.template                ← Toolchain bindings (auto-sources project.env)
│   ├── project.env.template           ← Per-project GitHub-project IDs + skills path
│   ├── PORTING.md.template            ← Per-project setup checklist
│   ├── settings.local.json.template   ← Default permission set for the agent team
│   └── qa-standards/
│       ├── quant-finance.md
│       ├── web-app.md
│       ├── cli-tool.md
│       └── data-pipeline.md
└── scripts/
    ├── init-project.sh                ← Bootstrap script for new projects (auto-detects GH_OWNER via gh api user)
    ├── init-github-tracker.sh         ← Create GitHub labels + Project fields
    ├── init-azure-tracker.sh          ← Verify ADO connection + print tag vocabulary (no seeding needed)
    ├── gh-setup.sh                    ← Create GitHub Project + repo and link them
    ├── azdo-setup.sh                  ← Verify existing ADO project/repo and emit AZ_* env block
    └── lib/
        └── find-python.sh             ← Shared Python-interpreter resolver
```

The **per-project** `.claude/` layout that Claude Code actually reads:

```
<project>/
├── CLAUDE.md                          ← Per-project config (filled in by you)
└── .claude/
    ├── agents/                        ← Subagents (copied verbatim by init-project.sh)
    │   ├── product-manager.md
    │   ├── software-engineer.md
    │   ├── tester.md
    │   ├── technical-writer.md
    │   ├── oncall-engineer.md
    │   └── refactoring-reviewer.md
    ├── commands/                      ← Slash commands (/execute, etc.)
    │   └── execute.md                 ← Deployed from skills/execute/SKILL.md
    ├── lib/tracker/                   ← Tracker abstraction (dispatcher + backends)
    ├── templates/                     ← Task and QA standards templates
    ├── env.sh                         ← Sourced by every agent; loads project.env,
    │                                    derives TRACKER_BACKEND from CLAUDE.md,
    │                                    sources lib/tracker/tracker.sh
    ├── project.env                    ← GitHub-project IDs + skills path (per-project)
    ├── PORTING.md                     ← Per-project setup checklist
    ├── settings.local.json            ← Local permission set (do NOT commit)
    └── copilot-instructions.md
```

> `commands/` is where Claude Code discovers custom `/` commands. Files placed in
> `.claude/skills/` are **not** picked up — that path is the playbook's internal layout only.

---

## GitHub Issues Mode

The playbook supports a **dual-mode tracker**: file-based (default) or GitHub Issues.

### When to Use Which

| Use Case | Recommended Mode |
|---|---|
| Small / experimental projects | File-based |
| Single-repo, solo developer | File-based |
| Multi-repo or team projects | GitHub Issues |
| Long-running projects with many tasks (20+) | GitHub Issues |
| Want visibility on GitHub web UI | GitHub Issues |

### How It Works

In GitHub Issues mode:
- **Tasks are GitHub Issues** instead of `*.todo.md` files
- **Pipeline states are labels** (`needs-grooming`, `ready-for-dev`, `in-progress`, etc.) instead of file renames
- **Specs, reports, and QA results are posted as issue comments** instead of appended to the task file
- **The project board** tracks everything (project number depends on which board you set up — `https://github.com/users/<your-github-user>/projects/<your-project-number>`)

The pipeline logic is identical — PM grooms, SWE implements, QA verifies, PM accepts — only the transport layer changes.

### Team Identity

All agents run under **your** `gh` credentials (the ideator's GitHub account). There are no separate GitHub accounts for PM, SWE, or QA. Each agent identifies itself by signing its comments:

```
## Implementation Report — SWE Agent
## QA Report — QA Agent
## Acceptance Review — PM Agent
```

Your `CLAUDE.md` is the single place that names you as the ideator and project owner. The `repo:` and `project:` fields tell agents which GitHub repo and Project board to operate on.

### How Agents Automatically Pick Up Work

Agents do **not** run in the background watching for new issues. The mechanism is:

1. **You run `/execute`** (or it loops automatically within a batch)
2. The orchestrator scans open issues by label state
3. It picks issues in **priority order**: `priority-high` > `priority-medium` > `priority-low`
4. Within the same priority, lowest issue number is picked first
5. The orchestrator dispatches the right agent based on the label:

| Issue Label | Agent Dispatched | Agent Does |
|---|---|---|
| `needs-grooming` + `role-pm` | PM | Reads issue, researches code, posts groomed spec as comment |
| `ready-for-dev` + `role-swe` | SWE | Reads spec comment, implements, posts impl report |
| `ready-for-qa` + `role-qa` | QA | Runs tests, posts QA report, sets PASS/FAIL |
| `ready-for-acceptance` + `role-pm` | PM | Reviews from user perspective, ACCEPT/REJECT |
| `rework-needed` + `role-swe` | SWE | Reads QA/PM failure notes, fixes, re-submits |
| `blocked` + `role-human` | **You** | Answer the question in the issue comments |

The loop continues until the backlog is empty or a human gate is hit.

### GitHub Project Board Fields

If a Project board is configured, you also get a visual kanban with these fields:

| Field | Values | Updated by |
|---|---|---|
| **Pipeline** | Backlog, Development, QA, Acceptance, Documentation, Done, Blocked | Orchestrator + agents |
| **Priority** | High, Medium, Low | You (on issue creation) — also surfaced as `priority-*` labels |
| **Agent** | PM, SWE, QA, TechWriter, On-Call, Human | Orchestrator + agents |
| **Status** | Backlog, Ready, In progress, In review, In documentation, Done | Orchestrator + agents |
| **QA Cycle** | 1, 2, 3 | SWE + QA |

Create these fields by running:
```bash
bash scripts/init-github-tracker.sh <your-github-user>/<your-repo> <your-project-number>
```

### Setup

```bash
# Bootstrap a project with GitHub Issues mode
bash scripts/init-project.sh /path/to/project quant-finance --github
```

This will:
1. Copy the agent files and the tracker abstraction (`.claude/lib/tracker/`) into the new project
2. Copy the `execute` slash command into `.claude/commands/`
3. Create all pipeline labels on the repo via `init-github-tracker.sh`
4. Set `tracker: github-issues` in the generated `CLAUDE.md`. `.claude/env.sh` reads this line at startup and exports `TRACKER_BACKEND=github-issues` for the agent team — agents never touch `gh` directly; they call `tracker_*` verbs that route to the right backend.

### Setting Up Labels Manually

If you want to add GitHub Issues support to an existing file-based project:

```bash
# Create all pipeline, priority, and role labels on a repo
bash scripts/init-github-tracker.sh <your-github-user>/<your-repo>
```

### Creating Your First Task

```bash
gh issue create \
  --title "Your first task" \
  --body "Description of what needs to be done" \
  --label "needs-grooming,priority-medium,role-pm" \
  --project "<your-github-user>/<your-project-number>"
```

Then run `/execute` in Claude Code — the GitHub-aware agents will pick it up.

See `process/GITHUB-TRACKER-GUIDE.md` for all `gh` commands and the full label reference.

---

## Azure DevOps Boards Mode

The team supports Azure DevOps Boards as a third tracker backend. The pipeline
semantics — state machine, role boundaries, QA cycle limit, dormant backlog —
are identical to GitHub mode. The transport layer differs: tags on work items
replace labels, the work-item Comments REST API replaces issue comments, and
WIQL queries replace `gh issue list`.

### When to Use Which

| Backend | Best for |
|---|---|
| `tracker: file` | Solo work, ephemeral experiments, offline / air-gapped |
| `tracker: github-issues` | Open-source projects, GitHub-native teams, public roadmaps |
| `tracker: azure-boards` | Microsoft / enterprise stacks, ADO-tracked engagements, mixed Boards + Repos workflows |

### How It Works

Same as GitHub mode (PM grooms → SWE implements → QA verifies → PM accepts → TechWriter docs)
except agents call `tracker_*` verbs instead of raw `az` calls. The
`lib/tracker/tracker_azure.sh` backend translates verbs into `az boards`
subcommands and direct REST calls for comments. Agents are **mode-agnostic**:
the same prompt runs against file, GitHub, or Azure backends.

### Prerequisites

- `az` CLI installed and authenticated (`az login` or `AZURE_DEVOPS_EXT_PAT` for CI)
- `azure-devops` extension: `az extension add --name azure-devops`
- An ADO **organization, project, and Azure Repos repository** already created
  in the web UI (the playbook does not create them — Phase B scope is
  "assume project and repo exist")
- Process template should be **Agile** (the default). Scrum / CMMI / Basic
  require setting the four `AZ_STATE_*` env vars in `.claude/project.env`
  (no source edit) — see `templates/PORTING.md.template` §4-AZ c for the
  per-process mappings.

### Setup

```bash
# 0. Verify the existing ADO org/project/repo and emit the project.env block:
bash ./agent-playbook/scripts/azdo-setup.sh \
  --org <your-azure-org> \
  --project <your-azure-project> \
  --repo <your-azure-repo>

# 1. Bootstrap the project with --azure:
bash ./agent-playbook/scripts/init-project.sh /path/to/your-project quant-finance --azure

# 2. Edit /path/to/your-project/.claude/project.env and paste the AZ_* exports
#    that azdo-setup.sh printed in step 0.

# 3. Verify the connection (also runs automatically at the end of init-project.sh
#    if AZ_ORG / AZ_PROJECT are filled in):
bash ./agent-playbook/scripts/init-azure-tracker.sh
```

### Creating Your First Work Item

```bash
source .claude/env.sh
tracker_create_issue \
  --title "Your first task" \
  --body "Description of what needs to be done" \
  --type feature --priority medium --role pm --state needs-grooming
```

Then run `/execute` in Claude Code — the agents will pick it up via the
tracker abstraction.

See `process/AZURE-TRACKER-GUIDE.md` for the tag vocabulary, transition matrix,
and quick-reference verb list.

---

## Discovery Issues

Agents can create **new backlog items** when they discover problems outside the scope of their current task — bugs in adjacent code, tech debt, missing edge cases, security concerns, etc.

### How It Works

1. The SWE, QA, or Refactoring Reviewer discovers an issue while working on their current task
2. They create a new backlog item (file-based `*.todo.md` or GitHub Issue) with a `[DISCOVERY]` prefix
3. They log the discovery in their report and continue with their original task
4. The PM will groom the discovery issue in a future pipeline cycle, just like any other task

### Rules

- **Never fixed inline** — the discovering agent does not expand the scope of their current task
- **Never self-assigned** — discovery issues go through PM grooming before anyone acts on them
- **Always includes evidence** — file path, line number, test name, or command that revealed the issue
- **Priority** — `high` only for security or data-loss risks; `medium` for everything else

### Which Agents Can Create Discovery Issues

| Agent | Typical Discoveries |
|---|---|
| **SWE** | Bugs in adjacent code, tech debt, naming inconsistencies |
| **QA** | Test gaps outside current scope, security concerns, documentation gaps |
| **Refactoring Reviewer** | Each proposed refactoring task from a code review |

PM and On-Call do not create discovery issues — PM creates tasks via grooming; On-Call creates tasks only for infrastructure incidents.

See `process/PROCESS.md` § 8 for the full specification.

---

## Adding New Skills

Skills are custom slash commands (e.g. `/execute`) that Claude Code loads from `.claude/commands/` in the project directory. The `agent-playbook/skills/` tree is the **source library** — it holds canonical `SKILL.md` files. To make a skill available in a project, its content must be deployed to `.claude/commands/<name>.md`.

### Adding a skill to the playbook (source)

1. Copy [`skills/_template/`](skills/_template/) to `agent-playbook/skills/<your-skill>/` and edit `SKILL.md`. The template covers the four required sections (pre-flight, workflow, error handling, "what this does NOT do") and points at `execute/SKILL.md` as a fully worked example.
2. Update the YAML frontmatter — `name:` must match the directory name; `description:` is the one-liner shown in `/help`.
3. If the skill relies on specific agent behaviour, document it in `process/PROCESS.md`.
4. **No edits to `init-project.sh` needed.** The bootstrap script globs `skills/*/SKILL.md` and deploys each to `.claude/commands/<name>.md` automatically. Directories whose name starts with `_` (like `_template/`) are skipped — use that prefix for examples or scaffolding you don't want deployed.

### Deploying a skill to a project

Claude Code reads slash commands **only** from `.claude/commands/` — not from `.claude/skills/`.

For projects bootstrapped *before* the new skill was added, copy it manually:

```bash
cp agent-playbook/skills/<name>/SKILL.md \
   /path/to/project/.claude/commands/<name>.md
```

For new projects, `init-project.sh` handles this for every skill in `skills/`.

---

## Onboarding Checklist

> **Tip:** for the canonical list of every placeholder, env var, and manual edit, see `USER-INPUTS.md`.

### File-Based Mode (default)
- [ ] Run `init-project.sh` to copy agents and templates to the new project
- [ ] Fill in `CLAUDE.md` (project name, tech stack, architecture, QA standards)
- [ ] Verify the path to `copilot-instructions.md` is correct in `CLAUDE.md`
- [ ] Run On-Call agent to initialise the GitHub repo (answers: visibility, branches, protection)
- [ ] Create your first `*.todo.md` task in `tracker/`
- [ ] Run `/execute` and respond to any agent questions at the gates above

### GitHub Issues Mode
- [ ] Run `gh-setup.sh` to create the GitHub Project board + repo (or pass `--link-only` if the repo already exists)
- [ ] Run `init-project.sh /path/to/project [qa-template] --github`
- [ ] Fill in `CLAUDE.md` (project name, tech stack, architecture, QA standards)
- [ ] Fill in `.claude/project.env` (`GH_REPO`, `GH_PROJECT_NUMBER`, `GH_PROJECT_ID`, all field/option IDs) — see `.claude/PORTING.md` §4 for the `gh` commands
- [ ] Verify the `repo:` and `project:` fields in `CLAUDE.md` are correct
- [ ] Verify `gh auth status` succeeds
- [ ] Run On-Call agent to initialise the GitHub repo (answers: visibility, branches, protection)
- [ ] Create your first GitHub Issue with `needs-grooming` label
- [ ] Run `/execute` and respond to any agent questions in the issue comments

### Azure DevOps Boards Mode
- [ ] Verify the ADO **organization, project, and Azure Repos repository already exist** (the playbook does not create them)
- [ ] Run `azdo-setup.sh --org … --project … --repo …` to verify the connection and emit the `AZ_*` env block
- [ ] Run `init-project.sh /path/to/project [qa-template] --azure`
- [ ] Fill in `CLAUDE.md` (project name, tech stack, architecture, QA standards, `azdo_*` block)
- [ ] Paste the `AZ_*` block from `azdo-setup.sh` into `.claude/project.env` — see `.claude/PORTING.md` §4-AZ
- [ ] Verify `az account show` succeeds and `az extension list | grep azure-devops` returns a hit
- [ ] If your project's process template is **not** Agile, set `AZ_STATE_NEW` / `AZ_STATE_ACTIVE` / `AZ_STATE_RESOLVED` / `AZ_STATE_CLOSED` in `.claude/project.env` (see `PORTING.md` §4-AZ c for per-process mappings)
- [ ] Run `init-azure-tracker.sh` to verify the connection (also runs at the end of `init-project.sh --azure`)
- [ ] Run On-Call agent to initialise git and add the ADO repo as `origin` (answers: branches)
- [ ] Create your first work item with `tracker_create_issue --state needs-grooming --role pm`
- [ ] Run `/execute` and respond to any agent questions in the work-item discussion
