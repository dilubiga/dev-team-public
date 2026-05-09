#!/usr/bin/env bash
# wire-github-project.sh — Resolve a GitHub Project's field/option IDs and wire
# them into a project's .claude/project.env so the dev-team pipeline works.
#
# This is the missing step between init-project.sh (creates .claude/ infra +
# repo labels) and a runnable /execute pipeline (which needs project.env
# fully populated with Project ID, field IDs, and single-select option IDs).
#
# Usage:
#   bash wire-github-project.sh /path/to/project [--project-name "<title>"] [--owner <gh-user>]
#
# Behaviour (idempotent):
#   1. Verifies .claude/env.sh exists; runs init-project.sh if not.
#   2. Resolves the GitHub Project by title (default: read from CLAUDE.md
#      `github_project_name:`). Creates it if missing.
#   3. Ensures the four single-select fields exist with the right options:
#         Pipeline   (Backlog, Grooming, Development, QA, Acceptance,
#                     Documentation, Done, Blocked)
#         Agent      (PM, SWE, QA, On-Call, TechWriter, Human)
#         Status     (Ready, In progress, In review, Done)   [GitHub default]
#         QA Cycle   (text field)
#      Missing fields/options are created. Existing ones are left untouched.
#   4. Writes resolved IDs into .claude/project.env (in place — preserves
#      comments, only updates the export lines).
#   5. Updates CLAUDE.md to point at the resolved project number.
#   6. Smoke-tests by sourcing .claude/env.sh and calling
#      `tracker_list_issues --count`.
#
# Requirements:
#   - gh CLI authenticated with scopes: repo, project, read:org
#   - jq
#
# Re-running is safe: every step checks current state first.

set -euo pipefail

# ── Colours / logging ────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[wire]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
skip()    { echo -e "${YELLOW}[skip]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; }

# ── Resolve playbook root (the dev-team toolkit dir containing this script) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INIT_PROJECT_SH="${SCRIPT_DIR}/init-project.sh"

# ── Args ──────────────────────────────────────────────────────────────────────
TARGET_DIR=""
PROJECT_NAME=""
OWNER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-name) PROJECT_NAME="$2"; shift 2 ;;
        --owner)        OWNER="$2";        shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        -*) error "Unknown flag: $1"; exit 2 ;;
        *)  if [[ -z "$TARGET_DIR" ]]; then TARGET_DIR="$1"; else
                error "Unexpected positional arg: $1"; exit 2
            fi
            shift ;;
    esac
done

if [[ -z "$TARGET_DIR" ]]; then
    error "Usage: bash wire-github-project.sh /path/to/project [--project-name TITLE] [--owner USER]"
    exit 2
fi
if [[ ! -d "$TARGET_DIR" ]]; then
    error "Project dir not found: $TARGET_DIR"
    exit 2
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# ── Tooling checks ────────────────────────────────────────────────────────────
command -v gh >/dev/null 2>&1 || { error "gh CLI not installed"; exit 2; }
command -v jq >/dev/null 2>&1 || { error "jq not installed"; exit 2; }
gh auth status >/dev/null 2>&1 || { error "gh not authenticated. Run: gh auth login"; exit 2; }

# ── Resolve OWNER ────────────────────────────────────────────────────────────
if [[ -z "$OWNER" ]]; then
    OWNER="$(gh api user --jq .login 2>/dev/null || true)"
fi
if [[ -z "$OWNER" ]]; then
    error "Cannot resolve GitHub owner. Pass --owner or run: gh auth login"
    exit 2
fi
info "Owner: ${OWNER}"
info "Project dir: ${TARGET_DIR}"

# ── Step 1: Run init-project.sh if .claude/env.sh missing ────────────────────
if [[ ! -f "${TARGET_DIR}/.claude/env.sh" ]]; then
    info ".claude/env.sh missing — running init-project.sh first"
    if [[ ! -x "$INIT_PROJECT_SH" ]] && [[ ! -f "$INIT_PROJECT_SH" ]]; then
        error "init-project.sh not found at ${INIT_PROJECT_SH}"
        exit 2
    fi
    bash "$INIT_PROJECT_SH" "$TARGET_DIR" data-pipeline --github
    ok "init-project.sh completed"
