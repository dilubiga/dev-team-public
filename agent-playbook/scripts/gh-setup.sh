#!/usr/bin/env bash
# gh-setup.sh — Create a GitHub Project, create (or link) a repo, and wire them together.
#
# Usage:
#   bash gh-setup.sh --owner <your-github-user> --project <your-project-name> --repo <your-repo> [OPTIONS]
#
# Required:
#   --owner   GitHub username or org (e.g. <your-github-user>)
#   --project GitHub Project title   (e.g. quant-finance)
#   --repo    Repository name        (e.g. <your-repo>)
#
# Options:
#   --description TEXT   Repo description (default: empty)
#   --private            Make the repo private (default: public)
#   --no-project         Skip project creation/linking
#   --no-repo            Skip repo creation (just create the project)
#   --link-only          Skip creation; only link an existing repo to an existing project
#
# Examples:
#   bash gh-setup.sh --owner <your-github-user> --project quant-finance --repo <your-repo>
#   bash gh-setup.sh --owner <your-github-user> --project quant-finance --repo vol-surface --private --description "Vol surface models"
#   bash gh-setup.sh --owner <your-github-user> --project quant-finance --repo existing-repo --link-only
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - For project operations: gh auth refresh -h github.com -s project,read:project

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[setup]${NC} $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
skip()    { echo -e "${YELLOW}[skip]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
OWNER=""
PROJECT_TITLE=""
REPO_NAME=""
REPO_DESC=""
REPO_VISIBILITY="--public"
CREATE_PROJECT=true
CREATE_REPO=true
LINK_ONLY=false

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --owner)       OWNER="$2";        shift 2 ;;
        --project)     PROJECT_TITLE="$2"; shift 2 ;;
        --repo)        REPO_NAME="$2";    shift 2 ;;
        --description) REPO_DESC="$2";    shift 2 ;;
        --private)     REPO_VISIBILITY="--private"; shift ;;
        --no-project)  CREATE_PROJECT=false; shift ;;
        --no-repo)     CREATE_REPO=false; shift ;;
        --link-only)   LINK_ONLY=true; CREATE_PROJECT=false; CREATE_REPO=false; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -z "${OWNER}" ]]         && die "--owner is required"
[[ -z "${PROJECT_TITLE}" ]] && die "--project is required"
[[ -z "${REPO_NAME}" ]]     && die "--repo is required"
# ── Find a working Python interpreter ────────────────────────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/lib/find-python.sh"

PY="$(_find_python)" || die "No Python interpreter found. Install Python or add it to PATH."
# ── Check gh auth ─────────────────────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
    die "gh CLI is not authenticated. Run: gh auth login"
fi

# Check project scope if needed
if [[ "${CREATE_PROJECT}" == true ]] || [[ "${LINK_ONLY}" == true ]]; then
    if ! gh auth status 2>&1 | grep -q "project"; then
        warn "Project scopes may be missing. If the script fails, run:"
        warn "  gh auth refresh -h github.com -s project,read:project"
    fi
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         GitHub Project & Repo Setup          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Owner   : ${OWNER}"
info "Project : ${PROJECT_TITLE}"
info "Repo    : ${OWNER}/${REPO_NAME}"
[[ -n "${REPO_DESC}" ]] && info "Desc    : ${REPO_DESC}"
info "Visibility: ${REPO_VISIBILITY/--/}"
echo ""

# ── Step 1: Create or find GitHub Project ─────────────────────────────────────
PROJECT_NUMBER=""
PROJECT_ID=""

