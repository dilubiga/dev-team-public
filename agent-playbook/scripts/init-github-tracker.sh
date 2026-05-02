#!/usr/bin/env bash
# init-github-tracker.sh — Set up GitHub Issues labels and Project fields for the agent pipeline.
#
# Usage:
#   bash init-github-tracker.sh [REPO] [PROJECT_NUMBER]
#
# Arguments:
#   REPO             Optional. GitHub repo in "owner/name" format (e.g., <your-github-user>/my-pricer).
#                    If omitted, uses the current repo from gh context.
#   PROJECT_NUMBER   Optional. If provided, also adds Pipeline, Priority, Agent, Status,
#                    and QA Cycle fields to the GitHub Project board.
#
# Examples:
#   bash init-github-tracker.sh <your-github-user>/my-pricer
#   bash init-github-tracker.sh <your-github-user>/my-pricer 3
#   bash init-github-tracker.sh                      # uses current repo
#
# This script is idempotent: running it twice will not create duplicate labels.

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[init]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
skip()    { echo -e "${YELLOW}[skip]${NC}  $*"; }
warning() { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Determine repo ───────────────────────────────────────────────────────────
if [[ $# -ge 1 ]] && [[ "$1" != "--"* ]]; then
    REPO="$1"
    shift
else
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
        error "Could not detect current repo. Pass it explicitly: bash init-github-tracker.sh <your-github-user>/<your-repo>"
        exit 1
    }
fi

PROJECT_NUMBER="${1:-}"
OWNER="${REPO%%/*}"

# Verify gh auth
if ! gh auth status &>/dev/null; then
    error "gh CLI is not authenticated. Run: gh auth login"
    exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Agent Playbook — GitHub Tracker Init           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
info "Repository: ${REPO}"
if [[ -n "${PROJECT_NUMBER}" ]]; then
    info "Project:    ${OWNER}/${PROJECT_NUMBER}"
fi
echo ""

CREATED=0
SKIPPED=0

create_label() {
    local name="$1"
    local color="$2"
    local desc="$3"

    if gh label create "$name" --color "$color" --description "$desc" --repo "${REPO}" 2>/dev/null; then
        ok "Created label: ${name}"
        ((CREATED++)) || true
    else
        skip "Label already exists: ${name}"
        ((SKIPPED++)) || true
    fi
}

# ── 1. Pipeline state labels ────────────────────────────────────────────────
echo -e "${BLUE}── Pipeline State Labels${NC}"

create_label "backlog"              "CCCCCC" "Dormant backlog item — human must promote to activate"
create_label "needs-grooming"       "D93F0B" "Raw task — waiting for PM to write spec"
create_label "ready-for-dev"        "0E8A16" "PM wrote spec — ready for SWE to implement"
create_label "in-progress"          "1D76DB" "SWE is implementing"
create_label "ready-for-qa"         "FBCA04" "SWE done — waiting for QA verification"
create_label "ready-for-acceptance" "BFD4F2" "QA passed — waiting for PM final review"
create_label "ready-for-docs"       "C5DEF5" "PM accepted — waiting for Technical Writer to produce docs"
create_label "docs-done"            "0E8A16" "Docs written — ready to commit and close"
create_label "rework-needed"        "E4E669" "QA failed or PM rejected — back to SWE"
create_label "blocked"              "B60205" "Waiting for human input (check Agent Questions)"

echo ""

# ── 2. Priority labels ──────────────────────────────────────────────────────
echo -e "${BLUE}── Priority Labels${NC}"

create_label "priority-high"   "B60205" "Must be done first"
create_label "priority-medium" "FBCA04" "Normal priority"
create_label "priority-low"    "C2E0C6" "Nice to have — do when backlog is clear"

echo ""

# ── 3. Role labels (which agent is responsible) ─────────────────────────────
echo -e "${BLUE}── Role Labels${NC}"

create_label "role-pm"         "D4C5F9" "Currently with Product Manager"
create_label "role-swe"        "BFD4F2" "Currently with Software Engineer"
create_label "role-qa"         "FEF2C0" "Currently with QA / Tester"
create_label "role-techwriter" "C5DEF5" "Currently with Technical Writer"
create_label "role-oncall"     "E6E6E6" "Currently with On-Call Engineer"
create_label "role-human"      "F9D0C4" "Waiting for human (ideator) input"

echo ""

# ── 4. Type labels ──────────────────────────────────────────────────────────
echo -e "${BLUE}── Type Labels${NC}"

create_label "type-feature"  "A2EEEF" "New feature or capability"
create_label "type-bugfix"   "D93F0B" "Bug fix"
create_label "type-refactor" "C5DEF5" "Code refactoring (no behavior change)"
create_label "type-infra"    "E6E6E6" "Infrastructure or CI/CD change"

echo ""

# ── 5. QA cycle tracking labels ─────────────────────────────────────────────
echo -e "${BLUE}── QA Cycle Labels${NC}"

create_label "qa-cycle-1"  "FEF2C0" "First QA review"
create_label "qa-cycle-2"  "FBCA04" "Second QA review (rework)"
create_label "qa-cycle-3"  "D93F0B" "Third QA review — escalate to human if fails"

echo ""

# ── 6. GitHub Project fields (if project number provided) ───────────────────
if [[ -n "${PROJECT_NUMBER}" ]]; then
    echo -e "${BLUE}── GitHub Project Fields (Project #${PROJECT_NUMBER})${NC}"

    if ! gh project view "${PROJECT_NUMBER}" --owner "${OWNER}" &>/dev/null; then
        error "Project ${OWNER}/${PROJECT_NUMBER} not found."
        error "Create it first: gh project create --owner ${OWNER} --title 'Project Name'"
        echo ""
    else
        # Pipeline field (single-select) — the kanban column
        gh project field-create "${PROJECT_NUMBER}" \
            --owner "${OWNER}" \
            --name "Pipeline" \
            --data-type "SINGLE_SELECT" \
            --single-select-options "Backlog,Development,QA,Acceptance,Documentation,Done,Blocked" \
            2>/dev/null && ok "Field: Pipeline" || skip "Field: Pipeline (may already exist)"

        # Priority field (single-select)
        gh project field-create "${PROJECT_NUMBER}" \
            --owner "${OWNER}" \
            --name "Priority" \
            --data-type "SINGLE_SELECT" \
            --single-select-options "High,Medium,Low" \
            2>/dev/null && ok "Field: Priority" || skip "Field: Priority (may already exist)"

        # Agent field (single-select) — who currently owns the item
        gh project field-create "${PROJECT_NUMBER}" \
            --owner "${OWNER}" \
            --name "Agent" \
            --data-type "SINGLE_SELECT" \
            --single-select-options "PM,SWE,QA,TechWriter,On-Call,Human" \
            2>/dev/null && ok "Field: Agent" || skip "Field: Agent (may already exist)"

        # Status field (single-select) — fine-grained state within a Pipeline column
        gh project field-create "${PROJECT_NUMBER}" \
            --owner "${OWNER}" \
            --name "Status" \
            --data-type "SINGLE_SELECT" \
            --single-select-options "Backlog,Ready,In progress,In review,In documentation,Done" \
            2>/dev/null && ok "Field: Status" || skip "Field: Status (may already exist)"

        # QA Cycle field (number) — rework count
        gh project field-create "${PROJECT_NUMBER}" \
            --owner "${OWNER}" \
            --name "QA Cycle" \
            --data-type "NUMBER" \
            2>/dev/null && ok "Field: QA Cycle" || skip "Field: QA Cycle (may already exist)"

        echo ""
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   Summary                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Created : ${CREATED} labels${NC}"
echo -e "  ${YELLOW}Skipped : ${SKIPPED} labels (already existed)${NC}"
echo ""
echo "  Create your first issue:"
echo "    gh issue create --repo ${REPO} \\"
echo "      --title 'My first task' \\"
echo "      --body 'Description here' \\"
echo "      --label 'needs-grooming,priority-medium,role-pm'"
echo ""
echo -e "${GREEN}Done.${NC}"
echo ""
