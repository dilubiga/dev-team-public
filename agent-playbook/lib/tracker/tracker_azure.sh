#!/usr/bin/env bash
# lib/tracker/tracker_azure.sh
#
# Azure DevOps Boards backend for the tracker abstraction.
# Wraps `az boards` (azure-devops CLI extension) calls to mirror the
# GitHub backend's surface. State / role / priority / type / qa-cycle
# vocabulary is identical — encoded as Azure DevOps work-item tags so
# the same logical labels work across all three backends.
#
# Required env (from .claude/project.env):
#   AZ_ORG       — organization URL (e.g. https://dev.azure.com/myorg) or short slug
#   AZ_PROJECT   — Azure DevOps project name
#   AZ_REPO      — repository name (Azure Repos)
# Optional:
#   AZ_AREA_PATH       — default Area Path for new work items (defaults to AZ_PROJECT)
#   AZ_ITERATION_PATH  — default Iteration Path for new work items
#   AZ_WORK_ITEM_TYPE  — work-item type for created issues (default: "Task")
#
# Authentication: assumes `az login` has been run, the azure-devops extension
# is installed (`az extension add --name azure-devops`), and the default
# organization is configured via `az devops configure` or AZ_ORG is set.
#
# Exit-code contract:
#   0 — success
#   1 — tracker error (work item not found, az exited non-zero, etc.)
#   2 — configuration error (az not logged in, required env var missing)

# ── Config helpers ──────────────────────────────────────────────────────────

_tracker_azure_check_config() {
    if [[ -z "${AZ_ORG:-}" || -z "${AZ_PROJECT:-}" ]]; then
        tracker_log_error "tracker_azure" "AZ_ORG or AZ_PROJECT not set in project.env"
        return 2
    fi
}

_tracker_azure_org_url() {
    # Normalise AZ_ORG to a full URL.
    case "${AZ_ORG:-}" in
        https://*) printf '%s\n' "${AZ_ORG%/}" ;;
        "")        return 2 ;;
        *)         printf 'https://dev.azure.com/%s\n' "${AZ_ORG}" ;;
    esac
}

_tracker_azure_default_area_path() {
    printf '%s\n' "${AZ_AREA_PATH:-${AZ_PROJECT}}"
}

_tracker_azure_default_work_item_type() {
    printf '%s\n' "${AZ_WORK_ITEM_TYPE:-Task}"
}

_tracker_azure_strip_id() {
    # "#42" → "42", "42" → "42"
    local raw="$1"
    raw="${raw#\#}"
    printf '%s\n' "$raw"
}

# ── State / role / priority / type vocabulary (identical to GitHub) ─────────

_tracker_azure_state_tag() {
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
        done)                  echo "" ;;
        *) return 1 ;;
    esac
}

_tracker_azure_role_tag() {
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

_tracker_azure_priority_tag() {
    case "$1" in
        high|medium|low) echo "priority-$1" ;;
        *) return 1 ;;
    esac
}

# Map our priority levels onto ADO's built-in 1-4 priority field
# (1 = highest, 4 = lowest). We use 1/2/3 for high/medium/low.
_tracker_azure_priority_number() {
    case "$1" in
        high)   echo "1" ;;
        medium) echo "2" ;;
        low)    echo "3" ;;
        *) return 1 ;;
    esac
}

_tracker_azure_type_tag() {
    case "$1" in
        feature|bugfix|refactor|infra) echo "type-$1" ;;
        *) return 1 ;;
    esac
}

