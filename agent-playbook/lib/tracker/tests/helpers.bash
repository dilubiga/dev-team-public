#!/usr/bin/env bash
# Shared helpers for the tracker bats suite.

setup_tracker_sandbox() {
    # Create an isolated tracker root for a single bats test, source the
    # dispatcher, and configure the file backend to use the sandbox.
    TRACKER_TEST_TMP="$(mktemp -d)"
    export TRACKER_FILE_ROOT="${TRACKER_TEST_TMP}/tracker"
    mkdir -p "${TRACKER_FILE_ROOT}/done" "${TRACKER_FILE_ROOT}/rejected"

    # Resolve repo root from the test file location: tests/ → lib/tracker → ../..
    TRACKER_LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    # shellcheck disable=SC1091
    source "${TRACKER_LIB_DIR}/tracker.sh"
}

teardown_tracker_sandbox() {
    if [[ -n "${TRACKER_TEST_TMP:-}" && -d "$TRACKER_TEST_TMP" ]]; then
        rm -rf "$TRACKER_TEST_TMP"
    fi
}
