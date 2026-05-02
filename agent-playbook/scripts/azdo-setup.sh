#!/usr/bin/env bash
# azdo-setup.sh — Verify an existing Azure DevOps org/project/repo and emit
# the export block for .claude/project.env.
#
# This is the Azure DevOps counterpart of gh-setup.sh. It does NOT create
# resources — Azure DevOps orgs cannot be created via CLI, and the Phase B
# scope is "assume project and repo exist". The script verifies they do,
# resolves IDs, and prints the env-var block for copy-paste.
#
# Usage:
#   bash azdo-setup.sh --org <slug-or-url> --project <name> --repo <name> [OPTIONS]
#
# Required:
#   --org      Azure DevOps organization (slug "myorg" or full URL "https://dev.azure.com/myorg")
#   --project  Azure DevOps project name (case-sensitive)
#   --repo     Azure Repos repository name (case-sensitive)
#
# Options:
#   --area-path PATH         Default Area Path for new work items (default: project root)
#   --iteration-path PATH    Default Iteration Path for new work items (default: blank → backlog)
#   --work-item-type TYPE    Work-item type for new items (default: "Task")
#   --emit-only              Skip verification, just print the env block (offline)
#
# Examples:
#   bash azdo-setup.sh --org myorg --project quant-finance --repo vol-surface
#   bash azdo-setup.sh --org https://dev.azure.com/myorg --project widget --repo svc \
#                      --area-path "widget/backend" --iteration-path "widget/Sprint 1"
#
# Prerequisites:
#   - az CLI installed and authenticated (az login OR AZURE_DEVOPS_EXT_PAT)
#   - azure-devops extension: az extension add --name azure-devops

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC}    $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()  { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Defaults ─────────────────────────────────────────────────────────────────
AZ_ORG_IN=""
AZ_PROJECT_IN=""
AZ_REPO_IN=""
AZ_AREA_PATH_IN=""
AZ_ITERATION_PATH_IN=""
AZ_WORK_ITEM_TYPE_IN=""
EMIT_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --org)             AZ_ORG_IN="$2";             shift 2 ;;
        --project)         AZ_PROJECT_IN="$2";         shift 2 ;;
        --repo)            AZ_REPO_IN="$2";            shift 2 ;;
        --area-path)       AZ_AREA_PATH_IN="$2";       shift 2 ;;
        --iteration-path)  AZ_ITERATION_PATH_IN="$2";  shift 2 ;;
        --work-item-type)  AZ_WORK_ITEM_TYPE_IN="$2";  shift 2 ;;
        --emit-only)       EMIT_ONLY=true;             shift ;;
        -h|--help)
            sed -n '2,28p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -z "$AZ_ORG_IN"     ]] && die "--org is required"
[[ -z "$AZ_PROJECT_IN" ]] && die "--project is required"
[[ -z "$AZ_REPO_IN"    ]] && die "--repo is required"

# Normalise org URL
case "$AZ_ORG_IN" in
    https://*) ORG_URL="${AZ_ORG_IN%/}" ;;
    *)         ORG_URL="https://dev.azure.com/${AZ_ORG_IN}" ;;
esac

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Azure DevOps Project & Repo Setup      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Org URL    : ${ORG_URL}"
info "Project    : ${AZ_PROJECT_IN}"
info "Repository : ${AZ_REPO_IN}"
echo ""

# ── Verification (unless --emit-only) ────────────────────────────────────────
if [[ "$EMIT_ONLY" == false ]]; then
    command -v az >/dev/null 2>&1 || die "az CLI not found. Install from https://aka.ms/azure-cli"

    if ! az extension list 2>/dev/null | grep -q '"name": *"azure-devops"'; then
        die "azure-devops extension missing. Run: az extension add --name azure-devops"
    fi

    if ! az account show >/dev/null 2>&1; then
        die "az is not logged in. Run 'az login' or export AZURE_DEVOPS_EXT_PAT."
    fi
    ok "az authenticated"

    echo -e "${BLUE}── Step 1: Verify project exists${NC}"
    if ! az devops project show \
            --org "$ORG_URL" --project "$AZ_PROJECT_IN" --output none 2>/dev/null; then
        die "Project '${AZ_PROJECT_IN}' not found in '${ORG_URL}'. Create it manually first (this script does not create projects)."
    fi
    ok "Project '${AZ_PROJECT_IN}' reachable"
    echo ""

    echo -e "${BLUE}── Step 2: Verify repository exists${NC}"
    if ! az repos show \
            --org "$ORG_URL" --project "$AZ_PROJECT_IN" --repository "$AZ_REPO_IN" \
            --output none 2>/dev/null; then
        die "Repository '${AZ_REPO_IN}' not found in '${AZ_PROJECT_IN}'. Create it manually first (this script does not create repos)."
    fi
    ok "Repository '${AZ_REPO_IN}' reachable"
    echo ""
fi

# ── Emit env-var block ───────────────────────────────────────────────────────
echo -e "${BLUE}── project.env block${NC}"
echo ""
echo "Copy the lines below into .claude/project.env (replacing the existing"
echo "AZ_* exports). Empty values use the documented defaults."
echo ""
cat <<EOF
export AZ_ORG="${AZ_ORG_IN}"
export AZ_PROJECT="${AZ_PROJECT_IN}"
export AZ_REPO="${AZ_REPO_IN}"
export AZ_AREA_PATH="${AZ_AREA_PATH_IN}"
export AZ_ITERATION_PATH="${AZ_ITERATION_PATH_IN}"
export AZ_WORK_ITEM_TYPE="${AZ_WORK_ITEM_TYPE_IN}"
EOF
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  Done                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Next step: run init-azure-tracker.sh to verify the connection end-to-end:"
echo "    bash $(dirname "${BASH_SOURCE[0]}")/init-azure-tracker.sh"
echo ""
