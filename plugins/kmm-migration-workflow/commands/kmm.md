---
description: Single entry point for KMM migrations. Auto-detects state and runs the right next phase. Pauses only on real decisions (scope, deviations, REQUIRES_APPROVAL, PR confirmation). Default mode for the whole skill.
argument-hint: "<scope-name?> [intent...]"
---

# /kmm

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

This is the **comfy default**. Most users never touch the named `/kmm-*` commands; they live here. The job of `/kmm` is to detect where the user is in the workflow and run the right next phase, pausing only when a real decision is needed.

## State detection (silent — no user prompt)

Decide the current phase by inspecting the worktree:

| Condition | Current phase | Next action |
|---|---|---|
| User passed `<scope-name>`, but `<repo>/kmm/<scope>/` does not exist | Pre-spec | Run `/kmm-specify` |
| `<repo>/kmm/<scope>/spec.md` exists, but `plan.md` does not | Spec'd, not planned | Run `/kmm-plan` |
| `plan.md` exists, but `tasks.md` does not | Planned, not tasked | Run `/kmm-tasks` |
| `tasks.md` has unchecked tasks (`[ ]`) | In execution | Run `/kmm-implement` |
| All tasks `[x]`, but last constitution-check entry is not `/kmm-verify: PASS` | Done, not verified | Run `/kmm-verify` |
| Verify PASS, no PR open for the branch | Verified, PR pending | Run `/kmm-pr` |
| PR open and merged | Done | Print "Migration complete." and exit |

If multiple `<scope>` directories exist and the user did not pass one, ask **one question** with the scopes as options + their current phase as descriptions. Recommend the most-recently-touched. Do not proceed without an answer.

## Auto-chain (the comfy mode) with one /clear boundary

The pipeline runs in **two sessions** separated by a recommended `/clear`:

```
Session 1 (planning):
  /kmm-specify  →  /kmm-plan
                     └── ends with "Approved. Run /clear then /kmm."

[user runs /clear]

Session 2 (execution):
  /kmm  (auto-detects state: plan.md present, tasks.md absent)
    →  /kmm-tasks  →  /kmm-implement  →  /kmm-verify  →  /kmm-pr
```

In each session, the auto-chain advances between phases unless one of these is true:

1. The user invoked `/kmm --step` (manual mode — pause between every phase).
2. A subagent emitted `REQUIRES_APPROVAL` (interpretive failure — must escalate to user).
3. The plan-analyzer surfaced a user-input-required HIGH finding (scope amendment, ambiguous decision).
4. We're about to run `/kmm-pr` (always pause for the final PR confirmation — public action).
5. **End of `/kmm-plan`** — always pause and instruct the user to `/clear`. Planning fills context; execution should start fresh.

In auto-chain, do NOT print "approve and continue?" between phases inside a session. The single approval at end of `/kmm-specify` is the green light for the planning session; the single approval at end of `/kmm-plan` is the green light for the execution session.

Print only one-line phase banners (`── /kmm-plan ──`) at each transition. Everything else stays terse per the orchestration protocol's communication-style rule.

## What auto-chain DOES NOT skip

The skill always pauses for:

- The **scope intent** (only if the invocation didn't already provide concrete files; see `/kmm-specify`'s goal-clarity gate).
- The **@Ignore master-failing-tests approval** in `/kmm-specify` (one `y / n / discuss`).
- Any **REQUIRES_APPROVAL** from a subagent.
- Any **plan-analyzer HIGH finding** that requires user input (scope amendment, library-choice ambiguity).
- The **PR confirmation** at the end of `/kmm-pr`.

These are real decisions; they don't get auto-handled.

## What the user sees in a clean run

```
$ /kmm auth-module — migrate AuthRepository, SessionStore, TokenManager, AuthApi
                     from app/src/main/java/com/example/auth/. UI and consumers
                     out of scope.

── /kmm-specify ──
Targets autodetected: commonMain, androidMain, iosArm64, iosX64.
Base branch: main.
2 master-failing tests outside scope. Will @Ignore + log as D-1. Continue? [y / n / discuss]
> y
Spec written.

── /kmm-plan ──
Reading 4 files. Researching libraries. Drafting plan...
plan-analyzer: 1 user gate.
  → User.kt is referenced by AuthApi but not in scope. Recommended: add to scope (Constitution §5). [y / discuss]
> y
Plan ready. 5 files, 5 swaps. 1 RATIFIED deviation.

── /kmm-tasks ──
Generated 11 tasks (5 capture, 1 lock, 5 migrate).

── /kmm-implement ──
Capturing baselines (5 parallel)... 35 tests green. Locked at a8d2e91f.
Migrating Level 0 (3 parallel)... Level 1 (1)... Level 2 (1)...
  → <File>:<line> — <API> not in plan (planning gap). Recommended: <multiplatform replacement> per Constitution platform-boundary §1. [y / discuss]
> y
All migrations complete.

── /kmm-verify ──
Round 1: 1 false-positive (residual android.util.Log import in AuthRepository).
Auto-fix dispatched. Re-verifying...
PASS. 5 files migrated, 35 tests green, 3 deviations all closed/ratified.

── /kmm-pr ──
Draft PR ready (open <repo>/kmm/auth-module/pr-draft.md to inspect). Open it?  [y / preview / discuss]
> y
✅ PR opened: https://github.com/example/repo/pull/247
```

Four user touches: scope @Ignore, scope amendment, planning-gap fix, PR open.

## Manual / step mode

If the user invokes `/kmm --step`, the skill pauses at every phase boundary with a `[continue / abort]` prompt. The named `/kmm-*` commands also continue to work for users who want to invoke a specific phase.

## Resume

If the user runs `/kmm` with no args and `<repo>/kmm/` has exactly one in-flight scope, resume it silently. If multiple scopes are in flight, ask which to resume (one question, options labelled with phase). If no scopes exist and no args given, print: "No scope specified. Run `/kmm <scope>` with the migration intent, e.g., `/kmm auth-module — migrate the auth feature's data layer`."

## Constitution check

`/kmm` itself does not run a constitution-check — each child phase runs its own. `/kmm`'s job is routing, not enforcement.

## Failure modes

- **Scope already exists with same name** — read its phase. If in-flight, resume. If complete (PR open or merged), tell the user; ask whether to start a new scope (different name) or revisit the existing one.
- **State detection is ambiguous** (e.g., tasks.md shows in-progress but worktree is on a different branch) — escalate to user with a one-question state summary; do not auto-pick.
- **The user passed `<scope>` but provided no intent** and no spec.md exists yet — proceed to `/kmm-specify`'s goal-clarity gate, which will ask. Don't guess.
