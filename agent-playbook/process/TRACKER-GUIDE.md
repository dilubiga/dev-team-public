# Task Tracker Guide

The tracker is a **file-based kanban board**. Each task is a markdown file. The file's suffix is its state.
A plain `ls tracker/` is your status view.

---

## Directory Structure

```
tracker/
├── 001-add-pricer.todo.md           ← backlog: waiting for PM grooming
├── 002-fix-null-handling.groomed.md ← ready for SWE
├── 003-refactor-auth.in-progress.md ← SWE implementing / QA testing
├── done/
│   └── 000-bootstrap-project.md    ← completed & committed
└── rejected/
    └── 004-bad-scope.md             ← archived after PM rejection (not reworked)
```

**The folder name is the status.** You do not need a separate kanban tool. `ls tracker/` is your board.

---

## File Naming Convention

```
NNN-short-description.STATE.md
```

| Part | Rule |
|---|---|
| `NNN` | Zero-padded 3-digit integer. Start at `001`. Never reuse a number. |
| `short-description` | Lowercase letters and hyphens only. Max 40 characters. No spaces. |
| `STATE` | One of: `todo`, `groomed`, `in-progress` |
| Files in `done/` or `rejected/` | Drop the state suffix: `NNN-short-description.md` |

**Good names:**
```
001-add-black-scholes-pricer.todo.md
042-fix-polars-null-coercion.todo.md
100-migrate-pandas-to-polars.groomed.md
```

**Bad names:**
```
task1.md                    ← no sequence number, no state
001 Add Pricer.todo.md      ← spaces not allowed
001-pricer.done.md          ← "done" is a directory, not a state suffix
```

---

## State Transitions

States change by **renaming the file**. Never change state by editing content alone.

```
Create         → tracker/NNN-desc.todo.md          (Ideator)
PM grooms      → tracker/NNN-desc.groomed.md       (PM agent renames)
SWE starts     → tracker/NNN-desc.in-progress.md   (SWE agent renames)
PM accepts     → tracker/done/NNN-desc.md           (PM/Orchestrator moves)
PM rejects     → stays in tracker/ as .in-progress.md, content updated
Abandoned      → tracker/rejected/NNN-desc.md       (Orchestrator archives)
```

**Why rename instead of edit?**
- `ls tracker/` gives an instant visual board without reading file contents
- File system timestamps show when each transition happened
- Simple glob patterns (`tracker/*.todo.md`) power the orchestrator's backlog scan

---

## Initializing the Tracker for a New Project

### Automatic (recommended)
```bash
bash agent-playbook/scripts/init-project.sh /path/to/project [qa-template]
```
This creates `tracker/`, `tracker/done/`, and `tracker/rejected/` for you.

### Manual
```bash
mkdir -p tracker/done tracker/rejected
```

That's it. No config files, no database, no migrations.

---

## Viewing Current Status

```bash
# Quick board view
ls tracker/

# Count by state
echo "Todo:        $(ls tracker/*.todo.md 2>/dev/null | wc -l)"
echo "Groomed:     $(ls tracker/*.groomed.md 2>/dev/null | wc -l)"
echo "In progress: $(ls tracker/*.in-progress.md 2>/dev/null | wc -l)"
echo "Done:        $(ls tracker/done/*.md 2>/dev/null | wc -l)"
echo "Rejected:    $(ls tracker/rejected/*.md 2>/dev/null | wc -l)"

# See what's blocked (has Agent Questions)
grep -l "## Agent Questions" tracker/*.md 2>/dev/null
```

---

## Creating a New Task

1. Copy the template:
   ```bash
   cp .claude/templates/task.todo.md tracker/NNN-short-description.todo.md
   ```
2. Open the file and fill in:
   - **Task title** (H1)
   - **Raw Description** — can be rough prose; the PM will refine it
   - **Priority** — `high`, `medium`, or `low`
   - **Project Context** — any notes about how this fits the larger project

3. Do NOT fill in anything below the `<!-- Below this line is filled by agents -->` separator.

---

## Task File Anatomy

A task file grows as it moves through the pipeline. Here's what it looks like at each stage:

### At creation (`*.todo.md`)
```markdown
# Task: Add Black-Scholes Pricer

## Raw Description
We need a function that prices European calls and puts using Black-Scholes.
Should handle both calls and puts, return price and delta at minimum.

## Priority
high

## Project Context
This is the core pricing engine. Other tasks depend on it.

---
<!-- Below this line is filled by agents — do not edit manually -->
```

### After PM grooming (`*.groomed.md`)
Spec sections are appended: Summary, User Story, Acceptance Criteria, Test Scenarios, Dependencies, Out of Scope.

### After SWE implementation (`*.in-progress.md`)
SWE Implementation Report is appended: files changed, approach, test results, decisions.

### After QA (`*.in-progress.md`, still)
QA Report is appended: criterion table, test output, domain standards check, verdict.

### After PM acceptance (`done/*.md`)
PM Acceptance Review is appended: verdict, rationale.

The file is a **complete audit trail** of the task's lifecycle.

---

## Handling Blocked Tasks

When an agent appends `## Agent Questions` to a task file:

1. The agent or orchestrator outputs a BLOCKED notice
2. The orchestrator skips this task and picks the next available one
3. You (the ideator) answer the question(s) in the task file
4. Restart the pipeline step that was blocked

```bash
# See all blocked tasks
grep -rl "## Agent Questions" tracker/

# Resume a blocked task after answering
claude --agent .claude/agents/product-manager.md \
  "Groom task tracker/005-blocked-task.todo.md (questions have been answered)"
```

---

## Growing Beyond 20+ Tasks

The file-based tracker works well up to ~20–30 tasks. Beyond that, consider:

- **GitHub Issues**: use `gh issue create` and update agent invocations to reference issue numbers
- The `CLAUDE.md` has a `tracker: file` setting; change to `tracker: github-issues` and update the
  orchestrator's scan commands accordingly

There is no migration script — the conceptual model (state machine, one item = one artifact) maps 1:1 to GitHub Issues. Task numbers map to issue numbers.
