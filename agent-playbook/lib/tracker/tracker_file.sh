#!/usr/bin/env bash
# lib/tracker/tracker_file.sh
#
# File-based tracker backend. Lifts the existing rename-based logic from
# process/PROCESS.md and process/TRACKER-GUIDE.md.
#
# Storage convention (unchanged from TRACKER-GUIDE.md):
#   tracker/NNN-short-desc.todo.md          ← raw, waiting for PM
#   tracker/NNN-short-desc.groomed.md       ← PM groomed, ready for SWE
#   tracker/NNN-short-desc.in-progress.md   ← SWE working OR QA testing
#   tracker/NNN-short-desc.backlog.md       ← dormant (Phase 0/3 addition)
#   tracker/done/NNN-short-desc.md          ← accepted
#   tracker/rejected/NNN-short-desc.md      ← abandoned
#
# Logical state → file suffix mapping (the file backend collapses GitHub-mode
# states that share a file location):
#
#   needs-grooming         → .todo.md
#   ready-for-dev          → .groomed.md
#   in-progress            → .in-progress.md
#   ready-for-qa           → .in-progress.md   (no rename; sentinel comment marks readiness)
#   ready-for-acceptance   → .in-progress.md   (idem)
#   rework-needed          → .in-progress.md   (idem)
#   ready-for-docs         → .in-progress.md   (idem)
#   backlog                → .backlog.md
#   blocked                → original suffix + sentinel comment
#   done                   → done/<id>-<desc>.md
#   rejected               → rejected/<id>-<desc>.md
#
# Issue IDs in this backend are zero-padded 3-digit numbers ("001", "042").
# When agents pass `--id 7`, the backend zero-pads to "007".

# Root of the tracker directory. Configurable so tests can override.
TRACKER_FILE_ROOT="${TRACKER_FILE_ROOT:-tracker}"

_tracker_file_pad_id() {
    # Pad an integer to 3 digits. Echo input unchanged if already non-numeric.
    local raw="$1"
    raw="${raw#\#}"  # drop leading '#'
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        printf '%03d\n' "$((10#$raw))"
    else
        printf '%s\n' "$raw"
    fi
}

_tracker_file_root() {
    # Print the tracker root, ensuring the subdirs exist.
    mkdir -p "${TRACKER_FILE_ROOT}/done" "${TRACKER_FILE_ROOT}/rejected"
    printf '%s\n' "${TRACKER_FILE_ROOT}"
}

_tracker_file_state_to_suffix() {
    # Map a logical state name to a file suffix (without leading dot).
    case "$1" in
        needs-grooming)        echo "todo" ;;
        ready-for-dev)         echo "groomed" ;;
        in-progress|ready-for-qa|ready-for-acceptance|rework-needed|ready-for-docs)
                               echo "in-progress" ;;
        backlog)               echo "backlog" ;;
        done|rejected)         echo "$1" ;;  # special: stored in done/ or rejected/ subdir
        *)                     return 1 ;;
    esac
}