else
    skip ".claude/env.sh already present"
fi

# ── Step 2: Resolve project name from CLAUDE.md if not given ─────────────────
CLAUDE_MD="${TARGET_DIR}/CLAUDE.md"
if [[ -z "$PROJECT_NAME" ]] && [[ -f "$CLAUDE_MD" ]]; then
    # Look for the first non-empty value after `github_project_name:`
    PROJECT_NAME="$(grep -E '^github_project_name:' "$CLAUDE_MD" | head -1 | sed -E 's/^github_project_name:[[:space:]]*//' || true)"
fi
if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$(basename "$TARGET_DIR")"
    warn "No --project-name given and CLAUDE.md has none; defaulting to '${PROJECT_NAME}'"
fi
info "Project title: ${PROJECT_NAME}"

# ── Step 3: Find or create the GitHub Project ────────────────────────────────
PROJECT_NUMBER="$(gh project list --owner "$OWNER" --format json --limit 200 \
    | jq -r --arg t "$PROJECT_NAME" '.projects[] | select(.title == $t) | .number' | head -1)"

if [[ -z "$PROJECT_NUMBER" ]]; then
    info "Project '${PROJECT_NAME}' not found — creating"
    gh project create --owner "$OWNER" --title "$PROJECT_NAME" >/dev/null
    PROJECT_NUMBER="$(gh project list --owner "$OWNER" --format json --limit 200 \
        | jq -r --arg t "$PROJECT_NAME" '.projects[] | select(.title == $t) | .number' | head -1)"
    [[ -n "$PROJECT_NUMBER" ]] || { error "Failed to create project"; exit 1; }
    ok "Created project #${PROJECT_NUMBER}"
else
    skip "Project #${PROJECT_NUMBER} '${PROJECT_NAME}' already exists"
fi

PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json | jq -r '.id')"
info "Project ID: ${PROJECT_ID}"

# ── Step 4: Ensure single-select fields with required options ────────────────
# Helper: dump current fields as JSON
dump_fields() { gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --limit 100; }

ensure_single_select_field() {
    # ensure_single_select_field <FieldName> <opt1,opt2,...>
    local field_name="$1"; local options_csv="$2"
    local fields_json; fields_json="$(dump_fields)"
    local existing_id
    existing_id="$(echo "$fields_json" | jq -r --arg n "$field_name" '.fields[] | select(.name == $n) | .id' | head -1)"
    if [[ -z "$existing_id" ]]; then
        info "Creating field '${field_name}' with options: ${options_csv}"
        gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
            --name "$field_name" \
            --data-type SINGLE_SELECT \
            --single-select-options "$options_csv" >/dev/null
        ok "Created field '${field_name}'"
    else
        # Field exists — check that all required options exist; if any are
        # missing, warn (gh CLI cannot add options to existing fields).
        local opts_have
        opts_have="$(echo "$fields_json" | jq -r --arg n "$field_name" '.fields[] | select(.name == $n) | .options[]?.name' | tr -d '\r' | tr '\n' ',' | sed 's/,$//')"
        IFS=',' read -ra wanted <<<"$options_csv"
        local missing=""
        for o in "${wanted[@]}"; do
            if ! echo ",${opts_have}," | grep -q ",${o},"; then
                missing="${missing}${o},"
            fi
        done
        if [[ -n "$missing" ]]; then
            warn "Field '${field_name}' exists but is missing options: ${missing%,}"
            warn "  → Add via the GitHub Projects UI; gh CLI cannot append options to an existing field."
        else
            skip "Field '${field_name}' present with all required options"
        fi
    fi
}

