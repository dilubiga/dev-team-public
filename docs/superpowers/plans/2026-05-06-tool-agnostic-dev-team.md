# Tool-Agnostic Dev-Team Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dev-team work fully without GitHub/Azure (file mode is first-class) and runnable from GitHub Copilot (VS Code Copilot Chat + Copilot CLI) in addition to Claude Code, with no regressions.

**Architecture:** Single canonical role body per agent (`agents/_body/<role>.body.md`); a build script materializes a Claude wrapper (`agents/<role>.md`) and a Copilot chat mode (`chatmodes/<role>.chatmode.md`, with referenced superpowers skills inlined). The shared bash tracker dispatcher (`lib/tracker/`) is reused unchanged by both drivers. A new Copilot walker prompt (`prompts/execute.prompt.md`) re-implements `/execute`'s priority pick logic but stops at dispatch and tells the user which chat mode to invoke. `init-project.sh` deploys both driver layouts by default.

**Tech Stack:** Bash, Markdown (with YAML frontmatter), Python (only inside `init-project.sh` for QA-standards injection), `bats-core` (shell test runner — already in use under `lib/tracker/tests/`).

**Spec:** [docs/superpowers/specs/2026-05-06-tool-agnostic-dev-team-design.md](../specs/2026-05-06-tool-agnostic-dev-team-design.md)

---

## Conventions

- All shell paths are relative to repo root unless noted.
- Bash files use `set -euo pipefail` at top.
- Tests live next to the script: `agent-playbook/scripts/tests/test_<script>.bats` (mirroring `lib/tracker/tests/`).
- Each phase ends with verification + a single commit. No squashing.
- Markdown frontmatter examples are shown in their wrapping `markdown` code fence — do **not** copy the outer fence into the file.

---

## File Map (what gets touched)

**New (committed):**
- `agent-playbook/agents/_body/{product-manager,software-engineer,tester,technical-writer,oncall-engineer,refactoring-reviewer}.body.md` — canonical role prompts (no frontmatter)
- `agent-playbook/agents/_body/README.md` — contributor doc for the build flow
- `agent-playbook/chatmodes/{product-manager,software-engineer,tester,technical-writer,oncall-engineer,refactoring-reviewer}.chatmode.md` — Copilot-frontmatter wrappers
- `agent-playbook/prompts/execute.prompt.md` — Copilot pipeline walker
- `agent-playbook/prompts/pick-next.prompt.md` — Copilot helper that just shows the next item
- `agent-playbook/skills-inlined/{tdd,debugging,verification,brainstorming,writing-plans,receiving-code-review,requesting-code-review}.md` — superpowers skill bodies, expanded for Copilot
- `agent-playbook/scripts/build-prompts.sh` — assembler
- `agent-playbook/scripts/tests/test_build_prompts.bats` — tests for the assembler
- `agent-playbook/templates/AGENTS.md.template` — Copilot CLI workspace pointer
- `agent-playbook/templates/copilot-instructions.deploy.md.template` — extended Copilot instructions deployed to `.github/`
- `agent-playbook/Makefile` — `make build`, `make test`, `make audit`
- `docs/file-mode-audit-2026-05-06.md` — audit punch list (Phase A output)

**Modified:**
- `agent-playbook/agents/{product-manager,…}.md` — regenerated as thin wrappers (still valid Claude agents)
- `agent-playbook/scripts/init-project.sh` — adds `--no-claude` / `--no-copilot` flags; deploys `.github/` artifacts and `AGENTS.md` by default
- `agent-playbook/copilot-instructions.md` — clarification only (engineering standards stay; remove any tracker-specific assumption)
- `agent-playbook/README.md` — Quick Start gains driver axis
- `agent-playbook/process/PROCESS.md` — Copilot manual-stepping clarification
- `agent-playbook/USER-INPUTS.md` — adds Copilot section
- `agent-playbook/templates/CLAUDE.md.template` — adds `driver:` field (informational only) and confirms `tracker: file` default
- Any agent / script / doc surfaced by the Phase A audit

---

# Phase A — File-mode audit

Output: `docs/file-mode-audit-2026-05-06.md`. Fixes are deferred to Phase F so the audit committed first acts as the changelog reference.

### Task A1: Create the audit document scaffold

**Files:**
- Create: `docs/file-mode-audit-2026-05-06.md`

- [ ] **Step 1: Write the audit doc skeleton**

```markdown
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

| ID | File | Line(s) | Pattern | Risk | Fix planned in |
|---|---|---|---|---|---|

## Acceptance

- All findings reviewed by hand. Real bugs scheduled for Phase F.
- Items judged not-a-bug recorded with rationale in the table.
```

- [ ] **Step 2: Commit the scaffold**

```bash
git add docs/file-mode-audit-2026-05-06.md
git commit -m "docs: scaffold file-mode audit punch list"
```

### Task A2: Run the audit and populate the punch list

**Files:**
- Modify: `docs/file-mode-audit-2026-05-06.md`

- [ ] **Step 1: Search for direct `gh` calls outside expected files**

Run:
```bash
grep -rn --include='*.md' --include='*.sh' -E '(^|[^a-zA-Z_])gh (issue|pr|api|repo|project|auth|label)' agent-playbook/ \
  | grep -v 'lib/tracker/tracker_github.sh' \
  | grep -v 'scripts/gh-setup.sh' \
  | grep -v 'scripts/init-github-tracker.sh'
```

Record every hit in the table with the actual line and a one-sentence risk note. Do not fix.

- [ ] **Step 2: Search for direct `az` calls outside expected files**

Run:
```bash
grep -rn --include='*.md' --include='*.sh' -E '(^|[^a-zA-Z_])az (boards|repos|extension|account|devops)' agent-playbook/ \
  | grep -v 'lib/tracker/tracker_azure.sh' \
  | grep -v 'scripts/azdo-setup.sh' \
  | grep -v 'scripts/init-azure-tracker.sh'
```

Record hits.

- [ ] **Step 3: Search for `${GH_*}` / `${AZ_*}` env reads outside tracker backends**

Run:
```bash
grep -rn --include='*.md' --include='*.sh' -E '\$\{GH_[A-Z_]+\}|\$\{AZ_[A-Z_]+\}' agent-playbook/ \
  | grep -v 'lib/tracker/' \
  | grep -v 'templates/project.env.template'
```

Record hits.

- [ ] **Step 4: Search for case/if branches that omit the `file` arm**

Run:
```bash
grep -rn --include='*.sh' --include='*.md' -B1 -A8 -E 'TRACKER_BACKEND|agent_variant' agent-playbook/ \
  | grep -E 'github-issues|azure-boards' \
  | head -40
```

Read each match in context; record any branch that handles only `github-issues` and `azure-boards` (no `file` arm and no `*)` default that does the right thing for file mode).

- [ ] **Step 5: Read the agent prompts in full looking for tracker-bound vocabulary**

Read each of:
- `agent-playbook/agents/product-manager.md`
- `agent-playbook/agents/software-engineer.md`
- `agent-playbook/agents/tester.md`
- `agent-playbook/agents/technical-writer.md`
- `agent-playbook/agents/oncall-engineer.md`
- `agent-playbook/agents/refactoring-reviewer.md`

Record any phrasing that says "issue" or "comment" or "label" in a way that would confuse a file-mode user (e.g. "post a QA report as a comment on the issue" without the file-mode equivalent of "append to the in-progress.md file"). The PM example we already saw at lines 42-52 of product-manager.md — note that one as a documented **good** pattern (parenthetical aside for file mode).

