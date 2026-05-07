# File-Mode Audit — 2026-05-06

Goal: confirm that every code path in `agent-playbook/` works for `tracker: file` projects without GitHub/Azure tooling installed, and that file mode is not a second-class citizen in docs / templates.

## Method

For each file class below, grep for the listed patterns and read each match in context. Record findings in the table; do not fix anything in this commit.

## Patterns searched

- Direct `gh ` / `gh-` / `gh_` / `gh.exe` invocations outside of `lib/tracker/tracker_github.sh` and `scripts/{gh-setup,init-github-tracker}.sh`
- Direct `az ` / `az.cmd` invocations outside of `lib/tracker/tracker_azure.sh` and `scripts/{azdo-setup,init-azure-tracker}.sh`
- `${GH_*}` / `${AZ_*}` reads outside of the tracker backends
- Hard-coded references to `issue` / `comment` / `label` semantics in agent prompts that have no file-mode equivalent
- `case` / `if` branches on `TRACKER_BACKEND` / `agent_variant` that omit the `file` arm
- Onboarding / Quick Start sections that silently assume a remote

## Findings

| ID | File | Line(s) | Pattern | Risk | Fix planned in |
|---|---|---|---|---|---|

## Acceptance

- All findings reviewed by hand. Real bugs scheduled for Phase F.
- Items judged not-a-bug recorded with rationale in the table.
