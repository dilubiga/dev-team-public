"""Pytest tests for the GitHub tracker backend.

Strategy: install a fake `gh` executable on $PATH that records its argv into a
JSONL file and replays canned responses based on the first sub-command. We
then call the bash verbs via `subprocess.run`, sourcing tracker.sh in the
shell, and assert on (a) exit code, (b) stdout, and (c) the recorded gh
invocations.
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]  # agent-playbook/
TRACKER_SH = REPO_ROOT / "lib" / "tracker" / "tracker.sh"


# ── Fake gh shim ─────────────────────────────────────────────────────────────


FAKE_GH_TEMPLATE = r"""#!/usr/bin/env bash
# Fake gh CLI for tracker tests. Records argv (one record per call) and
# replays canned stdout per sub-command.
set -e

log_file="${GH_FAKE_LOG}"
resp_file="${GH_FAKE_RESPONSES}"
failures_file="${GH_FAKE_FAILURES:-}"

# Record this invocation. Each arg is base64-encoded so newlines/tabs are
# safe; the line is "B64<sp>ARGC<sp>arg1<sp>arg2<sp>..." with each argN
# already base64-encoded.
{
    printf 'B64 %d' "$#"
    for arg in "$@"; do
        printf ' %s' "$(printf %s "$arg" | base64 -w0 2>/dev/null || printf %s "$arg" | base64)"
    done
    printf '\n'
} >> "$log_file"

a1="${1:-}"; a2="${2:-}"
case "$a1" in
    issue|repo|label|api|auth|project) key="$a1 $a2" ;;
    *) key="$a1" ;;
esac

if [[ -n "$failures_file" && -f "$failures_file" ]] && grep -Fxq "$key" "$failures_file"; then
    echo "fake gh: simulated failure for '$key'" >&2
    exit 1
fi

# Pull the canned response with awk (no python dependency).
if [[ -f "$resp_file" ]]; then
    awk -v key="$key" '
        BEGIN { found = 0 }
        # The response file is a TSV: <key>\t<base64-of-response>.
        $0 ~ "^"key"\t" {
            sub("^"key"\t", "")
            print
            found = 1
            exit
        }
    ' "$resp_file" | base64 -d 2>/dev/null || true
