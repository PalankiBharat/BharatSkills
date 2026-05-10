# Phase: implement

Executes the task list. Dispatches subagents only.

Read `constitution.md` and `references/orchestration-protocol.md` first.

**You do not write code.** You read `tasks.md`, dispatch the right subagent for each task, validate completion promises, update `tasks.md`, and loop until either the active checkpoint's tasks are complete or you hit a blocker that requires user input.

When tasks are batched by checkpoint (Constitution §13), implement runs **one checkpoint at a time**. After a checkpoint's tasks return `[x]`, the orchestrator routes to verify-phase scoped to that checkpoint, then pr-phase, then back here for the next.

## Inputs

- `tasks.md`, `architecture.md`, `migration-guide.md`, `spec.md`, `findings.md`
- The worktree

## Orchestration loop

Determine the **active checkpoint**: the lowest-numbered checkpoint with at least one unchecked task. Run only tasks in that checkpoint.

### 1. Find the next runnable batch

A task is runnable when:
- Its `checkpoint:` matches the active checkpoint
- Its checkbox is `[ ]`
- All its `depends-on` tasks are `[x]`
- Its phase predecessors are complete (B can't start until A is done; T-LOCK can't run until all B is done; D level L can't start until L-1 is done)

If multiple tasks are runnable in parallel (same checkpoint, same phase, same DAG level, no shared depends-on), dispatch concurrently.

### 2. Dispatch the right subagent

Each task's metadata names the subagent. Read its prompt file from `agents/`, pass verbatim as system prompt. Pass task-specific data in the user message.

| Task type | Subagent | Model |
|---|---|---|
| Phase A: Scaffold | `migrator` (scaffold mode) | sonnet |
| Phase B: Capture | `test-capturer` (`mode: baseline`) | sonnet |
| Phase B-smoke: T-SMOKE | `test-capturer` (`mode: smoke`) | sonnet |
| Phase C: Baseline lock | (orchestrator runs this) | — |
| Phase D: Migrate | `migrator` | sonnet |
| Phase D-smoke: SMOKE-RUN | (orchestrator runs gradle directly) | — |

### 3. Validate the completion promise

Read the last line of subagent output. Map per `references/completion-promises.md`:

| Promise | Action |
|---|---|
| `CAPTURE_COMPLETE` | Mark task `[x]`. Record notes. |
| `MIGRATE_COMPLETE` | Mark task `[x]`. |
| `RESEARCH_COMPLETE` | Record finding in `findings.md`. |
| `*_BLOCKED` | Escalate to user with diagnostic. Do not silently refire — recurring mechanical failures usually mean prevention is missing upstream (architecture, plan, or scope). Surface, don't loop. |
| `REQUIRES_APPROVAL` | Dispatch `researcher` to live-source any options the subagent named. Wait for `RESEARCH_COMPLETE`. Then escalate to user with options carrying live-source citations (Constitution §4). |

When an interpretive escalation results in a scope amendment or planning gap (e.g., a missed Platform API like `System.currentTimeMillis()` surfaces during migration), log the deviation in `migration-report.md` with a **structured Closure field**:

- Missing API replacement applied: `{ type: "grep:zero", pattern: "<old-api-call>", scope: "<file>" }`
- New library swap: `{ type: "grep:zero", pattern: "<old-package>", scope: "<file>" }`
- New scaffolding interface: `{ type: "test:exists", fqn: "<class>" }` or `{ type: "binding:present", type: "<NewInterface>", module: "<DI-module>" }`
- Behaviour ratification: status `RATIFIED` directly, no closure check.

Prefer a structured type so verify-phase can auto-close.

### 4. Update `tasks.md`

- Success: `[x]`, append one-line note (test count, target path).
- Block / interpretive escalation: `[!]`, paste BLOCKED or REQUIRES_APPROVAL inline. Wait for user direction.

Commit at batch boundaries: `tasks: <phase letter> progress <X/Y>`.

### 5. Honour `T-LOCK` exactly

When all Phase B tasks of the active checkpoint are `[x]`:

1. Run the test command from `spec.md`. All baseline tests must be GREEN.
2. `git add` everything (moved files in `androidMain`, new `commonTest` files).
3. `git commit -m "baseline: capture <scope>/<checkpoint> @ <SHA>"` where `<SHA>` is `git rev-parse HEAD`.
4. Append `baseline-locked-sha: <SHA>` to `spec.md` and commit.
5. Mark `T-LOCK` as `[x]`.

After T-LOCK, **never modify any file under `commonTest/`** without an approved deviation. If a migrator subagent attempts to, abort, log deviation as `OPEN`, escalate.

### 6. Level-boundary check (after every Phase D level)

After every file in a level returns `MIGRATE_COMPLETE`:
- Run the full baseline test suite.
- Run per-target compile checks for declared shared targets.
- Any failure → escalate to user (do not auto-refire).

This catches subtle multi-file interaction bugs.

### 7. Checkpoint-boundary check (after every Phase D checkpoint)

When all Phase D tasks of the active checkpoint are `[x]`:
- Run the full baseline test suite.
- Run per-target compile commands for declared shared targets.
- Run consumer compile commands.
- **Run the smoke test (`SMOKE-RUN`).** Read the gradle command from `architecture.md § Smoke test § JVM smoke § Gradle task` and execute. If `Instrumented smoke § Status` is `enabled`, also run the instrumented gradle command. Both must pass.
- The checkpoint must be **master-mergeable** (Constitution §13): targets compile, consumers compile, smoke passes, no dependency on later checkpoints.
- Any failure → escalate. Smoke failure post-migration usually means a Koin binding was missed in the migrated form, an `actual` is wrong, or DI module wiring drifted; the user decides whether to revisit architecture, plan, or migrator output.

### 8. Gradle invocation hygiene — sequential against a single worktree

Run gradle commands sequentially against a single worktree. The Kotlin compiler daemon's `lookups.tab` cache is held open by the running daemon and cannot be safely shared across concurrent invocations. Parallel `./gradlew` calls from the same worktree silently fall back to "compile without daemon" or fail outright.

- Within a phase or level, dispatch parallel **subagents** but the gradle commands they trigger must be serialized.
- For real parallelism (e.g., Android compile + iOS compile), run with separate `--gradle-user-home` directories.
- After killing a gradle (user aborts a sweep), call `./gradlew --stop` before the next invocation.

### 9. Constitution check at end of each phase

When a phase completes (Phase A done, Phase B done, T-LOCK done, or all Phase D done within active checkpoint):

- List principles touched.
- Pass/fail:
  - `[ ]` Every dispatched subagent returned a valid completion promise
  - `[ ]` Every blocked task is logged with reason
  - `[ ]` `tasks.md` reflects current state
  - `[ ]` Phase-specific gates passed (B: tests green; T-LOCK: SHA recorded; D level: full suite green; D checkpoint: targets and consumers green)

### 10. End of checkpoint

When the active checkpoint's tasks are all `[x]`:
- Print summary: checkpoint name, tasks executed, files migrated, deviations logged.
- Auto-advance to verify-phase scoped to this checkpoint. Print: `── verify (<checkpoint>) ──`.
- After verify+pr complete, return to implement-phase for the next checkpoint. When all checkpoints are done, the migration is complete.

## Failure modes

- **Subagent emits no completion promise** — treat as `*_BLOCKED` reason `malformed-completion-promise`. Escalate.
- **A migrator wants to modify a baseline test** — refuse. Log deviation, escalate. The subagent's output should never include `Edit` or `Write` to `commonTest/`.
- **Master moved during migration** — at implement-phase start, compare current base-branch SHA to `spec.md`'s baseline SHA. If a scope file was modified upstream, stop and force a replan: route back through architect and plan against the new SHA.
- **Checkpoint is not master-mergeable at its boundary** — refuse to advance. Either the checkpoint plan was wrong (route back to architect) or a migrator left work undone (escalate).
