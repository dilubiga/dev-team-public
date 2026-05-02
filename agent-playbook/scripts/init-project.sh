#!/usr/bin/env bash
# init-project.sh — Bootstrap a new project with the agent-playbook dev team.
#
# Usage:
#   bash init-project.sh /path/to/project [qa-template] [--github | --azure]
#
# Arguments:
#   /path/to/project   Absolute or relative path to the target project directory.
#                      Created automatically if it does not exist.
#   qa-template        Optional. One of: quant-finance | web-app | cli-tool | data-pipeline
#                      Defaults to: quant-finance
#   --github           Optional. Use GitHub Issues mode instead of file-based tracking.
#                      Configures CLAUDE.md and runs init-github-tracker.sh.
#   --azure            Optional. Use Azure DevOps Boards mode instead of file-based tracking.
#                      Configures CLAUDE.md and runs init-azure-tracker.sh (verification only).
#                      The Azure org/project/repo must already exist — this script does not
#                      create them. AZ_* env vars in .claude/project.env must be filled in
#                      manually after init (see PORTING.md §4-AZ).
#
# Examples:
#   bash init-project.sh ~/code/my-pricer quant-finance
#   bash init-project.sh ../my-web-app web-app
#   bash init-project.sh /tmp/test-project
#   bash init-project.sh ~/code/my-app quant-finance --github
#   bash init-project.sh ~/code/my-app quant-finance --azure
#
# This script is idempotent: running it twice will not overwrite existing files
# (except the QA standards file, which is always refreshed from the template).
#
# --github and --azure are mutually exclusive.

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Colour

info()    { echo -e "${BLUE}[init]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
skip()    { echo -e "${YELLOW}[skip]${NC}  $*"; }
warning() { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Resolve playbook root (directory containing this script) ─────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Resolve GitHub owner from `gh` CLI (auth required) ───────────────────────
# Falls back to the literal "__OWNER__" placeholder if gh is not available
# or not authenticated; the user can edit project.env by hand afterwards.
resolve_owner() {
    if command -v gh >/dev/null 2>&1; then
        gh api user --jq .login 2>/dev/null || echo ""
    else
        echo ""
    fi
}
OWNER="$(resolve_owner)"
if [[ -z "${OWNER}" ]]; then
    OWNER="__OWNER__"
fi

# ── Parse arguments ───────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    error "Usage: bash init-project.sh /path/to/project [qa-template]"
    error "       qa-template: quant-finance | web-app | cli-tool | data-pipeline"
    exit 1
fi

TARGET_DIR="$1"
QA_TEMPLATE="${2:-quant-finance}"

# ── Parse --github / --azure flag ─────────────────────────────────────────────
USE_GITHUB=false
USE_AZURE=false
for arg in "$@"; do
    case "$arg" in
        --github) USE_GITHUB=true ;;
        --azure)  USE_AZURE=true ;;
    esac
done

if [[ "${USE_GITHUB}" == true && "${USE_AZURE}" == true ]]; then
    error "--github and --azure are mutually exclusive."
    exit 1
fi

# If --github / --azure was passed as the second arg, fix QA_TEMPLATE
if [[ "${QA_TEMPLATE}" == "--github" || "${QA_TEMPLATE}" == "--azure" ]]; then
    QA_TEMPLATE="quant-finance"
fi

# Validate QA template name
VALID_TEMPLATES=("quant-finance" "web-app" "cli-tool" "data-pipeline")
if [[ ! " ${VALID_TEMPLATES[*]} " =~ " ${QA_TEMPLATE} " ]]; then
    error "Unknown QA template: '${QA_TEMPLATE}'"
    error "Valid options: quant-finance | web-app | cli-tool | data-pipeline"
    exit 1
fi

# Create target directory if it does not exist
if [[ ! -d "${TARGET_DIR}" ]]; then
    info "Target directory does not exist — creating: ${TARGET_DIR}"
    mkdir -p "${TARGET_DIR}"
    ok "Created ${TARGET_DIR}"
fi

