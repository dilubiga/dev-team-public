# Canonical Agent Bodies

Each `<role>.body.md` is the **single source of truth** for that role's prompt.
`scripts/build-prompts.sh` assembles two outputs from each body:

- `agents/<role>.md` — Claude Code agent (with Claude frontmatter)
- `chatmodes/<role>.chatmode.md` — VS Code Copilot chat mode (with Copilot
  frontmatter; any `${SUPERPOWERS_SKILLS_DIR}/<skill>/SKILL.md` reference is
  expanded inline from `skills-inlined/<skill>.md`)

## Editing

1. Edit `_body/<role>.body.md`.
2. Run `make build`.
3. Commit `_body/`, `agents/`, and `chatmodes/` together.

A pre-commit hook (`scripts/hooks/pre-commit`) enforces step 2; CI re-runs
`make build` and fails if the working tree changes.

## Frontmatter is owned by the build script

Do **not** add frontmatter to body files. The wrapper frontmatter lives in
`scripts/build-prompts.sh` and is the only place tool-name (`tools:`) lists
should change.
