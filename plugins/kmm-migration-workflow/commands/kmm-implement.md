---
description: Execute the task list. Opus dispatches subagents only — never writes labour code itself. Mechanical failures refire (max 3); interpretive failures escalate to user.
---

# /kmm-implement

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` and `skills/kmm-migration-workflow/references/orchestration-protocol.md` first.

This is the labour phase. **You do not write code.** You read `tasks.md`, dispatch the right subagent for each task, validate completion promises, update `tasks.md`, and loop until either all tasks are complete or you hit a blocker that requires user input.

## Inputs

- `<repo>/kmm/<scope>/tasks.md` — the ordered task list with subagent metadata
- `<repo>/kmm/<scope>/migration-guide.md` — per-file specs the agents read directly
- `<repo>/kmm/<scope>/spec.md` — declared targets, baseline SHA, test command
- `<repo>/kmm/<scope>/findings.md` — research, version pins
- `<repo>/.worktrees/kmm-<scope>/` — the working tree

## Orchestration loop

Repeat until `tasks.md` has no unchecked tasks **or** you escalate to the user:

### 1. Read `tasks.md`. Find the next runnable batch.

A task is runnable when:
- Its checkbox is `[ ]`
- All its `depends-on` tasks are `[x]`
- Its phase predecessors are complete (Phase B cannot start until Phase A is done; `T-LOCK` cannot run until all Phase B tasks are done; Phase D level L cannot start until level L-1 is done)

If multiple tasks are runnable in parallel (same phase, same DAG level, no shared depends-on), dispatch them concurrently. Otherwise dispatch one at a time.

### 2. Dispatch the right subagent.

Each task's metadata block specifies the subagent. Read the agent's prompt file from `agents/` and pass it as the system prompt for the subagent. Pass the task-specific data (source path, target path, expected test count, etc.) in the user message.

| Task type | Subagent | Model |
|---|---|---|
| Phase A: Scaffold | `migrator` (scaffold mode) | sonnet |
| Phase B: Capture | `test-capturer` | sonnet |
| Phase C: Baseline lock | (orchestrator runs this — not a subagent) | — |
| Phase D: Migrate | `migrator` | sonnet |
| After every Phase D file | `structural-verifier` | haiku |

The orchestrator (you) runs `T-LOCK` because it is bookkeeping (commit + record SHA), not labour. See `/kmm-tasks` for the lock procedure.

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

A `*_BLOCKED` is **interpretive** if the reason matches: `ambiguous behaviour`, `scope expansion`, `signature change required`, `behaviour change required`, `cannot reach 1:1 port`, `dependency without multiplatform replacement`, `decision required`. The orchestrator escalates to the user immediately with the full context — no retries.

If unsure, default to **interpretive** (escalate). Burning retries on questions only the user can answer is wasteful.

Strike count is per task, per subagent type. Reset when the task transitions to `[x]`.

When an interpretive escalation results in a scope amendment or a planning gap (e.g., a missed Platform API like `System.currentTimeMillis()` surfaces during migration), log the deviation in `migration-report.md` with a **structured Closure field**. Pick the type that matches the fix:

- Missing API replacement applied: `{ type: "grep:zero", pattern: "<old-api-call>", scope: "<migrated-file-path>" }`
- New library swap added: `{ type: "grep:zero", pattern: "<old-package>", scope: "<file-path>" }`
- New scaffolding interface added: `{ type: "test:exists", fqn: "<file-path-or-class>" }` or `{ type: "binding:present", type: "<NewInterface>", module: "<DI-module>" }`
- Behaviour ratification (user accepted a permanent change): set status `RATIFIED` directly, no closure check.

`manual` is the fallback when none of the above fit — but prefer a structured type whenever possible so `/kmm-verify` can auto-close.

### 5. Update `tasks.md` after every subagent run.

- On success: mark the checkbox `[x]`, add a one-line note with the subagent's relevant output (e.g., test count, target path).
- On mechanical retry: keep the checkbox `[ ]`, increment the strike counter in the metadata.
- On interpretive escalation: mark the checkbox with `[!]` (blocked-on-user), append the REQUIRES_APPROVAL text inline.

Commit `tasks.md` after every batch boundary (not after every single task — that would be noisy). The commit message: `tasks: <phase letter> progress <X/Y>`.

### 6. Honour `T-LOCK` exactly.

When all Phase B tasks are `[x]`:

1. Run the test command from `spec.md` against the worktree. All baseline tests must be GREEN.
2. `git add` everything in the worktree (including the moved files in `androidMain` and the new `commonTest` files).
3. `git commit -m "baseline: capture <scope> @ <SHA>"` where `<SHA>` is `git rev-parse HEAD`.
4. Append `baseline-locked-sha: <SHA>` to `spec.md` and commit.
5. Mark `T-LOCK` as `[x]`.

After `T-LOCK`, **never modify any file under `commonTest/`** without an approved deviation. If a migrator subagent attempts to modify a baseline test, abort the migration for that file, log the deviation as `OPEN`, and escalate to the user.

### 7. After every Phase D level, run the level-boundary check.

After every file in a level returns `MIGRATE_COMPLETE` and `VERIFY_PASS`:
- Run the full baseline test suite against the worktree (test command from `spec.md`).
- Run a per-target compile check for declared shared targets (commands from `plan.md`'s verification section).
- If any check fails, refire the relevant `migrator` for the file responsible. Strike counter applies.

This catches subtle multi-file interaction bugs before advancing to the next level.

### 8. Constitution check at the end of each phase.

When a phase completes (all Phase A tasks done, or all Phase B done, or `T-LOCK` done, or all Phase D done):

- List which principles were touched in this phase.
- Pass/fail:
  - `[ ]` Every dispatched subagent returned a valid completion promise
  - `[ ]` Every blocked task is logged with reason and strike count
  - `[ ]` `tasks.md` reflects current state
  - `[ ]` Phase-specific gates passed (Phase B: all tests green; T-LOCK: SHA recorded; Phase D level: full suite green)
- On fail: STOP. Report which checks failed.

### 9. End of `/kmm-implement`.

When all tasks are `[x]`:
- Print summary: tasks executed, files migrated, deviations logged.
- If reached via the `/kmm` chain, advance automatically to `/kmm-verify`. Print: `── /kmm-verify ──`. Do not prompt — the user's plan approval covered this.
- If invoked directly (manual mode), tell the user: "All tasks complete. Run `/kmm-verify` for the completeness audit before opening the PR." and stop.

## What you do NOT do

- **You never write code in the worktree.** No `Edit`, no `Write` to anything inside `<repo>/.worktrees/kmm-<scope>/` except the artifact files (`tasks.md`, `migration-report.md`, `findings.md`, `spec.md`). Never `commonMain`, never `androidMain`, never `commonTest`, never any consumer file.
- You never modify a baseline test post-`T-LOCK`. Only the migrated code can change to make a test pass; never the test.
- You never dispatch a subagent without its prompt file from `agents/`. The prompt is the contract.
- You never silently skip a task. If a task cannot run, escalate.

## Failure modes

- **Subagent emits no completion promise** — refire once with the instruction "your last response did not end with a completion promise; emit exactly one." If the second attempt also fails, treat as mechanical-blocked and apply strike rule.
- **Three strikes on a task** — escalate. Print: file, task, strike-1 reason, strike-2 reason, strike-3 reason. Ask the user how to proceed (fix it, defer the file, revise scope).
- **A migrator wants to modify a baseline test** — refuse. The subagent's output should never include `Edit` or `Write` to `commonTest/`. If it does, treat as a constitution violation, log a deviation, escalate.
- **Master moved during migration** — at `/kmm-implement` start, compare current base-branch SHA to `spec.md`'s baseline SHA. If a scope file was modified upstream, stop and force a replan: re-run `/kmm-plan` and `/kmm-tasks` against the new SHA. Constitution §7 forbids silent rebasing.
