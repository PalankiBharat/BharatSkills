---
description: Single entry point for KMM migrations. Auto-detects state and runs the right next phase. Pauses only on real decisions (scope, deviations, REQUIRES_APPROVAL, PR confirmation per checkpoint).
argument-hint: "<scope-name?> [intent...]"
---

# /kmm

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

This is the **only** command users need for running a migration. It auto-detects the current phase from on-disk artifacts and runs the right one. Phase logic lives in `skills/kmm-migration-workflow/references/phases/`; this file routes between them.

## Phases (in order)

**Full pipeline:**

```
specify    →   architect   →   plan   →   tasks   →   implement   →   verify   →   pr
                  ↑                                       ↑              ↓         ↓
              (NEW — clean-code                   (per checkpoint loop  ──┘         ↓
              decisions, refactor              when architecture splits the migration ──┐
              boundaries, checkpoints)         into checkpoints per Constitution §13)   ↓
                                                                                    [next checkpoint
                                                                                     OR migration done]
```

**Trivial-migration fast-path** (Constitution §14 Proportionality; see `references/fast-path.md`):

```
specify    →   bundle   →   verify   →   pr
                ↑
                (architect + plan + tasks + implement
                 generated as a single auto-bundle pass,
                 reviewers in parallel, atomic-migrate inline)
```

The fast-path triggers automatically at the end of specify-phase when the trivial heuristic passes (≤3 files, 0 expect/actual, 0 cross-file refactors, 0 HIGH-risk refactors, all swaps already-declared in `gradle/libs.versions.toml`). The decision is recorded in `findings.md` and persists across `/kmm` invocations. Override with `/kmm --full-pipeline` or `/kmm --fast-path`.

## State detection (silent — no user prompt)

Decide the current phase by inspecting the worktree:

| Condition | Current phase | Phase file to read |
|---|---|---|
| User passed `<scope>`, but `<repo>/kmm/<scope>/` does not exist | Pre-spec | `references/phases/specify.md` |
| `spec.md` exists, `findings.md` does not yet record a fast-path decision | Just-spec'd, route decision pending | (evaluate trivial heuristic — see below) |
| `findings.md` records `fast-path: yes`, bundle artifacts not yet emitted | Fast-path entry | `references/fast-path.md` (bundle phase) |
| `findings.md` records `fast-path: no` (or full-pipeline override), `architecture.md` does not exist | Spec'd, not architected | `references/phases/architect.md` |
| `architecture.md` exists with `ARCHITECTURE_STATUS: APPROVED`, `plan.md` does not | Architected, not planned | `references/phases/plan.md` |
| `plan.md` exists with `PLAN_STATUS: APPROVED`, `tasks.md` does not | Planned, not tasked | `references/phases/tasks.md` |
| `tasks.md` has unchecked tasks (`[ ]`) in any checkpoint | In execution | `references/phases/implement.md` |
| Active checkpoint has all `[x]` tasks but no `verify-passed` marker | Tasks done, not verified | (verify-phase logic — see below) |
| Active checkpoint has `verify-passed`, no PR URL recorded | Verified, PR pending | `references/phases/pr.md` |
| All checkpoints have PR URLs recorded | Migration done | Print "Migration complete." and exit |

**Trivial heuristic evaluation** (run once at end of specify-phase, decision persisted in `findings.md`):

```
fast_path = (
    in_scope_files <= 3
    AND expect_actual_count == 0
    AND cross_file_refactors == 0
    AND high_risk_refactors == 0
    AND all_swap_libraries_already_declared
)
```

If `fast_path` is true, route to the bundle phase (`references/fast-path.md`) instead of architect-phase. If false, route to architect-phase as before. CLI overrides: `/kmm --full-pipeline` forces full pipeline regardless; `/kmm --fast-path` forces fast-path with the user accepting any structural surprises as logged deviations.

