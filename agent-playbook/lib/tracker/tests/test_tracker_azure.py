"""Pytest tests for the Azure DevOps tracker backend.

Strategy mirrors test_tracker_github.py: install a fake `az` executable on
$PATH that records argv into a log file and replays canned responses keyed
by sub-command. We then call the bash verbs via `subprocess.run`, sourcing
tracker.sh, and assert on (a) exit code, (b) stdout, and (c) the recorded
az invocations.
"""
from __future__ import annotations

import base64
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]  # agent-playbook/
TRACKER_SH = REPO_ROOT / "lib" / "tracker" / "tracker.sh"


# ── Fake az shim ─────────────────────────────────────────────────────────────


FAKE_AZ_TEMPLATE = r"""#!/usr/bin/env bash
# Fake az CLI for tracker tests. Records argv (one record per call) and
# replays canned stdout per sub-command key.
set -e

log_file="${AZ_FAKE_LOG}"
resp_file="${AZ_FAKE_RESPONSES}"
failures_file="${AZ_FAKE_FAILURES:-}"

# Record this invocation, base64-encoded so embedded whitespace is safe.
{
    printf 'B64 %d' "$#"
    for arg in "$@"; do
        printf ' %s' "$(printf %s "$arg" | base64 -w0 2>/dev/null || printf %s "$arg" | base64)"
    done
    printf '\n'
} >> "$log_file"

# Build the lookup key.
#   az boards work-item show ...   → "boards work-item show"
#   az boards work-item create ... → "boards work-item create"
#   az boards work-item update ... → "boards work-item update"
#   az boards query ...            → "boards query"
#   az rest --method GET --uri ... → "rest GET"
#   az rest --method POST ...      → "rest POST"
#   anything else                  → "$1"
a1="${1:-}"; a2="${2:-}"; a3="${3:-}"
case "$a1" in
    boards)
        if [[ "$a2" == "work-item" ]]; then
            key="boards work-item $a3"
        else
            key="boards $a2"
        fi
        ;;
    rest)
        method=""
        # Scan args for --method <verb>.
        i=1
        for arg in "$@"; do
            if [[ "$arg" == "--method" ]]; then
                shift_i=$((i + 1))
                method="${!shift_i:-}"
                break
            fi
            i=$((i + 1))
        done
        key="rest ${method:-GET}"
        ;;
    *)
        key="$a1"
        ;;
esac

if [[ -n "$failures_file" && -f "$failures_file" ]] && grep -Fxq "$key" "$failures_file"; then
    echo "fake az: simulated failure for '$key'" >&2
    exit 1
fi

if [[ -f "$resp_file" ]]; then
    awk -v key="$key" '
        BEGIN { found = 0 }
        $0 ~ "^"key"\t" {
            sub("^"key"\t", "")
            print
            found = 1
            exit
        }
    ' "$resp_file" | base64 -d 2>/dev/null || true
fi
"""


def write_responses(path: Path, mapping: dict[str, str]) -> None:
    """Write the responses file as TSV: <key>\\t<base64-stdout>."""
    lines = []
    for key, val in mapping.items():
        encoded = base64.b64encode(val.encode("utf-8")).decode("ascii")
        lines.append(f"{key}\t{encoded}")
    path.write_text("\n".join(lines) + ("\n" if lines else ""))


