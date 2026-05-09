# Phase: tasks

Read by the `/kmm` orchestrator when state-detection routes to the **tasks** phase. Generates the ordered task list (tasks.md) from the approved plan, **batched by checkpoint** (Constitution §13).

Plan-phase must have completed and the plan approved (`plan.md` exists with `PLAN_STATUS: APPROVED`). If not, route back to the plan phase.

Read `skills/kmm-migration-workflow/constitution.md` first.

## Inputs

- `<repo>/kmm/<scope>/spec.md`
- `<repo>/kmm/<scope>/architecture.md` — checkpoint plan, refactor entries
- `<repo>/kmm/<scope>/plan.md`
- `<repo>/kmm/<scope>/migration-guide.md`

## What you do

### 1. Read the checkpoint plan from `architecture.md`.

The architect phase produced a checkpoint plan (Constitution §13). Each checkpoint declares:
- A name (e.g., `auth-relocation`, `auth-swaps`, `auth-refactor`)
- A goal (one line)
- The set of files included
- The kind of work in this checkpoint (relocation only / swaps / refactor / mixed)

Tasks below are emitted **per checkpoint, in order**. The skill executes a checkpoint to completion (capture → lock → migrate → verify → PR), merges it, then starts the next checkpoint. Each checkpoint is master-mergeable on its own.

If the checkpoint plan is a single bundle, the structure below collapses to one set of phases run end-to-end — the multi-checkpoint logic still applies, just with N=1.

### 2. Generate the ordered task list, batched by checkpoint.

Use `templates/tasks.md`. Tasks are grouped into checkpoints; within a checkpoint, into four phases (Scaffold → Capture → Lock → Migrate).

For each checkpoint `CP-K` in checkpoint-plan order:

#### Phase A: Scaffold (sequential, per checkpoint when applicable)

- One task per required scaffolding interface from `plan.md` whose dependent files are in this checkpoint.
- Subagent: `migrator` (in scaffolding mode — see `agents/migrator.md`).
- Format: `CP-K/S-1: Create <commonMain interface path> for <consumer file(s)>`
- All scaffolding for the checkpoint completes before any capture begins in that checkpoint.

#### Phase B: Baseline capture (parallel across files in the checkpoint)

- For each in-scope file F in this checkpoint (one task per file, all parallelizable within the checkpoint):
  - `CP-K/T-N: Capture baseline tests for <F>`
- Subagent: `test-capturer`. The subagent:
  - `git mv` F from its current Android path to `shared/src/androidMain/...` (package-only update, mechanical, zero behaviour change).
  - Updates consumer imports to the new androidMain path.
  - Writes characterization tests in `shared/src/commonTest/...` per the `Expected tests` field of F's migration-guide entry — including the **behaviour-preservation tests** for any Refactor entries on F.
  - Runs the test command from `spec.md`. All baseline tests must be GREEN before the subagent returns `CAPTURE_COMPLETE`.

Capture is per-checkpoint when checkpoints overlap files (rare — usually each file appears in exactly one checkpoint, the relocation one). When a file appears in only one checkpoint (the typical case), capture is done once in that checkpoint and the baseline tests carry across subsequent checkpoints unchanged (Constitution §8 — baseline immutable post-lock).

#### Phase C: Baseline lock (sequential, single task per checkpoint that does relocation)

- `CP-K/T-LOCK: Lock baseline for <checkpoint-name>. Commit "baseline: capture <scope>/<checkpoint> @ <SHA>". Record locked SHA in spec.md.`
- Orchestrator runs this task; verifies all Phase B tasks returned `CAPTURE_COMPLETE` and the full baseline test suite is green.
- After lock, the baseline is **immutable** per Constitution §8. No `commonTest` file may be modified without a user-approved deviation.

Subsequent checkpoints (swaps, refactor) inherit the same locked baseline — they don't re-capture, they only verify the baseline still passes against the new code state.

#### Phase D: Migration (DAG-ordered, parallel within levels)

- Topologically sort the checkpoint's in-scope files using `Migrate after` from `migration-guide.md`. Group into levels.
- For each level L (smallest level first):
  - For each file F in L (parallel within the level):
    - `CP-K/M-N: Migrate <F>`
  - Subagent: `migrator`. The subagent applies the file's `Diff specification` verbatim — Remove/Add/Modify entries for swaps/platform-APIs, **Refactor entries** for architecture-approved restructuring. Re-runs the baseline tests (already in `commonTest`). All tests must be GREEN before `MIGRATE_COMPLETE`.
  - After every parallel batch in a level completes:
    - Dispatch `structural-verifier` (haiku, read-only) per file. Returns `VERIFY_PASS` or `VERIFY_FAIL` with violations.
    - Any `VERIFY_FAIL` re-dispatches `migrator` with the violation list. Three strikes → escalate.