ensure_text_field() {
    local field_name="$1"
    local fields_json; fields_json="$(dump_fields)"
    local existing_id
    existing_id="$(echo "$fields_json" | jq -r --arg n "$field_name" '.fields[] | select(.name == $n) | .id' | head -1)"
    if [[ -z "$existing_id" ]]; then
        gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
            --name "$field_name" --data-type TEXT >/dev/null
        ok "Created text field '${field_name}'"
    else
        skip "Text field '${field_name}' already present"
    fi
}

ensure_single_select_field "Pipeline" "Backlog,Grooming,Development,QA,Acceptance,Documentation,Done,Blocked"
ensure_single_select_field "Agent"    "PM,SWE,QA,On-Call,TechWriter,Human"
# Status is created by GitHub on every project with default options Ready / In progress / In review / Done
ensure_text_field         "QA Cycle"

# ── Step 5: Resolve all field & option IDs ───────────────────────────────────
FIELDS_JSON="$(dump_fields)"

f_id() { echo "$FIELDS_JSON" | jq -r --arg n "$1" '.fields[] | select(.name == $n) | .id' | head -1; }
opt_id() {
    # opt_id <FieldName> <OptionName>
    echo "$FIELDS_JSON" | jq -r --arg f "$1" --arg o "$2" \
        '.fields[] | select(.name == $f) | .options[]? | select(.name == $o) | .id' | head -1
}

GH_FIELD_PIPELINE="$(f_id Pipeline)"
GH_FIELD_AGENT="$(f_id Agent)"
GH_FIELD_STATUS="$(f_id Status)"
GH_FIELD_QA_CYCLE="$(f_id 'QA Cycle')"

GH_PIPELINE_BACKLOG="$(opt_id Pipeline Backlog)"
GH_PIPELINE_DEVELOPMENT="$(opt_id Pipeline Development)"
GH_PIPELINE_QA="$(opt_id Pipeline QA)"
GH_PIPELINE_ACCEPTANCE="$(opt_id Pipeline Acceptance)"
GH_PIPELINE_DOCUMENTATION="$(opt_id Pipeline Documentation)"
GH_PIPELINE_DONE="$(opt_id Pipeline Done)"
GH_PIPELINE_BLOCKED="$(opt_id Pipeline Blocked)"

GH_AGENT_PM="$(opt_id Agent PM)"
GH_AGENT_SWE="$(opt_id Agent SWE)"
GH_AGENT_QA="$(opt_id Agent QA)"
GH_AGENT_TECHWRITER="$(opt_id Agent TechWriter)"
GH_AGENT_HUMAN="$(opt_id Agent Human)"

GH_STATUS_BACKLOG="$(opt_id Status Ready)"
GH_STATUS_IN_DOCS="$(opt_id Status 'In review')"
GH_STATUS_DONE="$(opt_id Status Done)"

# ── Resolve repo name (from CLAUDE.md or basename) ───────────────────────────
GH_REPO=""
if [[ -f "$CLAUDE_MD" ]]; then
    GH_REPO="$(grep -E '^repo:' "$CLAUDE_MD" | head -1 | sed -E 's|^repo:[[:space:]]*||; s|.*/||; s|\.git$||' || true)"
fi
[[ -n "$GH_REPO" ]] || GH_REPO="$(basename "$TARGET_DIR")"
info "Repo: ${OWNER}/${GH_REPO}"

# ── Step 6: Patch .claude/project.env in place ───────────────────────────────
ENV_FILE="${TARGET_DIR}/.claude/project.env"
[[ -f "$ENV_FILE" ]] || { error "${ENV_FILE} missing — init-project.sh did not run cleanly"; exit 1; }

set_env_var() {
    # set_env_var KEY VALUE [--quote]
    local key="$1"; local value="$2"; local quote="${3:-}"
    local replacement
    if [[ "$quote" == "--quote" ]]; then
        replacement="export ${key}=\"${value}\""
    else
        replacement="export ${key}=${value}"
    fi
    # Match `export KEY=...` (any value, quoted or not, possibly empty)
    if grep -qE "^export ${key}=" "$ENV_FILE"; then
        # Use awk to rewrite the line — avoids sed quoting hell with special chars
        awk -v k="$key" -v r="$replacement" \
            'BEGIN{found=0} { if ($0 ~ "^export " k "=") { print r; found=1 } else print } END{ if (!found) print r }' \
            "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
    else
        echo "$replacement" >> "$ENV_FILE"
    fi
}