fi
"""


import base64


def write_responses(path: Path, mapping: dict[str, str]) -> None:
    """Write the responses file as TSV: <key>\\t<base64-stdout>."""
    lines = []
    for key, val in mapping.items():
        encoded = base64.b64encode(val.encode("utf-8")).decode("ascii")
        lines.append(f"{key}\t{encoded}")
    path.write_text("\n".join(lines) + ("\n" if lines else ""))


@pytest.fixture
def gh_sandbox(tmp_path, monkeypatch):
    """Set up a fake gh on PATH, an empty log, and a responses file."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake_gh = bin_dir / "gh"
    fake_gh.write_text(FAKE_GH_TEMPLATE)
    fake_gh.chmod(fake_gh.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    log = tmp_path / "gh.log"
    responses = tmp_path / "gh-responses.tsv"
    failures = tmp_path / "gh-failures.txt"
    write_responses(responses, {})
    failures.write_text("")

    env = {
        **os.environ,
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "GH_FAKE_LOG": str(log),
        "GH_FAKE_RESPONSES": str(responses),
        "GH_FAKE_FAILURES": str(failures),
        "TRACKER_BACKEND": "github-issues",
        "GH_OWNER": "testowner",
        "GH_REPO": "testrepo",
        "GH_PROJECT_NUMBER": "1",
        "GH_PROJECT_ID": "PVT_kwTEST",
        "GH_FIELD_PIPELINE": "FIELD_PIPELINE",
        "GH_FIELD_AGENT": "FIELD_AGENT",
        "GH_FIELD_STATUS": "FIELD_STATUS",
        "GH_FIELD_QA_CYCLE": "FIELD_QA_CYCLE",
        "GH_PIPELINE_BACKLOG": "PL_BACKLOG",
        "GH_PIPELINE_DEVELOPMENT": "PL_DEV",
        "GH_PIPELINE_QA": "PL_QA",
        "GH_PIPELINE_ACCEPTANCE": "PL_ACCEPT",
        "GH_PIPELINE_DOCUMENTATION": "PL_DOCS",
        "GH_PIPELINE_DONE": "PL_DONE",
        "GH_PIPELINE_BLOCKED": "PL_BLOCKED",
        "GH_AGENT_PM": "AG_PM",
        "GH_AGENT_SWE": "AG_SWE",
        "GH_AGENT_QA": "AG_QA",
        "GH_AGENT_TECHWRITER": "AG_TW",
        "GH_AGENT_HUMAN": "AG_HUMAN",
    }
    return env, log, responses, failures


def run_tracker(env, *args):
    """Source tracker.sh and run a verb with args. Returns CompletedProcess."""
    cmd = ["bash", "-c", f'source "{TRACKER_SH}"; "$@"', "_"] + list(args)
    return subprocess.run(cmd, env=env, capture_output=True, text=True)


def gh_calls(log_path: Path) -> list[list[str]]:
    """Parse the base64-encoded log: each line is "B64 ARGC b64_arg1 b64_arg2 ..."."""
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


# ── Tests ────────────────────────────────────────────────────────────────────


def test_create_issue_invokes_gh_with_label_csv(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        "issue create": "https://github.com/testowner/testrepo/issues/42\n",
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
    calls = gh_calls(log)
    create_calls = [c for c in calls if c[:2] == ["issue", "create"]]
    assert len(create_calls) == 1
    argv = create_calls[0]
    assert "--repo" in argv and "testowner/testrepo" in argv
    assert "--title" in argv and "Add pricer" in argv
    label_csv = argv[argv.index("--label") + 1]
    assert "needs-grooming" in label_csv
    assert "role-pm" in label_csv
    assert "priority-high" in label_csv
    assert "type-feature" in label_csv


def test_comment_issue_passes_multiline_body(gh_sandbox):
    env, log, _, _ = gh_sandbox
    body = "## Implementation Report\n```python\ndef f(): pass\n```\nDone."
    cp = run_tracker(env, "tracker_comment_issue", "--id", "7", "--body", body)
    assert cp.returncode == 0, cp.stderr
    calls = [c for c in gh_calls(log) if c[:2] == ["issue", "comment"]]
    assert len(calls) == 1
    assert calls[0][2] == "7"
    assert calls[0][calls[0].index("--body") + 1] == body


def test_transition_groom_to_ready_for_dev_emits_label_swap_and_board_update(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        # gh issue view --json labels --jq '...' returns a CSV of label names.
        "issue view": "needs-grooming,role-pm,priority-high,type-feature",
        "project item-list": json.dumps({
            "items": [{"id": "ITEM_42", "content": {"number": 42}}]
        }),
    })
    cp = run_tracker(env, "tracker_transition",
        "--id", "42",
        "--from-state", "needs-grooming",
        "--to-state", "ready-for-dev",
    )
    assert cp.returncode == 0, cp.stderr

    calls = gh_calls(log)
    edit_calls = [c for c in calls if c[:2] == ["issue", "edit"]]
    assert len(edit_calls) == 1
    edit_argv = edit_calls[0]
    remove = edit_argv[edit_argv.index("--remove-label") + 1]
    add = edit_argv[edit_argv.index("--add-label") + 1]
    assert set(remove.split(",")) == {"needs-grooming", "role-pm"}
    assert set(add.split(",")) == {"ready-for-dev", "role-swe"}

    # Two project field updates: Pipeline + Agent.
    field_updates = [c for c in calls if c[:2] == ["project", "item-edit"]]
    assert len(field_updates) == 2
    field_ids = [c[c.index("--field-id") + 1] for c in field_updates]
    assert "FIELD_PIPELINE" in field_ids
    assert "FIELD_AGENT" in field_ids


def test_transition_with_qa_cycle_adds_qa_cycle_label_and_number_field(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        "issue view": "in-progress,role-swe,priority-medium,type-feature",
        "project item-list": json.dumps({
            "items": [{"id": "ITEM_7", "content": {"number": 7}}]
        }),
    })
    cp = run_tracker(env, "tracker_transition",
        "--id", "7",
        "--from-state", "in-progress",
        "--to-state", "ready-for-qa",
        "--qa-cycle", "1",
    )
    assert cp.returncode == 0, cp.stderr

    calls = gh_calls(log)
    edit = [c for c in calls if c[:2] == ["issue", "edit"]][0]
    add = edit[edit.index("--add-label") + 1]
    assert "ready-for-qa" in add.split(",")
    assert "role-qa" in add.split(",")
    assert "qa-cycle-1" in add.split(",")

    number_updates = [c for c in calls if c[:2] == ["project", "item-edit"] and "--number" in c]
    assert len(number_updates) == 1
    nu = number_updates[0]
    assert nu[nu.index("--field-id") + 1] == "FIELD_QA_CYCLE"
    assert nu[nu.index("--number") + 1] == "1"