TARGET_DIR="$(cd "${TARGET_DIR}" && pwd)"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Agent Playbook — Project Init         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Playbook root : ${PLAYBOOK_ROOT}"
info "Target project: ${TARGET_DIR}"
info "QA template   : ${QA_TEMPLATE}"
if [[ "${OWNER}" == "__OWNER__" ]]; then
    warning "GitHub owner : could not resolve via 'gh api user' — placeholder '__OWNER__' used. Edit .claude/project.env after init."
else
    info "GitHub owner  : ${OWNER}"
fi
if [[ "${USE_GITHUB}" == true ]]; then
    info "Tracker mode  : GitHub Issues"
elif [[ "${USE_AZURE}" == true ]]; then
    info "Tracker mode  : Azure DevOps Boards"
else
    info "Tracker mode  : File-based"
fi
echo ""

# ── Track what was created vs skipped ────────────────────────────────────────
CREATED=()
SKIPPED=()

copy_if_absent() {
    local src="$1"
    local dst="$2"
    if [[ -f "${dst}" ]]; then
        skip "${dst#${TARGET_DIR}/} (already exists)"
        SKIPPED+=("${dst#${TARGET_DIR}/}")
    else
        cp "${src}" "${dst}"
        ok "Created ${dst#${TARGET_DIR}/}"
        CREATED+=("${dst#${TARGET_DIR}/}")
    fi
}

mkdir_if_absent() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        skip "${dir#${TARGET_DIR}/}/ (already exists)"
    else
        mkdir -p "${dir}"
        ok "Created ${dir#${TARGET_DIR}/}/"
        CREATED+=("${dir#${TARGET_DIR}/}/")
    fi
}

# ── 1. Create .claude/ structure ─────────────────────────────────────────────
echo -e "${BLUE}── Step 1: Agent files (.claude/)${NC}"

mkdir_if_absent "${TARGET_DIR}/.claude"
mkdir_if_absent "${TARGET_DIR}/.claude/agents"
mkdir_if_absent "${TARGET_DIR}/.claude/commands"
mkdir_if_absent "${TARGET_DIR}/.claude/templates"
mkdir_if_absent "${TARGET_DIR}/.claude/templates/qa-standards"

# Copy agent files (each agent handles both file-based and GitHub modes)
for agent in product-manager software-engineer tester oncall-engineer refactoring-reviewer technical-writer; do
    src="${PLAYBOOK_ROOT}/agents/${agent}.md"
    dst="${TARGET_DIR}/.claude/agents/${agent}.md"
    if [[ ! -f "${src}" ]]; then
        warning "Agent file not found: ${src} — skipping"
        continue
    fi
    copy_if_absent "${src}" "${dst}"
done

