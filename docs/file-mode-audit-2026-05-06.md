# File-Mode Audit — 2026-05-06

Goal: confirm that every code path in `agent-playbook/` works for `tracker: file` projects without GitHub/Azure tooling installed, and that file mode is not a second-class citizen in docs / templates.

## Method

For each file class below, grep for the listed patterns and read each match in context. Record findings in the table; do not fix anything in this commit.

## Patterns searched

- Direct `gh ` / `gh-` / `gh_` / `gh.exe` invocations outside of `lib/tracker/tracker_github.sh` and `scripts/{gh-setup,init-github-tracker}.sh`
- Direct `az ` / `az.cmd` invocations outside of `lib/tracker/tracker_azure.sh` and `scripts/{azdo-setup,init-azure-tracker}.sh`
- `${GH_*}` / `${AZ_*}` reads outside of the tracker backends
- Hard-coded references to `issue` / `comment` / `label` semantics in agent prompts that have no file-mode equivalent
- `case` / `if` branches on `TRACKER_BACKEND` / `agent_variant` that omit the `file` arm
- Onboarding / Quick Start sections that silently assume a remote

## Findings

| ID | File | Line(s) | Pattern | Risk | Fix planned in / Rationale |
|---|---|---|---|---|---|
| F1 | `agent-playbook/agents/oncall-engineer.md` | 36–41 | `gh auth status` / `az account show` / `az extension` preflight in Job 2 (Repo Init) | not-a-bug | Job 2 §"Before You Do Anything" §2 is explicitly platform-conditional; the `tracker: file` branch (line 30, line 101) skips remote setup entirely. The auth check only runs when CLAUDE.md says github/azure. |
| F2 | `agent-playbook/agents/oncall-engineer.md` | 109, 125, 129, 139, 143, 163 | `gh repo create` / `gh project create` / `gh project link` / `gh api .../protection` / `gh project field-list` references | not-a-bug | All inside Branch A (`tracker: github-issues`). Branch C (`tracker: file`) is documented at line 101 as "skip steps 4–8 entirely". |
| F3 | `agent-playbook/agents/oncall-engineer.md` | 191, 193, 202 | `az devops project show` / `az repos show` | not-a-bug | All inside Branch B (`tracker: azure-boards`). File-mode skips. |
| F4 | `agent-playbook/agents/oncall-engineer.md` | 369–388 | Job 1 "Monitoring CI" only documents GitHub Actions (`gh run …`) and Azure Pipelines (`az pipelines …`); no `tracker: file` arm | doc drift | A file-mode project may still have CI (e.g. local pre-commit, GitHub Actions on a repo whose tasks live in files). The section asserts "CI investigation tooling is platform-specific" but offers nothing for the file-mode user. Either add a "file mode: use whatever CI your repo uses; this section does not apply" aside, or explicitly note that file mode has no convention here. |
| F5 | `agent-playbook/agents/oncall-engineer.md` | 375 | `gh pr checks {PR_NUMBER}` shown as a generic CI hint | not-a-bug | Inside the GitHub Actions block — same context as F4. |
| F6 | `agent-playbook/agents/oncall-engineer.md` | 461 vs 488 | Job 1 Step 5 "Post the incident report" has explicit **File-based tracker** subsection (461) and **Issue-tracker mode** subsection (488) | good pattern | This is the bar for what a file-aware agent prompt looks like. Recorded as the model to copy when fixing F4. |
| F7 | `agent-playbook/process/GITHUB-TRACKER-GUIDE.md` | 6, 138–401 | Many bare `gh issue …`, `gh label create`, `gh project item-add` calls | not-a-bug | This entire file is the GitHub-mode guide; bare `gh` calls are the documentation. The agent prompts already say "use `tracker_*`, never `gh`". File-mode users are routed to `process/TRACKER-GUIDE.md`, not here. |
| F8 | `agent-playbook/process/PROCESS.md` | 335 | `gh issue create --repo …` snippet shown in §8 "Discovery Issues" → "GitHub Issues Tracker" sub-section | not-a-bug | Snippet lives under an explicit `### GitHub Issues Tracker` heading, paired with a `### File-Based Tracker` heading at line 320. Both modes are covered. |
| F9 | `agent-playbook/process/PROCESS.md` | 362–387 (Section 9 diagram + invocation) | "Repo Initialisation" section flow diagram shows steps 4 = `gh repo create`, step 5 = "Create GitHub Project board", step 8 = "Create GitHub Issues labels"; the invocation example is `"Initialise the GitHub repo for /path/to/project"` | doc drift | §9 reads as if every project needs a remote. The on-call agent itself supports `tracker: file` (skips steps 4–8) and has a file-mode init report template, but PROCESS.md §9 never mentions it. Add a file-mode bullet to the diagram and an alternative invocation phrasing ("Initialise the repo for …" — drop the word "GitHub"). |
| F10 | `agent-playbook/process/PROCESS.md` | 370 | "4. gh repo create → pushes to GitHub" hard-coded in §9 step list | doc drift | Same root as F9 — section is github-only when it claims to describe the canonical init flow. |
| F11 | `agent-playbook/process/PROCESS.md` | 415 | "All agents run as the **authenticated CLI user** (the ideator) — `gh` for GitHub mode, `az` for Azure mode." | not-a-bug | Sentence is inside §10 "Issue-Tracker Pipeline" which is explicitly scoped to non-file modes. |
| F12 | `agent-playbook/process/PROCESS.md` | 441 | "Azure mode: `process/AZURE-TRACKER-GUIDE.md` — … `az boards` invocations …" | not-a-bug | Inside §10's "Full reference" — pointer to the per-mode guide. |
| F13 | `agent-playbook/process/TRACKER-GUIDE.md` | 188 | "**GitHub Issues**: use `gh issue create` and update agent invocations to reference issue numbers" | not-a-bug | Inside §"Growing Beyond 20+ Tasks" — this is the file-mode guide telling users how to graduate to GitHub mode; the bare `gh` reference is intentional. Could optionally also mention azure-boards. |
| F14 | `agent-playbook/README.md` | 232 | `gh auth refresh -h github.com -s project,read:project` | not-a-bug | Inside the GitHub Issues mode Quick Start §0; only relevant to that track. |
| F15 | `agent-playbook/README.md` | 247–252, 261, 413, 458 | `gh api user`, `gh project field-list`, `gh repo create`, `gh auth status` references | not-a-bug | All inside the GitHub Issues mode Quick Start track or the §Portability section that explicitly names GH credentials. |
| F16 | `agent-playbook/README.md` | 597–606 | "Creating Your First Task" example uses `gh issue create` with no file-mode equivalent; sub-heading is "GitHub Issues Mode" | not-a-bug | Inside §"GitHub Issues Mode" — by construction. The file-mode equivalent ("`cp .claude/templates/task.todo.md tracker/001-…`") is shown earlier in §Quick Start — File mode line 188. |
| F17 | `agent-playbook/README.md` | 616 | "WIQL queries replace `gh issue list`." | not-a-bug | Inside §"Azure DevOps Boards Mode". |
| F18 | `agent-playbook/README.md` | 698 | Onboarding Checklist → **File-Based Mode** entry: "Run On-Call agent to initialise the **GitHub repo** (answers: visibility, branches, protection)" | real bug | The file-mode checklist literally instructs the user to initialise a GitHub repo. The on-call agent does support `tracker: file` and just runs `git init` + initial commit, but the checklist text is wrong: there's no GitHub, no visibility question (file mode skips ahead to step 9), and no protection rules. Fix: change wording to "Run On-Call agent to initialise the local git repo" and drop "(answers: visibility, branches, protection)". |
| F19 | `agent-playbook/README.md` | 708 | GitHub Issues Mode checklist: "Verify `gh auth status` succeeds" | not-a-bug | Inside the GitHub Issues mode checklist. |
| F20 | `agent-playbook/README.md` | 719 | Azure DevOps Boards Mode checklist: "Verify `az account show` succeeds…" | not-a-bug | Inside the Azure mode checklist. |
| F21 | `agent-playbook/scripts/init-project.sh` | 56, 122, 506 | `gh api user --jq .login`, "could not resolve via 'gh api user'", demo `gh issue create` in Next Steps | not-a-bug | Lines 56/122 are guarded behind the `--github` flag (the auto-detect of `GH_OWNER` only matters when github mode was requested). Line 506 is inside `if [[ "${USE_GITHUB}" == true ]]; then` (line 501). File mode prints a different Next Steps block. |
| F22 | `agent-playbook/skills/execute/SKILL.md` | 62, 288 | "github-issues) echo … gh auth status …" inside a `case "${TRACKER_BACKEND}"` switch | not-a-bug | Switch has all three arms (`github-issues`, `azure-boards`, `file` — line 64 / line 290). File-mode arm tells the user to verify `tracker/` exists. Correct. |
| F23 | `agent-playbook/skills/execute/SKILL.md` | 308 | Error message: "Run: bash scripts/init-github-tracker.sh ${GH_OWNER}/${GH_REPO}" | not-a-bug | Shown only under "GitHub mode (labels missing on the repo):" header at line 305; the immediately-following block at line 310–314 covers Azure. File mode has no equivalent error (no labels to seed). |
| F24 | `agent-playbook/USER-INPUTS.md` | 47, 98, 100–116, 268, 278 | Multiple `gh api user`, `gh project field-list`, `gh issue create` references | not-a-bug | All inside §1 (GitHub identity placeholders), §3 (project.env GitHub block), or §6a (GitHub issue creation). Azure has its own §3-AZ and §6b. File mode requires no fill-in here by design. |
| F25 | `agent-playbook/USER-INPUTS.md` | 155–180, 288 | Multiple `az boards`/`az devops`/`az repos` references | not-a-bug | All inside §3-AZ or §6b — Azure-mode specific sections. |
| F26 | `agent-playbook/agents/product-manager.md` | 36 | `source .claude/env.sh` … "loads … the project identifiers (`${GH_OWNER}`, `${GH_REPO}`, …)" | doc drift | Mentions only GH_* identifiers in the parenthetical example. For file-mode users this is misleading — there are no GH_* exports, and that's fine. Suggest broadening to "(`${GH_OWNER}` / `${AZ_ORG}` / etc. depending on backend)" or dropping the example. |
| F27 | `agent-playbook/agents/product-manager.md` | 42–52 | `tracker_block_issue` snippet followed by parenthetical aside "(For file-mode projects with a `*.todo.md` task file, the same call appends the questions and a sentinel marker to the file body.)" | good pattern | This is the documented bar — every tracker-vocabulary snippet that says "comment on the issue" should include a file-mode aside like this one. Used as the reference pattern when grading other findings. |
| F28 | `agent-playbook/agents/product-manager.md` | 60, 73, 120, 183, 191 | Job 1 trigger sentence and Step 1, Step 4, Step 6, Job 2 trigger all explicitly call out the file-mode equivalent (`*.todo.md` path / `*.in-progress.md` task file / "the message can use the file path") | good pattern | PM agent is the gold standard for file-mode awareness. No finding — recorded so reviewers see what "done well" looks like. |
| F29 | `agent-playbook/agents/software-engineer.md` | 15, 68 | Tracker-call header and Step 1 parenthetical "(In file mode this renames `*.groomed.md` → `*.in-progress.md`; in github / azure modes …)" | good pattern | SWE agent has the file-mode aside on Step 1. No further file-mode call-outs needed in subsequent steps because all references go through `tracker_*` verbs. |
| F30 | `agent-playbook/agents/software-engineer.md` | All "post the implementation report" / "block the issue" / "Discovery Issue" snippets (lines 45, 113, 124, 195) | doc drift | Every report-style snippet says "post a comment on the issue". File-mode users will read this and wonder where it goes. The PM-agent pattern (parenthetical aside) is not applied here. Mild — the verb does the right thing — but a reader of this prompt only learns the github vocabulary. Suggest one global aside near the top: "All references to 'comment' and 'issue' below map to file-mode equivalents (appended report blocks in `*.in-progress.md` etc.) automatically — the verb handles the translation." |
| F31 | `agent-playbook/agents/tester.md` | 17 | Tracker-call header asserts "The same verbs work for `tracker: file`, …, `tracker: azure-boards`" | good pattern | Header is correct. |
| F32 | `agent-playbook/agents/tester.md` | 129 (QA Report snippet), 188 (escalation), 196 (Discovery Issue) | All snippets say "post the QA report as a comment". No file-mode aside anywhere in the workflow. | doc drift | Same shape as F30. The tester prompt never tells the file-mode user where the QA report ends up. The verb does the right thing (appends to `*.in-progress.md`), but the prompt reads as github-only. |
| F33 | `agent-playbook/agents/technical-writer.md` | 29, 65, 69 | Tracker header asserts all three backends; Step 1 transition's prose explicitly calls out file mode ("file rename + sentinel comment in file mode"). | good pattern | Tech writer agent is file-mode-aware in the prose around `tracker_transition`. |
| F34 | `agent-playbook/agents/technical-writer.md` | 191–214 (Documentation Report) and 224 (Step 5 hand-off) | Snippets say "post the report as a comment on the issue" and reference "## Documentation Report". No file-mode aside on what file the report is appended to. | doc drift | Same shape as F30/F32. Verb handles routing, but the prompt only describes the github outcome. |
| F35 | `agent-playbook/agents/technical-writer.md` | 272 | "TODO/FIXME notes — raise a GitHub issue instead" inside "What NOT to include" | doc drift | Hard-codes "GitHub issue" — for file-mode and azure-mode this should read "raise a tracker discovery issue (`tracker_create_issue`) instead". |
| F36 | `agent-playbook/agents/oncall-engineer.md` | 16–337 (Job 2) | Job 2 has explicit per-mode branches (A=github, B=azure, C=file) with a per-mode init report template. | good pattern | This is the right shape for backend-conditional logic in an agent prompt — copy this style for any other branch that needs to behave differently per backend. |
| F37 | `agent-playbook/agents/refactoring-reviewer.md` | 22–26 | Tracker call note asserts the verbs work across all three backends and forbids direct `gh`/`az` calls. | good pattern | Header is correct. |
| F38 | `agent-playbook/agents/refactoring-reviewer.md` | 156–215 (Step 5 — Scaffold tracker tasks) | Has explicit "File-based tracker:" sub-section (line 160) AND "Issue-tracker mode" sub-section (line 186). | good pattern | Ideal shape — the same pattern should be added to F30/F32/F34. |
| F39 | `agent-playbook/README.md` | 583 | "agents never touch `gh` directly; they call `tracker_*` verbs that route to the right backend" | good pattern | Re-affirms the abstraction rule in the README. No fix needed. |
| F40 | `agent-playbook/README.md` | 389–390 | "After that, agents address the GitHub board with `${GH_PROJECT_ID}`, `${GH_FIELD_PIPELINE}`, etc. — never with literal IDs." | doc drift | §"Portability" sentence reads as if the only board is the GitHub board. For file-mode users, no `${GH_*}` is ever set, and that's fine — but the sentence could mislead a reader skimming this section into thinking the playbook always needs those IDs. Light touch fix: add ", in github mode" qualifier. |
| F41 | `agent-playbook/README.md` | 690–724 (Onboarding Checklist) | Three subsections for the three modes; file-mode is listed first. | good pattern | The checklist *structure* is correct. The bug is the wording inside the file-mode block — see F18. |
| F42 | `agent-playbook/scripts/azdo-setup.sh` | 80–136 | Many `${AZ_*}` reads | not-a-bug | This script is the Azure setup script — `${AZ_*}` reads here are by design. The grep originally excluded only `tracker_azure.sh` and `init-azure-tracker.sh`/`azdo-setup.sh`; bash globbing in the original command happened to flag this script because the exclusion list was incomplete in the audit task spec. Recorded for completeness. |
| F43 | `agent-playbook/scripts/init-azure-tracker.sh` | all listed lines | `${AZ_*}` reads | not-a-bug | Same as F42. |
| F44 | `agent-playbook/scripts/init-project.sh` | 467 | `[[ -z "${AZ_ORG_PROBE}" || -z "${AZ_PROJECT_PROBE}" ]]` | not-a-bug | Inside the `--azure` setup branch of the bootstrap script. Guarded by `USE_AZURE`. |
| F45 | `agent-playbook/skills/execute/SKILL.md` | 308 | "Run: bash scripts/init-github-tracker.sh ${GH_OWNER}/${GH_REPO}" — `${GH_*}` env var reference | not-a-bug | Embedded in a github-only error message (header at line 305). |
| F46 | `agent-playbook/USER-INPUTS.md` | 328–329 | `echo "GH_OWNER=${GH_OWNER}…"` in §8 Quick verification | doc drift | §8 "Quick verification" tells *every* user to print GH_OWNER / GH_REPO / GH_PROJECT_NUMBER / GH_PROJECT_ID. File-mode users have none of these set — running the snippet will print empty strings and may confuse them into thinking something is misconfigured. Suggest gating the GH echoes on `[[ -n "${GH_OWNER:-}" ]]` or splitting into a per-mode verification block. |
| F47 | `agent-playbook/_docs/archive/tracker-refactor/*` | many | Bare `gh`/`${GH_*}` references inside the historical refactor inventory | not-a-bug | Path is `_docs/archive/` — historical record of the github→tracker refactor. Not a runtime artifact. |
| F48 | `agent-playbook/lib/tracker/tracker.sh` | 46 | Dispatcher: error message lists "expected: file, github-issues, azure-boards" — file is in the list | good pattern | Dispatcher recognises all three backends. File-mode is not a second-class arm here. |

