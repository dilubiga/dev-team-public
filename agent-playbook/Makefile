# Top-level Makefile for the agent-playbook repo.
#
# Runs the tracker abstraction's bats and pytest suites.

.PHONY: test test-tracker test-tracker-bats test-tracker-pytest

test: test-tracker

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
