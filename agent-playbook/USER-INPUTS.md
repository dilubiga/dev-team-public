# USER-INPUTS — Where you have to fill things in by hand

This is the single reference for every placeholder, environment variable, and
manual edit the agent-playbook expects from you, the human ideator. Work
through it top-to-bottom the first time you bootstrap a project; come back
to it whenever you copy/paste a snippet from the README or a guide and see
something in `<angle-brackets>`, `[BRACKETS]`, `__UNDERSCORES__`, or
`YOUR_…` shouting at you.

Every entry below names:

- **What to replace** — the literal placeholder string, exactly as it appears
- **Where it appears** — files where you'll see it
- **What to put instead** — the value you supply (and how to find it, if it's
  not obvious)

If a value is wrong or missing, the agents fail loudly — they never invent a
fallback. So fill these in *before* running `/execute`.

---

## 1. Identity placeholders (you, your repo, your project board)

These show up across the README, the GitHub-tracker guide, the templates,
and shell scripts as example/illustration text. They are **not** templated
— they're literal copy-paste examples you substitute when adapting commands.

The playbook standardises on the angle-bracket lowercase-hyphenated form.
A single placeholder name means the same thing wherever it appears.

| Placeholder | Replace with |
|---|---|
| `<your-github-user>` | Your GitHub username or org login (GitHub Issues mode) |
| `<your-repo>` | Your repository name (GitHub Issues mode) |
| `<your-project-name>` | The title of the GitHub Project board (only used by `gh-setup.sh` when **creating** a board) |
| `<your-project-number>` | The numeric ID of the GitHub Project (visible in the URL: `github.com/users/<your-github-user>/projects/<your-project-number>`) |
| `<your-azure-org>` | Azure DevOps organization slug ("myorg") or full URL ("https://dev.azure.com/myorg") |
| `<your-azure-project>` | Azure DevOps project name (case-sensitive) |
| `<your-azure-repo>` | Azure Repos repository name (case-sensitive) |
| `<your-area-path>` | Optional ADO Area Path for new work items; defaults to the project root |
| `<this-project>` / `<your-projects>` / `<projects-root>` | Path components used only to explain the default `Skills:` path in `CLAUDE.md.template` |
| `[PROJECT_NAME]` | Human-readable project name (page title in `CLAUDE.md`) |

### Script-internal substitution tokens (do not edit by hand)

These look like placeholders but are **resolved automatically by
`init-project.sh`** (via `gh api user --jq .login` plus `sed`). You only
edit them by hand if `gh` was not authenticated when you ran the bootstrap
script, in which case the script warns you and tells you which file to fix.

| Token | Where | Resolved to |
|---|---|---|
| `__OWNER__` | `templates/project.env.template` → `.claude/project.env` | Your GitHub login |
| `[OWNER]/N` | `templates/CLAUDE.md.template` → `CLAUDE.md` | `<your-github-user>/<your-project-number>` |
| `[OWNER]/[REPO_NAME]` | `templates/CLAUDE.md.template` → `CLAUDE.md` | `<your-github-user>/<your-repo>` |

After `init-project.sh` runs, grep the generated files for `__OWNER__` or
`[OWNER]` to confirm none remain. If any do, edit them by hand using the
table above.

---

## 2. `CLAUDE.md` (per project) — manual edits

`init-project.sh` copies `templates/CLAUDE.md.template` to
`<your-project>/CLAUDE.md`. You must fill in:

