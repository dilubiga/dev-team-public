#!/usr/bin/env bash
# lib/tracker/_common.sh
#
# Shared helpers for the tracker abstraction layer. Sourced by tracker.sh and
# every backend implementation. Never executed directly.
#
# Provides:
#   tracker_log_error  — print "<verb>: ERROR — <msg>" to stderr
#   tracker_log_warn   — print "<verb>: WARN — <msg>" to stderr
#   tracker_parse_flags — populate an associative array from "--key value" pairs
#   tracker_require_flag — assert a flag is non-empty, else error + exit 1
#
# Exit-code contract (used by every verb):
#   0 — success
#   1 — tracker error (issue not found, label invalid, network failure)
#   2 — configuration error (auth missing, env var missing, backend unknown)
#   3 — verb not supported by this backend

# Guard against double-sourcing.
if [[ -n "${_TRACKER_COMMON_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_TRACKER_COMMON_LOADED=1

tracker_log_error() {
    # Args: <verb> <message...>
    local verb="$1"; shift
    printf '%s: ERROR — %s\n' "$verb" "$*" >&2
}

tracker_log_warn() {
    local verb="$1"; shift
    printf '%s: WARN — %s\n' "$verb" "$*" >&2
}

tracker_parse_flags() {
    # Parse "--key value" pairs into the associative array named by $1.
    # Unknown flags are stored too; verbs validate required flags themselves.
    #
    # Usage:
    #   declare -A FLAGS
    #   tracker_parse_flags FLAGS "$@"
    #
    # Special flags:
    #   --foo            (no value) → FLAGS[foo]=1
    #   --foo bar        → FLAGS[foo]=bar
    #   --body-file PATH → FLAGS[body]=$(<PATH)  (convenience)
    local -n _flags="$1"; shift
    while (( $# > 0 )); do
        local key="$1"
        if [[ "$key" != --* ]]; then
            tracker_log_error "tracker_parse_flags" "expected --flag, got '$key'"
            return 2
        fi
        key="${key#--}"
        # Boolean flag if next arg is missing or another --flag.
        if (( $# == 1 )) || [[ "$2" == --* ]]; then
            _flags["$key"]=1
            shift
        else
            if [[ "$key" == "body-file" ]]; then
                if [[ ! -r "$2" ]]; then
                    tracker_log_error "tracker_parse_flags" "--body-file '$2' not readable"
                    return 1
                fi
                _flags["body"]="$(<"$2")"
            else
                _flags["$key"]="$2"
            fi
            shift 2
        fi
    done
}

tracker_require_flag() {
    # Args: <verb> <flag-name> <flag-value>
    local verb="$1" name="$2" value="${3:-}"
    if [[ -z "$value" ]]; then
        tracker_log_error "$verb" "missing required flag --$name"
        return 1
    fi
}

tracker_unsupported_verb() {
    # Helper for backends that explicitly do not support a verb.
    # Args: <verb> <backend-name>
    tracker_log_error "$1" "verb not supported by backend '$2'"
    return 3
}