set_env_var GH_OWNER          "$OWNER"          --quote
set_env_var GH_REPO           "$GH_REPO"        --quote
set_env_var GH_PROJECT_NUMBER "$PROJECT_NUMBER"
set_env_var GH_PROJECT_ID     "$PROJECT_ID"     --quote

set_env_var GH_FIELD_PIPELINE  "$GH_FIELD_PIPELINE"  --quote
set_env_var GH_FIELD_AGENT     "$GH_FIELD_AGENT"     --quote
set_env_var GH_FIELD_STATUS    "$GH_FIELD_STATUS"    --quote
set_env_var GH_FIELD_QA_CYCLE  "$GH_FIELD_QA_CYCLE"  --quote

set_env_var GH_PIPELINE_BACKLOG       "$GH_PIPELINE_BACKLOG"       --quote
set_env_var GH_PIPELINE_DEVELOPMENT   "$GH_PIPELINE_DEVELOPMENT"   --quote
set_env_var GH_PIPELINE_QA            "$GH_PIPELINE_QA"            --quote
set_env_var GH_PIPELINE_ACCEPTANCE    "$GH_PIPELINE_ACCEPTANCE"    --quote
set_env_var GH_PIPELINE_DOCUMENTATION "$GH_PIPELINE_DOCUMENTATION" --quote
set_env_var GH_PIPELINE_DONE          "$GH_PIPELINE_DONE"          --quote
set_env_var GH_PIPELINE_BLOCKED       "$GH_PIPELINE_BLOCKED"       --quote

set_env_var GH_AGENT_PM         "$GH_AGENT_PM"         --quote
set_env_var GH_AGENT_SWE        "$GH_AGENT_SWE"        --quote
set_env_var GH_AGENT_QA         "$GH_AGENT_QA"         --quote
set_env_var GH_AGENT_TECHWRITER "$GH_AGENT_TECHWRITER" --quote
set_env_var GH_AGENT_HUMAN      "$GH_AGENT_HUMAN"      --quote

set_env_var GH_STATUS_BACKLOG "$GH_STATUS_BACKLOG" --quote
set_env_var GH_STATUS_IN_DOCS "$GH_STATUS_IN_DOCS" --quote
set_env_var GH_STATUS_DONE    "$GH_STATUS_DONE"    --quote

ok "Wrote IDs to ${ENV_FILE}"

# ── Step 7: Update CLAUDE.md project pointer ─────────────────────────────────
if [[ -f "$CLAUDE_MD" ]]; then
    if grep -qE '^github_project_action:' "$CLAUDE_MD"; then
        awk -v num="$PROJECT_NUMBER" -v name="$PROJECT_NAME" '
            /^github_project_action:/ { print "github_project_action: use_existing"; next }
            /^github_project_name:/   { print "github_project_name: " name;          next }
            /^github_project_number:/ { print "github_project_number: " num;          next }
            { print }
        ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
        ok "Updated CLAUDE.md project pointer (use_existing, #${PROJECT_NUMBER})"
    else
        skip "CLAUDE.md has no github_project_* lines — leaving as-is"
    fi
fi

# ── Step 8: Smoke test ───────────────────────────────────────────────────────
info "Smoke-testing tracker..."
if ( cd "$TARGET_DIR" && bash -c 'set -e; source .claude/env.sh >/dev/null 2>&1; tracker_list_issues --count >/dev/null' ); then
    ok "tracker_list_issues works — pipeline is wired."
else
    error "Smoke test failed. Source .claude/env.sh and run tracker_list_issues --count to debug."
    exit 1
fi

echo
ok "Done. Run /execute in Claude Code to start the pipeline."
echo "    Project board: https://github.com/users/${OWNER}/projects/${PROJECT_NUMBER}"
