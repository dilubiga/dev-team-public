#!/usr/bin/env bats
# File backend: round-trip + edge cases.

load helpers

setup() {
    setup_tracker_sandbox
    export TRACKER_BACKEND=file
}
teardown() { teardown_tracker_sandbox; }

@test "create_issue writes a .todo.md and returns padded id" {
    run tracker_create_issue \
        --title "Add Black-Scholes pricer" --body "Need EU calls and puts." \
        --type feature --priority high --role pm --state needs-grooming
    [ "$status" -eq 0 ]
    [ "$output" = "#001" ]
    ls "${TRACKER_FILE_ROOT}/" | grep -q '^001-add-black-scholes-pricer\.todo\.md$'
}

@test "create_issue auto-increments the id" {
    tracker_create_issue --title "First"  --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_create_issue --title "Second" --body B --type feature --priority medium --role pm --state needs-grooming
    run tracker_create_issue --title "Third" --body B --type feature --priority medium --role pm --state needs-grooming
    [ "$status" -eq 0 ]
    [ "$output" = "#003" ]
}

@test "view_issue returns title/state and the file body" {
    tracker_create_issue --title "Pricer task" --body "raw body" \
        --type feature --priority medium --role pm --state needs-grooming
    run tracker_view_issue --id 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "TITLE: Pricer task" ]]
    [[ "$output" =~ "STATE: needs-grooming" ]]
    [[ "$output" =~ "raw body" ]]
}

@test "comment_issue appends to the file body" {
    tracker_create_issue --title "T" --body "B" --type bugfix --priority low --role pm --state needs-grooming
    tracker_comment_issue --id 1 --body "## Groomed Specification"$'\n'"acceptance criteria"
    run cat "${TRACKER_FILE_ROOT}/001-t.todo.md"
    [[ "$output" =~ "Groomed Specification" ]]
    [[ "$output" =~ "acceptance criteria" ]]
}

@test "transition: needs-grooming → ready-for-dev renames .todo.md → .groomed.md" {
    tracker_create_issue --title "x" --body B --type feature --priority medium --role pm --state needs-grooming
    run tracker_transition --id 1 --from-state needs-grooming --to-state ready-for-dev
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-x.groomed.md" ]
    [ ! -f "${TRACKER_FILE_ROOT}/001-x.todo.md" ]
}

@test "transition: ready-for-dev → in-progress renames .groomed.md → .in-progress.md" {
    tracker_create_issue --title "y" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_transition --id 1 --from-state needs-grooming --to-state ready-for-dev
    run tracker_transition --id 1 --from-state ready-for-dev --to-state in-progress
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-y.in-progress.md" ]
}

@test "transition: ready-for-qa keeps the file in .in-progress.md (collapsed state)" {
    tracker_create_issue --title "z" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_transition --id 1 --to-state ready-for-dev
    tracker_transition --id 1 --to-state in-progress
    run tracker_transition --id 1 --from-state in-progress --to-state ready-for-qa
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-z.in-progress.md" ]
}

@test "transition with --qa-cycle records cycle in body" {
    tracker_create_issue --title "q" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_transition --id 1 --to-state ready-for-dev
    tracker_transition --id 1 --to-state in-progress
    tracker_transition --id 1 --to-state ready-for-qa --qa-cycle 1
    grep -q "## QA Cycle: 1" "${TRACKER_FILE_ROOT}/001-q.in-progress.md"

    # Increment cycle on rework.
    tracker_transition --id 1 --to-state ready-for-qa --qa-cycle 2
    grep -q "## QA Cycle: 2" "${TRACKER_FILE_ROOT}/001-q.in-progress.md"
    ! grep -q "## QA Cycle: 1" "${TRACKER_FILE_ROOT}/001-q.in-progress.md"
}

@test "close_issue moves the file into done/" {
    tracker_create_issue --title "c" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_transition --id 1 --to-state ready-for-dev
    tracker_transition --id 1 --to-state in-progress
    run tracker_close_issue --id 1 --comment "shipped"
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/done/001-c.md" ]
    [ ! -f "${TRACKER_FILE_ROOT}/001-c.in-progress.md" ]
    grep -q "shipped" "${TRACKER_FILE_ROOT}/done/001-c.md"
}

