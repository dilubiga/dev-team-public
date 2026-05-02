# Tracker Abstraction — Interface Specification

This document is the contract between agent prompts / `/execute` and the tracker backends.
Every pipeline-time call to a tracker (create issue, post comment, transition state, etc.)
goes through one of the 12 verbs below. The dispatcher (`lib/tracker/tracker.sh`) routes each
verb to one of three backends (`file`, `github`, `azure`) based on `$TRACKER_BACKEND`.

---

## 1. Layout

```
lib/tracker/
├── tracker.sh             # dispatcher; sourced by env.sh
├── _common.sh             # logging, error formatting, JSON helpers
├── tracker_file.sh        # backend: file (lifts from process/TRACKER-GUIDE.md)
├── tracker_github.sh      # backend: github (lifts every gh call from agents)
├── tracker_azure.sh       # backend: azure (thin wrapper over tracker_azure.py)
├── tracker_azure.py       # ADO REST client (azure-devops SDK + raw requests where needed)
└── tests/
    ├── test_dispatcher.bats
    ├── test_tracker_file.bats
    ├── test_tracker_github.py   # mocks `gh` via $PATH shim
    └── test_tracker_azure.py    # mocks ADO REST via `responses`
```

The dispatcher is sourced (not exec'd) by `.claude/env.sh`, so every verb is available as a
bash function in the calling shell. Agent prompts and `/execute` call them directly.

---

## 2. Activation

```bash
source .claude/env.sh                # sources project.env, then lib/tracker/tracker.sh
export TRACKER_BACKEND=github-issues  # one of: file, github-issues, azure-boards
tracker_list_issues --state needs-grooming   # routes to tracker_github_list_issues
```

`TRACKER_BACKEND` is set by `.claude/env.sh` from the `tracker:` line of `CLAUDE.md`. If unset,
the dispatcher defaults to `file`. Any unrecognised value yields exit code **2** (configuration
error) before any backend code runs.

---

## 3. Error-code contract

Every verb in every backend returns one of:

| Code | Meaning | Examples |
|---|---|---|
| **0** | Success | issue created, comment posted, transition complete |
| **1** | Tracker error | issue not found, label invalid, network 5xx, malformed JSON |
| **2** | Configuration error | `gh` not authenticated, `az` not logged in, `$TRACKER_BACKEND` invalid, missing required env var (e.g., `AZ_ORG`) |
| **3** | Verb not supported by this backend | future read-only file backend that does not implement `tracker_transition` |

Errors print a single human-readable line on **stderr** prefixed with the backend name and verb,
e.g. `tracker_github tracker_transition: ERROR — issue #42 not found`. Stdout is reserved for
the verb's structured output (or empty if the verb has no return value).

---

## 4. Verb reference

Each verb has the same shape across backends. Inputs are `--flag value` pairs (no positional
args) so the bash, python, and gh CLIs can all forward them losslessly. Outputs are plain text
unless noted; `--json` is reserved as a future flag.

### 4.1 `tracker_list_issues`

List issues by state / role / priority / free-text search.

| Flag | Required | Values | Notes |
|---|---|---|---|
| `--state` | optional | `needs-grooming`, `ready-for-dev`, `in-progress`, `ready-for-qa`, `ready-for-acceptance`, `ready-for-docs`, `rework-needed`, `backlog`, `blocked`, `done` | Logical state names (the github backend maps these to labels; the azure backend maps to State+Tag combinations) |
| `--role` | optional | `pm`, `swe`, `qa`, `oncall`, `techwriter`, `human` | |
| `--priority` | optional | `high`, `medium`, `low` | |
| `--search` | optional | free-text keywords | Used by PM Step 4.5 dedupe |
| `--sort` | optional | `priority,number` (default), `number` | |
| `--count` | optional | flag | Print integer count instead of listing |

Output (one issue per line):
```
#NUMBER<TAB>TITLE<TAB>STATE<TAB>ROLE<TAB>PRIORITY
```

For the file backend, `#NUMBER` is the zero-padded sequence (`#001`) and STATE is one of
`todo|groomed|in-progress|done|rejected`. The orchestrator's grep already treats the column
shape as opaque, so this works.

If `--count`, output is a single integer on stdout.

### 4.2 `tracker_view_issue`

Print issue title, body, current state, current role, current priority — no comments.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number / task file id |

Output:
```
TITLE: <title>
STATE: <state>
ROLE:  <role>
PRIORITY: <priority>
LABELS: <comma-sep raw labels for github>  # absent for file backend

---
<body>
```

### 4.3 `tracker_view_issue_comments`

Print issue body + every comment in order. This is the workhorse for "read all artifacts"
flows (PM Job 2, SWE rework, QA verification, TW).

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number / task file id |

Output is a markdown stream:
```
TITLE: <title>
STATE: <state>
---
<body>
---
[comment author=<author> at=<iso-timestamp>]
<body>
---
[comment author=... at=...]
...
```

### 4.4 `tracker_create_issue`

Create a new issue.

| Flag | Required | Values |
|---|---|---|
| `--title` | yes | string |
| `--body` | yes | markdown (multi-line OK) |
| `--type` | yes | `feature`, `bugfix`, `refactor`, `infra` |
| `--priority` | yes | `high`, `medium`, `low` |
| `--role` | yes | initial role (typically `pm`) |
| `--state` | yes | initial state (typically `needs-grooming`) |

Output: the created issue id (`#42` for github, `#001-short-desc` for file).

### 4.5 `tracker_comment_issue`

Post a markdown comment on an issue.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--body` | yes | markdown |
| `--body-file` | optional | path to a file containing the body — preferred for long comments to avoid argv limits |

Exactly one of `--body` and `--body-file` must be set. Output: empty.

### 4.6 `tracker_transition`

Atomic state transition. Updates state, role, and (where supported) the project board fields,
all in one call. Returns non-zero on the first sub-step failure.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--from-state` | yes | logical state name |
| `--to-state` | yes | logical state name |
| `--from-role` | optional | logical role name (default: keep current) |
| `--to-role` | optional | logical role name (default: keep current) |
| `--qa-cycle` | optional | integer (sets QA Cycle field/tag/label) |

Implementations:
- **file**: `mv tracker/N-desc.<from-state>.md tracker/N-desc.<to-state>.md`. QA cycle is
  encoded as a `## QA Cycle: N` line in the file body, updated via `sed -i`.
- **github**: bundles `gh issue edit --remove-label "<from-state>,role-<from>" --add-label
  "<to-state>,role-<to>[,qa-cycle-N]"` with the project field updates (Pipeline, Agent, optional
  QA Cycle). Both halves must succeed or the verb returns non-zero with the failed sub-step
  named in the error message.
- **azure**: `PATCH /workitems/{id}` with `System.State` change + tag delta + custom-field
  update for QA Cycle, all in one REST call (ADO supports atomic JSON-Patch).

### 4.7 `tracker_set_qa_cycle`

Update only the QA Cycle counter, without changing state. Standalone form, mostly for repair;
normal use bundles this inside `tracker_transition --qa-cycle N`.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--cycle` | yes | integer ≥ 1 |

### 4.8 `tracker_close_issue`

Mark an issue accepted/done. Equivalent to a transition into the terminal state, but called out
separately because the close step has different semantics across backends (file: `mv` to
`done/`; github: label swap + `gh issue close`; azure: state → Closed).

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--comment` | optional | closing comment body |

### 4.9 `tracker_block_issue`

Move an issue into the `blocked` state with `role-human`, recording the previous role so
`tracker_unblock_issue` can restore it. Optionally posts a comment first.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--comment` | optional | block reason (markdown) |

The previous role is captured in a sentinel comment (`<!-- tracker:previous-role=swe -->`) on
the issue so `tracker_unblock_issue` can restore it without external state.

### 4.10 `tracker_unblock_issue`

Inverse of `tracker_block_issue`. The `--to-role` flag is the role that should own the issue
after unblocking; if omitted, the backend reads the most recent
`tracker:previous-role` sentinel comment.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--to-role` | optional | logical role name |

### 4.11 `tracker_capture_backlog_item`

Create a dormant backlog item (PM Step 4.5). Distinct from `tracker_create_issue` because it
applies the dormant state convention specific to each backend.

| Flag | Required | Values |
|---|---|---|
| `--title` | yes | concise verb + object |
| `--body` | yes | markdown (typically references parent issue) |
| `--parent-id` | optional | parent issue number (for cross-linking) |

Backend behaviour:
- **file**: write `tracker/NNN-desc.backlog.md`. Not picked up by the orchestrator's
  `*.todo.md` glob until promoted.
- **github**: `gh issue create --label "backlog,role-human"` — explicitly **without**
  `needs-grooming`.
- **azure**: create work item in State=`New`, Tags=`backlog,role-human`, Iteration=`Backlog`.

### 4.12 `tracker_promote_backlog_item`

Promote a dormant backlog item to active grooming.

| Flag | Required | Values |
|---|---|---|
| `--id` | yes | issue number |
| `--priority` | yes | `high`, `medium`, `low` |

Backend behaviour:
- **file**: `mv tracker/N-desc.backlog.md tracker/N-desc.todo.md`; write priority into the
  body if not already there.
- **github**: `gh issue edit --remove-label "backlog,role-human" --add-label "needs-grooming,priority-X,role-pm"`.
- **azure**: state stays `New`; tag delta `backlog,role-human` → `needs-grooming,role-pm`,
  priority field set to 1/2/3.

---

## 5. Backend support matrix

All 12 verbs are required of every backend. The verb-not-supported exit code (3) exists for
*future* backend variants (e.g., a read-only mirror). For the three backends shipping in this
refactor, no verb returns 3.

| Verb | file | github | azure |
|---|---|---|---|
| `tracker_list_issues` | ✓ | ✓ | ✓ |
| `tracker_view_issue` | ✓ | ✓ | ✓ |
| `tracker_view_issue_comments` | ✓ | ✓ | ✓ |
| `tracker_create_issue` | ✓ | ✓ | ✓ |
| `tracker_comment_issue` | ✓ | ✓ | ✓ |
| `tracker_transition` | ✓ | ✓ | ✓ |
| `tracker_set_qa_cycle` | ✓ | ✓ | ✓ |
| `tracker_close_issue` | ✓ | ✓ | ✓ |
| `tracker_block_issue` | ✓ | ✓ | ✓ |
| `tracker_unblock_issue` | ✓ | ✓ | ✓ |
| `tracker_capture_backlog_item` | ✓ | ✓ | ✓ |
| `tracker_promote_backlog_item` | ✓ | ✓ | ✓ |

---

## 6. Naming + dispatch

The dispatcher exports each verb as a bash function. Internally it forwards to
`tracker_<backend>_<verb>` (e.g., `tracker_github_transition`). Backends implement the
suffix functions and **do not** export them directly — only the dispatcher does.

```bash
# tracker.sh (sketch)
tracker_transition() {
    local backend="${TRACKER_BACKEND:-file}"
    case "$backend" in
        file)           tracker_file_transition "$@" ;;
        github-issues)  tracker_github_transition "$@" ;;
        azure-boards)   tracker_azure_transition "$@" ;;
        *) echo "tracker.sh: ERROR — unknown TRACKER_BACKEND='$backend'" >&2; return 2 ;;
    esac
}
```

If a backend does not implement a verb (currently never; reserved for future), its
`tracker_<backend>_<verb>` function is defined as a one-liner that returns 3. This keeps the
dispatcher uniform.

---

## 7. Observable-behaviour invariants

The whole point of going through this is that **agent behaviour does not change** — only the
transport. Specifically:

1. The state machine in `process/PROCESS.md` §2 and `process/GITHUB-TRACKER-GUIDE.md` §"Label
   Transitions Matrix" is preserved verbatim. The new abstraction layer does not introduce
   intermediate states and does not collapse existing ones.
2. The exact comment bodies posted by each agent (Groomed Specification, Implementation Report,
   QA Report, etc.) are unchanged.
3. The five iron rules (PROCESS.md §3) and the 3-cycle QA escalation are unchanged.
4. The `[ISSUE-NNN]` / `[TASK-NNN]` commit conventions are unchanged.
5. The `/execute` orchestrator's grep-based decision logic ("if PM output contains
   `GROOMED:`...") is unchanged. Each agent still emits the same status string at the end
   of its run.

If any of the above would change to make a verb work, **stop and ask** before merging.
