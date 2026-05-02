# `gh` Call Inventory — Phase 0

Every direct invocation of the `gh` CLI in the agent prompts, the `/execute` skill, and the
setup scripts. Each row says where the call lives, the exact command shape (with placeholders),
and the **semantic verb** it implements. The verb column is what the new tracker abstraction
must cover.

Conventions:
- `{N}` = an issue number known at runtime.
- `{REPO}` = `${GH_OWNER}/${GH_REPO}` (sourced from `.claude/project.env`).
- "pipeline-time" = called by an agent during the running PM→SWE→QA→PM loop. Must move
  behind `tracker_*`.
- "setup-time" = called once by `init-project.sh` / `gh-setup.sh` / `init-github-tracker.sh`
  / On-Call Job 2. Stays as-is per the refactor spec.

---

## 1. Pipeline-time calls (target of the refactor)

### `agents/product-manager.md`

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 33 | `gh issue comment {N} --body "## Agent Questions ..."` | `tracker_comment_issue` (BLOCKED notice) |
| 39 | `gh issue edit {N} --remove-label "needs-grooming,role-pm" --add-label "blocked,role-human"` | `tracker_block_issue` |
| 65 | `gh issue view {N} --comments` | `tracker_view_issue_comments` |
| 134 | `gh issue comment {N} --body "## Groomed Specification ..."` | `tracker_comment_issue` |
| 179 | `gh issue list --state open --search "<kw>" --json number,title,labels` | `tracker_list_issues --search ...` |
| 183 | `gh issue comment <MATCH_N> --body "Raised again during grooming..."` | `tracker_comment_issue` |
| 187 | `gh issue create --title ... --body ... --label "backlog,role-human"` | `tracker_capture_backlog_item` |
| 201 | `gh issue comment {N} --body "## Backlog Capture ..."` | `tracker_comment_issue` |
| 213 | `gh issue edit {N} --remove-label "needs-grooming,role-pm" --add-label "ready-for-dev,role-swe"` | `tracker_transition` (groom → dev) |
| 218 | `gh project item-list ... | jq ... ; gh_transition $ITEM_ID ${GH_PIPELINE_DEVELOPMENT} ${GH_AGENT_SWE}` | bundled inside `tracker_transition` |
| 255 | `gh issue view {N} --comments` | `tracker_view_issue_comments` |
| 300 | `gh issue comment {N} --body "## PM Acceptance: APPROVED ..."` | `tracker_comment_issue` |
| 310 | `gh issue edit {N} --remove-label "..." ; gh issue close {N}` (PM accepts) | `tracker_close_issue` |
| 315 | `gh project item-list / gh_transition` (Pipeline=Done) | bundled inside `tracker_close_issue` |
| 346 | `gh issue comment {N} --body "## PM Acceptance: REJECTED ..."` | `tracker_comment_issue` |
| 357 | `gh issue edit {N} --remove-label "ready-for-acceptance,role-pm" --add-label "rework-needed,role-swe"` | `tracker_transition` (PM rejects) |
| 362 | `gh project item-list / gh_transition` (Agent=SWE) | bundled inside `tracker_transition` |

