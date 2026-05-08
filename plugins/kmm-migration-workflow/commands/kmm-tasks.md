---
description: Generate the ordered task list (tasks.md) from the approved plan. Tasks are scaffold → capture (parallel) → baseline-lock → migrate (DAG-ordered).
---

# /kmm-tasks

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

`/kmm-plan` must have completed and the user must have approved the plan before this command runs. If `plan.md` does not exist or the user has not approved, stop and tell the user to run `/kmm-plan` first.

## Inputs

- `<repo>/kmm/<scope>/spec.md`
- `<repo>/kmm/<scope>/plan.md`
- `<repo>/kmm/<scope>/migration-guide.md`

## What you do

### 1. Generate the ordered task list.

Use `templates/tasks.md`. Tasks are grouped into four phases. Within a phase, tasks may be parallelizable as noted.

#### Phase A: Scaffold (sequential)

- One task per required scaffolding interface from `plan.md`.
- Subagent: `migrator` (in scaffolding mode — see `agents/migrator.md`).
- Format:
  - `S-1: Create <commonMain interface path> for <consumer file(s)>`
- All scaffolding completes before any capture begins. Reason: `commonTest` cannot compile without the interfaces in place.

#### Phase B: Baseline capture (parallel across files)

- For each in-scope file F (one task per file, all parallelizable):
  - `T-N: Capture baseline tests for <F>`
- Subagent: `test-capturer`. The subagent:
  - `git mv` F from its current Android path to `shared/src/androidMain/...` (package-only update, mechanical, zero behaviour change per Constitution §6).
  - Updates consumer imports to the new androidMain path.
  - Writes characterization tests in `shared/src/commonTest/...` per the `Expected tests` field of F's migration-guide entry.
  - Runs the test command from `spec.md`. All baseline tests must be GREEN before the subagent returns `CAPTURE_COMPLETE`.
- Tasks are parallelizable because each operates on a different file.

#### Phase C: Baseline lock (sequential, single task)

- `T-LOCK: Lock baseline. Commit "baseline: capture <scope> @ <SHA>". Record locked SHA in spec.md.`
- This task runs after **all** Phase B tasks complete.
- The orchestrator (you) runs this task — not a subagent — because it is bookkeeping, not labour.
  - Verify all Phase B tasks returned `CAPTURE_COMPLETE`.
  - Verify the full baseline test suite is green (run the test command from `spec.md` once more for safety).
  - `git add` and `git commit -m "baseline: capture <scope> @ <SHA>"`.
  - Append the locked-baseline SHA to `spec.md` under `baseline-locked-sha:`.
- After this task, the baseline is **immutable** per Constitution §7. No `commonTest` file may be modified without a user-approved deviation.

#### Phase D: Migration (DAG-ordered, parallel within levels)

- Topologically sort in-scope files using `Migrate after` from `migration-guide.md`. Group into levels.
- For each level L (smallest level first):
  - For each file F in L (parallel within the level):
    - `M-N: Migrate <F>`
  - Subagent: `migrator`. The subagent:
    - Moves F from `androidMain` to `commonMain` with library swaps and `expect`/`actual` per the migration-guide entry.
    - Re-runs the same baseline tests (which already exist in `commonTest`).
    - All tests must be GREEN. Subagent returns `MIGRATE_COMPLETE` only after a green test run.
  - After every parallel batch in a level completes:
    - Dispatch `structural-verifier` (haiku, read-only) per file in the batch — it diffs the migrated file against the staged-androidMain version recorded at capture time. Returns `VERIFY_PASS` or `VERIFY_FAIL` with violations.
    - Any `VERIFY_FAIL` re-dispatches `migrator` for that file with the violation list. Three strikes → escalate.
- Levels run sequentially: level L+1 cannot start until every file in level L is `MIGRATE_COMPLETE` and `VERIFY_PASS`.

### 2. Each task carries a metadata block.

Each task line is followed by indented metadata that the orchestrator reads at `/kmm-implement` time:

```
- [ ] T-3: Capture baseline tests for AuthRepository.kt
        subagent: test-capturer
        source: app/src/main/java/com/example/auth/AuthRepository.kt
        target-staging: shared/src/androidMain/kotlin/com/example/auth/AuthRepository.kt
        expected-tests: 7
        depends-on: S-1, S-2  (any scaffolding interfaces this file's tests need)
```

The format is plain markdown so it can be diffed and reviewed; the orchestrator parses lines starting with `subagent:`, `source:`, `target:`, etc.

### 3. Sanity-check the task list.

- Every in-scope file has exactly one capture task and exactly one migrate task (Constitution process discipline: one file = two tasks).
- Capture tasks all sit before `T-LOCK`.
- Migrate tasks all sit after `T-LOCK`.
- `Migrate after` constraints are honoured by the level grouping.
- No out-of-scope file appears.

If any check fails, fix the task list and re-check before presenting.

### 4. Print the task list summary (no approval prompt when chained)

Print a one-block summary:
- Total counts (`scaffold: A, capture: B, lock: 1, migrate: M, total: T`)
- DAG breakdown (`Level 0: N files, Level 1: N, ...`)
- Path to full file: `<repo>/kmm/<scope>/tasks.md`

If `/kmm-tasks` was reached via the `/kmm` chain (the user's plan approval covers it), do NOT ask for approval again — task generation is mechanical from an approved plan; there's no real decision here.

If `/kmm-tasks` was invoked directly, ask once: `[y / step / discuss]`. `y` means "proceed to `/kmm-implement` and auto-chain through verify."

### 5. Constitution check.

- Touched: §5 (scope unchanged), §7 (capture-before-migrate, lock task explicit), process discipline (one file = two tasks).
- Pass/fail:
  - `[ ]` Every in-scope file has exactly one capture task and one migrate task
  - `[ ]` All scaffolding tasks precede capture tasks
  - `[ ]` `T-LOCK` is single-instance and sits between capture and migrate
  - `[ ]` Migration tasks respect the DAG (`Migrate after` constraints)
- On fail: STOP. Report which checks failed.

### 6. Auto-advance (default) or stop (manual mode)

If reached via the `/kmm` chain, advance automatically to `/kmm-implement`. Print: `── /kmm-implement ──`.

If invoked directly and the user picked `y` in step 4, advance. Otherwise stop and tell the user: "Tasks generated. Run `/kmm-implement` to begin."

## What you do NOT do

- Do not start dispatching subagents. That is `/kmm-implement`.
- Do not modify `migration-guide.md` or `plan.md`. If the task list reveals a plan flaw, surface it and stop; the user runs `/kmm-plan` again to fix.

## Failure modes

- **A file lacks `Migrate after` data in `migration-guide.md`** — stop, run `/kmm-plan` again to fix the gap.
- **DAG produces only a single level** — that's fine if no files depend on each other; just confirm with the user.
