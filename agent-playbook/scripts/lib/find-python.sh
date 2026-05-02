#!/usr/bin/env bash
# lib/find-python.sh — portable Python interpreter discovery.
#
# Sourced by init-project.sh, gh-setup.sh, and env.sh.template (at deploy time
# the function is inlined). Provides a single _find_python() that tries PATH
# candidates first, then common Windows install locations.
#
# After sourcing, call:
#   PY="$(_find_python)" || die "No Python found"

_find_python() {
    # Prefer tools already on PATH.
    for cand in python3 python py; do
        if command -v "$cand" >/dev/null 2>&1 \
           && "$cand" --version >/dev/null 2>&1; then
            echo "$cand"
            return 0
        fi
    done

    # Windows fallback — Git Bash often does not expose the launcher.
    for p in /c/Users/*/AppData/Local/Programs/Python/*/python.exe \
             /c/Python*/python.exe \
             "/c/Program Files/Python"*"/python.exe"; do
        if [[ -x "$p" ]]; then
            echo "$p"
            return 0
        fi
    done

    return 1
}