**Active checkpoint** = the lowest-numbered checkpoint with at least one unchecked task OR with all `[x]` but no recorded PR URL. The orchestrator runs implement → verify → pr for the active checkpoint, then loops back to detect the next active checkpoint.

If multiple `<scope>` directories exist and the user did not pass one, ask **one question** with the scopes as options + their current phase as descriptions. Recommend the most-recently-touched. Do not proceed without an answer.

## How routing works

On every `/kmm` invocation:

1. Detect the current phase via the table above.
2. Read the phase file (`references/phases/<phase>.md`) into context.
3. Execute the phase's `What you do` steps as described in the file. The phase file is authoritative — follow it precisely.
4. On phase completion, the phase file specifies what happens next (auto-advance or stop).

Phases auto-advance unless one of these is true:
- User invoked `/kmm --step` (manual mode — pause between every phase).
- A subagent emitted `REQUIRES_APPROVAL` (interpretive failure).
- An analyzer (plan-analyzer / architecture-reviewer / completeness-verifier) surfaced a user-input-required HIGH finding.
- About to run pr-phase for a checkpoint (always pause for the PR confirmation — public action).

The verify-phase logic is inline (not a separate phase file), because it's a short dispatch:
1. Dispatch `agents/completeness-verifier.md` (sonnet, read-only) with the active checkpoint name.
2. On `VERIFY_COMPLETE_PASS`: auto-close structured deviations, mark `verify-passed` for the checkpoint in tasks.md, advance to pr-phase.
3. On `VERIFY_COMPLETE_FAIL`: append `Phase E: Remediation` tasks to tasks.md, route back to implement-phase.

For the full verify-phase contract (auto-close rules, remediation-task format), see `skills/kmm-migration-workflow/references/phases/verify-inline.md`. Or the user-facing `/kmm-verify` command.

## What auto-routing DOES NOT skip

The skill always pauses for:

- The **scope intent** (only if the invocation didn't already provide concrete files; see specify-phase's goal-clarity gate).
- The **@Ignore master-failing-tests approval** in specify-phase (one `y / n / discuss`).
- The **HIGH-risk refactor approvals** in architect-phase.
- The **architecture approval** at end of architect-phase.
- The **plan approval** at end of plan-phase.
- Any **REQUIRES_APPROVAL** from a subagent.
- Any **plan-analyzer / architecture-reviewer HIGH finding** that requires user input.
- The **PR confirmation** at the end of every pr-phase (per checkpoint).

These are real decisions; they don't get auto-handled.

## What the user sees in a clean run (single-checkpoint migration)

```
$ /kmm auth-module — migrate AuthRepository, SessionStore, TokenManager, AuthApi
                     from app/src/main/java/com/example/auth/. UI and consumers
                     out of scope.

── specify ──
Targets autodetected: commonMain, androidMain, iosArm64, iosX64.
Base branch: main.
2 master-failing tests outside scope. Will @Ignore + log as D-1. Continue? [y]
> y
Spec written.

── architect ──
Reading 4 files with clean-code lens. Drafting architecture...
3 surgical, 1 refactor (1 entry: remove AuthSdkHolder — clean-code §structure.no-scaffolding-without-behaviour, LOW risk).
Single-checkpoint migration estimated.
Architecture ready. Approve? [y]
> y

── plan ──
Reading 4 files. Researching libraries. Drafting plan...
plan-analyzer: clean.
Plan ready. 4 files, 3 swaps, 1 refactor entry, 5 expect/actual. 1 RATIFIED deviation.
Approve? [y]
> y

── tasks ──
Generated 9 tasks (4 capture, 1 lock, 4 migrate).

── implement ──
Capturing baselines (4 parallel)... 32 tests green. Locked at a8d2e91f.
Migrating Level 0 (3 parallel)... Level 1 (1)... All migrations complete.

── verify (auth-module) ──
PASS. 4 files migrated, 32 tests green, 1 refactor invariant pinned.

── pr (auth-module) ──
Draft PR ready. Open it? [y / preview / discuss]
> y
✅ PR opened: https://github.com/example/repo/pull/247

Migration complete.
```

