# Top-level Makefile for the agent-playbook repo.
#
# Targets:
#   build   — assemble agents/<role>.md and chatmodes/<role>.chatmode.md
#             from agents/_body/<role>.body.md (run after editing a body).
#   test    — run all bats + pytest suites.
#   check   — re-run `build` and fail if working tree changes (CI gate).
#   clean   — remove generated chatmodes (agents/ are committed).

.PHONY: build test test-tracker test-tracker-bats test-tracker-pytest test-scripts check clean

build:
	@bash scripts/build-prompts.sh

test: test-tracker test-scripts

test-tracker: test-tracker-bats test-tracker-pytest

test-tracker-bats:
	@bash lib/tracker/tests/run.sh

# Pytest target runs only if there are .py test files under lib/tracker/tests/.
test-tracker-pytest:
	@if ls lib/tracker/tests/test_*.py >/dev/null 2>&1; then \
		python -m pytest lib/tracker/tests/ -v; \
	else \
		echo "test-tracker-pytest: no Python tests yet — skipping."; \
	fi

test-scripts:
	@bats scripts/tests/

# Re-run build and fail if the working tree changes (CI gate).
check: build
	@if ! git diff --quiet -- agents/ chatmodes/; then \
		echo "ERROR: 'make build' changed tracked files. Re-run it locally and commit."; \
		git --no-pager diff -- agents/ chatmodes/; \
		exit 1; \
	fi

clean:
	@rm -rf chatmodes/