@test "block_issue records the previous role; unblock_issue clears the sentinel" {
    tracker_create_issue --title "b" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_transition --id 1 --to-state ready-for-dev
    tracker_transition --id 1 --to-state in-progress
    tracker_block_issue --id 1 --comment "Need clarification on scope"
    grep -q "tracker:previous-role=swe" "${TRACKER_FILE_ROOT}/001-b.in-progress.md"
    grep -q "tracker:blocked=true" "${TRACKER_FILE_ROOT}/001-b.in-progress.md"

    tracker_unblock_issue --id 1
    ! grep -q "tracker:blocked=true" "${TRACKER_FILE_ROOT}/001-b.in-progress.md"
    # Audit history (previous-role marker) is intentionally retained.
    grep -q "tracker:previous-role=swe" "${TRACKER_FILE_ROOT}/001-b.in-progress.md"
}

@test "list_issues filters by state and returns one row per match" {
    tracker_create_issue --title "alpha" --body B --type feature --priority high   --role pm --state needs-grooming
    tracker_create_issue --title "beta"  --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_create_issue --title "gamma" --body B --type feature --priority low    --role pm --state needs-grooming
    tracker_transition --id 2 --to-state ready-for-dev

    run tracker_list_issues --state needs-grooming
    [ "$status" -eq 0 ]
    # Two rows expected (alpha and gamma), in priority order: high before low.
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
    [[ "${lines[0]}" =~ "alpha" ]]
    [[ "${lines[1]}" =~ "gamma" ]]
}

@test "list_issues --count returns an integer" {
    tracker_create_issue --title "a" --body B --type feature --priority medium --role pm --state needs-grooming
    tracker_create_issue --title "b" --body B --type feature --priority medium --role pm --state needs-grooming
    run tracker_list_issues --state needs-grooming --count
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "list_issues --search filters case-insensitively" {
    tracker_create_issue --title "Rebuild auth middleware" --body "tokens" --type refactor --priority medium --role pm --state needs-grooming
    tracker_create_issue --title "Add pricer"               --body "options" --type feature  --priority medium --role pm --state needs-grooming
    run tracker_list_issues --search auth
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
    [[ "$output" =~ "Rebuild" ]]
}

@test "capture_backlog_item creates a dormant .backlog.md not visible to needs-grooming queries" {
    run tracker_capture_backlog_item --title "future cleanup" \
        --body "spun out of grooming" --priority medium
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-future-cleanup.backlog.md" ]

    # Not in the grooming queue.
    run tracker_list_issues --state needs-grooming --count
    [ "$output" = "0" ]
    # Visible to a backlog query.
    run tracker_list_issues --state backlog --count
    [ "$output" = "1" ]
}

@test "promote_backlog_item moves dormant → needs-grooming" {
    tracker_capture_backlog_item --title "hatch" --body B --priority medium
    run tracker_promote_backlog_item --id 1 --priority high
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-hatch.todo.md" ]
    [ ! -f "${TRACKER_FILE_ROOT}/001-hatch.backlog.md" ]
}

@test "missing required flag returns exit 1 with stderr message" {
    run tracker_view_issue   # no --id
    [ "$status" -eq 1 ]
    [[ "$output" =~ "missing required flag --id" ]]
}

@test "view on unknown id returns exit 1" {
    run tracker_view_issue --id 999
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "transition with unknown to-state errors out without touching the file" {
    tracker_create_issue --title "atomic" --body B --type feature --priority medium --role pm --state needs-grooming
    run tracker_transition --id 1 --to-state nonsense-state
    [ "$status" -ne 0 ]
    [[ "$output" =~ "unknown state" ]]
    [ -f "${TRACKER_FILE_ROOT}/001-atomic.todo.md" ]
}

@test "transition to current state is a no-op" {
    tracker_create_issue --title "n" --body B --type feature --priority medium --role pm --state needs-grooming
    local before; before="$(stat -c '%Y' "${TRACKER_FILE_ROOT}/001-n.todo.md" 2>/dev/null \
                             || stat -f '%m' "${TRACKER_FILE_ROOT}/001-n.todo.md")"
    run tracker_transition --id 1 --to-state needs-grooming
    [ "$status" -eq 0 ]
    [ -f "${TRACKER_FILE_ROOT}/001-n.todo.md" ]
}
