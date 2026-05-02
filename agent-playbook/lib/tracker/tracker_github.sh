#!/usr/bin/env bash
# lib/tracker/tracker_github.sh
#
# GitHub Issues backend. Wraps the `gh` CLI calls that previously lived in
# the agent prompts and the /execute skill. The state machine and label
# vocabulary are unchanged from process/GITHUB-TRACKER-GUIDE.md.
#
# Assumes the calling shell has already sourced .claude/env.sh, which exports
# GH_OWNER, GH_REPO, GH_PROJECT_NUMBER, GH_PROJECT_ID, GH_FIELD_*, GH_PIPELINE_*,
# GH_AGENT_*, GH_STATUS_* (see templates/project.env.template).
#
# Exit-code contract:
#   0 — success
#   1 — tracker error (issue not found, gh exited non-zero, etc.)
#   2 — configuration error (gh not authed, required env var missing)
#   3 — verb not supported (none today; reserved for future)

# ── Config helpers ──────────────────────────────────────────────────────────

_tracker_github_repo() {
    if [[ -z "${GH_OWNER:-}" || -z "${GH_REPO:-}" ]]; then
        tracker_log_error "tracker_github" "GH_OWNER or GH_REPO not set in project.env"
        return 2
    fi
    printf '%s/%s\n' "${GH_OWNER}" "${GH_REPO}"
}

_tracker_github_project_configured() {
    # 0 = a Project board is wired up; non-zero = labels-only mode.
    [[ -n "${GH_PROJECT_ID:-}" && -n "${GH_PROJECT_NUMBER:-}" \
       && -n "${GH_FIELD_PIPELINE:-}" && -n "${GH_FIELD_AGENT:-}" ]]
}

# ── State / role / project mapping ──────────────────────────────────────────

_tracker_github_state_label() {
    # Logical state → pipeline-state label name. Empty for terminal states.
    case "$1" in
        needs-grooming)        echo "needs-grooming" ;;
        ready-for-dev)         echo "ready-for-dev" ;;
        in-progress)           echo "in-progress" ;;
        ready-for-qa)          echo "ready-for-qa" ;;
        ready-for-acceptance)  echo "ready-for-acceptance" ;;
        ready-for-docs)        echo "ready-for-docs" ;;
        rework-needed)         echo "rework-needed" ;;
        backlog)               echo "backlog" ;;
        blocked)               echo "blocked" ;;
        done)                  echo "" ;;  # closed issue, no state label
        *) return 1 ;;
    esac
}

_tracker_github_role_label() {
    case "$1" in
        pm)         echo "role-pm" ;;
        swe)        echo "role-swe" ;;
        qa)         echo "role-qa" ;;
        oncall)     echo "role-oncall" ;;
        techwriter) echo "role-techwriter" ;;
        human)      echo "role-human" ;;
        *) return 1 ;;
    esac
}

_tracker_github_default_role_for_state() {
    case "$1" in
        needs-grooming)        echo "pm" ;;
        ready-for-dev)         echo "swe" ;;
        in-progress)           echo "swe" ;;
        ready-for-qa)          echo "qa" ;;
        ready-for-acceptance)  echo "pm" ;;
        ready-for-docs)        echo "techwriter" ;;
        rework-needed)         echo "swe" ;;
        backlog|blocked)       echo "human" ;;
        *) echo "" ;;
    esac
}

_tracker_github_pipeline_option_for_state() {
    case "$1" in
        needs-grooming|backlog)                  echo "${GH_PIPELINE_BACKLOG:-}" ;;
        ready-for-dev|in-progress|rework-needed) echo "${GH_PIPELINE_DEVELOPMENT:-}" ;;
        ready-for-qa)                            echo "${GH_PIPELINE_QA:-}" ;;
        ready-for-acceptance)                    echo "${GH_PIPELINE_ACCEPTANCE:-}" ;;
        ready-for-docs)                          echo "${GH_PIPELINE_DOCUMENTATION:-}" ;;
        blocked)                                 echo "${GH_PIPELINE_BLOCKED:-}" ;;
        done)                                    echo "${GH_PIPELINE_DONE:-}" ;;
        *) return 1 ;;
    esac
}

_tracker_github_agent_option_for_role() {
    case "$1" in
        pm)         echo "${GH_AGENT_PM:-}" ;;
        swe)        echo "${GH_AGENT_SWE:-}" ;;
        qa)         echo "${GH_AGENT_QA:-}" ;;
        techwriter) echo "${GH_AGENT_TECHWRITER:-}" ;;
        human|oncall) echo "${GH_AGENT_HUMAN:-}" ;;
        *) return 1 ;;
    esac
}