| Section | What to enter |
|---|---|
| `# Project: [PROJECT_NAME]` | Your project's name |
| `## Overview` | 2-3 sentences: what the project does, who uses it, what it produces |
| `## Tech Stack` | Languages, frameworks, key libraries with versions |
| `## Skills Path` | Informational — `env.sh` auto-detects the [obra/superpowers](https://github.com/obra/superpowers) skills directory. Override only by setting `SUPERPOWERS_SKILLS_DIR` in `.claude/project.env`. See `PORTING.md` §4e for install instructions. |
| `## Architecture` | Key directories and their purpose |
| `## Entry Points` | How to run the project, run tests, lint, format |
| `## QA Standards` | Auto-injected from one of the four QA standard templates if `init-project.sh` created CLAUDE.md fresh; otherwise paste from `.claude/templates/qa-standards/<template>.md` |
| `### Batch Size` (`batch_size:`) | How many tasks `/execute` processes per batch; default `2` |
| `### Task Tracker` (`tracker:`) | `file` (default), `github-issues`, or `azure-boards` (verbs implemented; not yet bootstrappable end-to-end via `init-project.sh`) |
| `### GitHub Project` block (`github_project_action`, `github_project_name`, `github_project_number`) | Only fill in when using `github-issues` mode and BEFORE running the on-call agent for repo init |
| `<!-- project: [OWNER]/N -->` and `<!-- repo: [OWNER]/[REPO_NAME] -->` | Replace `[OWNER]`, `N`, `[REPO_NAME]` with real values once known (init-project.sh does this for you in `--github` mode) |
| `### Azure DevOps Project` block (`azdo_org`, `azdo_project`, `azdo_repo`, optional `azdo_area_path` / `azdo_iteration_path` / `azdo_work_item_type`) | Only fill in when using `azure-boards` mode. The org/project/repo must already exist in ADO. |
| `### Agent Variant` (`agent_variant:`) | `file`, `github`, or `azure` — must match the tracker mode above |
| `## Domain-Specific Rules` | Any project-specific constraints beyond `copilot-instructions.md` |
| `## Dependencies Between Tasks` | Optional inter-task ordering notes |

---

## 3. `.claude/project.env` (per project) — manual edits

`init-project.sh` populates `GH_OWNER` automatically (if `gh` is
authenticated). Everything else is yours. The variables below are the names
defined in `templates/project.env.template`.

### 3a. Repo identity

| Variable | What to enter | How to find it |
|---|---|---|
| `GH_OWNER` | GitHub username or org login | Auto-filled, or `gh api user --jq .login` |
| `GH_REPO` | Repository name (no owner prefix) | The name of your repo |
| `GH_PROJECT_NUMBER` | Numeric Project board ID | `github.com/users/<owner>/projects/<your-project-number>` URL, or `gh project list --owner <your-github-user>` |
| `GH_PROJECT_ID` | Project node ID (`PVT_kw…`) | `gh project view <your-project-number> --owner <your-github-user> --format json \| jq '.id'` |

### 3b. Project board field IDs

Resolve all four with: `gh project field-list <your-project-number> --owner <your-github-user> --format json | jq '.fields[] | {name, id, type}'`

| Variable | Field name on board (single-select unless noted) |
|---|---|
| `GH_FIELD_PIPELINE` | `Pipeline` |
| `GH_FIELD_AGENT` | `Agent` |
| `GH_FIELD_STATUS` | `Status` |
| `GH_FIELD_QA_CYCLE` | `QA Cycle` (number field) |

### 3c. Pipeline option IDs (`Pipeline` field values)

Resolve with: `gh project field-list <your-project-number> --owner <your-github-user> --format json | jq '.fields[] | select(.name=="Pipeline") | .options[] | {name, id}'`

| Variable | Option name on board |
|---|---|
| `GH_PIPELINE_BACKLOG` | `Backlog` |
| `GH_PIPELINE_DEVELOPMENT` | `Development` |
| `GH_PIPELINE_QA` | `QA` |
| `GH_PIPELINE_ACCEPTANCE` | `Acceptance` |
| `GH_PIPELINE_DOCUMENTATION` | `Documentation` |
| `GH_PIPELINE_DONE` | `Done` |
| `GH_PIPELINE_BLOCKED` | `Blocked` |

> If your board does not have an option with the exact name, **create it on
> the board first** — do not invent placeholders.

### 3d. Agent option IDs (`Agent` field values)

| Variable | Option name on board |
|---|---|
| `GH_AGENT_PM` | `PM` |
| `GH_AGENT_SWE` | `SWE` |
| `GH_AGENT_QA` | `QA` |
| `GH_AGENT_TECHWRITER` | `TechWriter` |
| `GH_AGENT_HUMAN` | `Human` |

### 3e. Status option IDs (`Status` field values)

| Variable | Option name on board |
|---|---|
| `GH_STATUS_BACKLOG` | `Backlog` |
| `GH_STATUS_IN_DOCS` | `In documentation` |
| `GH_STATUS_DONE` | `Done` |

### 3-AZ. Azure DevOps mode (`tracker: azure-boards`)

Skip this section if you are using `tracker: file` or `tracker: github-issues`.

| Variable | What to enter | How to find it |
|---|---|---|
| `AZ_ORG` | Org slug or full URL | `az devops project list --org https://dev.azure.com/<your-azure-org>` |
| `AZ_PROJECT` | Project name (case-sensitive) | The visible name in the ADO web UI |
| `AZ_REPO` | Azure Repos repo name (case-sensitive) | `az repos list --org <org-url> --project <project> --query [].name -o tsv` |
| `AZ_AREA_PATH` *(optional)* | Default Area Path for new work items | `az boards area project list --org <org-url> --project <project>`; leave blank to default to project root |
| `AZ_ITERATION_PATH` *(optional)* | Default Iteration Path | `az boards iteration project list --org <org-url> --project <project>`; leave blank for backlog |
| `AZ_WORK_ITEM_TYPE` *(optional)* | Work-item type for new items | Default `Task`. Set to `User Story`, `Bug`, etc. as needed for your process. |

**Authentication** — interactive workstations: `az login` once (and
`az extension add --name azure-devops` if not already installed).
Headless / CI: export `AZURE_DEVOPS_EXT_PAT` with at least *Work Items: Read & Write*
and *Code: Read* scopes — the extension reads it automatically.

**Process template** — `tracker_azure.sh` maps `System.State` to the **Agile**
template values (`New`/`Active`/`Resolved`/`Closed`). For Scrum, CMMI, or Basic
projects, override per-state via env vars in `.claude/project.env` (no source edit
required):

| Variable | Agile (default) | Scrum | CMMI | Basic |
|---|---|---|---|---|
| `AZ_STATE_NEW` | `New` | `New` | `Proposed` | `To Do` |
| `AZ_STATE_ACTIVE` | `Active` | `Committed` | `Active` | `Doing` |
| `AZ_STATE_RESOLVED` | `Resolved` | `Done` | `Resolved` | `Doing` |
| `AZ_STATE_CLOSED` | `Closed` | `Done` | `Closed` | `Done` |

Verify your project's actual state names with:
`az boards work-item show --id <existing-id> -o json | jq '.fields["System.State"]'`.
`init-azure-tracker.sh` warns when the detected process template is not Agile.

### 3f. Skills directory

| Variable | What to enter |
|---|---|
| `SUPERPOWERS_SKILLS_DIR` | **Usually unset.** `env.sh` auto-detects, in order: an explicit value here, then `~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills` (Claude Code plugin), then `~/superpowers/skills`, `~/github/superpowers/skills`, `~/code/superpowers/skills`, `../../github/superpowers/skills`. Install: `/plugin install superpowers@claude-plugins-official` (Claude Code) or `git clone https://github.com/obra/superpowers ~/superpowers` (other tools). Override here with an absolute path only if auto-detect picks the wrong one. Verify with `ls "${SUPERPOWERS_SKILLS_DIR}/test-driven-development/SKILL.md"` after sourcing. |

---

## 4. `.claude/PORTING.md` (per project) — checklist

`init-project.sh` seeds this file as a per-project setup checklist. It is
not a placeholder file *per se*, but it lists the shell commands you must
run to discover the IDs in §3 above. Walk through it once after init.

---

## 5. Shell-script arguments (you supply at the command line)

These are not in any file — they're things you type when invoking scripts:

### `agent-playbook/scripts/gh-setup.sh`

```bash
bash gh-setup.sh \
  --owner <YOUR-GITHUB-USER> \
  --project <YOUR-PROJECT-NAME> \
  --repo <YOUR-REPO-NAME> \
  [--private] [--description "..."] [--link-only]
```

### `agent-playbook/scripts/init-project.sh`

```bash
bash init-project.sh <PATH-TO-NEW-PROJECT> [QA-TEMPLATE] [--github | --azure]
# QA-TEMPLATE: quant-finance | web-app | cli-tool | data-pipeline
# --github and --azure are mutually exclusive; default is file-based mode.
```

### `agent-playbook/scripts/init-github-tracker.sh`

```bash
bash init-github-tracker.sh <your-github-user>/<your-repo> [<your-project-number>]
```

### `agent-playbook/scripts/azdo-setup.sh`

```bash
bash azdo-setup.sh \
  --org <your-azure-org> \
  --project <your-azure-project> \
  --repo <your-azure-repo> \
  [--area-path "<your-area-path>"] \
  [--iteration-path "<your-area-path>/Sprint N"] \
  [--work-item-type "User Story"] \
  [--emit-only]
```

The org/project/repo must already exist; this script verifies them and emits
the `AZ_*` export block for `.claude/project.env`. Use `--emit-only` to skip
verification (e.g. when offline).

### `agent-playbook/scripts/init-azure-tracker.sh`

```bash
bash init-azure-tracker.sh
# Or with overrides if .claude/project.env is not yet populated:
bash init-azure-tracker.sh --org <your-azure-org> --project <your-azure-project> [--repo <your-azure-repo>]
```

Verifies authentication, the `azure-devops` extension, the project / repo /
area path, and prints the tag vocabulary the agents will use. Makes no writes.

### Agent invocations

```bash
claude --agent .claude/agents/oncall-engineer.md "Initialise the GitHub repo for <ABSOLUTE-PROJECT-PATH>"
claude --agent .claude/agents/refactoring-reviewer.md "Review module <PATH/TO/MODULE>/"
```

---

## 6. Issue / work-item creation

### 6a. GitHub Issues (`tracker: github-issues`)

Whenever you copy a `gh issue create …` snippet from the README or
GITHUB-TRACKER-GUIDE, substitute:

- `<your-github-user>` → your GitHub username
- `<your-repo>` → your repository name
- `<your-project-number>` → your numeric project ID

Example (filled in):

```bash
gh issue create --repo acme/widget-service \
  --title "Add Black-Scholes pricer" \
  --body "Implement the European-option pricer." \
  --label "needs-grooming,priority-medium,role-pm,type-feature" \
  --project "acme/1"
```

### 6b. Azure DevOps Boards (`tracker: azure-boards`)

In Azure mode, agents and humans alike create work items through the tracker
abstraction — never `az boards work-item create` directly. Source the env first
so `tracker_*` is available:

```bash
source .claude/env.sh
tracker_create_issue \
  --title "Add Black-Scholes pricer" \
  --body "Implement the European-option pricer." \
  --type feature --priority medium --role pm --state needs-grooming
```

The verb prints the new work-item ID (e.g. `#42`). Tags written: `needs-grooming`,
`role-pm`, `priority-medium`, `type-feature`. `Microsoft.VSTS.Common.Priority` is
also set to `2`. The work item lands at `AZ_AREA_PATH` (defaults to project root)
with `System.State=New`.

---

## 7. Things that look like placeholders but are NOT

To save you a search:

- `${GH_…}`, `${SUPERPOWERS_SKILLS_DIR}`, `${PY}`, `${PYTEST}`, etc. — these
  are runtime shell variables sourced from `.claude/env.sh` /
  `.claude/project.env`. You don't edit them inline; you set them once in
  `project.env`.
- `NNN` in task filenames (e.g. `001-add-feature.todo.md`) — a sequence
  number you choose when creating each task; not a global placeholder.
- `<unit>`, `<scenario>`, `<expected>` in test-name templates — these are
  guidance for naming individual tests, not values to substitute once.

---

## 8. Quick verification

After filling everything in, run from the project root:

```bash
source .claude/env.sh
check_toolchain && echo "toolchain OK"
echo "GH_OWNER=${GH_OWNER}, GH_REPO=${GH_REPO}, GH_PROJECT_NUMBER=${GH_PROJECT_NUMBER}"
echo "GH_PROJECT_ID=${GH_PROJECT_ID}"
ls "${SUPERPOWERS_SKILLS_DIR}" | head
```

You should see all four GH values populated, `toolchain OK`, and a list of
skill directories. If any line errors out, return to the table above and
fill in what's missing — do not run `/execute` until it passes.