_tracker_azure_default_role_for_state() {
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

# Map our pipeline state onto ADO's System.State so the kanban board
# stays in sync. ADO uses workflow-specific state names; the defaults
# below target the "Agile" process template (New / Active / Resolved /
# Closed). For Scrum / CMMI / Basic projects, override the per-state
# values via env vars in .claude/project.env without editing this file:
#
#   Agile (default):  AZ_STATE_NEW=New      AZ_STATE_ACTIVE=Active
#                     AZ_STATE_RESOLVED=Resolved  AZ_STATE_CLOSED=Closed
#   Scrum:            AZ_STATE_NEW=New      AZ_STATE_ACTIVE=Committed
#                     AZ_STATE_RESOLVED=Done      AZ_STATE_CLOSED=Done
#   CMMI:             AZ_STATE_NEW=Proposed AZ_STATE_ACTIVE=Active
#                     AZ_STATE_RESOLVED=Resolved  AZ_STATE_CLOSED=Closed
#   Basic:            AZ_STATE_NEW=To\ Do   AZ_STATE_ACTIVE=Doing
#                     AZ_STATE_RESOLVED=Doing     AZ_STATE_CLOSED=Done
#
# Verify your project's actual state names with:
#   az boards work-item show --id <existing-id> -o json | jq '.fields["System.State"]'
_tracker_azure_system_state() {
    local state_new="${AZ_STATE_NEW:-New}"
    local state_active="${AZ_STATE_ACTIVE:-Active}"
    local state_resolved="${AZ_STATE_RESOLVED:-Resolved}"
    local state_closed="${AZ_STATE_CLOSED:-Closed}"
    case "$1" in
        needs-grooming|backlog|blocked) echo "$state_new" ;;
        ready-for-dev)                  echo "$state_active" ;;
        in-progress|rework-needed)      echo "$state_active" ;;
        ready-for-qa)                   echo "$state_active" ;;
        ready-for-acceptance)           echo "$state_resolved" ;;
        ready-for-docs)                 echo "$state_resolved" ;;
        done)                           echo "$state_closed" ;;
        *) echo "" ;;
    esac
}

# ── Low-level az wrappers ───────────────────────────────────────────────────

_tracker_azure_az() {
    # Run an `az` command with --org and --project applied where useful.
    # Caller passes the subcommand and any extra args.
    local org_url
    org_url="$(_tracker_azure_org_url)" || return 2
    az "$@" --org "${org_url}" --project "${AZ_PROJECT}"
}

_tracker_azure_get_tags() {
    # Print the comma-separated System.Tags string for a work item.
    local id="$1"
    _tracker_azure_az boards work-item show --id "$id" --output json \
        | jq -r '.fields["System.Tags"] // ""'
}

_tracker_azure_set_tags() {
    # Replace System.Tags wholesale with the given semicolon-or-comma list.
    # ADO returns tags joined by "; "; az accepts either.
    local id="$1" tags_csv="$2"
    _tracker_azure_az boards work-item update --id "$id" \
        --fields "System.Tags=${tags_csv}" --output none
}