# ── Project board wrappers (lifted from env.sh.template) ────────────────────

_tracker_github_set_field() {
    # Single-select field. Args: <item-id> <field-id> <option-id> <label>
    local item_id="$1" field_id="$2" option_id="$3" label="${4:-field}"
    if [[ -z "$item_id" || -z "$field_id" || -z "$option_id" ]]; then
        tracker_log_error "tracker_github_set_field" \
            "empty arg (item_id='$item_id' field_id='$field_id' option_id='$option_id')"
        return 1
    fi
    if ! gh project item-edit --id "$item_id" --project-id "${GH_PROJECT_ID}" \
            --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null; then
        tracker_log_error "tracker_github_set_field" "failed to set ${label} on $item_id"
        return 1
    fi
}

_tracker_github_set_number_field() {
    local item_id="$1" field_id="$2" number="$3" label="${4:-field}"
    if [[ -z "$item_id" || -z "$field_id" || -z "$number" ]]; then
        tracker_log_error "tracker_github_set_number_field" "empty arg"
        return 1
    fi
    if ! gh project item-edit --id "$item_id" --project-id "${GH_PROJECT_ID}" \
            --field-id "$field_id" --number "$number" >/dev/null; then
        tracker_log_error "tracker_github_set_number_field" \
            "failed to set ${label} on $item_id"
        return 1
    fi
}

_tracker_github_item_id() {
    # Resolve the project item id for an issue number.
    local issue_number="$1"
    gh project item-list "${GH_PROJECT_NUMBER}" --owner "${GH_OWNER}" --format json \
      | jq -r --argjson n "$issue_number" \
            '.items[] | select(.content.number == $n) | .id' \
      | head -n1
}

_tracker_github_apply_board() {
    # Update Pipeline + Agent + optional Status + optional QA Cycle for an
    # issue. No-op when the project board is not configured.
    # Args: <issue-number> <to-state> <to-role> [<status-opt-id>] [<qa-cycle>]
    local n="$1" to_state="$2" to_role="$3" status_opt="${4:-}" qa_cycle="${5:-}"
    if ! _tracker_github_project_configured; then
        return 0
    fi
    local item_id pipeline_opt agent_opt
    item_id="$(_tracker_github_item_id "$n")"
    if [[ -z "$item_id" ]]; then
        tracker_log_error "tracker_github_apply_board" "no project item for issue #$n"
        return 1
    fi
    pipeline_opt="$(_tracker_github_pipeline_option_for_state "$to_state")" || pipeline_opt=""
    agent_opt="$(_tracker_github_agent_option_for_role "$to_role")" || agent_opt=""
    if [[ -n "$pipeline_opt" ]]; then
        _tracker_github_set_field "$item_id" "${GH_FIELD_PIPELINE}" "$pipeline_opt" Pipeline || return 1
    fi
    if [[ -n "$agent_opt" ]]; then
        _tracker_github_set_field "$item_id" "${GH_FIELD_AGENT}" "$agent_opt" Agent || return 1
    fi
    if [[ -n "$status_opt" && -n "${GH_FIELD_STATUS:-}" ]]; then
        _tracker_github_set_field "$item_id" "${GH_FIELD_STATUS}" "$status_opt" Status || return 1
    fi
    if [[ -n "$qa_cycle" && -n "${GH_FIELD_QA_CYCLE:-}" ]]; then
        _tracker_github_set_number_field "$item_id" "${GH_FIELD_QA_CYCLE}" \
            "$qa_cycle" "QA Cycle" || return 1
    fi
}

_tracker_github_strip_id() {
    # "#42" → "42", "42" → "42"
    local raw="$1"
    raw="${raw#\#}"
    printf '%s\n' "$raw"
}

_tracker_github_priority_label() {
    case "$1" in
        high|medium|low) echo "priority-$1" ;;
        *) return 1 ;;
    esac
}

_tracker_github_type_label() {
    case "$1" in
        feature|bugfix|refactor|infra) echo "type-$1" ;;
        *) return 1 ;;
    esac
}

# ── Verbs ───────────────────────────────────────────────────────────────────

