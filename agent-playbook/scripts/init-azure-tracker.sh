#!/usr/bin/env bash
# init-azure-tracker.sh — Verify Azure DevOps connectivity and surface the
# tag/state vocabulary the agent team uses.
#
# Unlike GitHub, Azure DevOps Boards has no fixed-label catalogue to seed:
# tags are created on first use by `az boards work-item update`. So this
# script's job is narrower than init-github-tracker.sh — it confirms that
# the org/project/repo identifiers in .claude/project.env actually resolve
# and prints the vocabulary the agents will write into System.Tags so the
# user can match them against any existing board taxonomy.
#
# Usage:
#   bash init-azure-tracker.sh                 # uses values from .claude/project.env
#   bash init-azure-tracker.sh --org X --project Y [--repo Z]  # ad-hoc override
#
# Idempotent: this script makes no writes; it only verifies.

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[init]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ok]${NC}    $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()  { echo -e "${RED}[error]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ── Source project.env if present ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Walk up from $PWD looking for .claude/project.env so the script works when
# run from a project root or from inside agent-playbook/scripts/.
_find_project_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" && "$dir" != "" ]]; do
        if [[ -f "$dir/.claude/project.env" ]]; then
            echo "$dir/.claude/project.env"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ENV="$(_find_project_env || true)"
if [[ -n "$PROJECT_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$PROJECT_ENV"
fi

# ── Parse overrides ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --org)     AZ_ORG="$2";     shift 2 ;;
        --project) AZ_PROJECT="$2"; shift 2 ;;
        --repo)    AZ_REPO="$2";    shift 2 ;;
        -h|--help)
            sed -n '2,18p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Sanity checks ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Agent Playbook — Azure DevOps Tracker Init     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# az CLI present?
command -v az >/dev/null 2>&1 || die "az CLI not found. Install from https://aka.ms/azure-cli"
ok "az CLI present"

# azure-devops extension installed?
if ! az extension list 2>/dev/null | grep -q '"name": *"azure-devops"'; then
    warn "azure-devops extension not installed."
    warn "Install with: az extension add --name azure-devops"
    die  "Re-run this script after installing the extension."
fi
ok "azure-devops extension installed"

# Logged in?
if ! az account show >/dev/null 2>&1; then
    warn "az is not logged in (and AZURE_DEVOPS_EXT_PAT not picked up)."
    warn "Run: az login   — or export AZURE_DEVOPS_EXT_PAT for headless auth."
    die  "Authentication required."
fi
ok "az login OK"

# Required env vars present?
[[ -n "${AZ_ORG:-}" ]]     || die "AZ_ORG not set. Edit .claude/project.env or pass --org."
[[ -n "${AZ_PROJECT:-}" ]] || die "AZ_PROJECT not set. Edit .claude/project.env or pass --project."

# Normalise org URL
case "$AZ_ORG" in
    https://*) ORG_URL="${AZ_ORG%/}" ;;
    *)         ORG_URL="https://dev.azure.com/${AZ_ORG}" ;;
esac

info "Organization : ${ORG_URL}"
info "Project      : ${AZ_PROJECT}"
[[ -n "${AZ_REPO:-}" ]] && info "Repository   : ${AZ_REPO}"
echo ""

# ── Verify project ───────────────────────────────────────────────────────────
echo -e "${BLUE}── Verifying project${NC}"

PROJECT_JSON="$(az devops project show \
    --org "$ORG_URL" --project "$AZ_PROJECT" --output json 2>&1)" || {
    err "Could not resolve project '${AZ_PROJECT}' in '${ORG_URL}'."
    err "Output: ${PROJECT_JSON}"
    die "Verify AZ_ORG / AZ_PROJECT spelling and that your account has access."
}
PROCESS_TEMPLATE="$(echo "$PROJECT_JSON" | jq -r '.capabilities.processTemplate.templateName // "unknown"')"
ok "Project '${AZ_PROJECT}' reachable (process template: ${PROCESS_TEMPLATE})"