_tracker_azure_compute_tag_target() {
    # Strip state/role/qa-cycle tags from the current set, keeping
    # priority-* and type-* and any unrecognised tags. Then append the new
    # state, role, and qa-cycle tags. Echoes the resulting comma-separated list.
    local current="$1" new_state_tag="$2" new_role_tag="$3" new_qa_tag="$4"
    awk -v cur="$current" \
        -v st="$new_state_tag" -v ro="$new_role_tag" -v qa="$new_qa_tag" '
        BEGIN {
            # ADO returns tags joined by "; ".
            n = split(cur, arr, /[,;] */)
            out_n = 0
            for (i = 1; i <= n; i++) {
                t = arr[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
                if (t == "") continue
                # Drop state, role, qa-cycle tags — we replace them.
                if (t ~ /^(needs-grooming|ready-for-dev|in-progress|ready-for-qa|ready-for-acceptance|ready-for-docs|rework-needed|backlog|blocked)$/) continue
                if (t ~ /^role-/) continue
                if (t ~ /^qa-cycle-/) continue
                out[++out_n] = t
            }
            if (st != "") out[++out_n] = st
            if (ro != "") out[++out_n] = ro
            if (qa != "") out[++out_n] = qa
            sep = ""
            for (i = 1; i <= out_n; i++) { printf "%s%s", sep, out[i]; sep = "," }
            print ""
        }'
}

# ── Verbs ───────────────────────────────────────────────────────────────────

tracker_azure_list_issues() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    _tracker_azure_check_config || return 2

    # Build a WIQL query; tags use CONTAINS WORDS. Closed items only when
    # state=done is explicitly requested.
    local closed_state="${AZ_STATE_CLOSED:-Closed}"
    local where=""
    where+="[System.TeamProject] = '${AZ_PROJECT}'"

    if [[ -n "${F[state]:-}" ]]; then
        if [[ "${F[state]}" == "done" ]]; then
            where+=" AND [System.State] = '${closed_state}'"
        else
            local tag; tag="$(_tracker_azure_state_tag "${F[state]}")" || {
                tracker_log_error "tracker_azure_list_issues" "unknown state '${F[state]}'"
                return 1
            }
            [[ -n "$tag" ]] && where+=" AND [System.Tags] CONTAINS WORDS '$tag'"
            where+=" AND [System.State] <> '${closed_state}'"
        fi
    else
        where+=" AND [System.State] <> '${closed_state}'"
    fi
    if [[ -n "${F[role]:-}" ]]; then
        local rtag; rtag="$(_tracker_azure_role_tag "${F[role]}")" || {
            tracker_log_error "tracker_azure_list_issues" "unknown role '${F[role]}'"
            return 1
        }
        where+=" AND [System.Tags] CONTAINS WORDS '$rtag'"
    fi
    if [[ -n "${F[priority]:-}" ]]; then
        local ptag; ptag="$(_tracker_azure_priority_tag "${F[priority]}")" || {
            tracker_log_error "tracker_azure_list_issues" "unknown priority '${F[priority]}'"
            return 1
        }
        where+=" AND [System.Tags] CONTAINS WORDS '$ptag'"
    fi
    if [[ -n "${F[search]:-}" ]]; then
        # Naive title contains; WIQL string escapes single quotes by doubling.
        local term="${F[search]//\'/\'\'}"
        where+=" AND [System.Title] CONTAINS '$term'"
    fi

    local wiql="SELECT [System.Id], [System.Title], [System.State], [System.Tags], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE ${where} ORDER BY [System.Id]"

    local raw
    raw="$(_tracker_azure_az boards query --wiql "$wiql" --output json 2>&1)" || {
        tracker_log_error "tracker_azure_list_issues" "az boards query failed: $raw"
        return 1
    }

    if [[ -n "${F[count]:-}" ]]; then
        printf '%s\n' "$raw" | jq -r 'length'
        return 0
    fi

    local sort_mode="${F[sort]:-priority,number}"
    local jq_sort
    if [[ "$sort_mode" == "number" ]]; then
        jq_sort='sort_by(.id)'
    else
        jq_sort='sort_by(
            (.fields["Microsoft.VSTS.Common.Priority"] // 4),
            .id
        )'
    fi

    printf '%s\n' "$raw" | jq -r "${jq_sort} | .[] |
        (.fields[\"System.Tags\"] // \"\") as \$tags_str |
        (\$tags_str | split(\"; \") | map(select(length > 0))) as \$tags |
        (\$tags | map(select(. as \$x | [
            \"needs-grooming\",\"ready-for-dev\",\"in-progress\",\"ready-for-qa\",
            \"ready-for-acceptance\",\"ready-for-docs\",\"rework-needed\",\"backlog\",\"blocked\"
        ] | index(\$x)) | not | not) | .[0] // (.fields[\"System.State\"] | ascii_downcase)) as \$state |
        (\$tags | map(select(startswith(\"role-\"))) | .[0] // \"-\" | sub(\"^role-\";\"\")) as \$role |
        ((.fields[\"Microsoft.VSTS.Common.Priority\"] // 4) | (
            if . == 1 then \"high\"
            elif . == 2 then \"medium\"
            elif . == 3 then \"low\"
            else \"-\" end)) as \$prio |
        \"#\(.id)\t\(.fields[\"System.Title\"])\t\(\$state)\t\(\$role)\t\(\$prio)\""
}

tracker_azure_view_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_view_issue" "id" "${F[id]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local raw
    raw="$(_tracker_azure_az boards work-item show --id "$n" --output json 2>&1)" || {
        tracker_log_error "tracker_azure_view_issue" "work item #$n not found: $raw"
        return 1
    }
    printf '%s\n' "$raw" | jq -r '
        (.fields["System.Tags"] // "" | split("; ") | map(select(length > 0))) as $tags |
        ($tags | map(select(startswith("role-"))) | .[0] // "-" | sub("^role-";"")) as $role |
        ((.fields["Microsoft.VSTS.Common.Priority"] // 4) | (
            if . == 1 then "high"
            elif . == 2 then "medium"
            elif . == 3 then "low"
            else "-" end)) as $prio |
        ($tags | map(select(. as $x | [
            "needs-grooming","ready-for-dev","in-progress","ready-for-qa",
            "ready-for-acceptance","ready-for-docs","rework-needed","backlog","blocked"
        ] | index($x)) | not | not) | .[0] // (.fields["System.State"] | ascii_downcase)) as $state |
        "TITLE: \(.fields["System.Title"])\nSTATE: \($state)\nROLE:  \($role)\nPRIORITY: \($prio)\nTAGS: \($tags | join(\",\"))\n---\n\(.fields["System.Description"] // "")"
    '
}

tracker_azure_view_issue_comments() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_view_issue_comments" "id" "${F[id]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    # `az boards work-item show --expand all` includes discussion if available;
    # comments live behind the work-item-tracking REST API. We use `az rest`
    # for portability.
    local org_url
    org_url="$(_tracker_azure_org_url)" || return 2
    local raw
    raw="$(az rest --method GET \
        --uri "${org_url}/${AZ_PROJECT}/_apis/wit/workitems/${n}/comments?api-version=7.1-preview.4" \
        --output json 2>&1)" || {
        tracker_log_error "tracker_azure_view_issue_comments" "az rest failed: $raw"
        return 1
    }
    printf '%s\n' "$raw" | jq -r '.comments[]? |
        "--- \(.createdBy.displayName // "unknown") @ \(.createdDate)\n\(.text)\n"'
}

tracker_azure_create_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    for f in title body type priority role state; do
        tracker_require_flag "tracker_azure_create_issue" "$f" "${F[$f]:-}" || return 1
    done
    _tracker_azure_check_config || return 2

    local state_tag role_tag prio_tag type_tag prio_num
    state_tag="$(_tracker_azure_state_tag "${F[state]}")" || {
        tracker_log_error "tracker_azure_create_issue" "unknown state '${F[state]}'"
        return 1
    }
    role_tag="$(_tracker_azure_role_tag "${F[role]}")" || {
        tracker_log_error "tracker_azure_create_issue" "unknown role '${F[role]}'"
        return 1
    }
    prio_tag="$(_tracker_azure_priority_tag "${F[priority]}")" || {
        tracker_log_error "tracker_azure_create_issue" "unknown priority '${F[priority]}'"
        return 1
    }
    prio_num="$(_tracker_azure_priority_number "${F[priority]}")" || return 1
    type_tag="$(_tracker_azure_type_tag "${F[type]}")" || {
        tracker_log_error "tracker_azure_create_issue" "unknown type '${F[type]}'"
        return 1
    }

    local tags="$state_tag,$role_tag,$prio_tag,$type_tag"
    local sys_state; sys_state="$(_tracker_azure_system_state "${F[state]}")"
    local wi_type; wi_type="$(_tracker_azure_default_work_item_type)"
    local area_path; area_path="$(_tracker_azure_default_area_path)"

    local args=(
        --type "$wi_type"
        --title "${F[title]}"
        --description "${F[body]}"
        --area "$area_path"
        --fields "System.Tags=${tags}" "Microsoft.VSTS.Common.Priority=${prio_num}"
    )
    [[ -n "${AZ_ITERATION_PATH:-}" ]] && args+=(--iteration "${AZ_ITERATION_PATH}")

    local out
    out="$(_tracker_azure_az boards work-item create "${args[@]}" --output json 2>&1)" || {
        tracker_log_error "tracker_azure_create_issue" "az boards work-item create failed: $out"
        return 1
    }
    local n; n="$(printf '%s\n' "$out" | jq -r '.id')"
    if [[ -z "$n" || "$n" == "null" ]]; then
        tracker_log_error "tracker_azure_create_issue" "could not parse work item id"
        return 1
    fi
    # Set System.State if it differs from the default new-item state.
    local default_new_state="${AZ_STATE_NEW:-New}"
    if [[ -n "$sys_state" && "$sys_state" != "$default_new_state" ]]; then
        _tracker_azure_az boards work-item update --id "$n" \
            --fields "System.State=${sys_state}" --output none || true
    fi
    printf '#%s\n' "$n"
}

tracker_azure_comment_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_comment_issue" "id" "${F[id]:-}" || return 1
    if [[ -z "${F[body]:-}" ]]; then
        tracker_log_error "tracker_azure_comment_issue" "missing --body or --body-file"
        return 1
    fi
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"
    local org_url; org_url="$(_tracker_azure_org_url)" || return 2

    # POST to /comments REST endpoint. Body is JSON.
    local payload
    payload="$(jq -n --arg text "${F[body]}" '{text: $text}')"
    local err
    err="$(az rest --method POST \
        --uri "${org_url}/${AZ_PROJECT}/_apis/wit/workitems/${n}/comments?api-version=7.1-preview.4" \
        --headers "Content-Type=application/json" \
        --body "$payload" --output none 2>&1)" || {
        tracker_log_error "tracker_azure_comment_issue" "comment POST failed: $err"
        return 1
    }
}

tracker_azure_transition() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_transition" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_azure_transition" "to-state" "${F[to-state]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local to_state="${F[to-state]}"
    local to_role="${F[to-role]:-$(_tracker_azure_default_role_for_state "$to_state")}"

    local state_tag; state_tag="$(_tracker_azure_state_tag "$to_state")" || {
        tracker_log_error "tracker_azure_transition" "unknown to-state '$to_state'"
        return 1
    }
    local role_tag=""
    if [[ -n "$to_role" ]]; then
        role_tag="$(_tracker_azure_role_tag "$to_role")" || {
            tracker_log_error "tracker_azure_transition" "unknown to-role '$to_role'"
            return 1
        }
    fi
    local qa_tag=""
    [[ -n "${F[qa-cycle]:-}" ]] && qa_tag="qa-cycle-${F[qa-cycle]}"

    local cur target sys_state
    cur="$(_tracker_azure_get_tags "$n")" || {
        tracker_log_error "tracker_azure_transition" "work item #$n not found"
        return 1
    }
    target="$(_tracker_azure_compute_tag_target "$cur" "$state_tag" "$role_tag" "$qa_tag")"
    sys_state="$(_tracker_azure_system_state "$to_state")"

    # az boards work-item update accepts multiple --fields key=value pairs.
    local update_args=(--id "$n" --fields "System.Tags=${target}")
    [[ -n "$sys_state" ]] && update_args+=("System.State=${sys_state}")

    local err
    err="$(_tracker_azure_az boards work-item update "${update_args[@]}" --output none 2>&1)" || {
        tracker_log_error "tracker_azure_transition" "az boards work-item update failed: $err"
        return 1
    }
}

tracker_azure_set_qa_cycle() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_set_qa_cycle" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_azure_set_qa_cycle" "cycle" "${F[cycle]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local cur target
    cur="$(_tracker_azure_get_tags "$n")" || {
        tracker_log_error "tracker_azure_set_qa_cycle" "work item #$n not found"
        return 1
    }
    # The compute helper drops state and role tags; preserve them by re-injecting
    # the current values from the work item.
    local keep_state keep_role
    keep_state="$(printf '%s' "$cur" | tr ',;' '\n' \
        | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,"")} $0 ~ /^(needs-grooming|ready-for-dev|in-progress|ready-for-qa|ready-for-acceptance|ready-for-docs|rework-needed|backlog|blocked)$/ {print; exit}')"
    keep_role="$(printf '%s' "$cur" | tr ',;' '\n' \
        | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,"")} /^role-/ {print; exit}')"
    target="$(_tracker_azure_compute_tag_target "$cur" "$keep_state" "$keep_role" "qa-cycle-${F[cycle]}")"

    local err
    err="$(_tracker_azure_set_tags "$n" "$target" 2>&1)" || {
        tracker_log_error "tracker_azure_set_qa_cycle" "tag update failed: $err"
        return 1
    }
}

tracker_azure_close_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_close_issue" "id" "${F[id]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    if [[ -n "${F[comment]:-}" ]]; then
        tracker_azure_comment_issue --id "$n" --body "${F[comment]}" || return 1
    fi
    local closed_state="${AZ_STATE_CLOSED:-Closed}"
    local err
    err="$(_tracker_azure_az boards work-item update --id "$n" \
        --state "$closed_state" --output none 2>&1)" || {
        tracker_log_error "tracker_azure_close_issue" "close failed: $err"
        return 1
    }
}

tracker_azure_block_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_block_issue" "id" "${F[id]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local cur cur_role
    cur="$(_tracker_azure_get_tags "$n")" || {
        tracker_log_error "tracker_azure_block_issue" "work item #$n not found"
        return 1
    }
    cur_role="$(printf '%s' "$cur" | tr ',;' '\n' \
        | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,"")} /^role-/ {print; exit}')"

    if [[ -n "${F[comment]:-}" ]]; then
        tracker_azure_comment_issue --id "$n" --body "${F[comment]}" || return 1
    fi
    # Sentinel comment so unblock can restore the role without external state.
    tracker_azure_comment_issue --id "$n" \
        --body "<!-- tracker:previous-role=${cur_role#role-} -->" || return 1

    local target
    target="$(_tracker_azure_compute_tag_target "$cur" "blocked" "role-human" "")"
    _tracker_azure_set_tags "$n" "$target" || return 1
    local new_state="${AZ_STATE_NEW:-New}"
    _tracker_azure_az boards work-item update --id "$n" \
        --fields "System.State=${new_state}" --output none || true
}

tracker_azure_unblock_issue() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_unblock_issue" "id" "${F[id]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local to_role="${F[to-role]:-}"
    if [[ -z "$to_role" ]]; then
        # Read the most recent sentinel comment from REST.
        local org_url comments_json
        org_url="$(_tracker_azure_org_url)" || return 2
        comments_json="$(az rest --method GET \
            --uri "${org_url}/${AZ_PROJECT}/_apis/wit/workitems/${n}/comments?api-version=7.1-preview.4&\$expand=all" \
            --output json 2>/dev/null)"
        to_role="$(printf '%s' "$comments_json" \
            | jq -r '.comments | reverse | map(.text) | .[] | capture("tracker:previous-role=(?<r>[a-z]+)")? | .r // empty' \
            | head -n1)"
    fi
    if [[ -z "$to_role" ]]; then
        tracker_log_error "tracker_azure_unblock_issue" \
            "could not determine previous role; pass --to-role explicitly"
        return 1
    fi
    local role_tag; role_tag="$(_tracker_azure_role_tag "$to_role")" || {
        tracker_log_error "tracker_azure_unblock_issue" "unknown to-role '$to_role'"
        return 1
    }

    local cur target
    cur="$(_tracker_azure_get_tags "$n")" || return 1
    # Drop "blocked" state tag and "role-human"; re-attach restored role.
    # Compute helper always replaces state+role, so leave state empty (caller
    # should issue a tracker_transition next to set the new state).
    target="$(_tracker_azure_compute_tag_target "$cur" "" "$role_tag" "")"
    _tracker_azure_set_tags "$n" "$target" || return 1
}

tracker_azure_capture_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_capture_backlog_item" "title" "${F[title]:-}" || return 1
    tracker_require_flag "tracker_azure_capture_backlog_item" "body" "${F[body]:-}" || return 1
    _tracker_azure_check_config || return 2

    local wi_type; wi_type="$(_tracker_azure_default_work_item_type)"
    local area_path; area_path="$(_tracker_azure_default_area_path)"
    local args=(
        --type "$wi_type"
        --title "${F[title]}"
        --description "${F[body]}"
        --area "$area_path"
        --fields "System.Tags=backlog,role-human"
    )
    [[ -n "${AZ_ITERATION_PATH:-}" ]] && args+=(--iteration "${AZ_ITERATION_PATH}")

    local out
    out="$(_tracker_azure_az boards work-item create "${args[@]}" --output json 2>&1)" || {
        tracker_log_error "tracker_azure_capture_backlog_item" "create failed: $out"
        return 1
    }
    local n; n="$(printf '%s\n' "$out" | jq -r '.id')"
    [[ -n "$n" && "$n" != "null" ]] || {
        tracker_log_error "tracker_azure_capture_backlog_item" "could not parse work item id"
        return 1
    }
    printf '#%s\n' "$n"
}

tracker_azure_promote_backlog_item() {
    declare -A F; tracker_parse_flags F "$@" || return $?
    tracker_require_flag "tracker_azure_promote_backlog_item" "id" "${F[id]:-}" || return 1
    tracker_require_flag "tracker_azure_promote_backlog_item" "priority" "${F[priority]:-}" || return 1
    _tracker_azure_check_config || return 2
    local n; n="$(_tracker_azure_strip_id "${F[id]}")"

    local prio_tag prio_num
    prio_tag="$(_tracker_azure_priority_tag "${F[priority]}")" || {
        tracker_log_error "tracker_azure_promote_backlog_item" \
            "unknown priority '${F[priority]}'"
        return 1
    }
    prio_num="$(_tracker_azure_priority_number "${F[priority]}")" || return 1

    local cur target
    cur="$(_tracker_azure_get_tags "$n")" || {
        tracker_log_error "tracker_azure_promote_backlog_item" "work item #$n not found"
        return 1
    }
    # Replace state (was "backlog") with "needs-grooming", role to "role-pm",
    # and ensure priority tag is present (priority-* is preserved by
    # _tracker_azure_compute_tag_target if already present; re-insert otherwise).
    target="$(_tracker_azure_compute_tag_target "$cur" "needs-grooming" "role-pm" "")"
    case ",$target," in
        *",priority-high,"*|*",priority-medium,"*|*",priority-low,"*) : ;;
        *) target="${target},${prio_tag}" ;;
    esac

    _tracker_azure_set_tags "$n" "$target" || return 1
    _tracker_azure_az boards work-item update --id "$n" \
        --fields "Microsoft.VSTS.Common.Priority=${prio_num}" --output none || true
}