tracker_github_list_issues() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    local repo; repo="$(_tracker_github_repo)" || return 2

    local labels=()
    if [[ -n "${F[state]:-}" ]]; then
        if [[ "${F[state]}" == "done" ]]; then
            # Closed issues only.
            :
        else
            local lbl; lbl="$(_tracker_github_state_label "${F[state]}")" || {
                tracker_log_error "tracker_github_list_issues" "unknown state '${F[state]}'"
                return 1
            }
            [[ -n "$lbl" ]] && labels+=("$lbl")
        fi
    fi
    if [[ -n "${F[role]:-}" ]]; then
        local rlbl; rlbl="$(_tracker_github_role_label "${F[role]}")" || {
            tracker_log_error "tracker_github_list_issues" "unknown role '${F[role]}'"
            return 1
        }
        labels+=("$rlbl")
    fi
    if [[ -n "${F[priority]:-}" ]]; then
        local plbl; plbl="$(_tracker_github_priority_label "${F[priority]}")" || {
            tracker_log_error "tracker_github_list_issues" "unknown priority '${F[priority]}'"
            return 1
        }
        labels+=("$plbl")
    fi

    local args=(--repo "$repo" --json number,title,labels,state)
    if (( ${#labels[@]} > 0 )); then
        local IFS=,; args+=(--label "${labels[*]}")
    fi
    if [[ -n "${F[search]:-}" ]]; then
        args+=(--search "${F[search]}")
    fi
    if [[ "${F[state]:-}" == "done" ]]; then
        args+=(--state closed)
    fi

    local raw
    raw="$(gh issue list "${args[@]}" 2>&1)" || {
        tracker_log_error "tracker_github_list_issues" "gh issue list failed: $raw"
        return 1
    }

    local sort_mode="${F[sort]:-priority,number}"
    local jq_sort
    if [[ "$sort_mode" == "number" ]]; then
        jq_sort='sort_by(.number)'
    else
        jq_sort='sort_by(
            (if (.labels | map(.name) | index("priority-high")) then 0
             elif (.labels | map(.name) | index("priority-medium")) then 1
             else 2 end),
            .number
        )'
    fi

    if [[ -n "${F[count]:-}" ]]; then
        printf '%s\n' "$raw" | jq -r 'length'
        return 0
    fi

    printf '%s\n' "$raw" | jq -r "${jq_sort} | .[] |
        # Priority label → text
        (.labels | map(.name) | (
            if index(\"priority-high\")   then \"high\"
            elif index(\"priority-medium\") then \"medium\"
            elif index(\"priority-low\")    then \"low\"
            else \"-\" end
        )) as \$prio |
        (.labels | map(.name) | map(select(startswith(\"role-\"))) | .[0] // \"-\" | sub(\"^role-\";\"\")) as \$role |
        (.labels | map(.name) | map(select(. as \$x | [
            \"needs-grooming\",\"ready-for-dev\",\"in-progress\",\"ready-for-qa\",
            \"ready-for-acceptance\",\"ready-for-docs\",\"rework-needed\",\"backlog\",\"blocked\"
        ] | index(\$x)) | not | not)) as \$states |
        (\$states[0] // (.state | ascii_downcase)) as \$state |
        \"#\(.number)\t\(.title)\t\(\$state)\t\(\$role)\t\(\$prio)\""
}

tracker_github_view_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_view_issue" "id" "${F[id]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"

    local raw
    raw="$(gh issue view "$n" --repo "$repo" --json title,body,labels,state 2>&1)" || {
        tracker_log_error "tracker_github_view_issue" "issue #$n not found: $raw"
        return 1
    }
    printf '%s\n' "$raw" | jq -r '
        (.labels | map(.name)) as $L |
        ($L | map(select(startswith("role-"))) | .[0] // "-" | sub("^role-";"")) as $role |
        ($L | (
            if   index("priority-high")   then "high"
            elif index("priority-medium") then "medium"
            elif index("priority-low")    then "low"
            else "-" end)) as $prio |
        ($L | map(select(. as $x | [
            "needs-grooming","ready-for-dev","in-progress","ready-for-qa",
            "ready-for-acceptance","ready-for-docs","rework-needed","backlog","blocked"
        ] | index($x)) | not | not) | .[0] // (.state | ascii_downcase)) as $state |
        "TITLE: \(.title)\nSTATE: \($state)\nROLE:  \($role)\nPRIORITY: \($prio)\nLABELS: \($L | join(\",\"))\n---\n\(.body)"
    '
}

tracker_github_view_issue_comments() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_view_issue_comments" "id" "${F[id]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"
    local raw
    raw="$(gh issue view "$n" --repo "$repo" --comments 2>&1)" || {
        tracker_log_error "tracker_github_view_issue_comments" "issue #$n not found"
        return 1
    }
    printf '%s\n' "$raw"
}

tracker_github_create_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    for f in title body type priority role state; do
        tracker_require_flag "tracker_github_create_issue" "$f" "${F[$f]:-}" || return 1
    done
    local repo; repo="$(_tracker_github_repo)" || return 2
    local labels=()
    local state_lbl; state_lbl="$(_tracker_github_state_label "${F[state]}")" || {
        tracker_log_error "tracker_github_create_issue" "unknown state '${F[state]}'"
        return 1
    }
    [[ -n "$state_lbl" ]] && labels+=("$state_lbl")
    local role_lbl; role_lbl="$(_tracker_github_role_label "${F[role]}")" || {
        tracker_log_error "tracker_github_create_issue" "unknown role '${F[role]}'"
        return 1
    }
    labels+=("$role_lbl")
    local prio_lbl; prio_lbl="$(_tracker_github_priority_label "${F[priority]}")" || {
        tracker_log_error "tracker_github_create_issue" "unknown priority '${F[priority]}'"
        return 1
    }
    labels+=("$prio_lbl")
    local type_lbl; type_lbl="$(_tracker_github_type_label "${F[type]}")" || {
        tracker_log_error "tracker_github_create_issue" "unknown type '${F[type]}'"
        return 1
    }
    labels+=("$type_lbl")

    local IFS=,
    local label_csv="${labels[*]}"
    unset IFS

    local args=(--repo "$repo" --title "${F[title]}" --body "${F[body]}" --label "$label_csv")
    if [[ -n "${GH_PROJECT_NUMBER:-}" && -n "${GH_OWNER:-}" ]]; then
        args+=(--project "${GH_OWNER}/${GH_PROJECT_NUMBER}")
    fi

    local url n
    url="$(gh issue create "${args[@]}" 2>&1)" || {
        tracker_log_error "tracker_github_create_issue" "gh issue create failed: $url"
        return 1
    }
    n="$(printf '%s\n' "$url" | grep -oE '/issues/[0-9]+' | tail -1 | grep -oE '[0-9]+')"
    if [[ -z "$n" ]]; then
        tracker_log_error "tracker_github_create_issue" \
            "could not parse issue number from gh output: $url"
        return 1
    fi
    printf '#%s\n' "$n"
}

tracker_github_comment_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_comment_issue" "id" "${F[id]:-}" || return 1
    if [[ -z "${F[body]:-}" ]]; then
        tracker_log_error "tracker_github_comment_issue" "missing --body or --body-file"
        return 1
    fi
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"
    local err
    err="$(gh issue comment "$n" --repo "$repo" --body "${F[body]}" 2>&1)" || {
        tracker_log_error "tracker_github_comment_issue" "gh issue comment failed: $err"
        return 1
    }
}

_tracker_github_compute_label_delta() {
    # Print "remove\nadd" given current and target labels.
    # Usage: _tracker_github_compute_label_delta <current-csv> <target-csv>
    local current="$1" target="$2"
    awk -v cur="$current" -v tgt="$target" '
        BEGIN {
            split(cur, c, ","); split(tgt, t, ",")
            for (i in c) seen_c[c[i]] = 1
            for (i in t) seen_t[t[i]] = 1
            remove_count = 0; add_count = 0
            for (l in seen_c) if (!(l in seen_t)) remove_list[++remove_count] = l
            for (l in seen_t) if (!(l in seen_c)) add_list[++add_count] = l
            sep = ""; for (i=1;i<=remove_count;i++) { printf "%s%s", sep, remove_list[i]; sep="," }
            print ""
            sep = ""; for (i=1;i<=add_count;i++) { printf "%s%s", sep, add_list[i]; sep="," }
            print ""
        }
    '
}

tracker_github_transition() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_transition" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_github_transition" "to-state" "${F[to-state]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"

    # Read current labels.
    local current_labels
    current_labels="$(gh issue view "$n" --repo "$repo" --json labels \
                        --jq '[.labels[].name] | join(",")' 2>&1)" || {
        tracker_log_error "tracker_github_transition" "issue #$n not found: $current_labels"
        return 1
    }

    # Build target label set: keep priority-* and type-*, replace state and role.
    local to_state="${F[to-state]}"
    local to_role="${F[to-role]:-$(_tracker_github_default_role_for_state "$to_state")}"
    local to_state_lbl to_role_lbl
    to_state_lbl="$(_tracker_github_state_label "$to_state")" || {
        tracker_log_error "tracker_github_transition" "unknown to-state '$to_state'"
        return 1
    }
    if [[ -n "$to_role" ]]; then
        to_role_lbl="$(_tracker_github_role_label "$to_role")" || {
            tracker_log_error "tracker_github_transition" "unknown to-role '$to_role'"
            return 1
        }
    fi

    # Strip state, role, qa-cycle labels from current; keep priority and type.
    local kept
    kept="$(printf '%s\n' "$current_labels" | tr ',' '\n' | awk '
        $0 ~ /^priority-/ || $0 ~ /^type-/ { print }
    ' | paste -sd, -)"

    local target="$kept"
    [[ -n "$to_state_lbl" ]] && target="${target:+${target},}${to_state_lbl}"
    [[ -n "${to_role_lbl:-}" ]] && target="${target:+${target},}${to_role_lbl}"
    if [[ -n "${F[qa-cycle]:-}" ]]; then
        target="${target:+${target},}qa-cycle-${F[qa-cycle]}"
    fi

    # Compute delta.
    local delta remove add
    delta="$(_tracker_github_compute_label_delta "$current_labels" "$target")"
    remove="$(printf '%s' "$delta" | sed -n '1p')"
    add="$(printf '%s' "$delta" | sed -n '2p')"

    if [[ -n "$remove" || -n "$add" ]]; then
        local edit_args=(--repo "$repo")
        [[ -n "$remove" ]] && edit_args+=(--remove-label "$remove")
        [[ -n "$add" ]] && edit_args+=(--add-label "$add")
        local err
        err="$(gh issue edit "$n" "${edit_args[@]}" 2>&1)" || {
            tracker_log_error "tracker_github_transition" \
                "gh issue edit failed (labels not changed atomically): $err"
            return 1
        }
    fi

    # Update project board if configured.
    _tracker_github_apply_board "$n" "$to_state" "$to_role" "" "${F[qa-cycle]:-}" || return 1
}

tracker_github_set_qa_cycle() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_set_qa_cycle" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_github_set_qa_cycle" "cycle" "${F[cycle]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"

    # Replace the qa-cycle-* label.
    local cur
    cur="$(gh issue view "$n" --repo "$repo" --json labels \
              --jq '[.labels[].name] | map(select(startswith("qa-cycle-"))) | join(",")' 2>&1)" || {
        tracker_log_error "tracker_github_set_qa_cycle" "issue #$n not found"
        return 1
    }
    local edit_args=(--repo "$repo" --add-label "qa-cycle-${F[cycle]}")
    if [[ -n "$cur" ]]; then
        edit_args+=(--remove-label "$cur")
    fi
    gh issue edit "$n" "${edit_args[@]}" >/dev/null || {
        tracker_log_error "tracker_github_set_qa_cycle" "gh issue edit failed"
        return 1
    }
    if _tracker_github_project_configured && [[ -n "${GH_FIELD_QA_CYCLE:-}" ]]; then
        local item_id; item_id="$(_tracker_github_item_id "$n")"
        if [[ -n "$item_id" ]]; then
            _tracker_github_set_number_field "$item_id" "${GH_FIELD_QA_CYCLE}" \
                "${F[cycle]}" "QA Cycle" || return 1
        fi
    fi
}

tracker_github_close_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_close_issue" "id" "${F[id]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"
    local args=(--repo "$repo")
    [[ -n "${F[comment]:-}" ]] && args+=(--comment "${F[comment]}")
    local err
    err="$(gh issue close "$n" "${args[@]}" 2>&1)" || {
        tracker_log_error "tracker_github_close_issue" "gh issue close failed: $err"
        return 1
    }
    if _tracker_github_project_configured; then
        local item_id pipeline_done
        item_id="$(_tracker_github_item_id "$n")"
        pipeline_done="${GH_PIPELINE_DONE:-}"
        if [[ -n "$item_id" && -n "$pipeline_done" ]]; then
            _tracker_github_set_field "$item_id" "${GH_FIELD_PIPELINE}" \
                "$pipeline_done" Pipeline || return 1
        fi
    fi
}

tracker_github_block_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_block_issue" "id" "${F[id]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"

    # Capture current role label as the previous role.
    local cur_role
    cur_role="$(gh issue view "$n" --repo "$repo" --json labels \
                  --jq '[.labels[].name] | map(select(startswith("role-"))) | .[0] // ""' 2>&1)" || {
        tracker_log_error "tracker_github_block_issue" "issue #$n not found"
        return 1
    }

    if [[ -n "${F[comment]:-}" ]]; then
        tracker_github_comment_issue --id "$n" --body "${F[comment]}" || return 1
    fi
    # Sentinel comment so unblock can restore the role without external state.
    tracker_github_comment_issue --id "$n" \
        --body "<!-- tracker:previous-role=${cur_role#role-} -->" || return 1

    local edit_args=(--repo "$repo" --add-label "blocked,role-human")
    [[ -n "$cur_role" ]] && edit_args+=(--remove-label "$cur_role")
    gh issue edit "$n" "${edit_args[@]}" >/dev/null || {
        tracker_log_error "tracker_github_block_issue" "gh issue edit failed"
        return 1
    }
    _tracker_github_apply_board "$n" "blocked" "human" "" "" || return 1
}

tracker_github_unblock_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_unblock_issue" "id" "${F[id]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"

    local to_role="${F[to-role]:-}"
    if [[ -z "$to_role" ]]; then
        # Read the most recent sentinel comment.
        to_role="$(gh issue view "$n" --repo "$repo" --comments \
                    --jq '.comments | map(.body) | reverse | .[] |
                          capture("tracker:previous-role=(?<r>[a-z]+)")? .r' 2>/dev/null \
                  | head -n1)"
    fi
    if [[ -z "$to_role" ]]; then
        tracker_log_error "tracker_github_unblock_issue" \
            "could not determine previous role; pass --to-role explicitly"
        return 1
    fi

    local to_role_lbl; to_role_lbl="$(_tracker_github_role_label "$to_role")" || {
        tracker_log_error "tracker_github_unblock_issue" "unknown to-role '$to_role'"
        return 1
    }

    gh issue edit "$n" --repo "$repo" \
        --remove-label "blocked,role-human" \
        --add-label "$to_role_lbl" >/dev/null || {
        tracker_log_error "tracker_github_unblock_issue" "gh issue edit failed"
        return 1
    }
    # Pipeline restoration is left to the caller's next tracker_transition.
}

tracker_github_capture_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_capture_backlog_item" "title" "${F[title]:-}" || return 1
    tracker_require_flag "tracker_github_capture_backlog_item" "body" "${F[body]:-}" || return 1
    local repo; repo="$(_tracker_github_repo)" || return 2

    local args=(--repo "$repo" --title "${F[title]}" --body "${F[body]}" \
                --label "backlog,role-human")
    if [[ -n "${GH_PROJECT_NUMBER:-}" && -n "${GH_OWNER:-}" ]]; then
        args+=(--project "${GH_OWNER}/${GH_PROJECT_NUMBER}")
    fi
    local url n
    url="$(gh issue create "${args[@]}" 2>&1)" || {
        tracker_log_error "tracker_github_capture_backlog_item" "gh issue create failed: $url"
        return 1
    }
    n="$(printf '%s\n' "$url" | grep -oE '/issues/[0-9]+' | tail -1 | grep -oE '[0-9]+')"
    [[ -n "$n" ]] || {
        tracker_log_error "tracker_github_capture_backlog_item" "could not parse issue number"
        return 1
    }
    printf '#%s\n' "$n"
}

tracker_github_promote_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_github_promote_backlog_item" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_github_promote_backlog_item" "priority" "${F[priority]:-}" || return 1
    local repo n; repo="$(_tracker_github_repo)" || return 2
    n="$(_tracker_github_strip_id "${F[id]}")"
    local prio_lbl; prio_lbl="$(_tracker_github_priority_label "${F[priority]}")" || {
        tracker_log_error "tracker_github_promote_backlog_item" \
            "unknown priority '${F[priority]}'"
        return 1
    }
    gh issue edit "$n" --repo "$repo" \
        --remove-label "backlog,role-human" \
        --add-label "needs-grooming,${prio_lbl},role-pm" >/dev/null || {
        tracker_log_error "tracker_github_promote_backlog_item" "gh issue edit failed"
        return 1
    }
    _tracker_github_apply_board "$n" "needs-grooming" "pm" "" "" || return 1
}
