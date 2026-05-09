# Phase: implement

Read by the `/kmm` orchestrator when state-detection routes to the **implement** phase. Executes the task list, dispatching subagents only.

Read `skills/kmm-migration-workflow/constitution.md` and `skills/kmm-migration-workflow/references/orchestration-protocol.md` first.

This is the labour phase. **You do not write code.** You read `tasks.md`, dispatch the right subagent for each task, validate completion promises, update `tasks.md`, and loop until either all tasks in the current checkpoint are complete or you hit a blocker that requires user input.

When tasks are batched by checkpoint (Constitution §13), implement runs **one checkpoint at a time**. After a checkpoint's tasks all return `[x]`, the orchestrator routes to the verify phase scoped to that checkpoint, then to the pr phase scoped to that checkpoint, then back here for the next checkpoint. The skill does not start checkpoint K+1 until checkpoint K's PR is opened (the user can choose to merge before continuing, or stack branches).

## Inputs

- `<repo>/kmm/<scope>/tasks.md` — the ordered task list with subagent metadata
- `<repo>/kmm/<scope>/architecture.md` — checkpoint plan, refactor entries
- `<repo>/kmm/<scope>/migration-guide.md` — per-file specs the agents read directly
- `<repo>/kmm/<scope>/spec.md` — declared targets, baseline SHA, test command
- `<repo>/kmm/<scope>/findings.md` — research, version pins
- `<repo>/.worktrees/kmm-<scope>/` — the working tree

## Orchestration loop

Determine the **active checkpoint** from `tasks.md`: the lowest-numbered checkpoint with at least one unchecked task. Run only tasks in that checkpoint until the checkpoint is fully `[x]`, then route to the verify phase scoped to that checkpoint.

Repeat until the active checkpoint's tasks are all `[x]` **or** you escalate to the user:

### 1. Read `tasks.md`. Find the next runnable batch in the active checkpoint.

A task is runnable when:
- Its `checkpoint:` matches the active checkpoint
- Its checkbox is `[ ]`
- All its `depends-on` tasks are `[x]`
- Its phase predecessors are complete (Phase B cannot start until Phase A is done; `T-LOCK` cannot run until all Phase B tasks are done; Phase D level L cannot start until level L-1 is done)

If multiple tasks are runnable in parallel (same checkpoint, same phase, same DAG level, no shared depends-on), dispatch them concurrently. Otherwise dispatch one at a time.

### 2. Dispatch the right subagent.

Each task's metadata block specifies the subagent. Read the agent's prompt file from `agents/` and pass it as the system prompt for the subagent. Pass the task-specific data (source path, target path, expected test count, etc.) in the user message.

| Task type | Subagent | Model |
|---|---|---|
| Phase A: Scaffold | `migrator` (scaffold mode) | sonnet |
| Phase B: Capture | `test-capturer` | sonnet |
| Phase C: Baseline lock | (orchestrator runs this — not a subagent) | — |
| Phase D: Migrate | `migrator` | sonnet |
| After every Phase D file | `structural-verifier` | haiku |

The orchestrator (you) runs `T-LOCK` because it is bookkeeping (commit + record SHA), not labour. See the tasks-phase reference for the lock procedure.

### 3. Validate the completion promise.

When a subagent stops, read the last line of its output. It must be one of the tokens defined in `references/completion-promises.md`. If the line is missing or malformed, treat it as a mechanical failure and refire.

Map the promise to an action:

| Promise | Action |
|---|---|
| `CAPTURE_COMPLETE` | Mark task `[x]`. Record any notes in tasks.md metadata. |
| `MIGRATE_COMPLETE` | Dispatch `structural-verifier` for the file. |
| `VERIFY_PASS` | Mark the migrate task `[x]`. |
| `VERIFY_FAIL: <violations>` | Refire `migrator` for the file with the violations list. |
| `RESEARCH_COMPLETE` | Record finding in `findings.md` (or wherever the dispatch context said to put it). |
| `*_BLOCKED` (mechanical) | Refire same subagent (max 3 strikes) with prior output + diagnostic. |
| `*_BLOCKED` (interpretive) | Escalate to user immediately. |
| `REQUIRES_APPROVAL: <description>` | Dispatch `researcher` to live-source any options the subagent named (libraries, versions, APIs, patterns). Wait for `RESEARCH_COMPLETE`. THEN escalate to user with options each carrying a live-source citation. Per Constitution §3 — never present recall-based options. Do not retry the original task before user decides. |

### 4. Mechanical-vs-interpretive classification.

A `*_BLOCKED` is **mechanical** if the reason matches: `tests red`, `build error`, `compile error`, `missing import`, `missing dependency`, `flaky test`, `timeout`. The orchestrator refires the same subagent with the prior failure output, the relevant logs, and the instruction "fix the root cause; do not modify tests".

A `*_BLOCKED` is **interpretive** if the reason matches: `ambiguous behaviour`, `scope expansion`, `signature change required`, `behaviour change required`, `cannot reach surgical port`, `refactor scope expansion`, `dependency without multiplatform replacement`, `decision required`. The orchestrator escalates to the user immediately with the full context — no retries.

If unsure, default to **interpretive** (escalate). Burning retries on questions only the user can answer is wasteful.

Strike count is per task, per subagent type. Reset when the task transitions to `[x]`.

When an interpretive escalation results in a scope amendment or a planning gap (e.g., a missed Platform API like `System.currentTimeMillis()` surfaces during migration), log the deviation in `migration-report.md` with a **structured Closure field**. Pick the type that matches the fix:

- Missing API replacement applied: `{ type: "grep:zero", pattern: "<old-api-call>", scope: "<migrated-file-path>" }`
- New library swap added: `{ type: "grep:zero", pattern: "<old-package>", scope: "<file-path>" }`
- New scaffolding interface added: `{ type: "test:exists", fqn: "<file-path-or-class>" }` or `{ type: "binding:present", type: "<NewInterface>", module: "<DI-module>" }`
- Behaviour ratification (user accepted a permanent change): set status `RATIFIED` directly, no closure check.

`manual` is the fallback when none of the above fit — but prefer a structured type whenever possible so the verify phase can auto-close.

### 5. Update `tasks.md` after every subagent run.

- On success: mark the checkbox `[x]`, add a one-line note with the subagent's relevant output (e.g., test count, target path).
- On mechanical retry: keep the checkbox `[ ]`, increment the strike counter in the metadata.
- On interpretive escalation: mark the checkbox with `[!]` (blocked-on-user), append the REQUIRES_APPROVAL text inline.

Commit `tasks.md` after every batch boundary (not after every single task — that would be noisy). The commit message: `tasks: <phase letter> progress <X/Y>`.

### 6. Honour `T-LOCK` exactly.

When all Phase B tasks of the active checkpoint are `[x]`:

1. Run the test command from `spec.md` against the worktree. All baseline tests must be GREEN.
2. `git add` everything in the worktree (including the moved files in `androidMain` and the new `commonTest` files).
3. `git commit -m "baseline: capture <scope>/<checkpoint> @ <SHA>"` where `<SHA>` is `git rev-parse HEAD`.
4. Append `baseline-locked-sha: <SHA>` to `spec.md` and commit.
5. Mark the checkpoint's `T-LOCK` as `[x]`.

After `T-LOCK`, **never modify any file under `commonTest/`** without an approved deviation. If a migrator subagent attempts to modify a baseline test, abort the migration for that file, log the deviation as `OPEN`, and escalate to the user.

### 7. After every Phase D level, run the level-boundary check.

After every file in a level returns `MIGRATE_COMPLETE` and `VERIFY_PASS`:
- Run the full baseline test suite against the worktree (test command from `spec.md`).
- Run a per-target compile check for declared shared targets (commands from `plan.md`'s verification section).
- If any check fails, refire the relevant `migrator` for the file responsible. Strike counter applies.

This catches subtle multi-file interaction bugs before advancing to the next level.

### 7b. After every checkpoint, run the checkpoint-boundary check.

When all Phase D tasks of the active checkpoint are `[x]`:
- Run the full baseline test suite against the worktree.
- Run per-target compile commands for declared shared targets.
- Run consumer compile commands.
- The checkpoint must be **master-mergeable** at this point (Constitution §13): declared targets compile cleanly, consumers compile cleanly, no dependency on later checkpoints.
- If any check fails, refire the relevant `migrator`. Strike counter applies.

### 8. Constitution check at the end of each phase.

When a phase completes (all Phase A tasks done, or all Phase B done, or `T-LOCK` done, or all Phase D done within the active checkpoint):

- List which principles were touched in this phase.
- Pass/fail:
  - `[ ]` Every dispatched subagent returned a valid completion promise
  - `[ ]` Every blocked task is logged with reason and strike count
  - `[ ]` `tasks.md` reflects current state
  - `[ ]` Phase-specific gates passed (Phase B: all tests green; T-LOCK: SHA recorded; Phase D level: full suite green; Phase D checkpoint: targets and consumers green)
- On fail: STOP. Report which checks failed.

### 9. End of checkpoint.

When the active checkpoint's tasks are all `[x]`:
- Print summary: checkpoint name, tasks executed, files migrated, deviations logged.
- Auto-advance to the **verify** phase scoped to this checkpoint. Print: `── verify (<checkpoint>) ──`. The user's plan approval covers this auto-advance.
- After verify+pr complete for this checkpoint, return to implement-phase for the next checkpoint (if any). When all checkpoints are done, the migration is complete.

## What you do NOT do

- **You never write code in the worktree.** No `Edit`, no `Write` to anything inside `<repo>/.worktrees/kmm-<scope>/` except the artifact files (`tasks.md`, `migration-report.md`, `findings.md`, `spec.md`). Never `commonMain`, never `androidMain`, never `commonTest`, never any consumer file.
- You never modify a baseline test post-`T-LOCK`. Only the migrated code can change to make a test pass; never the test.
- You never dispatch a subagent without its prompt file from `agents/`. The prompt is the contract.
- You never silently skip a task. If a task cannot run, escalate.
- You never start checkpoint K+1 before checkpoint K's PR is opened. Each checkpoint lands as a unit.

## Failure modes

- **Subagent emits no completion promise** — refire once with the instruction "your last response did not end with a completion promise; emit exactly one." If the second attempt also fails, treat as mechanical-blocked and apply strike rule.
- **Three strikes on a task** — escalate. Print: file, task, strike-1 reason, strike-2 reason, strike-3 reason. Ask the user how to proceed (fix it, defer the file, revise scope).
- **A migrator wants to modify a baseline test** — refuse. The subagent's output should never include `Edit` or `Write` to `commonTest/`. If it does, treat as a constitution violation, log a deviation, escalate.
- **Master moved during migration** — at implement-phase start, compare current base-branch SHA to `spec.md`'s baseline SHA. If a scope file was modified upstream, stop and force a replan: route back through architect and plan phases against the new SHA. Constitution §8 forbids silent rebasing.
- **A checkpoint is not master-mergeable at its boundary** (declared targets fail to compile in isolation, or consumers fail) — refuse to advance. Either the architect's checkpoint plan was wrong (route back to architect to widen the checkpoint) or a migrator left work undone (refire migrator).