### `agents/software-engineer.md`

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 22 | `gh issue view {N} --comments` | `tracker_view_issue_comments` |
| 39 | `gh issue comment {N} --body "## Agent Questions (SWE) ..."` | `tracker_comment_issue` |
| 44 | `gh issue edit {N} --remove-label "ready-for-dev,role-swe" --add-label "blocked,role-human"` | `tracker_block_issue` |
| 62 | `gh issue edit {N} --remove-label "ready-for-dev" --add-label "in-progress"` | `tracker_transition` (start) |
| 117–118 | `gh issue comment {N} ...` ; `gh issue edit {N} --remove-label "role-swe" --add-label "blocked,role-human"` | `tracker_comment_issue` + `tracker_block_issue` |
| 157 | `gh issue comment {N} --body "## Implementation Report ..."` | `tracker_comment_issue` |
| 187 / 198 / 208 | `gh issue edit {N} --remove-label "in-progress,role-swe[,qa-cycle-(N-1)]" --add-label "ready-for-qa,role-qa,qa-cycle-N"` | `tracker_transition` w/ `--qa-cycle N` |
| 192 / 202 / 212 | `gh project item-list / gh_transition $ITEM_ID ${GH_PIPELINE_QA} ${GH_AGENT_QA} "" N` | bundled inside `tracker_transition` |
| 234 | `gh issue view {N} --comments` (rework — read latest QA report) | `tracker_view_issue_comments` |
| 244 | `gh issue edit {N} --remove-label "rework-needed,qa-cycle-N" --add-label "ready-for-qa,role-qa,qa-cycle-(N+1)"` | `tracker_transition` w/ `--qa-cycle (N+1)` |
| 279 | `gh issue create --repo ${REPO} --title "[DISCOVERY] ..." --body ... --label "needs-grooming,priority-*,role-pm,type-*"` | `tracker_create_issue --type ... --priority ... --role pm --state needs-grooming` |

### `agents/tester.md`

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 25 | `gh issue view {N} --comments` | `tracker_view_issue_comments` |
| 45 | `gh issue comment {N} --body "**QA BLOCKED:** No Implementation Report ..."` | `tracker_comment_issue` |
| 74–75 | `gh issue comment ...` + `gh issue edit {N} --remove-label "role-qa" --add-label "blocked,role-human"` | `tracker_comment_issue` + `tracker_block_issue` |
| 173 | `gh issue comment {N} --body "## QA Report ..."` | `tracker_comment_issue` |
| 219 | `gh issue edit {N} --remove-label "ready-for-qa,role-qa" --add-label "ready-for-acceptance,role-pm"` | `tracker_transition` (QA pass) |
| 224 | `gh project item-list / gh_transition` (Pipeline=Acceptance, Agent=PM) | bundled inside `tracker_transition` |
| 239 | `gh issue edit {N} --remove-label "ready-for-qa,role-qa" --add-label "rework-needed,role-swe"` | `tracker_transition` (QA fail) |
| 244 | `gh project item-list / gh_transition` (Pipeline=Development, Agent=SWE) | bundled inside `tracker_transition` |
| 259 | `gh issue edit {N} --remove-label "ready-for-qa,role-qa" --add-label "blocked,role-human"` | `tracker_block_issue` (cycle 3 escalation) |
| 264 | `gh project item-list / gh_transition` (Pipeline=Blocked, Agent=Human) | bundled inside `tracker_block_issue` |
| 306 | `gh issue create --title "[DISCOVERY] ..." --body ... --label "needs-grooming,priority-*,role-pm,type-*"` | `tracker_create_issue` (discovery) |

### `agents/technical-writer.md`

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 26 | `gh issue view {N} --comments` | `tracker_view_issue_comments` |
| 48 | `gh issue edit {N} --remove-label "ready-for-acceptance,role-pm" --add-label "ready-for-docs,role-techwriter"` (or equivalent) | `tracker_transition` (TW takes over) |
| 53 | `gh project item-list / gh_transition` (Pipeline=Documentation, Agent=TechWriter) | bundled inside `tracker_transition` |
| 181 | `gh issue comment {N} --body "## Documentation Report ..."` | `tracker_comment_issue` |
| 207 | `gh issue edit {N} --remove-label "ready-for-docs,role-techwriter" --add-label "docs-done"` (or `ready-for-commit`) | `tracker_transition` (docs done) |
| 212 | `gh project item-list / gh_transition` (Pipeline=Done or commit-ready) | bundled inside `tracker_transition` |
| 227–228 | blocked path: `gh issue comment ...` + `gh issue edit {N} --remove-label "role-techwriter" --add-label "blocked,role-human"` | `tracker_comment_issue` + `tracker_block_issue` |