_tracker_file_find_path() {
    # Locate the file for a given padded id. Searches:
    #   tracker/NNN-*.todo.md
    #   tracker/NNN-*.groomed.md
    #   tracker/NNN-*.in-progress.md
    #   tracker/NNN-*.backlog.md
    #   tracker/done/NNN-*.md
    #   tracker/rejected/NNN-*.md
    # Echoes the first match. Returns 1 if none found.
    local id="$1" root
    root="$(_tracker_file_root)"
    local path
    for path in "${root}/${id}"-*.todo.md \
                "${root}/${id}"-*.groomed.md \
                "${root}/${id}"-*.in-progress.md \
                "${root}/${id}"-*.backlog.md \
                "${root}/done/${id}"-*.md \
                "${root}/rejected/${id}"-*.md; do
        if [[ -f "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

_tracker_file_path_state() {
    # Inverse of _tracker_file_state_to_suffix: report a path's logical state.
    local path="$1"
    case "$path" in
        */done/*)   echo "done" ;;
        */rejected/*) echo "rejected" ;;
        *.todo.md)  echo "needs-grooming" ;;
        *.groomed.md) echo "ready-for-dev" ;;
        *.in-progress.md) echo "in-progress" ;;
        *.backlog.md) echo "backlog" ;;
        *)          echo "unknown" ;;
    esac
}

_tracker_file_next_id() {
    # Compute the next available 3-digit id by scanning the tracker root.
    local root max=0
    root="$(_tracker_file_root)"
    local f base num
    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        num="${base%%-*}"
        if [[ "$num" =~ ^[0-9]{3}$ ]]; then
            (( 10#$num > max )) && max=$((10#$num))
        fi
    done < <(find "$root" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
    printf '%03d\n' "$((max + 1))"
}

_tracker_file_slugify() {
    # Sluggify a title for use in filenames: lowercase, hyphenate, max 40 chars.
    printf '%s\n' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
        | cut -c1-40
}

# ── Verbs ───────────────────────────────────────────────────────────────────

tracker_file_list_issues() {
    declare -A F
    tracker_parse_flags F "$@" || return $?

    local root state_filter="${F[state]:-}" priority_filter="${F[priority]:-}"
    local search="${F[search]:-}" count_only="${F[count]:-}"
    root="$(_tracker_file_root)"

    # Build the list of paths to consider based on state filter.
    local paths=()
    if [[ -n "$state_filter" ]]; then
        local suffix
        suffix="$(_tracker_file_state_to_suffix "$state_filter")" || {
            tracker_log_error "tracker_file_list_issues" "unknown state '$state_filter'"
            return 1
        }
        case "$suffix" in
            done)       paths+=("${root}/done"/*.md) ;;
            rejected)   paths+=("${root}/rejected"/*.md) ;;
            *)          paths+=("${root}"/*."${suffix}".md) ;;
        esac
    else
        paths+=("${root}"/*.todo.md "${root}"/*.groomed.md \
                "${root}"/*.in-progress.md "${root}"/*.backlog.md \
                "${root}"/done/*.md "${root}"/rejected/*.md)
    fi

    local matches=() p title state id priority
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] || continue
        local base; base="$(basename "$p")"
        id="${base%%-*}"
        # Strip id prefix and state suffix to recover the slug, then read
        # the H1 title from the file body for display.
        title="$(grep -m1 -E '^# ' "$p" 2>/dev/null | sed -E 's/^# (Task: )?//')"
        [[ -z "$title" ]] && title="${base}"
        state="$(_tracker_file_path_state "$p")"
        priority="$(grep -m1 -iE '^(priority|## priority)' "$p" 2>/dev/null \
                    | sed -E 's/.*: *//;s/^## priority *//I' | tr '[:upper:]' '[:lower:]' \
                    | grep -oE 'high|medium|low' || echo "medium")"
        # Search filter (case-insensitive substring on file body).
        # awk is used instead of `grep -iqF`: Git-Bash's grep aborts on
        # certain inputs in this codepath, so we cannot rely on it.
        if [[ -n "$search" ]]; then
            if ! awk -v s="$search" '
                BEGIN { IGNORECASE = 1; }
                index(tolower($0), tolower(s)) { found = 1; exit }
                END { exit !found }
            ' "$p" 2>/dev/null; then
                continue
            fi
        fi
        if [[ -n "$priority_filter" && "$priority" != "$priority_filter" ]]; then
            continue
        fi
        matches+=("#${id}"$'\t'"${title}"$'\t'"${state}"$'\t'"-"$'\t'"${priority}")
    done

    if [[ -n "$count_only" ]]; then
        printf '%d\n' "${#matches[@]}"
        return 0
    fi

    # Default sort: priority then number.
    local sort_mode="${F[sort]:-priority,number}"
    if [[ "$sort_mode" == "number" ]]; then
        printf '%s\n' "${matches[@]+"${matches[@]}"}" | sort -t$'\t' -k1,1
    else
        # priority order: high < medium < low; secondary on number ascending.
        printf '%s\n' "${matches[@]+"${matches[@]}"}" | awk -F'\t' '
            BEGIN { OFS=FS }
            { rank = ($5 == "high" ? 0 : ($5 == "medium" ? 1 : 2)); print rank, $0 }
        ' | sort -t$'\t' -k1,1n -k2,2 | cut -f2-
    fi
}

tracker_file_view_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_view_issue" "id" "${F[id]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_view_issue" "issue #$id not found"
        return 1
    }
    local title state
    title="$(grep -m1 -E '^# ' "$path" | sed -E 's/^# (Task: )?//')"
    state="$(_tracker_file_path_state "$path")"
    printf 'TITLE: %s\n' "$title"
    printf 'STATE: %s\n' "$state"
    printf 'ROLE:  %s\n' "$(_tracker_file_role_for_state "$state")"
    printf 'PRIORITY: %s\n' "$(grep -m1 -iE '^priority' "$path" | sed -E 's/.*: *//' \
                                | tr '[:upper:]' '[:lower:]' | grep -oE 'high|medium|low' || echo medium)"
    printf -- '---\n'
    cat "$path"
}

_tracker_file_role_for_state() {
    case "$1" in
        needs-grooming)        echo "pm" ;;
        ready-for-dev)         echo "swe" ;;
        in-progress)           echo "swe" ;;
        ready-for-qa)          echo "qa" ;;
        ready-for-acceptance)  echo "pm" ;;
        rework-needed)         echo "swe" ;;
        ready-for-docs)        echo "techwriter" ;;
        backlog)               echo "human" ;;
        blocked)               echo "human" ;;
        done|rejected)         echo "-" ;;
        *)                     echo "-" ;;
    esac
}