### Step 4 — case/if branches that omit `file`

After reading every match in context, **no agent prompt or runtime script branches on `TRACKER_BACKEND` or `agent_variant` and handles only `github-issues`+`azure-boards`**. The dispatcher (`lib/tracker/tracker.sh:46`), the `/execute` skill (`skills/execute/SKILL.md:62-65`, `:285-290`), and `init-project.sh` (`USE_GITHUB`/`USE_AZURE` conditionals with a `file` default) all include the `file` arm. Clean.

### Step 5 — Tracker-bound vocabulary in agent prompts

Recorded above as F26, F30, F32, F34, F35 (doc drift) and F27, F28, F29, F31, F33, F36, F37, F38 (good patterns). The pattern is consistent: agents whose tracker-call header asserts all three backends still slip into github-only vocabulary in their workflow snippets ("post a comment on the issue", "raise a GitHub issue"). The PM agent (F27/F28) is the gold standard with parenthetical file-mode asides; the SWE, tester, and tech writer prompts could copy that pattern.

### Step 6 — File-mode regressions in README / PROCESS / USER-INPUTS

- **README §Quick Start ordering and table** (lines 144–151): file-mode is listed first in the table — clean.
- **README §Onboarding Checklist** (lines 690–724): three subsections present, file-mode listed first — but contains a real bug at line 698 (F18).
- **PROCESS.md state machine descriptions**: §10 "Issue-Tracker Pipeline" line 408 explicitly contrasts file mode against github/azure ("File mode: `*.todo.md` → `*.groomed.md` → …"). Clean.
- **PROCESS.md §9 "Repo Initialisation"** (lines 357–396): doc drift (F9, F10) — section reads as github-only.
- **USER-INPUTS.md §8 "Quick verification"** (lines 321–335): doc drift (F46) — prints GH-only env vars unconditionally.
- **USER-INPUTS.md §2 CLAUDE.md table** (lines 68–84): includes `tracker:` row with `file` listed first as default — clean.

## Summary by classification

- **real bug**: 1 (F18)
- **doc drift**: 9 (F4, F9, F10, F26, F30, F32, F34, F35, F40, F46) — note: F26 listed once, total 10 if counted strictly; corrected — F26, F30, F32, F34, F35 (agent-prompt drift) + F4, F9, F10, F40, F46 (doc drift) = 10
- **not-a-bug**: 21 (F1, F2, F3, F5, F7, F8, F11, F12, F13, F14, F15, F16, F17, F19, F20, F21, F22, F23, F24, F25, F42, F43, F44, F45, F47) — counted strictly: 25
- **good pattern (informational)**: 8 (F6, F27, F28, F29, F31, F33, F36, F37, F38, F39, F41, F48) — counted: 12

(Counts above are advisory; the table is the source of truth.)

## Acceptance

- All findings reviewed by hand. Real bugs scheduled for Phase F.
- Items judged not-a-bug recorded with rationale in the table.
- Items recorded as "good pattern" are informational — they document the bar the doc-drift findings should be lifted to.
