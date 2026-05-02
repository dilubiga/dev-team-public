# Azure DevOps Boards Tracker Guide

The Azure DevOps Boards tracker uses **`System.Tags` as pipeline states** and
**work-item comments as artifacts**. Instead of renaming files (file mode) or
swapping labels (GitHub mode), agents transition tasks by replacing the state /
role / qa-cycle tag set on the work item. Instead of appending to markdown files,
agents post structured comments via the work-item Comments REST API.

A single `tracker_list_issues --state needs-grooming` command (a WIQL query
under the hood) replaces `ls tracker/*.state.md`.

The pipeline semantics — state machine, role boundaries, QA cycle limit, dormant
backlog — are identical to the GitHub mode. **This guide only documents what
differs in the ADO transport layer.** See `process/PROCESS.md` for the pipeline
itself and `process/GITHUB-TRACKER-GUIDE.md` for shared label / state vocabulary.

---

## Project / Repo / Boards

All work items live in an Azure DevOps **project** that contains:
- A **Boards** instance (kanban board, automatic — no separate creation step like GitHub Projects)
- An **Azure Repos** repository (the team's git remote)

Identifiers (set in `.claude/project.env`):

| Variable | Meaning | Example |
|---|---|---|
| `AZ_ORG` | Organization slug or full URL | `myorg` or `https://dev.azure.com/myorg` |
| `AZ_PROJECT` | Project name (case-sensitive) | `quant-finance` |
| `AZ_REPO` | Azure Repos repository name | `vol-surface` |
| `AZ_AREA_PATH` | Default area path for new work items (optional) | `quant-finance\backend` |
| `AZ_ITERATION_PATH` | Default iteration / sprint (optional) | `quant-finance\Sprint 5` |
| `AZ_WORK_ITEM_TYPE` | Work-item type for `tracker_create_issue` (optional, default `Task`) | `User Story` |

The project, repo, and any custom Area Path / Iteration Path **must already
exist** — the playbook does not create them. Use the ADO web UI for org-level
provisioning.

---

## Tag System

Tags encode three dimensions: **pipeline state**, **role**, and **qa cycle**.
Priority is encoded both as a tag (so `tracker_list_issues --priority high` can
filter via WIQL) and as `Microsoft.VSTS.Common.Priority` (the built-in 1-4
field, so the ADO web UI's sort-by-priority works out of the box).

`System.State` is also updated alongside tags so the kanban board reflects the
pipeline phase.

### Pipeline state tags

| Pipeline state | Tag | `System.State` (Agile template) |
|---|---|---|
| Dormant backlog | `backlog` | `New` |
| Raw task | `needs-grooming` | `New` |
| PM groomed | `ready-for-dev` | `Active` |
| SWE working | `in-progress` | `Active` |
| Ready for QA | `ready-for-qa` | `Active` |
| QA passed | `ready-for-acceptance` | `Resolved` |
| Ready for docs | `ready-for-docs` | `Resolved` |
| Rework needed | `rework-needed` | `Active` |
| Blocked | `blocked` | `New` |
| Accepted | *(no tag)* | `Closed` |

> If your project uses a non-Agile process template (Scrum, CMMI, Basic),
> override the four `AZ_STATE_*` env vars in `.claude/project.env` instead
> of editing the source. See `templates/PORTING.md.template` §4-AZ c for the
> per-process mappings. The tags themselves are process-independent.
> `init-azure-tracker.sh` warns when the detected template is not Agile.

### Role tags

Exactly **one** role tag is active per work item.

| Tag | Description |
|---|---|
| `role-pm` | Currently with Product Manager |
| `role-swe` | Currently with Software Engineer |
| `role-qa` | Currently with QA / Tester |
| `role-techwriter` | Currently with Technical Writer |
| `role-oncall` | Currently with On-Call Engineer |
| `role-human` | Waiting for the ideator (human) |

### Priority

Priority is encoded twice:

- **Tag**: `priority-high` / `priority-medium` / `priority-low` (so list / filter verbs work via WIQL `CONTAINS WORDS`)
- **Field**: `Microsoft.VSTS.Common.Priority` set to `1` (high), `2` (medium), `3` (low)

Both are written by `tracker_create_issue` and `tracker_promote_backlog_item`.
The web UI displays the field; the verbs read the tag.

### Type tags

One per work item (informational; does not drive pipeline routing).

| Tag | Description |
|---|---|
| `type-feature` | New feature or capability |
| `type-bugfix` | Bug fix |
| `type-refactor` | Code refactoring (no behaviour change) |
| `type-infra` | Infrastructure or CI/CD change |

### QA cycle tags

Same semantics as GitHub: `qa-cycle-1`, `qa-cycle-2`, `qa-cycle-3`. The
orchestrator enforces the 3-cycle limit by reading the active QA-cycle tag.

---

## Tag transitions

Same logical transitions as the GitHub guide; the verb dispatches to
`tracker_azure_*` which re-writes `System.Tags` wholesale and updates
`System.State` to match.

| Pipeline step | Verb | Effect |
|---|---|---|
| Create work item | `tracker_create_issue --state needs-grooming --role pm …` | Tags: `needs-grooming, role-pm, priority-*, type-*`. State: `New`. |
| PM captures backlog item | `tracker_capture_backlog_item --title … --body …` | Tags: `backlog, role-human`. State: `New`. |
| Human promotes backlog | `tracker_promote_backlog_item --id N --priority …` | Replaces `backlog`/`role-human` with `needs-grooming`/`role-pm`. |
| PM grooms | `tracker_transition --id N --to-state ready-for-dev --to-role swe` | Replaces state/role tags. State: `Active`. |
| SWE starts | `tracker_transition --id N --to-state in-progress` | Replaces state tag (role unchanged). State: `Active`. |
| SWE done | `tracker_transition --id N --to-state ready-for-qa --to-role qa --qa-cycle 1` | Adds `qa-cycle-1` tag. State: `Active`. |
| QA passes | `tracker_transition --id N --to-state ready-for-acceptance --to-role pm` | State: `Resolved`. |
| QA fails | `tracker_transition --id N --to-state rework-needed --to-role swe` | State: `Active`. |
| SWE reworks | `tracker_transition --id N --to-state ready-for-qa --to-role qa --qa-cycle N` | Replaces previous `qa-cycle-*` tag. |
| PM accepts | `tracker_transition --id N --to-state ready-for-docs --to-role techwriter` | State: `Resolved`. |
| TechWriter done | `tracker_close_issue --id N --comment "…"` | State: `Closed`. |
| Block | `tracker_block_issue --id N --comment "…"` | Tags: `blocked, role-human`. Sentinel comment records previous role for unblock. |
| Unblock | `tracker_unblock_issue --id N` | Restores previous role from sentinel comment; state cleared (caller transitions explicitly). |

Agents **never call `az` directly** — they use the `tracker_*` verbs. The same
verbs work in `tracker: file` and `tracker: github-issues` modes too.

---

## Reading work items

| Verb | Underlying ADO call |
|---|---|
| `tracker_list_issues [--state X --role Y --priority Z --search T]` | `az boards query --wiql "…"` |
| `tracker_view_issue --id N` | `az boards work-item show --id N` |
| `tracker_view_issue_comments --id N` | `az rest GET _apis/wit/workitems/N/comments` |

`tracker_list_issues` runs a WIQL query that filters `[System.TeamProject]`,
`[System.Tags] CONTAINS WORDS`, and (when `--state done`) `[System.State] = 'Closed'`.
Results are sorted by `Microsoft.VSTS.Common.Priority` then by ID — same order as
the GitHub backend.

---

## Comments

Comments are how the team logs reports (groom spec, QA report, PM acceptance,
TechWriter doc reference). They are posted via the work-item Comments REST API
(api-version 7.1-preview.4) because `az boards work-item update` does not have
a comment subcommand.

```bash
tracker_comment_issue --id N --body "## Implementation Report
…"
```

The body format mirrors GitHub mode — there is no ADO-specific markdown.
Comments are visible on the work-item page in the **Discussion** tab.

### Sentinel comments (block / unblock)

When `tracker_block_issue` runs, it posts a sentinel comment of the form
`<!-- tracker:previous-role=swe -->` so that `tracker_unblock_issue` can
restore the previous role without needing external state. This sentinel is
hidden by default in the ADO web UI markdown rendering.

---

## Authentication

| Mode | How |
|---|---|
| Interactive workstation | `az login` once. The `azure-devops` extension auto-uses the cached token. |
| Headless / CI | Export `AZURE_DEVOPS_EXT_PAT` with at least *Work Items: Read & Write* and *Code: Read* scopes. |

The extension is required: `az extension add --name azure-devops`.

`init-azure-tracker.sh` checks both conditions on every run and bails out with
a clear error if either is missing.

---

## What's intentionally not used

For people coming from the GitHub backend, the following ADO concepts are
**not** used by the tracker abstraction (and therefore do not need to be
configured):

- **Custom work-item fields**: the only field written beyond the built-ins is
  `Microsoft.VSTS.Common.Priority`. State / role / qa-cycle are tags, not
  fields. There is no analogue of the GitHub Project's `Pipeline` /
  `Agent` / `Status` / `QA Cycle` custom-field block.
- **Boards columns / swimlanes**: the kanban board ADO renders is purely
  visual. The pipeline truth lives in `System.Tags`, which the agents read
  and write. You can rearrange the board however you like; the agents do
  not touch column definitions.
- **Iteration Path**: optional. If you set `AZ_ITERATION_PATH`, new work
  items go into that sprint; otherwise they stay on the backlog and the
  team works the priority-sorted queue.
- **Process customisation**: the abstraction targets the stock Agile
  process template by default. For Scrum / CMMI / Basic, override the
  four `AZ_STATE_*` env vars in `.claude/project.env` (no source edit
  needed). To add or rename pipeline states beyond the existing
  vocabulary requires editing `_tracker_azure_state_tag` in
  `lib/tracker/tracker_azure.sh` and the matching dispatcher entries.

---

## Quick reference

```bash
# Source the abstraction (loads tracker_* verbs)
source .claude/env.sh

# List the queue
tracker_list_issues --state needs-grooming
tracker_list_issues --state ready-for-qa --role qa

# View a work item with its comments
tracker_view_issue --id 42
tracker_view_issue_comments --id 42

# Create a task
tracker_create_issue --title "Add Black-Scholes pricer" \
    --body "Implement the European-option pricer." \
    --type feature --priority medium --role pm --state needs-grooming

# Transition through the pipeline
tracker_transition --id 42 --to-state ready-for-dev --to-role swe
tracker_transition --id 42 --to-state in-progress
tracker_transition --id 42 --to-state ready-for-qa --to-role qa --qa-cycle 1

# Comment
tracker_comment_issue --id 42 --body "## QA Report — PASS …"

# Close
tracker_close_issue --id 42 --comment "Accepted and committed in 8a3f…"

# Block / unblock
tracker_block_issue   --id 42 --comment "Need clarification on rounding mode."
tracker_unblock_issue --id 42
```