def test_transition_propagates_gh_failure(gh_sandbox):
    env, _, responses, failures = gh_sandbox
    write_responses(responses, {
        "issue view": "needs-grooming,role-pm",
        "project item-list": json.dumps({
            "items": [{"id": "ITEM_1", "content": {"number": 1}}]
        }),
    })
    failures.write_text("issue edit\n")
    cp = run_tracker(env, "tracker_transition",
        "--id", "1",
        "--to-state", "ready-for-dev",
    )
    assert cp.returncode != 0
    assert "gh issue edit failed" in cp.stderr


def test_close_issue_calls_gh_close_and_sets_pipeline_done(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        "project item-list": json.dumps({
            "items": [{"id": "ITEM_5", "content": {"number": 5}}]
        }),
    })
    cp = run_tracker(env, "tracker_close_issue", "--id", "5", "--comment", "Done.")
    assert cp.returncode == 0, cp.stderr

    calls = gh_calls(log)
    close = [c for c in calls if c[:2] == ["issue", "close"]]
    assert len(close) == 1
    assert close[0][close[0].index("--comment") + 1] == "Done."

    pipe = [c for c in calls if c[:2] == ["project", "item-edit"]
            and "--single-select-option-id" in c
            and c[c.index("--single-select-option-id") + 1] == "PL_DONE"]
    assert len(pipe) == 1


def test_list_issues_state_filter_invokes_gh_with_label(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        "issue list": json.dumps([
            {"number": 9, "title": "Lorem", "state": "OPEN",
             "labels": [{"name": "needs-grooming"}, {"name": "role-pm"},
                        {"name": "priority-high"}]},
        ]),
    })
    cp = run_tracker(env, "tracker_list_issues", "--state", "needs-grooming")
    assert cp.returncode == 0, cp.stderr
    assert "Lorem" in cp.stdout
    assert "#9" in cp.stdout

    calls = [c for c in gh_calls(log) if c[:2] == ["issue", "list"]]
    assert len(calls) == 1
    assert "--label" in calls[0]
    assert calls[0][calls[0].index("--label") + 1] == "needs-grooming"


def test_unknown_to_state_returns_exit_1(gh_sandbox):
    env, _, _, _ = gh_sandbox
    cp = run_tracker(env, "tracker_transition",
        "--id", "1", "--to-state", "imaginary-state")
    assert cp.returncode == 1
    assert "unknown to-state" in cp.stderr


def test_block_then_unblock_uses_sentinel_to_restore_role(gh_sandbox):
    env, log, responses, _ = gh_sandbox
    write_responses(responses, {
        # `gh issue view --json labels --jq '...'` resolves the role label
        # server-side; fake gh just replays whatever the agent would see.
        "issue view": "role-swe\n",
        "project item-list": json.dumps({
            "items": [{"id": "ITEM_3", "content": {"number": 3}}]
        }),
    })
    cp = run_tracker(env, "tracker_block_issue", "--id", "3", "--comment", "need clarification")
    assert cp.returncode == 0, cp.stderr

    # Verify we wrote the sentinel comment.
    comments = [c for c in gh_calls(log) if c[:2] == ["issue", "comment"]]
    assert any("tracker:previous-role=swe" in c[c.index("--body") + 1] for c in comments)
