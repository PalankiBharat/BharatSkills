# Phase: tasks

Generates `tasks.md` from the approved plan, batched by checkpoint (Constitution §13). Plan-phase must have completed and the plan approved.

Read `constitution.md` first.

## Inputs

- `spec.md`, `architecture.md` (checkpoint plan, refactor entries), `plan.md`, `migration-guide.md`

## Steps

### 1. Read the checkpoint plan from `architecture.md`

Each checkpoint declares: name, goal, file set, kind of work (relocation / swaps / refactor / mixed). Tasks are emitted **per checkpoint, in order**. The skill executes a checkpoint to completion (capture → lock → migrate → verify → PR), merges it, then starts the next.

If the checkpoint plan is a single bundle, the structure below collapses to one set of phases run end-to-end (N=1).

### 2. Generate the ordered task list, batched by checkpoint

Use `templates/tasks.md`. Tasks grouped into checkpoints; within a checkpoint, four phases (Scaffold → Capture → Lock → Migrate).

For each checkpoint `CP-K`:

#### Phase A: Scaffold (sequential per checkpoint)

- One task per scaffolding interface from `plan.md` whose dependent files are in this checkpoint.
- Subagent: `migrator` (scaffold mode).
- `CP-K/S-1: Create <commonMain interface path> for <consumer file(s)>`

#### Phase B: Baseline capture (parallel within checkpoint)

For each in-scope file F:
- `CP-K/T-N: Capture baseline tests for <F>`
- Subagent: `test-capturer` (`mode: baseline`). Performs:
  - `git mv` F to `shared/src/androidMain/...` (mechanical, zero behaviour change).
  - Updates consumer imports to the androidMain path.
  - Writes characterization tests in `shared/src/commonTest/...` per `Expected tests` — **including behaviour-preservation tests for any Refactor entries**.
  - Runs the test command. All tests GREEN before `CAPTURE_COMPLETE`.

When a file appears in only one checkpoint (typical), capture happens once and the baseline carries across subsequent checkpoints unchanged (Constitution §8).

#### Phase B-smoke: Smoke test capture (single task per scope, after all baseline captures)

Emitted once for the whole scope (in the first checkpoint that captures), not per checkpoint:

- `CP-1/T-SMOKE: Write smoke test from architecture.md § Smoke test`
- Subagent: `test-capturer` (`mode: smoke`). Reads the smoke spec from `architecture.md`, writes the JVM smoke test (and instrumented variant if enabled), runs the JVM smoke against the staged form. Must pass before `CAPTURE_COMPLETE`.
- Depends-on: every Phase B task in this checkpoint that touches a type the smoke resolves.

#### Phase C: Baseline lock (sequential, single task per relocation checkpoint)

- `CP-K/T-LOCK: Lock baseline for <checkpoint-name>. Commit "baseline: capture <scope>/<checkpoint> @ <SHA>". Record locked SHA in spec.md.`
- Orchestrator runs this (bookkeeping, not subagent labour).
- Verifies all Phase B returned `CAPTURE_COMPLETE` and the full baseline test suite is green.
- After lock, `commonTest/` is **immutable** per Constitution §8.

Subsequent checkpoints (swaps, refactor) inherit the locked baseline.

#### Phase D: Migration (DAG-ordered, parallel within levels)

- Topologically sort the checkpoint's files using `Migrate after` from `migration-guide.md`.
- For each level L (smallest first), files in L run in parallel:
  - `CP-K/M-N: Migrate <F>`
  - Subagent: `migrator`. Applies `Diff specification` verbatim — Remove/Add/Modify for swaps, Refactor entries for restructuring. Re-runs baseline tests. All GREEN before `MIGRATE_COMPLETE`.
- Levels run sequentially: L+1 cannot start until every file in L is `MIGRATE_COMPLETE`.

#### Phase D-smoke: Re-run smoke test (single task per checkpoint, after all migrate tasks)

After every Phase D task in `CP-K` is `[x]`:

- `CP-K/SMOKE-RUN: Re-run JVM smoke test against migrated form`
- Run-by: orchestrator (gradle invocation; not a subagent).
- Command: from `architecture.md § Smoke test § JVM smoke § Gradle task`.
- If `architecture.md § Smoke test § Instrumented smoke § Status` is `enabled`, also run the instrumented gradle command.
- Both must pass before the checkpoint advances to verify-phase.
- Failure → escalate to user with the smoke test's failure output. Don't auto-refire migrators; a smoke fail post-migration usually means a Koin binding was missed in the migrated form, an `actual` is wrong, or DI module wiring drifted. Surface, don't loop.

This is the runtime gate per Constitution Verification §8 — runtime breakage introduced in CP-K is found at CP-K, not after CP-(K+1) ships.

#### Phase E: Checkpoint verify + PR (per checkpoint)

After all Phase D tasks (including SMOKE-RUN) in `CP-K` are `[x]`:
- Auto-advance to verify-phase scoped to `CP-K`.
- On `VERIFY_COMPLETE_PASS`, auto-advance to pr-phase for `CP-K`.
- Merge (or push and tell user), then return to tasks-phase for `CP-(K+1)`.

### 3. Each task carries a metadata block

```
- [ ] CP-1/T-3: Capture baseline tests for AuthRepository.kt
        checkpoint: auth-relocation
        subagent: test-capturer
        source: app/src/main/java/com/example/auth/AuthRepository.kt
        target-staging: shared/src/androidMain/kotlin/com/example/auth/AuthRepository.kt
        expected-tests: 7
        depends-on: CP-1/S-1, CP-1/S-2
```

For migrate tasks, also `path: surgical | refactor` and (when refactor) `refactor-entries: R-1, R-2`.

### 4. Sanity check

- Every in-scope file has exactly one capture task and one migrate task across all checkpoints.
- Capture tasks for a file sit before that file's checkpoint's `T-LOCK`.
- Migrate tasks sit after the file's `T-LOCK`.
- `Migrate after` constraints honoured by level grouping.
- Every file's `checkpoint:` matches `migration-guide.md`'s `Checkpoint:` field.
- Exactly one `T-SMOKE` task exists across the whole scope (in the first capture-bearing checkpoint).
- Every checkpoint that has Phase D tasks has exactly one `SMOKE-RUN` task after them.
- No out-of-scope file appears.

If any check fails, fix and re-check.

### 5. Print summary (no approval prompt when chained)

- Checkpoints in order with per-checkpoint counts (`CP-1 auth-relocation: 5 capture, 1 lock, 0 migrate`)
- Total counts (`scaffold: A, capture: B, lock: K, migrate: M, total: T`)
- DAG breakdown per checkpoint
- Path: `<repo>/kmm/<scope>/tasks.md`

If chained from `/kmm`, do not re-ask for approval — task generation is mechanical from the approved plan. In `--step` mode, ask once.

### 6. Constitution check

Touched: §6 (scope unchanged), §8 (capture-before-migrate, lock per checkpoint), §13 (batched by checkpoint), Verification §8 (smoke task gates per checkpoint).

Checklist:
- `[ ]` Every in-scope file has exactly one capture task and one migrate task
- `[ ]` Tasks batched by checkpoint, in checkpoint-plan order
- `[ ]` All scaffolding tasks within a checkpoint precede its capture tasks
- `[ ]` Each relocation checkpoint has a single `T-LOCK` between capture and migrate
- `[ ]` Migration tasks respect the DAG
- `[ ]` Refactor migrate tasks reference `architecture.md` entries via `refactor-entries:`
- `[ ]` One `T-SMOKE` task exists in the scope; one `SMOKE-RUN` per checkpoint with Phase D tasks

### 7. Auto-advance

Print `── implement ──` and advance.

## Failure modes

- **A file lacks `Migrate after` data** — route back to plan-phase.
- **A file has `path: refactor` but no `Refactor entries`** — route back to plan-phase.
- **A checkpoint contains files whose DAG dependencies span checkpoints** — route back to architect-phase.