if [[ "${CREATE_PROJECT}" == true ]]; then
    echo -e "${BLUE}── Step 1: GitHub Project${NC}"

    # Check if a project with this title already exists
    EXISTING=$(gh project list --owner "${OWNER}" --format json \
        | "${PY}" -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('projects', []):
    if p['title'] == sys.argv[1]:
        print(str(p['number']) + ' ' + p['id'])
        break
" "${PROJECT_TITLE}" 2>/dev/null || true)

    if [[ -n "${EXISTING}" ]]; then
        PROJECT_NUMBER=$(echo "${EXISTING}" | cut -d' ' -f1)
        PROJECT_ID=$(echo "${EXISTING}" | cut -d' ' -f2)
        skip "Project '${PROJECT_TITLE}' already exists (#${PROJECT_NUMBER})"
    else
        PROJECT_URL=$(gh project create --owner "${OWNER}" --title "${PROJECT_TITLE}" --format json \
            | "${PY}" -c "import sys,json; d=json.load(sys.stdin); print(d.get('url',''))" 2>/dev/null || \
            gh project create --owner "${OWNER}" --title "${PROJECT_TITLE}" 2>&1 | grep -oP 'https://\S+' | head -1 || true)

        # Re-fetch number and ID after creation
        EXISTING=$(gh project list --owner "${OWNER}" --format json \
            | "${PY}" -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('projects', []):
    if p['title'] == sys.argv[1]:
        print(str(p['number']) + ' ' + p['id'])
        break
" "${PROJECT_TITLE}" 2>/dev/null || true)

        PROJECT_NUMBER=$(echo "${EXISTING}" | cut -d' ' -f1)
        PROJECT_ID=$(echo "${EXISTING}" | cut -d' ' -f2)
        ok "Created project '${PROJECT_TITLE}' (#${PROJECT_NUMBER})"
    fi
    echo ""
else
    # Look up existing project
    echo -e "${BLUE}── Step 1: Locating existing GitHub Project${NC}"
    EXISTING=$(gh project list --owner "${OWNER}" --format json \
        | "${PY}" -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('projects', []):
    if p['title'] == sys.argv[1]:
        print(str(p['number']) + ' ' + p['id'])
        break
" "${PROJECT_TITLE}" 2>/dev/null || true)

    if [[ -z "${EXISTING}" ]]; then
        die "Project '${PROJECT_TITLE}' not found for owner '${OWNER}'. Remove --no-project or --link-only to create it."
    fi
    PROJECT_NUMBER=$(echo "${EXISTING}" | cut -d' ' -f1)
    PROJECT_ID=$(echo "${EXISTING}" | cut -d' ' -f2)
    ok "Found project '${PROJECT_TITLE}' (#${PROJECT_NUMBER})"
    echo ""
fi

# ── Step 2: Create or verify GitHub Repo ─────────────────────────────────────
REPO_ID=""
REPO_FULL="${OWNER}/${REPO_NAME}"

if [[ "${CREATE_REPO}" == true ]]; then
    echo -e "${BLUE}── Step 2: GitHub Repository${NC}"

    # Check if repo already exists
    REPO_ID=$(gh repo view "${REPO_FULL}" --json id -q '.id' 2>/dev/null || true)

    if [[ -n "${REPO_ID}" ]]; then
        skip "Repo '${REPO_FULL}' already exists"
    else
        DESC_FLAG=""
        [[ -n "${REPO_DESC}" ]] && DESC_FLAG="--description ${REPO_DESC}"

        gh repo create "${REPO_FULL}" ${REPO_VISIBILITY} ${DESC_FLAG} >/dev/null
        REPO_ID=$(gh repo view "${REPO_FULL}" --json id -q '.id')
        ok "Created repo '${REPO_FULL}'"
    fi
    echo ""
else
    echo -e "${BLUE}── Step 2: Locating existing repo${NC}"
    REPO_ID=$(gh repo view "${REPO_FULL}" --json id -q '.id' 2>/dev/null || true)
    [[ -z "${REPO_ID}" ]] && die "Repo '${REPO_FULL}' not found. Remove --no-repo or --link-only to create it."
    ok "Found repo '${REPO_FULL}' (${REPO_ID})"
    echo ""
fi

# ── Step 3: Link repo to project ─────────────────────────────────────────────
echo -e "${BLUE}── Step 3: Link repo to project${NC}"

LINK_RESULT=$(gh api graphql -f query="
mutation {
  linkProjectV2ToRepository(input: {projectId: \"${PROJECT_ID}\", repositoryId: \"${REPO_ID}\"}) {
    repository { name }
  }
}" 2>&1 || true)

if echo "${LINK_RESULT}" | grep -q '"name"'; then
    ok "Linked '${REPO_FULL}' to project '${PROJECT_TITLE}' (#${PROJECT_NUMBER})"
elif echo "${LINK_RESULT}" | grep -qi "already"; then
    skip "'${REPO_FULL}' is already linked to project '#${PROJECT_NUMBER}'"
else
    warn "Link step returned unexpected output:"
    warn "${LINK_RESULT}"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  Done                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Repository :${NC} https://github.com/${REPO_FULL}"
echo -e "  ${GREEN}Project    :${NC} https://github.com/users/${OWNER}/projects/${PROJECT_NUMBER}"
echo ""
