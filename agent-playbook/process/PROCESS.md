# Development Pipeline — Process Document

This is the **single source of truth** for how the agent team operates.
Every agent and every orchestrator session must follow this document without exception.
If this document conflicts with an agent's instructions, this document wins.

---

## Table of Contents

1. [Pipeline Overview](#1-pipeline-overview)
2. [Task Lifecycle](#2-task-lifecycle)
3. [Role Boundaries](#3-role-boundaries)
4. [Orchestrator Rules](#4-orchestrator-rules)
5. [Rejection & Rework Flow](#5-rejection--rework-flow)
6. [Commit Convention](#6-commit-convention)
7. [Refactoring Workflow](#7-refactoring-workflow)
8. [Discovery Issues](#8-discovery-issues)
9. [Repo Initialisation (One-Time Setup)](#9-repo-initialisation-one-time-setup)
10. [Issue-Tracker Pipeline](#10-issue-tracker-pipeline-when-tracker-github-issues-or-tracker-azure-boards)
11. [CI/CD Failure Flow](#11-cicd-failure-flow)

---

## 1. Pipeline Overview

```
  ┌────────────────────────────────────────────────────────────────────┐
  │                        IDEATOR (Human)                             │
  │  Creates *.todo.md tasks  │  Answers agent questions  │ Approves push│
  └──────────────┬────────────────────────────────────────────────────┘
                 │
                 ▼
  ┌──────────────────────────┐
  │   PM — Grooming (Job 1)  │  Researches codebase, writes spec
  │   *.todo.md              │──► *.groomed.md
  │   [STOP if ambiguous]    │    (or BLOCKED waiting for human)
  └──────────────┬───────────┘
                 │
                 ▼
  ┌──────────────────────────┐
  │   SWE — Implementation   │  Reads spec, writes tests first (TDD),
  │   *.groomed.md           │  implements, runs suite
  │   [STOP if unclear]      │──► *.in-progress.md + implementation report
  └──────────────┬───────────┘
                 │
                 ▼
  ┌──────────────────────────┐       ┌─────────────────────────────┐
  │   QA — Verification      │ FAIL  │  SWE reworks                │
  │   *.in-progress.md       │──────►│  (max 3 cycles total)       │
  │                          │       │  cycle 3 fail → human gate  │
  └──────────────┬───────────┘       └─────────────────────────────┘
                 │ PASS
                 ▼
  ┌──────────────────────────┐       ┌─────────────────────────────┐
  │   PM — Acceptance (Job 2)│REJECT │  SWE reworks with PM notes  │
  │   *.in-progress.md       │──────►│  may need re-grooming       │
  │                          │       └─────────────────────────────┘
  └──────────────┬───────────┘
                 │ ACCEPT
                 ▼
  ┌──────────────────────────┐
  │   TechWriter — Docs      │  Writes theory doc in _docs/theory/
  │   Pipeline=Documentation │──► DOCS DONE
  │   Status=In documentation│
  └──────────────┬───────────┘
                 │ DOCS DONE
                 ▼
  ┌──────────────────────────┐
  │   IDEATOR reviews diff   │  Human approves git push
  │   Orchestrator commits   │──► tracker/done/NNN-description.md
  └──────────────────────────┘
```

---

## 2. Task Lifecycle

Tasks are tracked as files in the `tracker/` directory. The file's extension suffix is its state.
**State transitions happen via file rename, not by editing content.**

| State | File pattern | Meaning | Who transitions |
|---|---|---|---|
| **Todo** | `NNN-desc.todo.md` | Raw task, waiting for PM | Ideator creates it |
| **Groomed** | `NNN-desc.groomed.md` | PM wrote spec, ready for SWE | PM renames from `.todo.md` |
| **In Progress** | `NNN-desc.in-progress.md` | SWE implementing OR QA testing | SWE renames from `.groomed.md` |
| **Done** | `done/NNN-desc.md` | PM accepted, code committed | PM/Orchestrator moves to `done/` |
| **Rejected** | `rejected/NNN-desc.md` | PM rejected at acceptance | Orchestrator archives after rework |

### Naming Convention
```
NNN-short-description.STATE.md
```
- `NNN` — zero-padded 3-digit sequence number (001, 002, ..., 099, 100)
- `short-description` — lowercase, hyphens, max 40 chars
- `STATE` — one of: `todo`, `groomed`, `in-progress`
- Files in `done/` and `rejected/` drop the state suffix

**Examples:**
```
tracker/001-add-black-scholes-pricer.todo.md
tracker/001-add-black-scholes-pricer.groomed.md
tracker/001-add-black-scholes-pricer.in-progress.md
tracker/done/001-add-black-scholes-pricer.md
```

---

## 3. Role Boundaries

These rules are **absolute**. No exceptions, no "just this once".

| Role | Can do | Cannot do |
|---|---|---|
| **Ideator (human)** | Everything | — |
| **PM** | Read code, write specs, read reports, rename files | Write code, run tests, commit |
| **SWE** | Read/write code, run tests locally, rename task file once | Decide completeness, commit, push |
| **QA** | Read code, run tests, write reports | Fix code, accept/reject task, commit |
| **Technical Writer** | Read code, write docs in `_docs/theory/`, post documentation reports | Modify code or tests, accept tasks, commit |
| **On-Call** | Fix infra/tooling, run any command | Change feature logic, accept tasks |
| **Refactoring Reviewer** | Read code, write review report, create todo files | Change code, run pipeline, commit |
| **Orchestrator** | Spawn agents, rename files, commit (after PM accept + tech writer + human approval) | Skip steps, accept tasks, write code |

### The Five Iron Rules
1. **PM NEVER writes code** — not even a one-liner "to illustrate"
2. **SWE NEVER decides if a task is complete** — QA and PM do
3. **QA NEVER fixes code** — QA reports; SWE fixes
4. **On-Call NEVER changes feature logic** — infra only; feature bugs escalate to QA
5. **Orchestrator NEVER skips PM grooming or QA** — both are mandatory for every task

---

## 4. Orchestrator Rules

The orchestrator is the main Claude Code session that coordinates the agents. It follows these rules:

### Batch Processing
- Default batch size: **2 tasks** (configurable per project in `CLAUDE.md` under `batch_size`)
- Pick the next `N` tasks from `tracker/*.todo.md`, ordered by sequence number
- Process tasks in a batch before starting the next batch
- If a task is **blocked** (waiting for human input), skip it and pick the next available task
- Do NOT process more than `batch_size` tasks simultaneously
- **Refactoring tasks** that the Refactoring Reviewer created as `*.todo.md` files are processed identically to any other task — PM grooms them, SWE implements, QA verifies, PM accepts. No special handling is needed.

### The Recurring Loop
After completing a batch:
1. Check if any `*.todo.md` tasks remain in `tracker/`
2. If yes: process the next batch automatically
3. If no: report "Backlog empty — all tasks complete." and stop

This loop continues without human intervention unless a gate is hit.

### Agent Invocation Syntax
```bash
# PM grooming
claude --agent .claude/agents/product-manager.md \
  "Groom task tracker/NNN-description.todo.md"

# SWE implementation
claude --agent .claude/agents/software-engineer.md \
  "Implement task tracker/NNN-description.groomed.md"

# QA verification
claude --agent .claude/agents/tester.md \
  "Verify task tracker/NNN-description.in-progress.md"

# PM acceptance
claude --agent .claude/agents/product-manager.md \
  "Acceptance review for task tracker/NNN-description.in-progress.md"

# Technical Writer (after PM accept, GitHub mode)
claude --agent .claude/agents/technical-writer.md \
  "Write theory documentation for issue #NNN in repo <your-github-user>/<your-repo>"

# On-Call (as needed)
claude --agent .claude/agents/oncall-engineer.md \
  "Diagnose failure: [paste error summary]"

# Refactoring review (manual, not part of main loop)
claude --agent .claude/agents/refactoring-reviewer.md \
  "Review module src/pricing/"
```

### Commit Protocol
After PM acceptance and **human approval of the diff**:
```bash
git add <files changed by this task only>
git commit -m "[TASK-NNN] brief description of what was implemented"
```
- One commit per task (squash if SWE made multiple commits)
- Commit message must reference the task number
- **Never `git push` without explicit human instruction**

### Handling Failure Cycles
```
QA FAIL cycle 1 → return task to SWE, append QA report
QA FAIL cycle 2 → return task to SWE, append QA report (second)
QA FAIL cycle 3 → STOP, escalate to human: "Task NNN has failed QA 3 times. Human review needed."

PM REJECT → return task to SWE with rejection notes
            If PM rejects after cycle 2 QA pass → consider re-grooming:
            ask human if the spec needs to change
```

---

## 5. Rejection & Rework Flow

### QA Fails
```
QA appends failure report to *.in-progress.md
  └── Orchestrator calls SWE with: "Fix QA failures in tracker/NNN.in-progress.md"
      SWE reads QA report, fixes issues, re-runs tests, updates implementation report
      └── Orchestrator calls QA again
          └── if PASS: proceed to PM acceptance
              if FAIL: repeat (max 3 total cycles)
                       if cycle 3 FAIL: escalate to human
```

### PM Rejects
```
PM appends rejection notes to task file
  └── Orchestrator calls SWE with: "Rework based on PM rejection in tracker/NNN.in-progress.md"
      SWE reads rejection reasons, implements changes
      └── Orchestrator calls QA again (counts as a new cycle)
          └── Proceed normally through QA → PM
              If PM rejects again after QA pass:
              Orchestrator asks human: "PM has rejected twice. Do you want to re-groom the spec?"
```

### Block / Unblock contract

When an agent is blocked by ambiguity it calls `tracker_block_issue --id N --comment "..."`. The dispatcher sets the state to `blocked` and the role to `human`, and writes a sentinel comment (`<!-- tracker:previous-role=swe -->` or similar) recording the role that was active before the block.

When the human answers and the orchestrator (or a future agent) calls `tracker_unblock_issue --id N`, the dispatcher reads the sentinel and restores the previous **role** — but it does **not** restore the previous state. The work item is left in an in-between condition until the caller issues a follow-up `tracker_transition --id N --to-state <next>`.

**Rule:** every `tracker_unblock_issue` call must be immediately followed by a `tracker_transition --to-state` so the work item lands on a real pipeline state. The orchestrator and any agent that performs unblocks must follow this two-call sequence; otherwise the kanban / queue shows a work item with `role-<X>` but no state tag, and `/execute`'s state-based scan will skip it.

This contract holds across all three backends. The file backend is slightly more forgiving (it preserves the on-disk state suffix through block/unblock) but the rule is the same: callers must transition explicitly.

---

## 6. Commit Convention

```
[TASK-NNN] brief description in imperative mood
```

**Examples:**
```
[TASK-001] add Black-Scholes pricer with Greeks
[TASK-007] fix null handling in ETL pipeline
[TASK-023] refactor auth middleware to inject token store
```

**Rules:**
- Imperative mood ("add", "fix", "refactor" — not "added", "fixes")
- Brief: max 72 characters total including the prefix
- Each task = one commit; squash if SWE made intermediate commits
- Reference the task number so the commit links to the tracker file

---

## 7. Refactoring Workflow

The refactoring workflow is a **separate entry point** from the main pipeline.

```
Ideator specifies scope
      │
      ▼
Refactoring Reviewer reads code → produces review report + proposed tasks
      │
      ▼
Ideator reviews report, selects which tasks to action
      │
      ▼
Selected tasks become *.todo.md files in tracker/
      │
      ▼
Normal pipeline: PM groom → SWE implement → QA verify → PM accept → commit
```

Refactoring tasks flow through the full pipeline like any other task.
The PM will groom them (possibly abbreviated, since the reviewer's report is already detailed).
QA will verify that the refactor preserved behavior (existing tests must still pass).

---

## 8. Discovery Issues

During implementation or QA verification, agents may discover problems **outside the scope of the
current task** — a bug in adjacent code, tech debt, a missing edge case, a security concern, etc.

### Rule: Never Fix Inline

Discovery issues are **never fixed inline**. The discovering agent creates a new backlog item and
continues with their current task. The discovery item enters the normal pipeline: the PM will groom it,
prioritize it, and assign it to the SWE when the time comes.

### Who Can Create Discovery Issues

| Agent | When | What they create |
|---|---|---|
| **SWE** | During implementation — finding bugs, tech debt, or edge cases in adjacent code | Backlog task (file or issue) |
| **QA** | During testing — finding test gaps, security concerns, or bugs outside current scope | Backlog task (file or issue) |
| **Refactoring Reviewer** | During code review — each proposed refactoring becomes a task | Backlog tasks (file or issue) |

**PM and On-Call do NOT create discovery issues** — PM creates tasks via grooming; On-Call creates tasks
only for infrastructure incidents.

> **Exception — PM backlog capture during grooming.** During Job 1 (task grooming), the PM iterates over
> the `Out of Scope` bullets of the spec it just wrote and captures each concrete, actionable one as a
> **dormant** backlog issue (`backlog` + `role-human`, NOT `needs-grooming`). This is not a
> discovery issue in the SWE/QA sense — it does not enter the active pipeline and is invisible to the
> orchestrator until a human promotes it. See `agents/product-manager.md` Step 4.5 for the
> qualification rules (strict: verb + object, no vague aspirations) and `process/GITHUB-TRACKER-GUIDE.md`
> for the label transitions.

### File-Based Tracker

```bash
cp .claude/templates/task.todo.md tracker/NNN-discovery-brief-description.todo.md
```

The agent fills in:
- `# Task: [DISCOVERY] Brief description`
- References the current task/issue that was being worked on
- Includes evidence: file path, line number, test name, or command
- Sets priority: `high` for security/data-loss risks, `medium` for everything else

### GitHub Issues Tracker

```bash
gh issue create --repo <your-github-user>/<your-repo> \
  --title "[DISCOVERY] Brief description" \
  --body "..." \
  --label "needs-grooming,priority-medium,role-pm,type-bugfix" \
  --project "<your-github-user>/<your-project-number>"
```

Labels:
- Always `needs-grooming` and `role-pm` — the PM must groom it before anyone acts on it
- `type-bugfix` for bugs, `type-refactor` for tech debt, `type-feature` for missing functionality
- `priority-high` for security or data-loss risks, `priority-medium` otherwise

### Constraints

1. **Never self-assign** — the discovering agent must not pick up their own discovery issue
2. **Never expand current task scope** — the discovery is a separate backlog item
3. **Always include evidence** — file, line, test, or command that revealed the issue
4. **Always reference the originating task** — so the PM has context when grooming
5. **Log it in your report** — SWE logs in Implementation Report, QA logs in QA Report, Reviewer logs in Review Report

---

## 9. Repo Initialisation (One-Time Setup)

This step runs **once per project**, before the main pipeline starts. It is not part of the recurring
PM→SWE→QA loop.

```
Ideator confirms: visibility, branch strategy, protection rules
      │
      ▼
On-Call — Job 2
  1. git init -b main
  2. Create .gitignore (if absent)
  3. Initial commit (staged files only — never git add .)
  4. gh repo create → pushes to GitHub
  5. Create GitHub Project board (if requested) → links to repo, updates CLAUDE.md
  6. Create develop branch (if requested)
  7. Apply branch protection rules to main (if requested)
  8. Create GitHub Issues labels (if tracker: github-issues)
      │
      ▼
Ideator reviews repo on GitHub, confirms setup
      │
      ▼
Normal pipeline begins (PM groom → SWE → QA → PM accept → commit → push)
```

**Invocation:**
```bash
claude --agent .claude/agents/oncall-engineer.md \
  "Initialise the GitHub repo for /path/to/project"
```

**On-Call will ask before proceeding:**
- Repository visibility: public or private?
- Default branch: `main` or other?
- Create `develop` branch alongside `main`?
- Apply branch protection rules to `main`?

On-Call never pushes to an existing remote without explicit human confirmation.

---

## 10. Issue-Tracker Pipeline (when `tracker: github-issues` or `tracker: azure-boards`)

When a project uses an issue-tracker backend, the pipeline logic is identical to the file-based mode,
but the transport layer changes entirely. **The pipeline semantics are the same across both
backends** — the same agents run, the same state machine applies, and the orchestrator's behaviour
is identical. Only the underlying mechanism (labels + Project fields vs. tags + `System.State`)
differs.

### State machine
- **File mode**: `*.todo.md` → `*.groomed.md` → `*.in-progress.md` → `done/` (renames)
- **Issue-tracker modes**: `needs-grooming` → `ready-for-dev` → `in-progress` → `ready-for-qa` → `ready-for-acceptance` → `ready-for-docs` → issue / work-item closed
  - In **GitHub mode** the state is the active label on the issue, plus a `docs-done` label between PM accept and close.
  - In **Azure mode** the state is the active state-tag on the work item, paired with a `System.State` value (Agile: New / Active / Resolved / Closed by default; configurable per-project via `AZ_STATE_*` env vars).
- **Dormant side state**: `backlog` + `role-human` — captured by the PM from Out-of-Scope bullets during grooming. Not part of the active pipeline; a human must promote it by swapping to `needs-grooming` + `role-pm` (via `tracker_promote_backlog_item`) before it enters the state machine above.

### Agent identity
All agents run as the **authenticated CLI user** (the ideator) — `gh` for GitHub mode, `az` for Azure mode. Agents identify themselves by signing their comments (e.g., `## Implementation Report — SWE Agent`). There are no separate accounts per agent in either backend.

### Priority
The orchestrator picks issues in priority order: `priority-high` > `priority-medium` > `priority-low`. Within the same priority, lowest ID wins. The dispatcher's `tracker_list_issues` returns items pre-sorted by priority then ID in both backends.

### Visual kanban
- **GitHub mode**: if a Project is configured, the orchestrator updates Project fields (Pipeline, Status, Priority, Agent, QA Cycle) alongside labels for a kanban view on the GitHub web UI.
  - Pipeline stages: Backlog → Development → QA → Acceptance → **Documentation** → Done (plus a side-state of Blocked)
  - Status values: Backlog → Ready → In progress → In review → **In documentation** → Done
  - Grooming is **not** a separate Pipeline value. While the PM is grooming, the issue stays in `Backlog` with `needs-grooming` + `role-pm`.
- **Azure mode**: ADO renders a kanban board automatically per Boards. Columns map to `System.State` (Agile: New / Active / Resolved / Closed). The state-tag (e.g. `ready-for-qa`) carries the fine-grained pipeline phase within a `System.State`. No custom Project-board fields are required.

### Role tags / labels
Exactly one `role-*` label / tag is active at a time, showing who currently owns the issue / work item. When an agent is blocked and needs human input, it sets the state to `blocked` and the role to `role-human` (see §5 "Block / Unblock contract").

### QA cycle tracking
QA cycle labels / tags (`qa-cycle-1`, `qa-cycle-2`, `qa-cycle-3`) are used instead of counting sections in a file. The orchestrator reads them to enforce the 3-cycle limit. Same vocabulary in both backends.

### Commit convention
Both issue-tracker modes use the same commit convention, with issue / work-item numbers in place of task file numbers:
```
[ISSUE-NNN] brief description in imperative mood
```

### Full reference
- GitHub mode: `process/GITHUB-TRACKER-GUIDE.md` — label system, transition matrix, `gh` commands, Project-board field updates.
- Azure mode: `process/AZURE-TRACKER-GUIDE.md` — tag system, transition matrix, `az boards` invocations, Comments REST API usage.

Both guides implement the same pipeline semantics described above; the differences are limited to the transport layer.

---

## 11. CI/CD Failure Flow

```
CI fails on a commit (lint, tests, build, deploy)
      │
      ▼
On-Call diagnoses root cause
      │
      ├── Infrastructure issue → On-Call fixes → verifies → reports
      │
      └── Feature code issue → On-Call escalates to QA as a QA failure
                                (creates a new task or flags existing one)
```

On-Call **never modifies feature logic** to make CI pass. If a test failure
points to a bug in the code under test, On-Call hands it back to the QA / SWE
loop instead of patching the symptom.
