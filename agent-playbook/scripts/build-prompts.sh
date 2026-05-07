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
    [software-engineer]="Implements code and writes tests according to groomed specifications. Follows the project coding standards without exception. Never decides whether a task is complete — that is QA's and PM's job."
    [tester]="Independently verifies implementation against groomed specs and domain-specific QA standards. Never fixes code — only reports failures with precision. A partial pass is a fail."
    [technical-writer]="Produces reference / theory / user-facing documentation for every implemented feature that warrants it. Runs after PM acceptance, before the issue is fully closed. Writes to _docs/ — uses LaTeX-friendly Markdown when the feature involves domain math."
    [oncall-engineer]="Two jobs — (1) diagnoses and fixes CI/CD/infra failures, never touching feature logic; (2) initialises a new project repo (git init + remote setup + tracker bootstrap). Read the invocation to know which job applies."
    [refactoring-reviewer]="Reviews existing code against the project's coding standards and produces a prioritized refactoring plan. Never changes code directly — produces a structured report that feeds into the normal PM→SWE→QA pipeline as a set of refactoring tasks."
    [sample]="Sample agent used only by the build-prompts.sh test suite."
)

declare -A CLAUDE_TOOLS=(
    [product-manager]="Read, Edit, Write, Glob, Grep, Bash"
    [software-engineer]="Read, Edit, Write, Bash, Glob, Grep"
    [tester]="Read, Edit, Write, Bash, Glob, Grep"
    [technical-writer]="Read, Edit, Write, Glob, Grep, Bash"
    [oncall-engineer]="Read, Edit, Write, Bash, Glob, Grep"
    [refactoring-reviewer]="Read, Edit, Write, Bash, Glob, Grep"
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
    skills=$( { grep -oE '\$\{SUPERPOWERS_SKILLS_DIR\}/[a-zA-Z0-9_-]+/SKILL\.md' "${body_file}" || true; } \
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
