#!/usr/bin/env bash
# lib/tracker/tracker.sh
#
# Tracker dispatcher. Sourced by .claude/env.sh after project.env is loaded.
# Routes each verb to one of three backends based on $TRACKER_BACKEND:
#   - file           → tracker_file.sh           (default)
#   - github-issues  → tracker_github.sh
#   - azure-boards   → tracker_azure.sh
#
# All 12 verbs are exposed as bash functions in the calling shell.
# See lib/tracker/_docs/interface-spec.md for the full contract.

# Guard against double-sourcing.
if [[ -n "${_TRACKER_DISPATCHER_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_TRACKER_DISPATCHER_LOADED=1

_TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Always source common helpers.
# shellcheck disable=SC1091
source "${_TRACKER_DIR}/_common.sh"

# Source every backend; each one defines its tracker_<backend>_<verb> functions
# but does not export them. Backends are cheap to source — they only define
# functions, no side effects.
# shellcheck disable=SC1091
source "${_TRACKER_DIR}/tracker_file.sh"
# shellcheck disable=SC1091
source "${_TRACKER_DIR}/tracker_github.sh"
# shellcheck disable=SC1091
source "${_TRACKER_DIR}/tracker_azure.sh"

_tracker_resolve_backend() {
    # Translate $TRACKER_BACKEND (or default 'file') into the backend slug used
    # in function names. Returns 0 + prints slug on stdout for valid values;
    # returns 2 + prints nothing for invalid values.
    local backend="${TRACKER_BACKEND:-file}"
    case "$backend" in
        file)            echo "file" ;;
        github-issues)   echo "github" ;;
        azure-boards)    echo "azure" ;;
        *)
            tracker_log_error "tracker.sh" \
                "unknown TRACKER_BACKEND='$backend' (expected: file, github-issues, azure-boards)"
            return 2 ;;
    esac
}

_tracker_dispatch() {
    # Args: <verb-suffix> <flags...>
    # Calls tracker_<backend>_<verb-suffix> with the remaining args.
    local verb_suffix="$1"; shift
    local backend
    backend="$(_tracker_resolve_backend)" || return 2
    local fn="tracker_${backend}_${verb_suffix}"
    if ! declare -F "$fn" >/dev/null; then
        tracker_log_error "tracker.sh" "no implementation for '$fn'"
        return 3
    fi
    "$fn" "$@"
}

# ── Public verbs ────────────────────────────────────────────────────────────

tracker_list_issues()           { _tracker_dispatch list_issues "$@"; }
tracker_view_issue()            { _tracker_dispatch view_issue "$@"; }
tracker_view_issue_comments()   { _tracker_dispatch view_issue_comments "$@"; }
tracker_create_issue()          { _tracker_dispatch create_issue "$@"; }
tracker_comment_issue()         { _tracker_dispatch comment_issue "$@"; }
tracker_transition()            { _tracker_dispatch transition "$@"; }
tracker_set_qa_cycle()          { _tracker_dispatch set_qa_cycle "$@"; }
tracker_close_issue()           { _tracker_dispatch close_issue "$@"; }
tracker_block_issue()           { _tracker_dispatch block_issue "$@"; }
tracker_unblock_issue()         { _tracker_dispatch unblock_issue "$@"; }
tracker_capture_backlog_item()  { _tracker_dispatch capture_backlog_item "$@"; }
tracker_promote_backlog_item()  { _tracker_dispatch promote_backlog_item "$@"; }