# Deploy every slash command in skills/<name>/SKILL.md to .claude/commands/<name>.md.
# Adding a new skill is a one-step operation: drop a SKILL.md under skills/<name>/
# and re-run init-project.sh — no edits to this script needed.
# Directories starting with "_" are private (e.g. _template/) and are skipped.
for skill_md in "${PLAYBOOK_ROOT}/skills"/*/SKILL.md; do
    [[ -f "${skill_md}" ]] || continue
    skill_name="$(basename "$(dirname "${skill_md}")")"
    [[ "${skill_name}" == _* ]] && continue
    copy_if_absent "${skill_md}" "${TARGET_DIR}/.claude/commands/${skill_name}.md"
done

# Copy copilot-instructions.md
copy_if_absent \
    "${PLAYBOOK_ROOT}/copilot-instructions.md" \
    "${TARGET_DIR}/.claude/copilot-instructions.md"

# Copy task template
copy_if_absent \
    "${PLAYBOOK_ROOT}/templates/task.todo.md" \
    "${TARGET_DIR}/.claude/templates/task.todo.md"

# Seed settings.local.json so the agent team can run out of the box.
# Without this, the first SWE run blocks on permission prompts for mkdir,
# pytest, ruff, Write(*), etc.
copy_if_absent \
    "${PLAYBOOK_ROOT}/templates/settings.local.json.template" \
    "${TARGET_DIR}/.claude/settings.local.json"

# Seed env.sh so SWE / QA / execute resolve the Python toolchain uniformly,
# even on Git Bash for Windows where `pytest` may not be on PATH but `py` is.
copy_if_absent \
    "${PLAYBOOK_ROOT}/templates/env.sh.template" \
    "${TARGET_DIR}/.claude/env.sh"

# Deploy the tracker dispatcher and backends. env.sh sources tracker.sh
# from this location, which makes the tracker_* verbs available to every
# agent regardless of backend (file / github-issues / azure-boards).
TRACKER_SRC="${PLAYBOOK_ROOT}/lib/tracker"
TRACKER_DST="${TARGET_DIR}/.claude/lib/tracker"
if [[ -d "${TRACKER_SRC}" ]]; then
    if [[ -d "${TRACKER_DST}" ]]; then
        skip ".claude/lib/tracker/ (already exists)"
        SKIPPED+=(".claude/lib/tracker/")
    else
        mkdir -p "${TARGET_DIR}/.claude/lib"
        cp -R "${TRACKER_SRC}" "${TRACKER_DST}"
        # Drop test scaffolding — projects don't run the abstraction's tests.
        rm -rf "${TRACKER_DST}/tests"
        ok "Created .claude/lib/tracker/ (dispatcher + backends)"
        CREATED+=(".claude/lib/tracker/")
    fi
else
    warning "lib/tracker not found at ${TRACKER_SRC} — tracker_* verbs will be unavailable in the new project."
fi

# Seed project.env with the owner already filled in. This file holds the
# GitHub Project board IDs and the superpowers skills path — every agent
# references it via env vars instead of hardcoding values.
PROJECT_ENV_DST="${TARGET_DIR}/.claude/project.env"
if [[ -f "${PROJECT_ENV_DST}" ]]; then
    skip ".claude/project.env (already exists)"
    SKIPPED+=(".claude/project.env")
else
    sed "s|__OWNER__|${OWNER}|g" \
        "${PLAYBOOK_ROOT}/templates/project.env.template" \
        > "${PROJECT_ENV_DST}"
    ok "Created .claude/project.env (GH_OWNER=${OWNER})"
    CREATED+=(".claude/project.env")
fi

# Seed PORTING.md so the human knows what manual steps remain after init.
copy_if_absent \
    "${PLAYBOOK_ROOT}/templates/PORTING.md.template" \
    "${TARGET_DIR}/.claude/PORTING.md"

# Copy all QA standards templates
for qa_file in quant-finance web-app cli-tool data-pipeline; do
    copy_if_absent \
        "${PLAYBOOK_ROOT}/templates/qa-standards/${qa_file}.md" \
        "${TARGET_DIR}/.claude/templates/qa-standards/${qa_file}.md"
done

echo ""

# ── 2. Create _docs/ directory and copy PROCESS.md ───────────────────────────
echo -e "${BLUE}── Step 2: Process docs (_docs/)${NC}"

mkdir_if_absent "${TARGET_DIR}/_docs"

copy_if_absent \
    "${PLAYBOOK_ROOT}/process/PROCESS.md" \
    "${TARGET_DIR}/_docs/PROCESS.md"

copy_if_absent \
    "${PLAYBOOK_ROOT}/process/TRACKER-GUIDE.md" \
    "${TARGET_DIR}/_docs/TRACKER-GUIDE.md"

if [[ "${USE_GITHUB}" == true ]]; then
    copy_if_absent \
        "${PLAYBOOK_ROOT}/process/GITHUB-TRACKER-GUIDE.md" \
        "${TARGET_DIR}/_docs/GITHUB-TRACKER-GUIDE.md"
fi

if [[ "${USE_AZURE}" == true ]]; then
    copy_if_absent \
        "${PLAYBOOK_ROOT}/process/AZURE-TRACKER-GUIDE.md" \
        "${TARGET_DIR}/_docs/AZURE-TRACKER-GUIDE.md"
fi

echo ""

# ── 3. Create tracker/ directories ───────────────────────────────────────────
echo -e "${BLUE}── Step 3: Task tracker (tracker/)${NC}"

mkdir_if_absent "${TARGET_DIR}/tracker"
mkdir_if_absent "${TARGET_DIR}/tracker/done"
mkdir_if_absent "${TARGET_DIR}/tracker/rejected"

echo ""

# ── 4. Copy CLAUDE.md (never overwrite) ──────────────────────────────────────
echo -e "${BLUE}── Step 4: CLAUDE.md${NC}"

if [[ -f "${TARGET_DIR}/CLAUDE.md" ]]; then
    skip "CLAUDE.md (already exists — will not overwrite)"
    SKIPPED+=("CLAUDE.md")
else
    cp "${PLAYBOOK_ROOT}/templates/CLAUDE.md.template" "${TARGET_DIR}/CLAUDE.md"
    ok "Created CLAUDE.md from template"
    CREATED+=("CLAUDE.md")
fi

echo ""

# ── 5. Inject selected QA standards into CLAUDE.md (only if just created) ────
echo -e "${BLUE}── Step 5: QA standards${NC}"

QA_STANDARDS_SRC="${PLAYBOOK_ROOT}/templates/qa-standards/${QA_TEMPLATE}.md"

if [[ ! -f "${QA_STANDARDS_SRC}" ]]; then
    warning "QA standards template not found: ${QA_STANDARDS_SRC}"
    warning "You will need to fill in ## QA Standards in CLAUDE.md manually."
else
    # Only inject if CLAUDE.md was just created (not already present)
    if [[ " ${CREATED[*]} " =~ " CLAUDE.md " ]]; then
        # Extract the content block (everything after the first --- line) from the QA template
        QA_CONTENT=$(tail -n +5 "${QA_STANDARDS_SRC}")
        # Replace the placeholder comment in CLAUDE.md with the actual QA standards
        # Use Python for reliable multi-line replacement (avoids sed portability issues)
        source "${SCRIPT_DIR}/lib/find-python.sh"
        PYTHON_CMD="$(_find_python)" || true
        if [[ -z "${PYTHON_CMD}" ]]; then
            warning "Python not found — skipping QA standards injection."
            warning "Manually paste content from .claude/templates/qa-standards/${QA_TEMPLATE}.md into CLAUDE.md"
        else
        "${PYTHON_CMD}" - "${TARGET_DIR}/CLAUDE.md" "${QA_STANDARDS_SRC}" <<'PYEOF'
import sys
import re

claude_path = sys.argv[1]
qa_path = sys.argv[2]

with open(claude_path, "r", encoding="utf-8") as f:
    claude_content = f.read()

with open(qa_path, "r", encoding="utf-8") as f:
    qa_lines = f.readlines()

# Skip YAML frontmatter and the H1 title line from the QA template
# Keep everything from "## QA Standards" onward
qa_body_lines = []
in_body = False
for line in qa_lines:
    if line.startswith("## QA Standards"):
        in_body = True
    if in_body:
        qa_body_lines.append(line)

qa_body = "".join(qa_body_lines).strip()

# Replace the placeholder comment block in CLAUDE.md
placeholder = """## QA Standards
<!-- Paste the contents of ONE qa-standards template here, or reference it by path.
     Options:
       .claude/templates/qa-standards/quant-finance.md
       .claude/templates/qa-standards/web-app.md
       .claude/templates/qa-standards/cli-tool.md
       .claude/templates/qa-standards/data-pipeline.md
     You can also paste the content directly here and customize it. -->"""

if placeholder in claude_content:
    new_content = claude_content.replace(placeholder, qa_body)
    with open(claude_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Injected {qa_path.split('/')[-1]} into CLAUDE.md")
else:
    print("Placeholder not found in CLAUDE.md — QA standards section may have been customized already.")
PYEOF
        ok "Injected ${QA_TEMPLATE} QA standards into CLAUDE.md"
        fi
    else
        skip "QA standards injection (CLAUDE.md already existed — edit it manually)"
        info "  Reference: .claude/templates/qa-standards/${QA_TEMPLATE}.md"
    fi
fi

echo ""

# ── 5b. Configure GitHub Issues mode in CLAUDE.md (if --github) ──────────────
if [[ "${USE_GITHUB}" == true ]] && [[ " ${CREATED[*]} " =~ " CLAUDE.md " ]]; then
    echo -e "${BLUE}── Step 5b: GitHub Issues configuration${NC}"

    # Derive repo name from target directory name
    REPO_NAME=$(basename "${TARGET_DIR}")

    # Update tracker mode
    sed -i 's/^tracker: file$/tracker: github-issues/' "${TARGET_DIR}/CLAUDE.md"

    # Switch agent_variant to github
    sed -i 's/^agent_variant: file$/agent_variant: github/' "${TARGET_DIR}/CLAUDE.md"

    # Replace [OWNER]/[REPO_NAME] placeholders in the resolved-references comments
    sed -i "s|\[OWNER\]/N|${OWNER}/<your-project-number>|g" "${TARGET_DIR}/CLAUDE.md"
    sed -i "s|\[OWNER\]/\[REPO_NAME\]|${OWNER}/${REPO_NAME}|g" "${TARGET_DIR}/CLAUDE.md"

    ok "Configured CLAUDE.md for GitHub Issues mode (repo: ${OWNER}/${REPO_NAME})"
    echo ""
fi

# ── 5c. Run init-github-tracker.sh (if --github) ─────────────────────────────
if [[ "${USE_GITHUB}" == true ]]; then
    echo -e "${BLUE}── Step 5c: GitHub labels setup${NC}"

    REPO_NAME=$(basename "${TARGET_DIR}")
    INIT_GITHUB_SCRIPT="${PLAYBOOK_ROOT}/scripts/init-github-tracker.sh"

    if [[ -f "${INIT_GITHUB_SCRIPT}" ]]; then
        info "Running init-github-tracker.sh for ${OWNER}/${REPO_NAME}..."
        bash "${INIT_GITHUB_SCRIPT}" "${OWNER}/${REPO_NAME}" || {
            warning "GitHub label setup failed — you can run it manually later:"
            warning "  bash ${INIT_GITHUB_SCRIPT} ${OWNER}/${REPO_NAME}"
        }
    else
        warning "init-github-tracker.sh not found at ${INIT_GITHUB_SCRIPT}"
        warning "Create labels manually using the GITHUB-TRACKER-GUIDE.md"
    fi
    echo ""
fi

# ── 5d. Configure Azure DevOps mode in CLAUDE.md (if --azure) ────────────────
if [[ "${USE_AZURE}" == true ]] && [[ " ${CREATED[*]} " =~ " CLAUDE.md " ]]; then
    echo -e "${BLUE}── Step 5d: Azure DevOps configuration${NC}"

    # Update tracker mode to azure-boards
    sed -i 's/^tracker: file$/tracker: azure-boards/' "${TARGET_DIR}/CLAUDE.md"

    # Switch agent_variant to azure
    sed -i 's/^agent_variant: file$/agent_variant: azure/' "${TARGET_DIR}/CLAUDE.md"

    ok "Configured CLAUDE.md for Azure DevOps Boards mode"
    info "  Fill in azdo_org / azdo_project / azdo_repo in CLAUDE.md"
    info "  and AZ_ORG / AZ_PROJECT / AZ_REPO in .claude/project.env"
    echo ""
fi

# ── 5e. Run init-azure-tracker.sh (if --azure and project.env is filled in) ──
if [[ "${USE_AZURE}" == true ]]; then
    echo -e "${BLUE}── Step 5e: Azure DevOps connection check${NC}"

    INIT_AZURE_SCRIPT="${PLAYBOOK_ROOT}/scripts/init-azure-tracker.sh"

    if [[ ! -f "${INIT_AZURE_SCRIPT}" ]]; then
        warning "init-azure-tracker.sh not found at ${INIT_AZURE_SCRIPT}"
        warning "Run it manually after filling in .claude/project.env."
    else
        # Source project.env from the new project to see whether AZ_ORG / AZ_PROJECT
        # are already populated. If not, defer the check — running the script
        # without those values would just bail out noisily.
        # shellcheck disable=SC1090,SC1091
        AZ_ORG_PROBE=""; AZ_PROJECT_PROBE=""
        if [[ -f "${TARGET_DIR}/.claude/project.env" ]]; then
            AZ_ORG_PROBE="$(grep -E '^export AZ_ORG=' "${TARGET_DIR}/.claude/project.env" | sed 's/.*="\(.*\)"/\1/')"
            AZ_PROJECT_PROBE="$(grep -E '^export AZ_PROJECT=' "${TARGET_DIR}/.claude/project.env" | sed 's/.*="\(.*\)"/\1/')"
        fi
        if [[ -z "${AZ_ORG_PROBE}" || -z "${AZ_PROJECT_PROBE}" ]]; then
            info "AZ_ORG / AZ_PROJECT not yet set in .claude/project.env — skipping connection check."
            info "Edit project.env, then run:"
            info "  bash ${INIT_AZURE_SCRIPT}"
        else
            info "Running init-azure-tracker.sh..."
            ( cd "${TARGET_DIR}" && bash "${INIT_AZURE_SCRIPT}" ) || {
                warning "Azure connection check failed — fix the issue, then re-run:"
                warning "  bash ${INIT_AZURE_SCRIPT}"
            }
        fi
    fi
    echo ""
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  Summary                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Created : ${#CREATED[@]} items${NC}"
echo -e "  ${YELLOW}Skipped : ${#SKIPPED[@]} items (already existed)${NC}"
echo ""

# ── 7. Next steps ─────────────────────────────────────────────────────────────
echo -e "${BLUE}── Next Steps${NC}"
echo ""
echo "  1. Open ${TARGET_DIR}/CLAUDE.md and fill in:"
echo "       - Project name and overview"
echo "       - Tech stack"
echo "       - Architecture (key directories)"
echo "       - Entry points (how to run tests, lint, etc.)"
echo "       - Domain-specific rules"
echo ""
if [[ "${USE_GITHUB}" == true ]]; then
    echo "  2. Fill in .claude/project.env (GH_REPO, GH_PROJECT_NUMBER, GH_PROJECT_ID,"
    echo "     and the field/option IDs). See .claude/PORTING.md §4 for the gh commands."
    echo ""
    echo "  3. Create your first task as a GitHub Issue:"
    echo "       gh issue create --title \"Your first task\" \\"
    echo "         --body \"Description of what needs to be done\" \\"
    echo "         --label \"needs-grooming,priority-medium,role-pm\""
    echo ""
    echo "  4. Open Claude Code in ${TARGET_DIR} and run:"
    echo "       /execute"
    echo ""
    echo "  5. View your project board at:"
    echo "       https://github.com/users/${OWNER}/projects/<your-project-number>"
elif [[ "${USE_AZURE}" == true ]]; then
    echo "  2. Fill in .claude/project.env: AZ_ORG, AZ_PROJECT, AZ_REPO. See .claude/PORTING.md"
    echo "     §4-AZ for the az commands. Optional: AZ_AREA_PATH, AZ_ITERATION_PATH, AZ_WORK_ITEM_TYPE."
    echo ""
    echo "  3. Verify the Azure DevOps connection:"
    echo "       bash ${PLAYBOOK_ROOT}/scripts/init-azure-tracker.sh"
    echo ""
    echo "  4. Create your first work item:"
    echo "       source .claude/env.sh"
    echo "       tracker_create_issue --title 'Your first task' --body 'Description here' \\"
    echo "         --type feature --priority medium --role pm --state needs-grooming"
    echo ""
    echo "  5. Open Claude Code in ${TARGET_DIR} and run:"
    echo "       /execute"
else
    echo "  2. Create your first task:"
    echo "       cp ${TARGET_DIR}/.claude/templates/task.todo.md \\"
    echo "          ${TARGET_DIR}/tracker/001-your-first-task.todo.md"
    echo ""
    echo "  3. Open Claude Code in ${TARGET_DIR} and run:"
    echo "       /execute"
fi
echo ""
echo "  For a code review of existing code:"
echo "       claude --agent .claude/agents/refactoring-reviewer.md \\"
echo "         \"Review module src/your_module/\""
echo ""
echo -e "${GREEN}Done. Your agent team is ready.${NC}"
echo ""
