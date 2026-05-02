#!/usr/bin/env bash
# Run the bats portion of the tracker test suite.
# Usage: bash lib/tracker/tests/run.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats >/dev/null 2>&1; then
    echo "run.sh: ERROR — bats not on PATH. Install with: npm install -g bats" >&2
    exit 2
fi

exec bats "${DIR}"/*.bats