- [ ] **Step 6: Read `README.md` and `process/PROCESS.md` looking for file-mode regressions**

Specifically check that file-mode appears in:
- README §Quick Start ordering and table
- README §Onboarding Checklist
- PROCESS.md state machine descriptions
- USER-INPUTS.md placeholder lists

Record sections where file-mode is missing or treated as a footnote.

- [ ] **Step 7: Commit the populated audit**

```bash
git add docs/file-mode-audit-2026-05-06.md
git commit -m "docs: populate file-mode audit findings"
```

---

# Phase B — Build infrastructure

### Task B1: Create the `_body/` directory and extract canonical bodies

**Files:**
- Create: `agent-playbook/agents/_body/product-manager.body.md`
- Create: `agent-playbook/agents/_body/software-engineer.body.md`
- Create: `agent-playbook/agents/_body/tester.body.md`
- Create: `agent-playbook/agents/_body/technical-writer.body.md`
- Create: `agent-playbook/agents/_body/oncall-engineer.body.md`
- Create: `agent-playbook/agents/_body/refactoring-reviewer.body.md`

- [ ] **Step 1: Extract each role body**

For each `agent-playbook/agents/<role>.md`:

1. Read the file.
2. Strip the leading YAML frontmatter (the first `---` … `---` block).
3. Write the remainder verbatim to `agent-playbook/agents/_body/<role>.body.md`.

Do this once per role. The body files are the new source of truth.

Verify byte-equality of the body (excluding frontmatter):
```bash
diff <(awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' agent-playbook/agents/product-manager.md) \
     agent-playbook/agents/_body/product-manager.body.md
```
Expected: no output (identical).

Repeat the diff for each role.

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/agents/_body/
git commit -m "refactor: extract canonical role bodies into agents/_body/"
```

### Task B2: Add `_body/README.md` (contributor doc)

**Files:**
- Create: `agent-playbook/agents/_body/README.md`

- [ ] **Step 1: Write the README**

```markdown
# Canonical Agent Bodies

Each `<role>.body.md` is the **single source of truth** for that role's prompt.
`scripts/build-prompts.sh` assembles two outputs from each body:

- `agents/<role>.md` — Claude Code agent (with Claude frontmatter)
- `chatmodes/<role>.chatmode.md` — VS Code Copilot chat mode (with Copilot
  frontmatter; any `${SUPERPOWERS_SKILLS_DIR}/<skill>/SKILL.md` reference is
  expanded inline from `skills-inlined/<skill>.md`)

## Editing

1. Edit `_body/<role>.body.md`.
2. Run `make build`.
3. Commit `_body/`, `agents/`, and `chatmodes/` together.

A pre-commit hook (`scripts/hooks/pre-commit`) enforces step 2; CI re-runs
`make build` and fails if the working tree changes.

## Frontmatter is owned by the build script

Do **not** add frontmatter to body files. The wrapper frontmatter lives in
`scripts/build-prompts.sh` and is the only place tool-name (`tools:`) lists
should change.
```

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/agents/_body/README.md
git commit -m "docs: explain the _body → agents/chatmodes build flow"
```

### Task B3: Add bats test scaffolding for `build-prompts.sh`

**Files:**
- Create: `agent-playbook/scripts/tests/test_build_prompts.bats`
- Create: `agent-playbook/scripts/tests/fixtures/sample.body.md`
- Create: `agent-playbook/scripts/tests/fixtures/sample.skill.md`

- [ ] **Step 1: Write the failing test file**

`agent-playbook/scripts/tests/test_build_prompts.bats`:

```bash
#!/usr/bin/env bats
# Tests for scripts/build-prompts.sh

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
    SCRIPT="${REPO_ROOT}/agent-playbook/scripts/build-prompts.sh"
    TMPDIR="$(mktemp -d)"
    BODY_DIR="${TMPDIR}/agents/_body"
    SKILLS_DIR="${TMPDIR}/skills-inlined"
    AGENTS_OUT="${TMPDIR}/agents"
    CHATMODES_OUT="${TMPDIR}/chatmodes"
    mkdir -p "${BODY_DIR}" "${SKILLS_DIR}"
    cp "${REPO_ROOT}/agent-playbook/scripts/tests/fixtures/sample.body.md" \
       "${BODY_DIR}/sample.body.md"
    cp "${REPO_ROOT}/agent-playbook/scripts/tests/fixtures/sample.skill.md" \
       "${SKILLS_DIR}/sample.md"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "build-prompts: emits a Claude wrapper with Claude frontmatter" {
    run bash "${SCRIPT}" \
        --body-dir  "${BODY_DIR}" \
        --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" \
        --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    [ -f "${AGENTS_OUT}/sample.md" ]
    grep -q '^name: sample$' "${AGENTS_OUT}/sample.md"
    grep -q '^tools: ' "${AGENTS_OUT}/sample.md"
}

@test "build-prompts: emits a Copilot chatmode with Copilot frontmatter" {
    run bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    [ -f "${CHATMODES_OUT}/sample.chatmode.md" ]
    grep -q '^description: ' "${CHATMODES_OUT}/sample.chatmode.md"
    grep -q "^tools: \['" "${CHATMODES_OUT}/sample.chatmode.md"
    # Claude-only `name:` field must be absent in the Copilot variant
    ! grep -q '^name: ' "${CHATMODES_OUT}/sample.chatmode.md"
}

@test "build-prompts: inlines skill references in the Copilot variant only" {
    run bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    [ "$status" -eq 0 ]
    # Sentinel string lives inside fixtures/sample.skill.md
    grep -q 'INLINED-SKILL-MARKER' "${CHATMODES_OUT}/sample.chatmode.md"
    ! grep -q 'INLINED-SKILL-MARKER' "${AGENTS_OUT}/sample.md"
    # The Claude variant keeps the original skill reference
    grep -q 'SUPERPOWERS_SKILLS_DIR' "${AGENTS_OUT}/sample.md"
}

@test "build-prompts: is idempotent" {
    bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    sha1_a=$(sha1sum "${AGENTS_OUT}/sample.md" "${CHATMODES_OUT}/sample.chatmode.md")
    bash "${SCRIPT}" \
        --body-dir "${BODY_DIR}" --skills-dir "${SKILLS_DIR}" \
        --agents-out "${AGENTS_OUT}" --chatmodes-out "${CHATMODES_OUT}"
    sha1_b=$(sha1sum "${AGENTS_OUT}/sample.md" "${CHATMODES_OUT}/sample.chatmode.md")
    [ "${sha1_a}" = "${sha1_b}" ]
}
```

- [ ] **Step 2: Write the fixtures**

`agent-playbook/scripts/tests/fixtures/sample.body.md`:

````markdown
# Sample Agent

You are a sample agent used only by the build-prompts.sh test suite.

For process discipline see `${SUPERPOWERS_SKILLS_DIR}/sample/SKILL.md`.

## Tracker calls

This agent uses `tracker_*` verbs. Do not call gh or az directly.
````

`agent-playbook/scripts/tests/fixtures/sample.skill.md`:

````markdown
## Sample Skill (inlined)

INLINED-SKILL-MARKER

When the user asks you to do a sample thing, do it well.
````