### `agents/refactoring-reviewer.md`

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 187 | `gh issue create --repo ${REPO} --title ... --body ... --label "needs-grooming,priority-*,role-pm,type-refactor"` | `tracker_create_issue` (refactor task) |

### `agents/oncall-engineer.md` (Job 1 — incidents only)

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 329 | `gh issue comment {N} --body "## On-Call Incident Report ..."` | `tracker_comment_issue` |
| 356 | `gh issue create --title ... --label "needs-grooming,priority-*,role-pm,type-infra"` | `tracker_create_issue` |

> Job 2 of On-Call (project init) is **setup-time** — its `gh repo create`, `gh project create`,
> `gh project link`, `gh api .../branches/.../protection`, `gh api graphql` calls are out of
> scope for this refactor. They mirror what `scripts/gh-setup.sh` does but with a different
> entry point.

### `skills/execute/SKILL.md` (orchestrator)

| Line | Command (shape) | Semantic verb |
|---|---|---|
| 64–70 | `gh issue list --label "<state>" --json number,title --jq '...'` (×7 states) | `tracker_list_issues --state <state>` |
| 101 | `gh issue list --label "${label}" --json number,title,labels --jq 'sort_by(...)'` | `tracker_list_issues --state <state> --sort priority,number` |
| 150 | `gh issue view {N} --comments` (check for unanswered Agent Questions) | `tracker_view_issue_comments` |
| 251 | `gh issue close {N} --comment "Implemented, documented, and committed."` | `tracker_close_issue` |
| 262–264 | `gh issue list --label "X" --json number --jq 'length'` (end-of-batch counts) | `tracker_list_issues --state <state> --count` |

---

## 2. Setup-time calls (out of scope — stay as-is)

These calls are run once at project bootstrap. They configure the GitHub repo and the Project
board. They are not invoked by the running pipeline and therefore do not need to go through the
tracker abstraction. They will be **paralleled** by the new `scripts/az-setup.sh` and
`scripts/init-azure-tracker.sh` for ADO mode.

| File | Lines | Calls | Purpose |
|---|---|---|---|
| `scripts/gh-setup.sh` | 108, 123–128, 146 | `gh project list`, `gh project create` | Create / locate the GitHub Project |
| `scripts/gh-setup.sh` | 173, 181–188 | `gh repo view`, `gh repo create` | Create / locate the repo |
| `scripts/gh-setup.sh` | 197 | `gh api graphql` (linkProjectV2ToRepository mutation) | Link project to repo |
| `scripts/init-github-tracker.sh` | 40, 74, 140, 146–170, 189 | `gh repo view`, `gh label create`, `gh project view`, `gh project field-create` | Create labels + Project fields |
| `scripts/init-project.sh` | 48, 107, 407 | `gh api user`, demo `gh issue create` | Resolve owner; print example |
| `agents/oncall-engineer.md` Job 2 | 84, 100, 104, 114, 138 | `gh repo create`, `gh project create/link`, `gh api .../protection` | Project bootstrap (parallels `gh-setup.sh`) |
| `templates/env.sh.template` | 101–102, 116–117 | `gh project item-edit ... --single-select-option-id` / `--number` | Project field updates — wrapped in helpers `gh_set_field`, `gh_set_number_field`, `gh_transition` and called by every pipeline-time transition |

> **Note on `gh_transition` (env.sh template).** The pipeline-time wrappers `gh_transition`,
> `gh_set_field`, and `gh_set_number_field` are pipeline-time even though they live in
> `env.sh.template`. They will be **moved into `lib/tracker/tracker_github.sh`** in Phase 2
> so the github backend owns the project-field logic. `env.sh.template` will be slimmed down
> to toolchain-only exports (`PY`, `PYTEST`, etc.) plus the source of `project.env`.