@pytest.fixture
def az_sandbox(tmp_path):
    """Set up a fake az on PATH, an empty log, and a responses file."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake_az = bin_dir / "az"
    fake_az.write_text(FAKE_AZ_TEMPLATE, encoding="utf-8")
    fake_az.chmod(fake_az.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    log = tmp_path / "az.log"
    responses = tmp_path / "az-responses.tsv"
    failures = tmp_path / "az-failures.txt"
    write_responses(responses, {})
    failures.write_text("")

    env = {
        **os.environ,
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "AZ_FAKE_LOG": str(log),
        "AZ_FAKE_RESPONSES": str(responses),
        "AZ_FAKE_FAILURES": str(failures),
        "TRACKER_BACKEND": "azure-boards",
        "AZ_ORG": "testorg",
        "AZ_PROJECT": "TestProject",
        "AZ_REPO": "testrepo",
    }
    return env, log, responses, failures


def run_tracker(env, *args):
    """Source tracker.sh and run a verb with args. Returns CompletedProcess."""
    cmd = ["bash", "-c", f'source "{TRACKER_SH}"; "$@"', "_"] + list(args)
    return subprocess.run(cmd, env=env, capture_output=True, text=True)


def az_calls(log_path: Path) -> list[list[str]]:
    """Parse the base64-encoded log: each line is "B64 ARGC b64_arg1 ..."."""
    if not log_path.exists():
        return []
    out = []
    for line in log_path.read_text().splitlines():
        if not line.startswith("B64 "):
            continue
        parts = line.split(" ")
        argc = int(parts[1])
        decoded = [
            base64.b64decode(parts[2 + i]).decode("utf-8") if parts[2 + i] else ""
            for i in range(argc)
        ]
        out.append(decoded)
    return out


def calls_matching(calls: list[list[str]], prefix: list[str]) -> list[list[str]]:
    return [c for c in calls if c[: len(prefix)] == prefix]


# ── Tests ────────────────────────────────────────────────────────────────────


def test_create_issue_invokes_az_with_tags_and_priority(az_sandbox):
    env, log, responses, _ = az_sandbox
    write_responses(responses, {
        "boards work-item create": json.dumps({"id": 42}),
    })
    cp = run_tracker(env, "tracker_create_issue",
        "--title", "Add pricer",
        "--body", "spec body",
        "--type", "feature",
        "--priority", "high",
        "--role", "pm",
        "--state", "needs-grooming",
    )
    assert cp.returncode == 0, cp.stderr
    assert cp.stdout.strip() == "#42"

    creates = calls_matching(az_calls(log), ["boards", "work-item", "create"])
    assert len(creates) == 1
    argv = creates[0]
    assert argv[argv.index("--title") + 1] == "Add pricer"
    assert argv[argv.index("--description") + 1] == "spec body"
    assert argv[argv.index("--type") + 1] == "Task"  # default work-item type
    # --org normalised to a full URL.
    assert argv[argv.index("--org") + 1] == "https://dev.azure.com/testorg"
    assert argv[argv.index("--project") + 1] == "TestProject"
    # --fields receives "System.Tags=…" plus priority. Both are passed as
    # consecutive positional values to a single --fields flag.
    fields_idx = argv.index("--fields")
    assert argv[fields_idx + 1].startswith("System.Tags=")
    tags_csv = argv[fields_idx + 1].split("=", 1)[1]
    tag_set = set(tags_csv.split(","))
    assert {"needs-grooming", "role-pm", "priority-high", "type-feature"} <= tag_set
    assert argv[fields_idx + 2] == "Microsoft.VSTS.Common.Priority=1"


def test_create_issue_with_non_default_state_updates_system_state(az_sandbox):
    env, log, responses, _ = az_sandbox
    write_responses(responses, {
        "boards work-item create": json.dumps({"id": 7}),
    })
    cp = run_tracker(env, "tracker_create_issue",
        "--title", "T", "--body", "B", "--type", "bugfix",
        "--priority", "medium", "--role", "swe", "--state", "in-progress",
    )
    assert cp.returncode == 0, cp.stderr
    updates = calls_matching(az_calls(log), ["boards", "work-item", "update"])
    # Should include a follow-up update setting System.State=Active.
    assert any(
        "System.State=Active" in u[u.index("--fields") + 1]
        for u in updates if "--fields" in u
    ), updates


def test_comment_issue_posts_to_rest_api(az_sandbox):
    env, log, _, _ = az_sandbox
    body = "## Implementation Report\n```python\ndef f(): pass\n```\nDone."
    cp = run_tracker(env, "tracker_comment_issue", "--id", "7", "--body", body)
    assert cp.returncode == 0, cp.stderr

    rest = calls_matching(az_calls(log), ["rest"])
    posts = [c for c in rest if "--method" in c and c[c.index("--method") + 1] == "POST"]
    assert len(posts) == 1
    argv = posts[0]
    uri = argv[argv.index("--uri") + 1]
    assert "/_apis/wit/workitems/7/comments" in uri
    payload = json.loads(argv[argv.index("--body") + 1])
    assert payload == {"text": body}


def test_transition_groom_to_ready_for_dev_swaps_tags(az_sandbox):
    env, log, responses, _ = az_sandbox
    # ADO returns System.Tags joined with "; ". Include type/priority so we can
    # confirm those are preserved across the transition.
    show_response = json.dumps({
        "id": 42,
        "fields": {
            "System.Tags": "needs-grooming; role-pm; priority-high; type-feature",
            "System.State": "New",
        },
    })
    write_responses(responses, {"boards work-item show": show_response})
    cp = run_tracker(env, "tracker_transition",
        "--id", "42",
        "--from-state", "needs-grooming",
        "--to-state", "ready-for-dev",
    )
    assert cp.returncode == 0, cp.stderr

    updates = calls_matching(az_calls(log), ["boards", "work-item", "update"])
    assert len(updates) == 1
    argv = updates[0]
    fields_idx = argv.index("--fields")
    tags_field = argv[fields_idx + 1]
    assert tags_field.startswith("System.Tags=")
    tag_set = set(tags_field.split("=", 1)[1].split(","))
    # State and role swapped; priority/type preserved.
    assert "needs-grooming" not in tag_set
    assert "role-pm" not in tag_set
    assert "ready-for-dev" in tag_set
    assert "role-swe" in tag_set
    assert "priority-high" in tag_set
    assert "type-feature" in tag_set
    # System.State carried as a second --fields key=value.
    assert argv[fields_idx + 2] == "System.State=Active"


def test_transition_with_qa_cycle_adds_qa_cycle_tag(az_sandbox):
    env, log, responses, _ = az_sandbox
    show_response = json.dumps({
        "id": 7,
        "fields": {
            "System.Tags": "in-progress; role-swe; priority-medium; type-feature",
            "System.State": "Active",
        },
    })
    write_responses(responses, {"boards work-item show": show_response})
    cp = run_tracker(env, "tracker_transition",
        "--id", "7",
        "--from-state", "in-progress",
        "--to-state", "ready-for-qa",
        "--qa-cycle", "1",
    )
    assert cp.returncode == 0, cp.stderr

    updates = calls_matching(az_calls(log), ["boards", "work-item", "update"])
    assert len(updates) == 1
    tags_field = updates[0][updates[0].index("--fields") + 1]
    tag_set = set(tags_field.split("=", 1)[1].split(","))
    assert "ready-for-qa" in tag_set
    assert "role-qa" in tag_set
    assert "qa-cycle-1" in tag_set


def test_transition_propagates_az_failure(az_sandbox):
    env, _, responses, failures = az_sandbox
    write_responses(responses, {
        "boards work-item show": json.dumps({
            "id": 1, "fields": {"System.Tags": "needs-grooming; role-pm"},
        }),
    })
    failures.write_text("boards work-item update\n")
    cp = run_tracker(env, "tracker_transition",
        "--id", "1", "--to-state", "ready-for-dev",
    )
    assert cp.returncode != 0
    assert "az boards work-item update failed" in cp.stderr


def test_close_issue_calls_update_state_closed(az_sandbox):
    env, log, _, _ = az_sandbox
    cp = run_tracker(env, "tracker_close_issue", "--id", "5", "--comment", "Done.")
    assert cp.returncode == 0, cp.stderr

    # The comment goes through az rest POST first.
    rest_posts = [
        c for c in calls_matching(az_calls(log), ["rest"])
        if "--method" in c and c[c.index("--method") + 1] == "POST"
    ]
    assert len(rest_posts) == 1
    payload = json.loads(rest_posts[0][rest_posts[0].index("--body") + 1])
    assert payload["text"] == "Done."

    updates = calls_matching(az_calls(log), ["boards", "work-item", "update"])
    closes = [u for u in updates if "--state" in u and u[u.index("--state") + 1] == "Closed"]
    assert len(closes) == 1
    assert closes[0][closes[0].index("--id") + 1] == "5"


def test_list_issues_state_filter_invokes_wiql_query(az_sandbox):
    env, log, responses, _ = az_sandbox
    wiql_response = json.dumps([
        {
            "id": 9,
            "fields": {
                "System.Title": "Lorem",
                "System.State": "New",
                "System.Tags": "needs-grooming; role-pm; priority-high",
                "Microsoft.VSTS.Common.Priority": 1,
            },
        }
    ])
    write_responses(responses, {"boards query": wiql_response})
    cp = run_tracker(env, "tracker_list_issues", "--state", "needs-grooming")
    assert cp.returncode == 0, cp.stderr
    assert "Lorem" in cp.stdout
    assert "#9" in cp.stdout

    queries = calls_matching(az_calls(log), ["boards", "query"])
    assert len(queries) == 1
    wiql = queries[0][queries[0].index("--wiql") + 1]
    assert "[System.Tags] CONTAINS WORDS 'needs-grooming'" in wiql
    assert "[System.State] <> 'Closed'" in wiql


def test_unknown_to_state_returns_exit_1(az_sandbox):
    env, _, responses, _ = az_sandbox
    # show is called before the to-state is validated; provide a stub.
    write_responses(responses, {
        "boards work-item show": json.dumps({"id": 1, "fields": {"System.Tags": ""}}),
    })
    cp = run_tracker(env, "tracker_transition",
        "--id", "1", "--to-state", "imaginary-state")
    assert cp.returncode == 1
    assert "unknown to-state" in cp.stderr


def test_block_then_unblock_uses_sentinel_to_restore_role(az_sandbox):
    env, log, responses, _ = az_sandbox
    write_responses(responses, {
        "boards work-item show": json.dumps({
            "id": 3,
            "fields": {"System.Tags": "in-progress; role-swe; priority-high"},
        }),
    })
    cp = run_tracker(env, "tracker_block_issue", "--id", "3", "--comment", "need clarification")
    assert cp.returncode == 0, cp.stderr

    rest_posts = [
        c for c in calls_matching(az_calls(log), ["rest"])
        if "--method" in c and c[c.index("--method") + 1] == "POST"
    ]
    # User comment + sentinel comment.
    assert len(rest_posts) == 2
    bodies = [json.loads(c[c.index("--body") + 1])["text"] for c in rest_posts]
    assert any("tracker:previous-role=swe" in b for b in bodies)
    assert any(b == "need clarification" for b in bodies)