- Levels run sequentially: level L+1 cannot start until every file in level L is `MIGRATE_COMPLETE` and `VERIFY_PASS`.

#### Phase E: Checkpoint verify + PR (per checkpoint)

After all Phase D tasks in `CP-K` are `[x]`:
- Implement-phase auto-advances to verify-phase for `CP-K`. The completeness-verifier runs scoped to `CP-K`'s file set.
- On `VERIFY_COMPLETE_PASS`, auto-advance to pr-phase for `CP-K`. User confirms the per-checkpoint PR draft.
- Merge (or push and tell user to merge), then return to tasks-phase for `CP-(K+1)`.

This per-checkpoint verify+PR cycle is the heart of Constitution §13 — each checkpoint lands on master independently, reviewable in minutes.

### 3. Each task carries a metadata block.

Each task line is followed by indented metadata that the orchestrator reads at implement-phase time:

```
- [ ] CP-1/T-3: Capture baseline tests for AuthRepository.kt
        checkpoint: auth-relocation
        subagent: test-capturer
        source: app/src/main/java/com/example/auth/AuthRepository.kt
        target-staging: shared/src/androidMain/kotlin/com/example/auth/AuthRepository.kt
        expected-tests: 7
        depends-on: CP-1/S-1, CP-1/S-2  (any scaffolding interfaces this file's tests need)
```

For migrate tasks, also record `path: surgical | refactor` and (when `path: refactor`) `refactor-entries: R-1, R-2` referencing the architecture entries.

The format is plain markdown so it can be diffed and reviewed; the orchestrator parses lines starting with `checkpoint:`, `subagent:`, `source:`, etc.

### 4. Sanity-check the task list.

- Every in-scope file has exactly one capture task and exactly one migrate task across all checkpoints (Constitution process discipline: one file = two tasks).
- Capture tasks for a file sit before that file's checkpoint's `T-LOCK`.
- Migrate tasks sit after their checkpoint's `T-LOCK` (or after a prior checkpoint's `T-LOCK` if this checkpoint inherits the baseline).
- `Migrate after` constraints are honoured by the level grouping within each checkpoint.
- Every file's `checkpoint:` metadata matches its assignment in `migration-guide.md`'s `Checkpoint:` field.
- No out-of-scope file appears.

If any check fails, fix the task list and re-check before presenting.

### 5. Print the task list summary (no approval prompt when chained)

Print a one-block summary:
- Checkpoints in order with per-checkpoint counts (`CP-1 auth-relocation: 5 capture, 1 lock, 0 migrate`)
- Total counts across checkpoints (`scaffold: A, capture: B, lock: K (one per relocation checkpoint), migrate: M, total: T`)
- DAG breakdown per checkpoint (`Level 0: N files, Level 1: N, ...`)
- Path to full file: `<repo>/kmm/<scope>/tasks.md`

If reached via the `/kmm` chain (the user's plan approval covers it), do NOT ask for approval again — task generation is mechanical from an approved plan.

In `--step` mode, ask once: `[y / step / discuss]`.

### 6. Constitution check.

- Touched: §6 (scope unchanged), §8 (capture-before-migrate, lock task explicit per checkpoint), §13 (tasks batched by checkpoint), process discipline (one file = two tasks).
- Pass/fail:
  - `[ ]` Every in-scope file has exactly one capture task and one migrate task
  - `[ ]` Tasks are batched by checkpoint, in checkpoint-plan order
  - `[ ]` All scaffolding tasks within a checkpoint precede its capture tasks
  - `[ ]` Each relocation checkpoint has a single `T-LOCK` between capture and migrate
  - `[ ]` Migration tasks respect the DAG (`Migrate after` constraints)
  - `[ ]` Refactor migrate tasks reference `architecture.md` entries via `refactor-entries:`
- On fail: STOP. Report which checks failed.

### 7. Auto-advance to implement phase

Auto-advance to the **implement** phase. Print: `── implement ──`.

In `--step` mode, stop and print: "Tasks generated. Re-run `/kmm` to begin implementation."

## What you do NOT do

- Do not start dispatching subagents. That is the implement phase.
- Do not modify `migration-guide.md`, `plan.md`, or `architecture.md`. If the task list reveals a plan flaw, surface it and route the orchestrator back to the plan phase.
- Do not collapse checkpoint boundaries. If checkpoints exist in the plan, tasks ship as checkpoints.

## Failure modes

- **A file lacks `Migrate after` data in `migration-guide.md`** — stop, route back to plan phase.
- **A file has `path: refactor` but no `Refactor entries`** — stop, route back to plan phase to either add the entries or change the path to `surgical`.
- **A checkpoint contains files whose DAG dependencies span checkpoints** — stop, route back to architect phase to either widen the checkpoint or move dependencies forward.
- **DAG produces only a single level within a checkpoint** — fine if no files depend on each other; just confirm with the user.
