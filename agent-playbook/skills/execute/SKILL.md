---
name: execute
description: Runs the full PM→SWE→QA→PM→TechWriter pipeline against any tracker backend (file, github-issues, azure-boards). Invoke with /execute from any project configured via CLAUDE.md.
---

# Execute Pipeline (file / GitHub / Azure)

You are the **orchestrator**. Your job is to drive the development pipeline from backlog to committed code. You coordinate agents — you do not write code, review specs, or make acceptance decisions yourself.

This skill is **backend-agnostic**: every issue / work-item operation goes through the `tracker_*` verbs from `.claude/lib/tracker/tracker.sh`. The dispatcher routes to the file / GitHub / Azure backend based on `${TRACKER_BACKEND}`, derived from the `tracker:` line in `CLAUDE.md`. **Never call `gh` or `az` directly.**

Announce at start: `Running the /execute pipeline (backend: ${TRACKER_BACKEND}).`

---

## Pre-flight Checks

Before starting, verify:

1. **Read `CLAUDE.md`** — confirm the project is configured:
   - `tracker:` is one of `file`, `github-issues`, `azure-boards`
   - `agent_variant:` is set (`file`, `github`, or `azure`) and matches `tracker:`
   - `batch_size` is set (default: 2)
   - `## QA Standards` section is present
   - `## Skills Path` points to a real superpowers skills directory

2. **Read `_docs/PROCESS.md`** (or `.claude/PROCESS.md`) — this governs your behavior. If it conflicts with anything in this skill, `PROCESS.md` wins.

3. **Verify agent files exist:**
   ```bash
   ls .claude/agents/
   # Expected: product-manager.md, software-engineer.md, tester.md,
   #           oncall-engineer.md, technical-writer.md, refactoring-reviewer.md
   ```

4. **Source the project env and verify the toolchain:**
   ```bash
   if [[ ! -f .claude/env.sh ]]; then
       echo "EXECUTE BLOCKED: .claude/env.sh not found. Re-run init-project.sh to regenerate."
       exit 1
   fi
   source .claude/env.sh
   if ! check_toolchain; then
       echo "EXECUTE BLOCKED: Python toolchain incomplete (see warnings above)."
       echo "Install the missing tools with: ${PIP} install pytest ruff black isort"
       exit 1
   fi
   if [[ -z "${TRACKER_BACKEND:-}" ]]; then
       echo "EXECUTE BLOCKED: TRACKER_BACKEND not set. Check the 'tracker:' line in CLAUDE.md."
       exit 1
   fi
   echo "Toolchain OK — PY=${PY}  PYTEST='${PYTEST}'  TRACKER_BACKEND=${TRACKER_BACKEND}"
   ```

   Sourcing `env.sh` auto-loads `.claude/project.env` and the tracker dispatcher. Every agent the orchestrator spawns inherits this environment, so the `tracker_*` verbs are available everywhere downstream. **Do not skip this step** — a green preflight is the single source of truth that tests can actually be executed this session.

5. **Verify backend authentication.** The `tracker_*` verbs themselves return exit code 2 with a clear message when their backend's required env / auth is missing, so the easiest preflight is to make a cheap read call and check the exit code:
   ```bash
   if ! tracker_list_issues --count >/dev/null 2>&1; then
       echo "EXECUTE BLOCKED: tracker backend '${TRACKER_BACKEND}' is not usable."
       case "${TRACKER_BACKEND}" in
         github-issues)  echo "  → Verify: gh auth status; check GH_OWNER / GH_REPO / GH_PROJECT_ID in .claude/project.env." ;;
         azure-boards)   echo "  → Verify: az account show; az extension list | grep azure-devops; check AZ_ORG / AZ_PROJECT in .claude/project.env." ;;
         file)           echo "  → Verify: tracker/ directory exists in the project root." ;;
       esac
       exit 1
   fi
   ```