tracker_file_view_issue_comments() {
    # In file mode, the "comments" are sections appended below the
    # "<!-- Below this line is filled by agents -->" marker. We surface the
    # file body verbatim — agents already write structured markdown sections.
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_view_issue_comments" "id" "${F[id]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_view_issue_comments" "issue #$id not found"
        return 1
    }
    local title state
    title="$(grep -m1 -E '^# ' "$path" | sed -E 's/^# (Task: )?//')"
    state="$(_tracker_file_path_state "$path")"
    printf 'TITLE: %s\n' "$title"
    printf 'STATE: %s\n' "$state"
    printf -- '---\n'
    cat "$path"
}

tracker_file_create_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    for f in title body type priority role state; do
        tracker_require_flag "tracker_file_create_issue" "$f" "${F[$f]:-}" || return 1
    done
    local id slug suffix path root
    id="$(_tracker_file_next_id)"
    slug="$(_tracker_file_slugify "${F[title]}")"
    suffix="$(_tracker_file_state_to_suffix "${F[state]}")" || {
        tracker_log_error "tracker_file_create_issue" "unsupported state '${F[state]}'"
        return 1
    }
    root="$(_tracker_file_root)"

    case "$suffix" in
        done|rejected)
            tracker_log_error "tracker_file_create_issue" \
                "cannot create issue directly in state '${F[state]}'"
            return 1 ;;
    esac

    path="${root}/${id}-${slug}.${suffix}.md"
    {
        printf '# Task: %s\n\n' "${F[title]}"
        printf '## Raw Description\n%s\n\n' "${F[body]}"
        printf '## Priority\n%s\n\n' "${F[priority]}"
        printf '## Type\n%s\n\n' "${F[type]}"
        printf '## Role\n%s\n\n' "${F[role]}"
        printf -- '---\n<!-- Below this line is filled by agents — do not edit manually -->\n'
    } > "$path"
    printf '#%s\n' "$id"
}

tracker_file_comment_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_comment_issue" "id" "${F[id]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local body="${F[body]:-}"
    if [[ -z "$body" ]]; then
        tracker_log_error "tracker_file_comment_issue" "missing --body or --body-file"
        return 1
    fi
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_comment_issue" "issue #$id not found"
        return 1
    }
    {
        printf '\n'
        printf '%s\n' "$body"
    } >> "$path"
}

