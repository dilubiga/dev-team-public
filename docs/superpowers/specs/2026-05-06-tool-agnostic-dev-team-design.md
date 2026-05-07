# Tool-Agnostic Dev-Team — Design Spec

**Date:** 2026-05-06
**Status:** Approved (pending implementation plan)

---

## 1. Goals

1. **Tracker-agnostic logic.** The dev-team pipeline must work end-to-end without GitHub or Azure DevOps — file mode is a first-class citizen, not a degraded fallback.
2. **Driver-agnostic agents.** The same agents must be usable from **GitHub Copilot** (VS Code Copilot Chat + Copilot CLI) in addition to Claude Code, with no loss of functionality.
3. **No regressions.** Every existing capability — Claude Code path, GitHub mode, Azure mode, the `/execute` orchestrator, refactoring-reviewer, on-call init flow — must continue to work exactly as it does today.

## 2. Non-goals

- Running multiple agents in parallel under Copilot. Copilot has no equivalent of Claude Code's sub-agent dispatch; the Copilot pipeline is **manually stepped** by the user.
- Supporting Copilot in JetBrains / Visual Studio in this iteration. Targets are **VS Code Copilot Chat** and **Copilot CLI**.
- Replacing or competing with the existing Claude Code path. Both drivers coexist.

## 3. Architecture

### 3.1 Single source of truth for agent prompts

Each role gets a canonical body file with no frontmatter:

```
agent-playbook/agents/_body/<role>.body.md
```

Two assembled outputs are generated from each body and committed to the repo:

| Output | Location | Frontmatter |
|---|---|---|
| Claude agent | `agent-playbook/agents/<role>.md` | Claude (`name:`, `description:`, `tools:`) |
| Copilot chat mode | `agent-playbook/chatmodes/<role>.chatmode.md` | Copilot (`description:`, `tools:`) |

The Copilot variant additionally has any `${SUPERPOWERS_SKILLS_DIR}/<skill>/SKILL.md` references **expanded inline** from `agent-playbook/skills-inlined/<skill>.md` (canonical copies maintained in this repo).

### 3.2 Build script

```
agent-playbook/scripts/build-prompts.sh
```

Responsibilities:
- For each `_body/<role>.body.md`, write `agents/<role>.md` (Claude wrapper) and `chatmodes/<role>.chatmode.md` (Copilot wrapper, with skill bodies inlined).
- Idempotent — running it twice produces identical output.
- A `Makefile` target (`make build`) and an optional pre-commit hook invoke it.
- Assembled outputs are committed; editing a body without rebuilding will be caught by CI / pre-commit.

### 3.3 Tracker layer (unchanged)

`agent-playbook/lib/tracker/` (deployed to `<project>/.claude/lib/tracker/`) is the single dispatcher used by **both** Claude agents and Copilot chat modes. Every chat mode begins with `source .claude/env.sh` exactly like every Claude agent does today. Backend routing (`file` / `github-issues` / `azure-boards`) is unchanged.

### 3.4 Copilot orchestration (manual per-agent)

Copilot has no automatic sub-agent dispatch. Two artifacts replace `/execute`:

**Chat modes** (`.github/chatmodes/<role>.chatmode.md`) — one per role. The user picks the mode from the VS Code chat-mode dropdown, then types the action (e.g. `groom #7`).

**Walker prompt** (`.github/prompts/execute.prompt.md`) — re-implements `/execute`'s pre-flight + backlog scan + priority pick, **but stops at dispatch time** and tells the user which chat mode to switch to next:

> Next item: #12 (state: `ready-for-dev`, role: SWE).
> Switch to the `software-engineer` chat mode and run: `implement #12`.

After the user runs that mode, they re-invoke `execute.prompt.md` to advance the pipeline.

The Copilot CLI path uses the same prompt files (Copilot CLI supports `.github/prompts/`). Workspace-level instructions live in a thin `AGENTS.md` at the repo root (Copilot CLI reads `AGENTS.md`); it points at `CLAUDE.md` and `.github/copilot-instructions.md` to avoid drift.