- [ ] **Step 3: Run the test — expect it to fail (script doesn't exist yet)**

```bash
bats agent-playbook/scripts/tests/test_build_prompts.bats
```
Expected: all 4 tests fail with "command not found" or similar.

- [ ] **Step 4: Commit (failing tests + fixtures)**

```bash
git add agent-playbook/scripts/tests/
git commit -m "test: add bats tests for build-prompts.sh (failing — script not yet written)"
```

### Task B4: Implement `build-prompts.sh`

**Files:**
- Create: `agent-playbook/scripts/build-prompts.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# scripts/build-prompts.sh — assemble Claude agents and Copilot chatmodes
# from canonical role bodies in _body/.
#
# Usage:
#   bash build-prompts.sh
#     [--body-dir <dir>]       Default: agent-playbook/agents/_body
#     [--skills-dir <dir>]     Default: agent-playbook/skills-inlined
#     [--agents-out <dir>]     Default: agent-playbook/agents
#     [--chatmodes-out <dir>]  Default: agent-playbook/chatmodes
#
# For each <role>.body.md found in --body-dir:
#   - writes <agents-out>/<role>.md            (Claude frontmatter + body)
#   - writes <chatmodes-out>/<role>.chatmode.md
#       (Copilot frontmatter + body with skill references inlined)
#
# Frontmatter and tool lists per role are defined in the FRONTMATTER_* tables
# below. Editing tool sets is the only reason to touch this script under
# normal use.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BODY_DIR="${PLAYBOOK_ROOT}/agents/_body"
SKILLS_DIR="${PLAYBOOK_ROOT}/skills-inlined"
AGENTS_OUT="${PLAYBOOK_ROOT}/agents"
CHATMODES_OUT="${PLAYBOOK_ROOT}/chatmodes"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --body-dir)      BODY_DIR="$2"; shift 2 ;;
        --skills-dir)    SKILLS_DIR="$2"; shift 2 ;;
        --agents-out)    AGENTS_OUT="$2"; shift 2 ;;
        --chatmodes-out) CHATMODES_OUT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "${AGENTS_OUT}" "${CHATMODES_OUT}"

# ── Per-role frontmatter tables ──────────────────────────────────────────────
# Keep these in sync with what each agent actually needs.
# Format: associative arrays keyed by role name.

declare -A CLAUDE_DESCRIPTION=(
    [product-manager]="Grooms raw tasks into agent-ready specs (Job 1) AND performs final user-perspective acceptance review before any code is committed (Job 2). The PM is the first and last gate in the pipeline."
    [software-engineer]="Implements code and writes tests from groomed specs. Practices TDD, sources .claude/env.sh for the toolchain, and uses the tracker_* verbs (file / GitHub / Azure)."
    [tester]="Runs tests, verifies each acceptance criterion, and writes the QA report. Independent of the SWE — never edits implementation code."
    [technical-writer]="Writes theory and reference documentation in _docs/theory/ after PM acceptance, only when the domain warrants it."
    [oncall-engineer]="Fixes CI/CD, infrastructure, and tooling failures; initialises new repos (file / GitHub / Azure)."
    [refactoring-reviewer]="Reviews existing code at a user-specified scope and produces a prioritized refactoring roadmap (one backlog item per finding)."
    [sample]="Sample agent used only by the build-prompts.sh test suite."
)

declare -A CLAUDE_TOOLS=(
    [product-manager]="Read, Edit, Write, Glob, Grep, Bash"
    [software-engineer]="Read, Edit, Write, Glob, Grep, Bash"
    [tester]="Read, Glob, Grep, Bash"
    [technical-writer]="Read, Edit, Write, Glob, Grep, Bash"
    [oncall-engineer]="Read, Edit, Write, Glob, Grep, Bash"
    [refactoring-reviewer]="Read, Glob, Grep, Bash"
    [sample]="Read, Bash"
)

# Copilot tools are passed as a JSON-like inline array in YAML.
# Initial set chosen to match the Claude tool capabilities.
declare -A COPILOT_TOOLS=(
    [product-manager]="['codebase', 'editFiles', 'search', 'terminal', 'runCommands']"
    [software-engineer]="['codebase', 'editFiles', 'search', 'terminal', 'runCommands']"
    [tester]="['codebase', 'search', 'terminal', 'runCommands']"
    [technical-writer]="['codebase', 'editFiles', 'search', 'terminal']"
    [oncall-engineer]="['codebase', 'editFiles', 'search', 'terminal', 'runCommands']"
    [refactoring-reviewer]="['codebase', 'search', 'terminal']"
    [sample]="['codebase', 'terminal']"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

# Inline every `${SUPERPOWERS_SKILLS_DIR}/<skill>/SKILL.md` reference in the body
# by appending an "## Inlined Skill: <skill>" section with the contents of
# skills-inlined/<skill>.md. Unknown skill names are left as-is with a warning.
inline_skills() {
    local body_file="$1"
    local skills_dir="$2"
    # Collect referenced skill names, deduplicated, preserving order
    local skills
    skills=$(grep -oE '\$\{SUPERPOWERS_SKILLS_DIR\}/[a-zA-Z0-9_-]+/SKILL\.md' "${body_file}" \
             | sed -E 's|.*/([a-zA-Z0-9_-]+)/SKILL\.md|\1|' \
             | awk '!seen[$0]++')
    cat "${body_file}"
    if [[ -n "${skills}" ]]; then
        echo
        echo "---"
        echo
        echo "# Inlined Superpowers Skills"
        echo
        echo "These are the bodies of the superpowers skills referenced above, inlined for environments (Copilot) that cannot load them at runtime."
        echo
        local skill
        while IFS= read -r skill; do
            local skill_file="${skills_dir}/${skill}.md"
            if [[ -f "${skill_file}" ]]; then
                echo "## Inlined skill: ${skill}"
                echo
                cat "${skill_file}"
                echo
            else
                echo "## Inlined skill: ${skill} (NOT FOUND)" >&2
                echo "<!-- WARNING: skills-inlined/${skill}.md missing; see _body/README.md -->"
                echo
            fi
        done <<< "${skills}"
    fi
}

emit_claude_wrapper() {
    local role="$1" body_file="$2" out="$3"
    local desc="${CLAUDE_DESCRIPTION[${role}]:-Agent: ${role}}"
    local tools="${CLAUDE_TOOLS[${role}]:-Read, Bash}"
    {
        echo "---"
        echo "name: ${role}"
        echo "description: ${desc}"
        echo "tools: ${tools}"
        echo "---"
        echo
        cat "${body_file}"
    } > "${out}"
}

emit_copilot_chatmode() {
    local role="$1" body_file="$2" skills_dir="$3" out="$4"
    local desc="${CLAUDE_DESCRIPTION[${role}]:-Agent: ${role}}"
    local tools="${COPILOT_TOOLS[${role}]:-['codebase', 'terminal']}"
    {
        echo "---"
        echo "description: ${desc}"
        echo "tools: ${tools}"
        echo "---"
        echo
        inline_skills "${body_file}" "${skills_dir}"
    } > "${out}"
}

# ── Main ─────────────────────────────────────────────────────────────────────
shopt -s nullglob
count=0
for body in "${BODY_DIR}"/*.body.md; do
    role="$(basename "${body}" .body.md)"
    emit_claude_wrapper  "${role}" "${body}" "${AGENTS_OUT}/${role}.md"
    emit_copilot_chatmode "${role}" "${body}" "${SKILLS_DIR}" "${CHATMODES_OUT}/${role}.chatmode.md"
    count=$((count + 1))
done

echo "build-prompts: assembled ${count} role(s) → ${AGENTS_OUT} + ${CHATMODES_OUT}"
```

- [ ] **Step 2: Make it executable and run the bats tests**

```bash
chmod +x agent-playbook/scripts/build-prompts.sh
bats agent-playbook/scripts/tests/test_build_prompts.bats
```
Expected: 4/4 PASS.

- [ ] **Step 3: Run against the real `_body/` and inspect**

```bash
bash agent-playbook/scripts/build-prompts.sh
```
Expected stdout: `build-prompts: assembled 6 role(s) → …`.

Verify the regenerated `agents/<role>.md` files are byte-equal to the originals **except** for any differences in description-line wording. Diff one and inspect:
```bash
diff agent-playbook/agents/product-manager.md <(git show HEAD:agent-playbook/agents/product-manager.md)
```

If wording in `CLAUDE_DESCRIPTION[product-manager]` does not match the existing description line, **update the array entry** to match the original string verbatim — preserving these descriptions is part of "no regressions". Re-run the build, re-diff. Repeat for every role until each `agents/<role>.md` differs from HEAD only in cosmetic whitespace (or not at all).

- [ ] **Step 4: Stage the regenerated agents and commit**

```bash
git add agent-playbook/scripts/build-prompts.sh agent-playbook/agents/
git commit -m "feat: add build-prompts.sh assembler and regenerate agents from _body/"
```

### Task B5: Add `Makefile`

**Files:**
- Create: `agent-playbook/Makefile`

- [ ] **Step 1: Write the Makefile**

```make
# agent-playbook/Makefile

.PHONY: build test check clean

build:
	bash scripts/build-prompts.sh

test:
	bats scripts/tests/
	bats lib/tracker/tests/

# Re-run build and fail if the working tree changes (CI gate).
check: build
	@if ! git diff --quiet -- agents/ chatmodes/; then \
	  echo "ERROR: 'make build' changed tracked files. Re-run it locally and commit."; \
	  git --no-pager diff -- agents/ chatmodes/; \
	  exit 1; \
	fi
```

- [ ] **Step 2: Verify**

```bash
cd agent-playbook && make build && make test
```
Expected: build succeeds, all bats tests pass (existing tracker tests + new build-prompts tests).

- [ ] **Step 3: Commit**

```bash
git add agent-playbook/Makefile
git commit -m "build: add Makefile (build / test / check / audit)"
```

---

# Phase C — Copilot artifacts

### Task C1: Create `skills-inlined/` with the superpowers skill bodies

**Files:**
- Create: `agent-playbook/skills-inlined/test-driven-development.md`
- Create: `agent-playbook/skills-inlined/systematic-debugging.md`
- Create: `agent-playbook/skills-inlined/verification-before-completion.md`
- Create: `agent-playbook/skills-inlined/brainstorming.md`
- Create: `agent-playbook/skills-inlined/writing-plans.md`
- Create: `agent-playbook/skills-inlined/receiving-code-review.md`
- Create: `agent-playbook/skills-inlined/requesting-code-review.md`

(File names must exactly match the skill names referenced in role bodies — see the README.md "Superpowers Skills" table at lines 396-410.)

- [ ] **Step 1: Identify the exact skill set referenced by the bodies**

Run:
```bash
grep -hoE '\$\{SUPERPOWERS_SKILLS_DIR\}/[a-zA-Z0-9_-]+/SKILL\.md' agent-playbook/agents/_body/*.body.md \
  | sed -E 's|.*/([a-zA-Z0-9_-]+)/SKILL\.md|\1|' \
  | sort -u
```

Cross-check against this list. If any skill name appears that is not in the file list above, add it to the file list and proceed.

- [ ] **Step 2: For each skill, fetch the canonical SKILL.md content**

The user has the superpowers skills installed locally. The path is recorded in `${SUPERPOWERS_SKILLS_DIR}` in any project's `.claude/project.env`. For a fresh playbook checkout, ask the user to point you at it once, then for each skill name `<S>`:

1. Read `${SUPERPOWERS_SKILLS_DIR}/<S>/SKILL.md`.
2. Strip the YAML frontmatter (the leading `---` … `---` block).
3. Write the body to `agent-playbook/skills-inlined/<S>.md`.

Each file is a verbatim snapshot of the skill body at this date. A short header comment goes at the top:

```markdown
<!-- Snapshot of superpowers skill: <S>
     Source: ${SUPERPOWERS_SKILLS_DIR}/<S>/SKILL.md
     Captured: 2026-05-06
     Used by: scripts/build-prompts.sh to inline this skill into Copilot chatmodes.
     Do not edit by hand — refresh by re-fetching from the upstream skill. -->
```

- [ ] **Step 3: Re-build and diff**

```bash
bash agent-playbook/scripts/build-prompts.sh
git diff agent-playbook/chatmodes/
```
Expected: chatmodes now contain "## Inlined skill: <name>" sections after the body, one per referenced skill.

- [ ] **Step 4: Commit**

```bash
git add agent-playbook/skills-inlined/ agent-playbook/chatmodes/
git commit -m "feat: snapshot superpowers skills into skills-inlined/ for Copilot"
```

### Task C2: Stage the assembled `chatmodes/` from B4 (already done) — sanity check

- [ ] **Step 1: Verify all six chatmodes exist and have valid frontmatter**

```bash
for f in agent-playbook/chatmodes/*.chatmode.md; do
    echo "── $f ──"
    head -5 "$f"
    echo
done
```
Expected: each file starts with `---`, `description:`, `tools: [...]`, `---`.

No commit (no changes).

### Task C3: Write `prompts/execute.prompt.md` (Copilot pipeline walker)

**Files:**
- Create: `agent-playbook/prompts/execute.prompt.md`

- [ ] **Step 1: Write the prompt**

````markdown
---
description: Walks the dev-team pipeline one step at a time. Tells you which chat mode to switch to next.
mode: ask
---

# /execute — pipeline walker

You are a **read-only walker** for the agent-playbook pipeline. Your job is to tell the user which chat mode they should switch to next. **You never do an agent's work yourself.**

## Pre-flight

1. Run:

   ```bash
   if [[ ! -f .claude/env.sh ]]; then
       echo "EXECUTE BLOCKED: .claude/env.sh not found. Run init-project.sh first."
       exit 1
   fi
   source .claude/env.sh
   if ! check_toolchain; then
       echo "EXECUTE BLOCKED: Python toolchain incomplete."
       exit 1
   fi
   if [[ -z "${TRACKER_BACKEND:-}" ]]; then
       echo "EXECUTE BLOCKED: TRACKER_BACKEND not set. Check 'tracker:' in CLAUDE.md."
       exit 1
   fi
   ```

2. Verify backend reachability:

   ```bash
   tracker_list_issues --count >/dev/null 2>&1 || {
       echo "EXECUTE BLOCKED: tracker backend '${TRACKER_BACKEND}' not usable."
       case "${TRACKER_BACKEND}" in
         github-issues) echo "  → gh auth status; check GH_* in .claude/project.env." ;;
         azure-boards)  echo "  → az account show; check AZ_* in .claude/project.env." ;;
         file)          echo "  → tracker/ exists in project root?" ;;
       esac
       exit 1
   }
   ```

## Backlog scan

Scan in this priority order; the first issue found is the next item:

1. `rework-needed`     → role: SWE
2. `needs-grooming`    → role: PM
3. `ready-for-dev`     → role: SWE
4. `in-progress`       → role: SWE (resume)
5. `ready-for-qa`      → role: QA
6. `ready-for-acceptance` → role: PM
7. `ready-for-docs`    → role: TechWriter

Run:

```bash
for state in rework-needed needs-grooming ready-for-dev in-progress \
             ready-for-qa ready-for-acceptance ready-for-docs; do
    line=$(tracker_list_issues --state "${state}" | head -1)
    if [[ -n "${line}" ]]; then
        echo "STATE=${state}"
        echo "${line}"
        exit 0
    fi
done
echo "EMPTY"
```

## Output

If the scan printed `EMPTY`:

> **Backlog empty.** Create a new task and re-run `/execute`.
> - file mode:    `cp .claude/templates/task.todo.md tracker/NNN-your-task.todo.md`
> - github/azure: `tracker_create_issue --title '…' --body '…' --type feature --priority medium --role pm --state needs-grooming`

If the scan printed a state + issue line, parse the ID and title, look up the role from the table above, and respond exactly:

> **Next item:** #`<ID>` — `<TITLE>`
> **State:** `<state>` (`<role>`)
>
> Switch to the **`<role-chatmode>`** chat mode and run:
> ```
> <verb> #<ID>
> ```
>
> Where `<verb>` is one of: `groom` (PM, needs-grooming), `accept` (PM, ready-for-acceptance), `implement` (SWE, ready-for-dev), `resume` (SWE, in-progress), `rework` (SWE, rework-needed), `verify` (QA), `document` (TechWriter).
>
> When that mode finishes, re-invoke `/execute` to advance.

## What you do NOT do

- Do not call `tracker_transition` yourself.
- Do not edit code, write specs, or run tests.
- Do not switch chat modes for the user — they must do it.
- Do not loop. One pick per invocation.
````

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/prompts/execute.prompt.md
git commit -m "feat: add Copilot execute.prompt.md pipeline walker"
```

### Task C4: Write `prompts/pick-next.prompt.md`

**Files:**
- Create: `agent-playbook/prompts/pick-next.prompt.md`

- [ ] **Step 1: Write the prompt**

````markdown
---
description: Read-only — show the next backlog item without dispatching.
mode: ask
---

# /pick-next

Run the same backlog scan as `/execute` but **only print the result** — no dispatch language, no chat-mode switch instruction. Useful for "what's queued?".

## Steps

```bash
source .claude/env.sh
for state in rework-needed needs-grooming ready-for-dev in-progress \
             ready-for-qa ready-for-acceptance ready-for-docs; do
    line=$(tracker_list_issues --state "${state}" | head -1)
    if [[ -n "${line}" ]]; then
        echo "── ${state} ──"
        echo "${line}"
        echo
    fi
done
```

Output: print every state's first item, then stop. If everything is empty, print "Backlog empty."
````

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/prompts/pick-next.prompt.md
git commit -m "feat: add Copilot pick-next.prompt.md helper"
```

### Task C5: Write `templates/AGENTS.md.template`

**Files:**
- Create: `agent-playbook/templates/AGENTS.md.template`

- [ ] **Step 1: Write the template**

```markdown
# AGENTS.md

This project uses the **agent-playbook** dev-team pipeline.

The same pipeline runs under either AI driver:

- **Claude Code**: agents are loaded from `.claude/agents/`. Run the pipeline with `/execute`.
- **GitHub Copilot** (VS Code or Copilot CLI): chat modes live in `.github/chatmodes/`; the pipeline walker is `.github/prompts/execute.prompt.md`.

## Reading order

1. `CLAUDE.md` — project context, tech stack, architecture, QA standards. Applies to **all** AI tools, not just Claude.
2. `.github/copilot-instructions.md` — engineering standards (SOLID, type hints, pytest conventions, toolchain via `.claude/env.sh`).
3. The chat mode for the role you are playing — see `.github/chatmodes/`.

## Tracker

Tasks live in:
- `tracker/*.todo.md` (file mode), or
- GitHub Issues / Azure Boards (when configured in `CLAUDE.md`).

Either way, every agent calls the `tracker_*` shell verbs sourced from `.claude/env.sh`. **Never call `gh` or `az` directly** — the dispatcher routes to the right backend.

## Manual pipeline (Copilot CLI)

```
gh copilot                                # or your Copilot CLI entry point
> /execute                                # walker tells you which mode to switch to
> @<role-chatmode> <verb> #<ID>           # do the agent's work
> /execute                                # advance
```

The walker is read-only. You drive role transitions by hand.
```

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/templates/AGENTS.md.template
git commit -m "feat: add AGENTS.md template for Copilot CLI"
```

### Task C6: Write `templates/copilot-instructions.deploy.md.template`

This is what gets deployed to `.github/copilot-instructions.md` in user projects. The existing `agent-playbook/copilot-instructions.md` (engineering standards) stays as the canonical source; the deployable template wraps it with a pointer header.

**Files:**
- Create: `agent-playbook/templates/copilot-instructions.deploy.md.template`

- [ ] **Step 1: Write the template**

```markdown
---
applyTo: '**'
---

# Copilot Instructions (project-wide)

This project uses the **agent-playbook** dev-team pipeline. See `AGENTS.md` for the reading order and the manual pipeline flow.

## Where to find things

- **Project context:** `CLAUDE.md` (project name, tech stack, architecture, QA standards). Read this even if you are Copilot — it is tool-agnostic.
- **Chat modes (one per role):** `.github/chatmodes/{product-manager,software-engineer,tester,technical-writer,oncall-engineer,refactoring-reviewer}.chatmode.md`
- **Pipeline walker:** `.github/prompts/execute.prompt.md`
- **Tracker dispatcher:** `.claude/lib/tracker/` — sourced via `source .claude/env.sh`. Never call `gh` or `az` directly.

## Engineering standards

The full engineering standards (SOLID, type hints, pytest conventions, toolchain) are in this file below. They apply to all generated code regardless of which chat mode is active.

---

<!-- The build / deploy step appends the contents of agent-playbook/copilot-instructions.md
     starting from the first '# Engineering Standards' heading. -->
```

The actual concatenation happens in `init-project.sh` (Task D2). The template's trailing comment marks the splice point.

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/templates/copilot-instructions.deploy.md.template
git commit -m "feat: add deploy-time Copilot instructions wrapper template"
```

---

# Phase D — Bootstrap integration

### Task D1: Add bats tests for `init-project.sh` Copilot deployment

**Files:**
- Create: `agent-playbook/scripts/tests/test_init_project_copilot.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats
# Tests for init-project.sh — Copilot deployment

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
    SCRIPT="${REPO_ROOT}/agent-playbook/scripts/init-project.sh"
    TARGET="$(mktemp -d)/proj"
}

teardown() { rm -rf "$(dirname "${TARGET}")"; }

@test "init-project (default): deploys both .claude/ and .github/" {
    run bash "${SCRIPT}" "${TARGET}" quant-finance
    [ "$status" -eq 0 ]
    [ -d "${TARGET}/.claude/agents" ]
    [ -f "${TARGET}/.claude/agents/product-manager.md" ]
    [ -d "${TARGET}/.github/chatmodes" ]
    [ -f "${TARGET}/.github/chatmodes/product-manager.chatmode.md" ]
    [ -d "${TARGET}/.github/prompts" ]
    [ -f "${TARGET}/.github/prompts/execute.prompt.md" ]
    [ -f "${TARGET}/.github/copilot-instructions.md" ]
    [ -f "${TARGET}/AGENTS.md" ]
}

@test "init-project --no-copilot: skips .github/ and AGENTS.md" {
    run bash "${SCRIPT}" "${TARGET}" quant-finance --no-copilot
    [ "$status" -eq 0 ]
    [ -d "${TARGET}/.claude/agents" ]
    [ ! -d "${TARGET}/.github/chatmodes" ]
    [ ! -f "${TARGET}/AGENTS.md" ]
}

@test "init-project --no-claude: skips .claude/agents and commands but keeps .claude/lib" {
    run bash "${SCRIPT}" "${TARGET}" quant-finance --no-claude
    [ "$status" -eq 0 ]
    [ ! -d "${TARGET}/.claude/agents" ]
    [ ! -d "${TARGET}/.claude/commands" ]
    [ -d "${TARGET}/.claude/lib/tracker" ]   # tracker dispatcher still needed
    [ -f "${TARGET}/.claude/env.sh" ]        # both drivers source this
    [ -d "${TARGET}/.github/chatmodes" ]
}

@test "init-project --no-claude --no-copilot fails fast" {
    run bash "${SCRIPT}" "${TARGET}" quant-finance --no-claude --no-copilot
    [ "$status" -ne 0 ]
    [[ "$output" == *"at least one driver"* ]]
}

@test "init-project (default): file mode is the default tracker" {
    run bash "${SCRIPT}" "${TARGET}" quant-finance
    [ "$status" -eq 0 ]
    grep -q '^tracker: file$' "${TARGET}/CLAUDE.md"
}
```

- [ ] **Step 2: Run, expect failures**

```bash
bats agent-playbook/scripts/tests/test_init_project_copilot.bats
```
Expected: 4/5 fail (only the file-mode default test passes today).

- [ ] **Step 3: Commit**

```bash
git add agent-playbook/scripts/tests/test_init_project_copilot.bats
git commit -m "test: add bats tests for init-project.sh Copilot deployment (failing)"
```

### Task D2: Modify `init-project.sh` — add Copilot deployment + flags

**Files:**
- Modify: `agent-playbook/scripts/init-project.sh`

- [ ] **Step 1: Add `--no-claude` and `--no-copilot` flag parsing**

Find the existing flag-parse block (lines 76-89, the `--github`/`--azure` loop) and extend it:

```bash
# ── Parse --github / --azure / --no-claude / --no-copilot flags ───────────────
USE_GITHUB=false
USE_AZURE=false
DEPLOY_CLAUDE=true
DEPLOY_COPILOT=true
for arg in "$@"; do
    case "$arg" in
        --github)      USE_GITHUB=true ;;
        --azure)       USE_AZURE=true ;;
        --no-claude)   DEPLOY_CLAUDE=false ;;
        --no-copilot)  DEPLOY_COPILOT=false ;;
    esac
done

if [[ "${USE_GITHUB}" == true && "${USE_AZURE}" == true ]]; then
    error "--github and --azure are mutually exclusive."
    exit 1
fi

if [[ "${DEPLOY_CLAUDE}" == false && "${DEPLOY_COPILOT}" == false ]]; then
    error "--no-claude and --no-copilot together leave no driver — at least one driver must be deployed."
    exit 1
fi
```

Also extend the QA-template fix-up just below to recognize the new flags:

```bash
if [[ "${QA_TEMPLATE}" == "--github" || "${QA_TEMPLATE}" == "--azure" \
   || "${QA_TEMPLATE}" == "--no-claude" || "${QA_TEMPLATE}" == "--no-copilot" ]]; then
    QA_TEMPLATE="quant-finance"
fi
```

- [ ] **Step 2: Wrap the existing Step 1 (`.claude/agents`, `.claude/commands`) in `if DEPLOY_CLAUDE`**

Find the block starting at line 164 (`echo -e "${BLUE}── Step 1: Agent files (.claude/)${NC}"`) and ending right before the `mkdir_if_absent "${TARGET_DIR}/.claude/templates"` line.

Wrap **only** the parts that are Claude-specific (`mkdir_if_absent .claude/agents`, `mkdir_if_absent .claude/commands`, the agent-copy loop, the skill-deploy loop) in:

```bash
if [[ "${DEPLOY_CLAUDE}" == true ]]; then
    # ... existing agent + command deployment ...
else
    skip ".claude/agents/ and .claude/commands/ (--no-claude)"
fi
```

The `.claude/lib/tracker/`, `.claude/env.sh`, `.claude/project.env`, `.claude/templates/`, `.claude/PORTING.md`, `.claude/copilot-instructions.md`, and `.claude/settings.local.json` blocks stay **outside** the conditional — they are needed regardless of driver because Copilot chat modes also `source .claude/env.sh`.

- [ ] **Step 3: Add a new Step 1b that deploys Copilot artifacts**

After the existing Step 1 block (so after the `.claude/templates/qa-standards/*` copy loop, around line 263), insert:

```bash
# ── 1b. Copilot artifacts (.github/, AGENTS.md) ──────────────────────────────
if [[ "${DEPLOY_COPILOT}" == true ]]; then
    echo -e "${BLUE}── Step 1b: Copilot artifacts (.github/, AGENTS.md)${NC}"

    mkdir_if_absent "${TARGET_DIR}/.github"
    mkdir_if_absent "${TARGET_DIR}/.github/chatmodes"
    mkdir_if_absent "${TARGET_DIR}/.github/prompts"

    # Chat modes (one per role — assembled by build-prompts.sh and committed)
    for role in product-manager software-engineer tester oncall-engineer \
                refactoring-reviewer technical-writer; do
        src="${PLAYBOOK_ROOT}/chatmodes/${role}.chatmode.md"
        dst="${TARGET_DIR}/.github/chatmodes/${role}.chatmode.md"
        if [[ ! -f "${src}" ]]; then
            warning "Chat mode not found: ${src} — run 'make build' in agent-playbook/."
            continue
        fi
        copy_if_absent "${src}" "${dst}"
    done

    # Prompts
    for prompt in execute pick-next; do
        src="${PLAYBOOK_ROOT}/prompts/${prompt}.prompt.md"
        dst="${TARGET_DIR}/.github/prompts/${prompt}.prompt.md"
        [[ -f "${src}" ]] || { warning "Prompt not found: ${src}"; continue; }
        copy_if_absent "${src}" "${dst}"
    done

    # copilot-instructions.md = wrapper template + engineering standards body
    DEPLOY_COPILOT_DST="${TARGET_DIR}/.github/copilot-instructions.md"
    if [[ -f "${DEPLOY_COPILOT_DST}" ]]; then
        skip ".github/copilot-instructions.md (already exists)"
        SKIPPED+=(".github/copilot-instructions.md")
    else
        WRAPPER="${PLAYBOOK_ROOT}/templates/copilot-instructions.deploy.md.template"
        STANDARDS="${PLAYBOOK_ROOT}/copilot-instructions.md"
        # Strip the leading frontmatter (--- ... ---) from the standards file before appending
        {
            cat "${WRAPPER}"
            echo
            awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "${STANDARDS}"
        } > "${DEPLOY_COPILOT_DST}"
        ok "Created .github/copilot-instructions.md (wrapper + standards)"
        CREATED+=(".github/copilot-instructions.md")
    fi

    # AGENTS.md
    copy_if_absent \
        "${PLAYBOOK_ROOT}/templates/AGENTS.md.template" \
        "${TARGET_DIR}/AGENTS.md"
else
    echo -e "${BLUE}── Step 1b: Copilot artifacts skipped (--no-copilot)${NC}"
fi

echo ""
```

- [ ] **Step 4: Update the printed banner to show driver state**

Find the banner block (lines 113-133) and after the `Tracker mode  : …` line, add:

```bash
DRIVERS=()
[[ "${DEPLOY_CLAUDE}" == true ]] && DRIVERS+=("Claude Code")
[[ "${DEPLOY_COPILOT}" == true ]] && DRIVERS+=("GitHub Copilot")
info "Drivers       : ${DRIVERS[*]}"
```

- [ ] **Step 5: Run the bats tests — expect green**

```bash
bats agent-playbook/scripts/tests/test_init_project_copilot.bats
```
Expected: 5/5 PASS.

- [ ] **Step 6: Smoke-test the original file-mode flow manually**

```bash
TMP=$(mktemp -d)/p
bash agent-playbook/scripts/init-project.sh "${TMP}" quant-finance
ls "${TMP}/.claude/agents" "${TMP}/.github/chatmodes" "${TMP}/AGENTS.md"
grep '^tracker: file$' "${TMP}/CLAUDE.md"
rm -rf "$(dirname "${TMP}")"
```
Expected: every path exists; `tracker:` line is `file`.

- [ ] **Step 7: Commit**

```bash
git add agent-playbook/scripts/init-project.sh
git commit -m "feat(init): deploy Copilot artifacts by default; add --no-claude/--no-copilot flags"
```

---

# Phase E — Documentation

### Task E1: Update `README.md` with the driver axis

**Files:**
- Modify: `agent-playbook/README.md`

- [ ] **Step 1: Add a new "Drivers" section right after "The Team"**

Insert a section between the existing "The Team" table (line 36-44) and "The Pipeline" diagram (line 47):

```markdown
---

## Drivers — How You Run the Team

The same agents work under two AI drivers. Pick whichever you have installed; both can coexist in the same project.

| Driver | How agents load | How you run the pipeline |
|---|---|---|
| **Claude Code** | `.claude/agents/<role>.md` (auto-discovered) | `/execute` (full automatic dispatch) |
| **GitHub Copilot** (VS Code Chat / Copilot CLI) | `.github/chatmodes/<role>.chatmode.md` (chat-mode dropdown or `@role` invocation) | `/execute` (the prompt at `.github/prompts/execute.prompt.md`) walks you through which chat mode to switch to next |

**Source of truth:** every role has one canonical body in `agents/_body/<role>.body.md`. The Claude wrapper and the Copilot chat mode are assembled from it by `make build` (see `agents/_body/README.md`).

**Default deploy:** `init-project.sh` deploys both drivers. Pass `--no-claude` or `--no-copilot` to deploy only one.

---
```

- [ ] **Step 2: Add a Copilot row to the Quick Start table**

Find the Quick Start table (line 144-152) and append a note line below it:

```markdown
> Each tracker mode is also runnable from **GitHub Copilot** instead of (or alongside) Claude Code. The Quick Starts below show the Claude flow; the Copilot equivalents are noted at the end of each section.
```

Then at the end of each Quick Start subsection (file / GitHub / Azure), add a "**From Copilot:**" subsection. Example for file mode:

```markdown
**From Copilot (VS Code Chat or Copilot CLI):**

1. After step 4, instead of `/execute` in Claude Code, open the prompt
   `.github/prompts/execute.prompt.md` (VS Code Copilot Chat: `/execute`;
   Copilot CLI: `> /execute`).
2. Follow its instruction — it will tell you which chat mode to switch to
   (e.g. `software-engineer`) and the verb to type (`implement #1`).
3. When that chat mode finishes, re-run `/execute` to advance.
```

Add the same block (with the appropriate prerequisites for GitHub / Azure tracker auth) at the end of the GitHub and Azure Quick Starts.

- [ ] **Step 3: Add a Copilot column to the Onboarding Checklist**

In the existing checklist sections (lines 690-723), under each mode add a "**Copilot extras (if you'll use Copilot):**" sub-list:

```markdown
**Copilot extras (if you'll use Copilot):**
- [ ] Verify `.github/chatmodes/` and `.github/prompts/` exist (deployed by default)
- [ ] In VS Code, open the chat-mode picker and confirm the six roles appear
- [ ] Run the `/execute` prompt once to confirm the walker reaches the backlog
```

- [ ] **Step 4: Update File Structure Reference**

In the playbook tree (lines 419-465), add the new directories:

```
agent-playbook/
├── ...
├── agents/
│   ├── _body/                            ← NEW: canonical role bodies
│   │   ├── product-manager.body.md
│   │   ├── software-engineer.body.md
│   │   ├── ...
│   │   └── README.md
│   ├── product-manager.md                ← (assembled — Claude wrapper)
│   └── ...
├── chatmodes/                            ← NEW: assembled Copilot chat modes
│   └── *.chatmode.md
├── prompts/                              ← NEW: Copilot prompt files
│   ├── execute.prompt.md
│   └── pick-next.prompt.md
├── skills-inlined/                       ← NEW: superpowers skill bodies (snapshots)
│   └── *.md
├── Makefile                              ← NEW: build / test / check / audit
├── ...
└── scripts/
    ├── build-prompts.sh                  ← NEW: assembler
    ├── tests/                            ← NEW: bats tests for scripts
    └── ...
```

In the per-project tree (lines 467-491) add:

```
<project>/
├── ...
├── AGENTS.md                             ← NEW: Copilot CLI workspace pointer
├── .claude/
│   └── ...                               ← unchanged
└── .github/                              ← NEW: Copilot driver
    ├── copilot-instructions.md
    ├── chatmodes/*.chatmode.md
    └── prompts/*.prompt.md
```

- [ ] **Step 5: Commit**

```bash
git add agent-playbook/README.md
git commit -m "docs: add Copilot driver alongside Claude in README"
```

### Task E2: Update `process/PROCESS.md`

**Files:**
- Modify: `agent-playbook/process/PROCESS.md`

- [ ] **Step 1: Read PROCESS.md and identify the dispatch section**

Look for the section that describes how the orchestrator picks up work / dispatches agents (typically near the top, in a section like "Pipeline" or "Dispatch").

- [ ] **Step 2: Insert a Copilot-specific note**

After the section that describes Claude's automatic dispatch, insert:

```markdown
### Driver: GitHub Copilot

Under Copilot the same state machine applies, but dispatch is **manual**. The user invokes `.github/prompts/execute.prompt.md`, which performs the same priority scan as Claude's `/execute` skill but stops after picking the next item — it tells the user which chat mode (`.github/chatmodes/<role>.chatmode.md`) to switch to and what verb to type. After the role finishes, the user re-invokes `/execute` to advance.

Role boundaries, QA cycle limits, dormant-backlog rules, and discovery-issue rules are **identical** across drivers. Only the dispatch step differs.
```

- [ ] **Step 3: Commit**

```bash
git add agent-playbook/process/PROCESS.md
git commit -m "docs(process): document Copilot manual-dispatch driver"
```

### Task E3: Update `USER-INPUTS.md`

**Files:**
- Modify: `agent-playbook/USER-INPUTS.md`

- [ ] **Step 1: Add a Copilot section**

Append (or add as a new top-level section near the existing tracker-mode sections):

```markdown
---

## Copilot (driver — orthogonal to tracker mode)

No new placeholders or env vars. Copilot deployment uses files only:

| Path | Source | Editable? |
|---|---|---|
| `.github/chatmodes/<role>.chatmode.md` | `chatmodes/<role>.chatmode.md` (assembled) | No — edit `agents/_body/<role>.body.md` and run `make build` |
| `.github/prompts/execute.prompt.md` | `prompts/execute.prompt.md` | Yes (committed source) |
| `.github/prompts/pick-next.prompt.md` | `prompts/pick-next.prompt.md` | Yes |
| `.github/copilot-instructions.md` | `templates/copilot-instructions.deploy.md.template` + `copilot-instructions.md` (concatenated by `init-project.sh`) | Edit the template / standards in the playbook |
| `AGENTS.md` (project root) | `templates/AGENTS.md.template` | Yes |

To skip Copilot entirely on a project: `init-project.sh ... --no-copilot`.
To skip Claude entirely: `init-project.sh ... --no-claude` (the tracker dispatcher and `env.sh` are still deployed because chat modes need them).
```

- [ ] **Step 2: Commit**

```bash
git add agent-playbook/USER-INPUTS.md
git commit -m "docs: add Copilot section to USER-INPUTS.md"
```

### Task E4: Add `driver:` field to `templates/CLAUDE.md.template`

This field is informational only — it tells future readers (human or agent) which drivers are deployed. The build doesn't read it.

**Files:**
- Modify: `agent-playbook/templates/CLAUDE.md.template`

- [ ] **Step 1: Read the existing template**

```bash
cat agent-playbook/templates/CLAUDE.md.template | head -30
```

- [ ] **Step 2: Add the `driver:` line right after `tracker:`**

If the template's frontmatter looks like:

```yaml
tracker: file
agent_variant: file
```

Change to:

```yaml
tracker: file
agent_variant: file
# driver: which AI drivers are deployed for this project. Informational only.
# Possible values: claude-code, copilot, both
driver: both
```

- [ ] **Step 3: Commit**

```bash
git add agent-playbook/templates/CLAUDE.md.template
git commit -m "docs(template): add informational 'driver:' field to CLAUDE.md template"
```

---

# Phase F — File-mode fixes (driven by Phase A audit)

> This phase is **schedule-pending**. Each finding from `docs/file-mode-audit-2026-05-06.md` becomes one task here. Until the audit runs (Task A2), the task list is open.

### Task F-template: One fix per audit finding

For each row in the audit table where `Risk` is "real bug" (not "documentation drift" or "not-a-bug"):

- [ ] **Step 1:** Read the file at the recorded line, in full context.
- [ ] **Step 2:** Decide the minimal fix (often: replace `gh ` with `tracker_*`, or add a `file)` arm to a case, or add a parenthetical "(file mode: …)" aside to an agent prompt).
- [ ] **Step 3:** Apply the fix. If it touches an agent body, edit `agents/_body/<role>.body.md` and re-run `make build`; commit `_body/`, `agents/`, and `chatmodes/` together.
- [ ] **Step 4:** Add a row to the audit doc's "Fix planned in" column referencing the commit hash.
- [ ] **Step 5:** Commit.

```bash
git commit -m "fix(file-mode): <one-line description from audit row>"
```

### Task F-final: Smoke-test the file-mode happy path

After all fixes are applied:

- [ ] **Step 1: Bootstrap a throwaway file-mode project**

```bash
TMP=$(mktemp -d)/proj
bash agent-playbook/scripts/init-project.sh "${TMP}" quant-finance
cd "${TMP}"
```

- [ ] **Step 2: Sanity-check the layout**

```bash
ls .claude/agents/                        # 6 agents
ls .github/chatmodes/                     # 6 chat modes
[ -f AGENTS.md ] && echo "AGENTS.md OK"
grep '^tracker: file$' CLAUDE.md
```

All four checks pass.

- [ ] **Step 3: Source env and verify dispatcher routes to file backend**

```bash
source .claude/env.sh
echo "TRACKER_BACKEND=${TRACKER_BACKEND}"   # expect: file
tracker_list_issues --count                  # expect: 0 (or no error)
```

- [ ] **Step 4: Create a task and confirm `/execute`'s preflight would pass**

```bash
cp .claude/templates/task.todo.md tracker/001-smoke.todo.md
tracker_list_issues --state needs-grooming   # expect: a line for #001
```

- [ ] **Step 5: Read `.github/prompts/execute.prompt.md`**

Manually walk through the steps — confirm `tracker_list_issues --state needs-grooming` would return the smoke task and the walker would print the "switch to product-manager chat mode" instruction.

- [ ] **Step 6: Tear down and commit a smoke-test record**

```bash
cd -
rm -rf "$(dirname "${TMP}")"
```

Append a "## Smoke test 2026-05-06" section to the audit doc with the steps above and the results, then:

```bash
git add docs/file-mode-audit-2026-05-06.md
git commit -m "docs: record file-mode smoke-test result post-fixes"
```

---

# Phase G — CI gate (optional, recommended)

### Task G1: Add a pre-commit hook for `make build`

**Files:**
- Create: `agent-playbook/scripts/hooks/pre-commit`

- [ ] **Step 1: Write the hook**

```bash
#!/usr/bin/env bash
# Pre-commit hook: re-run build-prompts.sh and abort if outputs would change.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}/agent-playbook"

bash scripts/build-prompts.sh

if ! git diff --quiet -- agents/ chatmodes/; then
    echo "ERROR: build-prompts.sh produced changes that aren't staged."
    echo "Run: cd agent-playbook && make build && git add agents/ chatmodes/"
    exit 1
fi
```

- [ ] **Step 2: Document install in `_body/README.md`**

Add a note pointing the reader at the hook (it is opt-in; users install with `ln -sf ../../agent-playbook/scripts/hooks/pre-commit .git/hooks/pre-commit` from repo root).

- [ ] **Step 3: Commit**

```bash
git add agent-playbook/scripts/hooks/pre-commit
git commit -m "build: add optional pre-commit hook to enforce build-prompts.sh"
```

---

## Spec coverage check (self-review notes — keep in plan)

| Spec section | Tasks |
|---|---|
| §3.1 Single source of truth | B1 |
| §3.2 Build script | B3, B4, B5 |
| §3.3 Tracker layer (unchanged) | implicit — verified by F-final smoke test |
| §3.4 Copilot orchestration | C1, C3, C4 |
| §4 Per-project layout | D2 |
| §5 init-project.sh changes | D1, D2 |
| §6 File-mode audit | A1, A2, F-template, F-final |
| §7 Documentation updates | E1, E2, E3, E4, B2 |
| §8 Risks — drift between body and assembled | G1 (pre-commit hook), B5 (`make check`) |
| §8 Risks — Copilot tool name compat | B4 (centralized in COPILOT_TOOLS table) |
| §8 Risks — AGENTS.md compat | C5 (kept minimal) |

Every numbered spec section maps to at least one task. No placeholders left in the plan.