6. **Scan the backlog:**
   ```bash
   for state in needs-grooming ready-for-dev in-progress rework-needed \
                ready-for-qa ready-for-acceptance ready-for-docs; do
       echo "── ${state} ──"
       tracker_list_issues --state "${state}"
   done
   ```

   `tracker_list_issues` prints one tab-separated line per issue: `#ID\tTITLE\tSTATE\tROLE\tPRIORITY`. Default sort is priority then ID.

   If every state is empty:
   ```
   EXECUTE COMPLETE: No issues in the pipeline. Create your first task and re-run /execute.
     - file mode:    cp .claude/templates/task.todo.md tracker/001-your-task.todo.md
     - github mode:  tracker_create_issue --title '…' --body '…' --type feature --priority medium --role pm --state needs-grooming
     - azure mode:   same tracker_create_issue invocation as github
   ```
   Stop.

---

## Main Loop

### Step 1 — Pick the next batch

Read `batch_size` from `CLAUDE.md` (default: 2).

Collect issues in this priority order. Within each tier, items are already returned by priority then ID (the dispatcher's default sort), so the first `batch_size` lines you read are the next batch:

1. **`rework-needed`** — issues that failed QA or were rejected take absolute priority (route back to SWE)
2. **`in-progress`** — issues already started (resume them)
3. **`ready-for-qa`** — issues waiting for QA
4. **`ready-for-acceptance`** — issues waiting for PM acceptance
5. **`ready-for-docs`** — issues waiting for technical writer
6. **`ready-for-dev`** — groomed and ready for SWE
7. **`needs-grooming`** — raw issues needing PM grooming

```bash
# Iterate tiers in order; collect up to ${batch_size} issues total.
for state in rework-needed in-progress ready-for-qa ready-for-acceptance \
             ready-for-docs ready-for-dev needs-grooming; do
    tracker_list_issues --state "${state}"
done
```

Skip any issue whose state is `blocked` (those are waiting for human input — they don't appear in the queries above by construction; the `blocked` state is its own filter).

If no issues are found in any state:
```
EXECUTE COMPLETE: Backlog is empty. All issues are done or no issues exist.
```
Stop.

### Step 2 — For each issue in the batch, run the pipeline

Process issues sequentially within a batch (not in parallel).

#### 2a — Handle rework issues first (`rework-needed`)

Route back to SWE:

```bash
claude --agent .claude/agents/software-engineer.md \
  "Fix rework on issue #{NUMBER}. Read the latest QA Report or PM Rejection comment for specific failures."
```

After SWE completes, the issue should have transitioned to `ready-for-qa`. Proceed to QA (step 2c).

#### 2b — PM Grooming (if issue has `needs-grooming`)

Check the issue comments for an unanswered `## Agent Questions` section:

```bash
tracker_view_issue_comments --id {NUMBER}
```

If unanswered questions exist:
```
EXECUTE BLOCKED: Issue #{NUMBER} is waiting for human input.
Answer the question(s) in the issue comments / discussion, then re-run /execute.
```
Skip this issue and continue to the next.

Otherwise spawn the PM agent:

```bash
claude --agent .claude/agents/product-manager.md \
  "Groom issue #{NUMBER}"
```

After the PM runs:
- If PM output contains `GROOMED:` → the issue now has `ready-for-dev`. Proceed to SWE.
- If PM output contains `BLOCKED:` → skip this issue. Log: `Issue #{NUMBER} blocked — human input needed.`

#### 2c — SWE Implementation (if issue has `ready-for-dev`)

```bash
claude --agent .claude/agents/software-engineer.md \
  "Implement issue #{NUMBER}"
```

After SWE runs:
- If the issue now has `ready-for-qa` and an Implementation Report comment exists → proceed to QA.
- If SWE output contains `BLOCKED:` → skip issue, log it.

#### 2d — QA Verification (if issue has `ready-for-qa`)

```bash
claude --agent .claude/agents/tester.md \
  "Test issue #{NUMBER}"
```

After QA runs:
- If QA output contains `QA PASS:` → the issue now has `ready-for-acceptance`. Proceed to PM acceptance.
- If QA output contains `QA FAIL:` → determine cycle number from the QA report comment.
  - Cycle 1 or 2: the issue now has `rework-needed`. Route back to SWE (step 2a).
  - Cycle 3 (`QA CYCLE 3 FAIL`): **stop and escalate**:
    ```
    EXECUTE BLOCKED: Issue #{NUMBER} has failed QA 3 times.
    Human review required. Read the issue comments for the full history.
    ```
    Skip this issue.
- If QA output contains `QA BLOCKED:` → log and skip.

#### 2e — PM Acceptance Review (if issue has `ready-for-acceptance`)

```bash
claude --agent .claude/agents/product-manager.md \
  "Acceptance review for issue #{NUMBER}"
```

After PM runs:
- If PM output contains `ACCEPTED:` → proceed to technical writer (step 2f).
- If PM output contains `REJECTED:` → the issue now has `rework-needed`. Route to SWE (step 2a).
  If PM has rejected twice for the same issue, **pause and ask the human**:
  ```
  EXECUTE PAUSED: PM has rejected issue #{NUMBER} twice.
  The spec may need revision. Please review the issue comments
  and advise: (a) rework the spec, (b) abandon the task, or (c) override and commit as-is.
  ```

#### 2f — Technical Writer Documentation (if issue has `ready-for-docs`)

```bash
claude --agent .claude/agents/technical-writer.md \
  "Write documentation for issue #{NUMBER}"
```

After the tech-writer runs:
- If output contains `DOCS DONE:` → proceed to commit (step 2g).
- If output contains `TECHWRITER BLOCKED:` → log and skip. Human must resolve.

#### 2g — Commit (after DOCS DONE)

**Before committing, display the diff for human review:**
```bash
git diff --stat HEAD
git diff HEAD
```

Output:
```
EXECUTE READY TO COMMIT: Issue #{NUMBER} — diff shown above.
Please review and confirm: type 'yes' to commit, or 'no' to pause.
```

Wait for human confirmation. If confirmed:

```bash
git add <files listed in SWE implementation report comment>
git add _docs/<doc file listed in Documentation Report comment>
git commit -m "[ISSUE-{NUMBER}] brief description"
```

Then close the issue:

```bash
tracker_close_issue --id {NUMBER} --comment "Implemented, documented, and committed."
```

**Never `git push` without explicit human instruction. Never.**

---

## Step 3 — End of batch

After processing all issues in the current batch, check whether more remain:

```bash
remaining=$((
  $(tracker_list_issues --state needs-grooming  --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state ready-for-dev   --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state rework-needed   --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state in-progress     --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state ready-for-qa    --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state ready-for-acceptance --count 2>/dev/null || echo 0) +
  $(tracker_list_issues --state ready-for-docs  --count 2>/dev/null || echo 0)
))
echo "Active issues remaining: ${remaining}"
```

If issues remain → report progress and start the next batch (loop back to Step 1).
If backlog is empty → report:
```
EXECUTE COMPLETE: All issues processed.
Done: [N]  Blocked: [N]  Skipped: [N]
```

---

## Error Handling

### Tracker backend not authenticated / not configured
```
EXECUTE BLOCKED: tracker backend '<value>' is not usable.
```
Per-backend remediation:
- `github-issues`: run `gh auth login`; verify `GH_OWNER` / `GH_REPO` / `GH_PROJECT_ID` in `.claude/project.env`.
- `azure-boards`: run `az login` (or export `AZURE_DEVOPS_EXT_PAT`); install the extension with `az extension add --name azure-devops`; verify `AZ_ORG` / `AZ_PROJECT` in `.claude/project.env`.
- `file`: ensure `tracker/` exists in the project root.

### Issue has no body or description
```
EXECUTE ERROR: Issue #{NUMBER} has no description.
Add a task description to the issue body, then re-run /execute.
```

### Agent produces no output / crashes
```
EXECUTE ERROR: [agent-name] failed on issue #{NUMBER}. No output or unrecognized output.
Manual intervention required. Check the issue comments and re-run the affected step.
```

### Pipeline labels / state vocabulary missing on the backend
GitHub mode (labels missing on the repo):
```
EXECUTE ERROR: Pipeline labels not found in repo.
Run: bash scripts/init-github-tracker.sh ${GH_OWNER}/${GH_REPO}
```
Azure mode (project / process template not reachable):
```
EXECUTE ERROR: Azure DevOps project not reachable.
Run: bash scripts/init-azure-tracker.sh
```

---

## What /execute Does NOT Do

- Does not write code
- Does not evaluate specs or test results
- Does not override PM or QA decisions
- Does not skip any pipeline step
- Does not push to remote repositories
- Does not create issues — only processes existing ones
- Does not call `gh` or `az` directly — every issue / work-item operation goes through `tracker_*`
