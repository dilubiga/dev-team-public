---
name: _template
description: Reference template for new skills. Directories starting with "_" are skipped by init-project.sh, so this file is never deployed to a project.
---

# Skill Template

Copy this directory to `agent-playbook/skills/<your-skill>/` and edit. Then:

1. Update the YAML frontmatter (`name:` and `description:`).
2. Replace the body below with the skill's actual logic.
3. Run `bash agent-playbook/scripts/init-project.sh /path/to/test-project quant-finance` and confirm the skill is copied to `.claude/commands/<your-skill>.md`.
4. Invoke it from Claude Code with `/<your-skill>`.

The deployed skill becomes a slash command. Claude Code reads slash commands from `.claude/commands/` only — `init-project.sh` deploys every `skills/*/SKILL.md` automatically (skipping directories whose name starts with `_`).

---

## When to use

State the trigger plainly. Example: "Invoke when the user types `/foo` from any project where `tracker:` is set."

If the skill is meant to be invoked by another skill (e.g. as a sub-routine), say so — and reference the parent.

---

## Pre-flight checks

Every pipeline-driving skill should:

1. Read `CLAUDE.md` and verify the configuration the skill depends on (tracker mode, agent_variant, batch_size, QA standards, skills path).
2. Source `.claude/env.sh` (loads toolchain + project.env + the `tracker_*` dispatcher).
3. Run `check_toolchain` if the skill executes tests / lints.
4. If the skill talks to the issue tracker, do a cheap `tracker_list_issues --count` probe and bail with per-backend remediation guidance if it fails.

See [`skills/execute/SKILL.md`](../execute/SKILL.md) for a fully worked example of these four checks.

---

## Workflow

Number the steps. Each step:

- States the trigger condition (`if issue has X`, `after PM accept`, etc.).
- Gives the exact command(s) to run, using `tracker_*` for any tracker interaction (never raw `gh` or `az`).
- Defines the success / failure / blocked output strings the orchestrator can match on.

Example:

### Step 1 — Probe state

```bash
tracker_view_issue --id {NUMBER}
```

### Step 2 — Take action

```bash
tracker_transition --id {NUMBER} --to-state in-progress --to-role <role>
```

If the transition fails:
```
SKILL BLOCKED: tracker transition failed for issue #{NUMBER}.
```

---

## Error handling

List the failure modes the orchestrator (or the user) needs to recognise, and the message to print for each. Prefer `EXECUTE BLOCKED:` / `EXECUTE ERROR:` / `EXECUTE COMPLETE:` style markers so other skills can grep for them.

---

## What this skill does NOT do

A short list of out-of-scope actions, mirroring the discipline of `skills/execute/SKILL.md`. This is the most useful section for a future reader trying to understand the skill's blast radius.
