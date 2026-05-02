#!/usr/bin/env bats
# Dispatcher routing + error-code contract.

load helpers

setup() { setup_tracker_sandbox; }
teardown() { teardown_tracker_sandbox; }

@test "default backend is 'file' when TRACKER_BACKEND is unset" {
    unset TRACKER_BACKEND
    # Empty list on a fresh sandbox → exit 0, empty stdout.
    run tracker_list_issues --state needs-grooming
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "TRACKER_BACKEND=file routes to the file backend" {
    export TRACKER_BACKEND=file
    run tracker_list_issues --state needs-grooming
    [ "$status" -eq 0 ]
}

@test "TRACKER_BACKEND=github-issues routes to github (config error when env unset)" {
    export TRACKER_BACKEND=github-issues
    unset GH_OWNER GH_REPO
    run tracker_list_issues --state needs-grooming
    [ "$status" -eq 2 ]
    [[ "$output" =~ "GH_OWNER or GH_REPO not set" ]]
}

@test "TRACKER_BACKEND=azure-boards routes to azure (config error when env unset)" {
    export TRACKER_BACKEND=azure-boards
    unset AZ_ORG AZ_PROJECT
    run tracker_create_issue --title T --body B --type bugfix --priority high --role pm --state needs-grooming
    [ "$status" -eq 2 ]
    [[ "$output" =~ "AZ_ORG or AZ_PROJECT not set" ]]
}

@test "unknown TRACKER_BACKEND yields exit code 2 (config error)" {
    export TRACKER_BACKEND=trello
    run tracker_list_issues
    [ "$status" -eq 2 ]
    [[ "$output" =~ "unknown TRACKER_BACKEND" ]]
}

@test "every public verb is defined as a function" {
    for verb in tracker_list_issues tracker_view_issue tracker_view_issue_comments \
                tracker_create_issue tracker_comment_issue tracker_transition \
                tracker_set_qa_cycle tracker_close_issue tracker_block_issue \
                tracker_unblock_issue tracker_capture_backlog_item \
                tracker_promote_backlog_item; do
        run declare -F "$verb"
        [ "$status" -eq 0 ] || { echo "missing verb: $verb"; return 1; }
    done
}

@test "every backend defines all 12 verb suffixes" {
    for backend in file github azure; do
        for suffix in list_issues view_issue view_issue_comments create_issue \
                      comment_issue transition set_qa_cycle close_issue \
                      block_issue unblock_issue capture_backlog_item \
                      promote_backlog_item; do
            local fn="tracker_${backend}_${suffix}"
            run declare -F "$fn"
            [ "$status" -eq 0 ] || { echo "missing: $fn"; return 1; }
        done
    done
}