## What the user sees in a checkpointed run

When architecture splits the migration into checkpoints (Constitution §13), the loop runs once per checkpoint:

```
── architect ──
12 files: 8 surgical, 4 refactor (6 entries: 4 LOW, 2 MEDIUM). HIGH-risk: 0.
Migration size triggers checkpoint plan:
  CP-1: auth-relocation (12 files moved + baselines captured)
  CP-2: auth-swaps (4 library swaps + expect/actual)
  CP-3: auth-refactor (6 architecture-approved refactors)
Approve checkpoints? [A: as proposed / B: single PR / C: discuss]
> A
Architecture approved.

── plan ──
[plan with 12 file entries, 6 refactor entries, 3 checkpoints]
Approve? [y]
> y

── tasks ──
Generated 27 tasks across 3 checkpoints.

── implement (CP-1: auth-relocation) ──
[capture all 12, lock]

── verify (CP-1) ──
PASS.

── pr (CP-1) ──
Draft PR ready (`kmm(auth-relocation): move auth files into androidMain + capture baselines`). Open? [y]
> y
✅ CP-1 PR: https://github.com/example/repo/pull/247

── implement (CP-2: auth-swaps) ──
[apply swaps to all 12 files]

── verify (CP-2) ──
PASS.

── pr (CP-2) ──
[draft, open]
✅ CP-2 PR: https://github.com/example/repo/pull/248

── implement (CP-3: auth-refactor) ──
[apply refactors]

── verify (CP-3) ──
PASS. 6 refactor invariants pinned.

── pr (CP-3) ──
[draft, open]
✅ CP-3 PR: https://github.com/example/repo/pull/249

Migration auth-module complete: 3 PRs opened.
```

## Manual / step mode

If the user invokes `/kmm --step`, the orchestrator pauses at every phase boundary with a `[continue / abort]` prompt. The user can interleave manual edits between phases.

## Resume

`/kmm` with no args: if `<repo>/kmm/` has exactly one in-flight scope, resume it silently. If multiple are in flight, ask which to resume (one question, options labelled with phase + active checkpoint). If none and no args given, print: "No scope specified. Run `/kmm <scope>` with the migration intent."

## Other entry points

For workflows that don't fit `/kmm`'s linear flow, three independent commands stay user-invocable:

- **`/kmm-verify`** — re-run the completeness audit on a migration directory (yours or someone else's). Useful after manual edits, after a merge, or when the user wants a fresh check without re-running the whole pipeline.
- **`/kmm-audit <pr>`** — read-only principles audit of any KMM migration PR (whether made with this skill or not). Returns a table of findings; on user opt-in, posts inline GitHub comments. Distinct from verify (which checks completeness against the skill's artifacts).
- **`/kmm-retro`** — re-run the skill retrospective on a completed (or in-flight) migration. Useful for capturing skill-improvement signals after manual mid-flight edits.

These commands run independently — they don't auto-chain into the migration pipeline.

## Constitution check

`/kmm` itself does not run a constitution-check — each phase runs its own. `/kmm`'s job is routing, not enforcement.

## Failure modes

- **Scope already exists with same name** — read its phase. If in-flight, resume. If complete (every checkpoint has a PR URL), tell the user; ask whether to start a new scope (different name) or revisit the existing one.
- **State detection is ambiguous** (e.g., tasks.md shows in-progress but worktree is on a different branch) — escalate to user with a one-question state summary; do not auto-pick.
- **The user passed `<scope>` but provided no intent** and no spec.md exists yet — proceed to specify-phase's goal-clarity gate, which will ask. Don't guess.
- **An expected phase file is missing** (e.g., `references/phases/architect.md` not present) — surface the error; the skill installation is broken.