---

## 3. Verb taxonomy — induced from the inventory

Every pipeline-time call collapses into one of these 12 verbs (the exact set named in the
prompt). No extra verbs were discovered.

| Verb | Inputs | Outputs | Used by |
|---|---|---|---|
| `tracker_list_issues` | `--state STATE` and/or `--role ROLE` and/or `--priority P` and/or `--search KW` and/or `--sort priority,number` and/or `--count` | one issue summary per line, OR an integer if `--count` | `/execute` orchestrator (queue picker), PM (backlog dedup search) |
| `tracker_view_issue` | `--id N` | issue title + body + labels + state (no comments) | (rare; agents typically need comments) |
| `tracker_view_issue_comments` | `--id N` | issue body + every comment, in order, with author + timestamp | PM (Job 1, Job 2), SWE (rework), QA, TW, `/execute` (block check) |
| `tracker_create_issue` | `--title T --body B --type {feature,bugfix,refactor,infra} --priority {high,medium,low} --role {pm,swe,qa,oncall,human} --state {needs-grooming,backlog,...}` | created issue id (e.g. `#42`) | SWE / QA / refactor-reviewer / on-call (discovery + new tasks) |
| `tracker_comment_issue` | `--id N --body B` (multi-line markdown supported) | — | every agent (reports, agent-questions, audit notes) |
| `tracker_transition` | `--id N --from-state S1 --to-state S2 [--from-role R1 --to-role R2] [--qa-cycle N]` | — | every state-changing agent step except block / close / capture / promote |
| `tracker_set_qa_cycle` | `--id N --cycle N` | — | only as part of `tracker_transition` in normal use; standalone for repair |
| `tracker_close_issue` | `--id N [--comment B]` | — | PM acceptance |
| `tracker_block_issue` | `--id N [--comment B]` | — | any agent on ambiguity / cycle-3 |
| `tracker_unblock_issue` | `--id N --to-role R` | — | human (after answering an Agent Question) |
| `tracker_capture_backlog_item` | `--title T --body B [--parent-id N]` | created issue id | PM Job 1, Step 4.5 |
| `tracker_promote_backlog_item` | `--id N --priority P` | — | human (manual promotion of dormant backlog) |

### Notes on the interface

1. **Atomicity.** `tracker_transition` is atomic from the agent's perspective. In the github
   backend it must perform (a) the `gh issue edit --remove-label / --add-label` swap,
   (b) the project item lookup, (c) the `gh project item-edit` field updates (Pipeline + Agent +
   optional Status + optional QA Cycle). If any sub-step fails, the verb returns non-zero and the
   error message describes which sub-step failed. The dispatcher does not retry partial state.

2. **Error-code contract** (per the Phase-1 spec):
   - `0` — success
   - `1` — tracker error (issue not found, label invalid, network failure)
   - `2` — configuration error (`gh` not authenticated, `az` not logged in, missing env vars)
   - `3` — verb not supported by this backend

3. **Backend-supported verbs.** The file backend supports all 12 verbs except
   `tracker_capture_backlog_item` and `tracker_promote_backlog_item`, which it implements as
   creating a `*.backlog.md` (dormant) and renaming it to `*.todo.md` respectively. (See the
   spec doc `interface-spec.md` for the per-verb decision matrix.)

4. **Plain-text output.** Every verb that returns data emits the same plain-text shape across
   backends. The orchestrator's grep-based parsing in `/execute` continues to work — the github
   and azure backends marshal API responses into the same shape the file backend already emits.

5. **`gh_transition` migration.** The helper currently lives in `templates/env.sh.template` and
   is called directly by agent prompts. After Phase 2 it disappears from `env.sh.template` (the
   template is slimmed to toolchain-only) and its logic moves into `tracker_github.sh` behind
   `tracker_transition`. Agent prompts stop calling `gh_transition` directly — they call
   `tracker_transition`.