# Warn if the process template is not Agile (the one tracker_azure.sh maps to).
case "$PROCESS_TEMPLATE" in
    Agile)
        ok "Process template 'Agile' matches the System.State map in tracker_azure.sh"
        ;;
    Scrum|CMMI|Basic|unknown)
        warn "Process template '${PROCESS_TEMPLATE}' is not 'Agile'."
        warn "tracker_azure.sh maps states to Agile values (New/Active/Resolved/Closed)."
        warn "Set AZ_STATE_NEW / AZ_STATE_ACTIVE / AZ_STATE_RESOLVED / AZ_STATE_CLOSED in"
        warn ".claude/project.env to override (no source edit needed). Common mappings:"
        warn "  Scrum:  NEW=New      ACTIVE=Committed  RESOLVED=Done   CLOSED=Done"
        warn "  CMMI:   NEW=Proposed ACTIVE=Active     RESOLVED=Resolved CLOSED=Closed"
        warn "  Basic:  NEW='To Do'  ACTIVE=Doing      RESOLVED=Doing  CLOSED=Done"
        ;;
esac

echo ""

# ── Verify repo (if specified) ───────────────────────────────────────────────
if [[ -n "${AZ_REPO:-}" ]]; then
    echo -e "${BLUE}── Verifying repository${NC}"
    if az repos show \
        --org "$ORG_URL" --project "$AZ_PROJECT" --repository "$AZ_REPO" \
        --output none 2>/dev/null; then
        ok "Repository '${AZ_REPO}' reachable"
    else
        err "Could not resolve repository '${AZ_REPO}' in project '${AZ_PROJECT}'."
        die "Verify AZ_REPO spelling. Run 'az repos list --project ${AZ_PROJECT}' to see available repos."
    fi
    echo ""
fi

# ── Verify area path ─────────────────────────────────────────────────────────
echo -e "${BLUE}── Verifying area path${NC}"
EFFECTIVE_AREA="${AZ_AREA_PATH:-${AZ_PROJECT}}"
if az boards area project list \
    --org "$ORG_URL" --project "$AZ_PROJECT" --output json 2>/dev/null \
    | jq -e --arg p "$EFFECTIVE_AREA" '.. | objects | select(.name? == $p)' >/dev/null 2>&1; then
    ok "Area path '${EFFECTIVE_AREA}' exists"
else
    # `az boards area project list` returns a tree; the project root always
    # exists by construction even if the listing schema misses a match.
    if [[ "$EFFECTIVE_AREA" == "$AZ_PROJECT" ]]; then
        ok "Area path defaults to project root '${AZ_PROJECT}' (always exists)"
    else
        warn "Area path '${EFFECTIVE_AREA}' not found by 'az boards area project list'."
        warn "Verify it exists, or unset AZ_AREA_PATH to fall back to '${AZ_PROJECT}'."
    fi
fi
echo ""

# ── Print the tag vocabulary the agents will use ─────────────────────────────
echo -e "${BLUE}── Tag vocabulary (created on-demand on first work-item update)${NC}"
echo ""
cat <<'EOF'
  State tags:
    backlog               needs-grooming        ready-for-dev
    in-progress           ready-for-qa          ready-for-acceptance
    ready-for-docs        rework-needed         blocked
    (state "done" → System.State=Closed, no tag)

  Role tags:
    role-pm   role-swe   role-qa   role-techwriter   role-oncall   role-human

  Priority tags (mirror Microsoft.VSTS.Common.Priority 1/2/3):
    priority-high         priority-medium        priority-low

  Type tags:
    type-feature          type-bugfix
    type-refactor         type-infra

  QA-cycle tags:
    qa-cycle-1            qa-cycle-2             qa-cycle-3
EOF
echo ""
echo "  Tags are created on the work item the first time tracker_azure_*"
echo "  writes them. No pre-seeding step is needed. If your ADO project"
echo "  enforces a tag allow-list, add the tags above before running the"
echo "  pipeline."
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   Summary                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
ok "Connection verified for ${AZ_PROJECT} @ ${ORG_URL}"
echo ""
echo "  Create your first work item:"
echo "    source .claude/env.sh"
echo "    tracker_create_issue --title 'My first task' --body '…' \\"
echo "      --type feature --priority medium --role pm --state needs-grooming"
echo ""
echo -e "${GREEN}Done.${NC}"
echo ""