tracker_file_transition() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_transition" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_file_transition" "to-state" "${F[to-state]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"

    local from_path; from_path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_transition" "issue #$id not found"
        return 1
    }

    local to_suffix
    to_suffix="$(_tracker_file_state_to_suffix "${F[to-state]}")" || {
        tracker_log_error "tracker_file_transition" "unknown state '${F[to-state]}'"
        return 1
    }

    local from_state cur_suffix
    from_state="$(_tracker_file_path_state "$from_path")"
    cur_suffix="$(_tracker_file_state_to_suffix "$from_state")" || cur_suffix=""

    # If --from-state is provided, sanity-check it.
    if [[ -n "${F[from-state]:-}" && "${F[from-state]}" != "$from_state" ]]; then
        local current_suffix expected_suffix
        current_suffix="$(_tracker_file_state_to_suffix "$from_state" 2>/dev/null || echo "?")"
        expected_suffix="$(_tracker_file_state_to_suffix "${F[from-state]}" 2>/dev/null || echo "?")"
        if [[ "$current_suffix" != "$expected_suffix" ]]; then
            tracker_log_error "tracker_file_transition" \
                "issue #$id is in '$from_state' but --from-state asked '${F[from-state]}'"
            return 1
        fi
    fi

    local root base new_path
    root="$(_tracker_file_root)"
    base="$(basename "$from_path")"
    # Strip the existing state suffix to recover "<id>-<slug>".
    local stem
    case "$from_path" in
        */done/*|*/rejected/*) stem="${base%.md}" ;;
        *) stem="${base%.${cur_suffix}.md}" ;;
    esac

    case "$to_suffix" in
        done)     new_path="${root}/done/${stem}.md" ;;
        rejected) new_path="${root}/rejected/${stem}.md" ;;
        *)        new_path="${root}/${stem}.${to_suffix}.md" ;;
    esac

    # Idempotent: same suffix → no rename, but still update QA cycle if asked.
    if [[ "$from_path" != "$new_path" ]]; then
        mv -- "$from_path" "$new_path" || {
            tracker_log_error "tracker_file_transition" "rename failed"
            return 1
        }
    fi

    if [[ -n "${F[qa-cycle]:-}" ]]; then
        tracker_file_set_qa_cycle --id "$id" --cycle "${F[qa-cycle]}" || return $?
    fi
}

tracker_file_set_qa_cycle() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_set_qa_cycle" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_file_set_qa_cycle" "cycle" "${F[cycle]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_set_qa_cycle" "issue #$id not found"
        return 1
    }
    # If a "## QA Cycle: N" line already exists, replace it; else append.
    if grep -qE '^## QA Cycle: ' "$path"; then
        # Use a portable in-place edit (no GNU-only -i extension).
        local tmp; tmp="$(mktemp)"
        sed -E "s/^## QA Cycle: .*/## QA Cycle: ${F[cycle]}/" "$path" > "$tmp" && mv -- "$tmp" "$path"
    else
        printf '\n## QA Cycle: %s\n' "${F[cycle]}" >> "$path"
    fi
}

tracker_file_close_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_close_issue" "id" "${F[id]:-}" || return 1
    if [[ -n "${F[comment]:-}" ]]; then
        tracker_file_comment_issue --id "${F[id]}" --body "${F[comment]}" || return $?
    fi
    tracker_file_transition --id "${F[id]}" --to-state done
}

tracker_file_block_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_block_issue" "id" "${F[id]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_block_issue" "issue #$id not found"
        return 1
    }
    local cur_state; cur_state="$(_tracker_file_path_state "$path")"
    local cur_role;  cur_role="$(_tracker_file_role_for_state "$cur_state")"
    {
        printf '\n<!-- tracker:previous-role=%s -->\n' "$cur_role"
        printf '<!-- tracker:blocked=true -->\n'
        if [[ -n "${F[comment]:-}" ]]; then
            printf '\n## Agent Questions\n%s\n' "${F[comment]}"
        fi
    } >> "$path"
}

tracker_file_unblock_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_unblock_issue" "id" "${F[id]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_unblock_issue" "issue #$id not found"
        return 1
    }
    # Strip the blocked sentinel; keep the previous-role marker as audit history.
    local tmp; tmp="$(mktemp)"
    grep -v '^<!-- tracker:blocked=true -->$' "$path" > "$tmp" && mv -- "$tmp" "$path"
}

tracker_file_capture_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_capture_backlog_item" "title" "${F[title]:-}" || return 1
    tracker_require_flag "tracker_file_capture_backlog_item" "body" "${F[body]:-}" || return 1
    tracker_file_create_issue \
        --title "${F[title]}" \
        --body "${F[body]}" \
        --type "${F[type]:-feature}" \
        --priority "${F[priority]:-medium}" \
        --role human \
        --state backlog
}

tracker_file_promote_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_file_promote_backlog_item" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_file_promote_backlog_item" "priority" "${F[priority]:-}" || return 1
    local id; id="$(_tracker_file_pad_id "${F[id]}")"
    local path; path="$(_tracker_file_find_path "$id")" || {
        tracker_log_error "tracker_file_promote_backlog_item" "issue #$id not found"
        return 1
    }
    if [[ "$(_tracker_file_path_state "$path")" != "backlog" ]]; then
        tracker_log_error "tracker_file_promote_backlog_item" \
            "issue #$id is not in backlog state"
        return 1
    fi
    # Update priority section in body, then transition backlog → needs-grooming.
    local tmp; tmp="$(mktemp)"
    awk -v p="${F[priority]}" '
        /^## Priority *$/ { print; getline; print p; next }
        /^## Priority *: */ { sub(/:.*/, ": " p); print; next }
        { print }
    ' "$path" > "$tmp" && mv -- "$tmp" "$path"
    tracker_file_transition --id "$id" --to-state needs-grooming
}