## 4. Per-project deployed layout (file mode + both drivers)

```
<project>/
├── CLAUDE.md
├── AGENTS.md                              ← NEW: Copilot CLI workspace instructions
├── tracker/
├── _docs/
├── .claude/
│   ├── agents/                            ← unchanged
│   ├── commands/execute.md                ← unchanged
│   ├── lib/tracker/                       ← unchanged (shared dispatcher)
│   ├── env.sh, project.env, …             ← unchanged
│   └── PORTING.md
└── .github/
    ├── copilot-instructions.md            ← extended: standards + pointers to chat modes / prompts
    ├── chatmodes/                         ← NEW (6 files, one per role)
    └── prompts/                           ← NEW
        ├── execute.prompt.md
        └── pick-next.prompt.md
```

The shape of `.claude/` is byte-for-byte compatible with what Claude Code reads today.

## 5. `init-project.sh` changes

Add two flags, orthogonal to `--github` / `--azure`:

| Flag | Effect |
|---|---|
| `--no-claude` | Skip `.claude/agents/`, `.claude/commands/` (still deploys `.claude/lib/`, `env.sh`, `project.env` because Copilot chat modes also source them) |
| `--no-copilot` | Skip `.github/chatmodes/`, `.github/prompts/`, `AGENTS.md` |

**Default (no flag):** deploy both. A project can be driven from either tool with no re-bootstrap.

## 6. File-mode audit (deliverable: `docs/file-mode-audit-2026-05-06.md`)

Walk every agent, script, doc, and template. Find and fix anywhere that:
- Hard-codes `gh ` / `az ` calls (instead of `tracker_*` verbs)
- Reads `${GH_*}` / `${AZ_*}` without checking `${TRACKER_BACKEND}`
- Branches only on `github-issues` / `azure-boards` (forgetting `file`)
- Treats file mode as a second-class citizen in onboarding docs / templates
- Calls `gh-setup.sh`, `azdo-setup.sh`, `init-github-tracker.sh`, `init-azure-tracker.sh` along the no-flag path of `init-project.sh`

Acceptance test: a clean smoke run of file-mode bootstrap → first task → `/execute` (Claude path) → `/execute` (Copilot walker prompt). Verified by reading transcripts; no live LLM run required.

## 7. Documentation updates

- `README.md` Quick Start gains a "driver" axis (Claude / Copilot) orthogonal to the tracker-mode axis (File / GitHub / Azure). Six combinations, each walkable top-to-bottom.
- `process/PROCESS.md` clarifies that the same pipeline applies under Copilot, with manual mode-switching at each role boundary.
- `USER-INPUTS.md` adds a Copilot section listing the new artifacts and where they live.
- `agents/_body/README.md` documents the build flow for contributors.

## 8. Open risks

- **Drift between `_body/` and committed assembled files.** Mitigated by `make build` + a pre-commit hook + a CI check that runs `make build` and fails if the working tree changes.
- **Copilot chat-mode tool names** (`tools:` frontmatter) differ across Copilot versions. Initial set: `['codebase', 'editFiles', 'runCommands', 'search', 'terminal']`. Adjust per role as needed.
- **`AGENTS.md` semantics** vary between Copilot CLI versions. Keep it minimal (pointer file only) so older versions still benefit.
- **Skills inlined into chat modes inflate context.** Acceptable — Copilot prompt-file size limits are generous and the inlined skills are short.

## 9. Out of scope (future work)

- A dedicated `claude.md ↔ AGENTS.md` synchronization tool. For now, `AGENTS.md` is a pointer.
- Auto-detection of which driver the user is in (so the walker prompt could omit the "switch to mode X" step under Claude). Not needed — Claude users use `/execute`, Copilot users use the walker.
- Native Copilot CLI agent dispatch (does not exist yet).
