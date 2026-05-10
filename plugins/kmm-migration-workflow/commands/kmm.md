---
description: Single entry point for KMM migrations. Auto-detects state and runs the right next phase. Pauses only on real decisions (scope, deviations, REQUIRES_APPROVAL, PR confirmation per checkpoint).
argument-hint: "<scope-name?> [intent...]"
---

# /kmm

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

This is the **only** command users need for running a migration. It auto-detects the current phase from on-disk artifacts and runs the right one. Phase logic lives in `skills/kmm-migration-workflow/references/phases/`.

## Phases

**Full pipeline:**
```
specify → architect → plan → tasks → implement → verify → pr
                                       ↑              ↓     ↓
                                       (per checkpoint loop when architecture
                                        splits the migration into checkpoints
                                        per Constitution §13)
                                                                [next checkpoint
                                                                 OR migration done]
```

**Trivial-migration fast-path** (Constitution §14; see `references/fast-path.md`):
```
specify → bundle → verify → pr
            ↑
            (architect + plan + tasks + implement
             generated as a single auto-bundle pass)
```

The fast-path triggers automatically at the end of specify-phase when the trivial heuristic passes (≤3 files, 0 expect/actual, 0 cross-file refactors, 0 HIGH-risk refactors, all swaps already-declared in `gradle/libs.versions.toml`). Override with `/kmm --full-pipeline` or `/kmm --fast-path`.

## State detection (silent)

| Condition | Current phase | Phase file |
|---|---|---|
| User passed `<scope>`, but `<repo>/kmm/<scope>/` does not exist | Pre-spec | `references/phases/specify.md` |
| `spec.md` exists, `findings.md` does not yet record a fast-path decision | Just-spec'd | (evaluate trivial heuristic) |
| `findings.md` records `fast-path: yes`, bundle artifacts not yet emitted | Fast-path entry | `references/fast-path.md` |
| `findings.md` records `fast-path: no` (or full-pipeline override), `architecture.md` does not exist | Spec'd, not architected | `references/phases/architect.md` |
| `architecture.md` exists with `ARCHITECTURE_STATUS: APPROVED`, `plan.md` does not | Architected, not planned | `references/phases/plan.md` |
| `plan.md` exists with `PLAN_STATUS: APPROVED`, `tasks.md` does not | Planned, not tasked | `references/phases/tasks.md` |
| `tasks.md` has unchecked tasks (`[ ]`) in any checkpoint | In execution | `references/phases/implement.md` |
| Active checkpoint has all `[x]` tasks but no `verify-passed` marker | Tasks done, not verified | (verify-phase logic — below) |
| Active checkpoint has `verify-passed`, no PR URL recorded | Verified, PR pending | `references/phases/pr.md` |
| All checkpoints have PR URLs recorded | Migration done | Print "Migration complete." and exit |

**Trivial heuristic** (run once at end of specify-phase, decision persisted in `findings.md`):

```
fast_path = (
    in_scope_files <= 3
    AND expect_actual_count == 0
    AND cross_file_refactors == 0
    AND high_risk_refactors == 0
    AND all_swap_libraries_already_declared
)
```

If true, route to `references/fast-path.md`. Else route to architect-phase.

**Active checkpoint** = the lowest-numbered checkpoint with at least one unchecked task OR with all `[x]` but no recorded PR URL. The orchestrator runs implement → verify → pr for the active checkpoint, then loops back to detect the next.

If multiple `<scope>` directories exist and the user did not pass one, ask **one question** with the scopes as options + their current phase as descriptions. Recommend the most-recently-touched.

## Routing

On every `/kmm` invocation:

1. Detect the current phase via the table above.
2. Read the phase file into context.
3. Execute the phase's `Steps` as described.
4. On phase completion, the phase file specifies what happens next (auto-advance or stop).

Phases auto-advance unless one of these is true:
- User invoked `/kmm --step` (manual mode).
- A subagent emitted `REQUIRES_APPROVAL`.
- An analyzer surfaced a user-input-required HIGH finding.
- About to run pr-phase (always pause for PR confirmation — public action).

## Verify-phase (inline)

Verify is a short dispatch:
1. Dispatch `agents/completeness-verifier.md` (sonnet, read-only) with the active checkpoint name.
2. On `VERIFY_COMPLETE_PASS`: auto-close structured deviations (per `commands/kmm-verify.md`), mark `verify-passed` for the checkpoint in tasks.md, advance to pr-phase.
3. On `VERIFY_COMPLETE_FAIL`: escalate to user with the gap list. Do not auto-generate remediation tasks. A fail at this point usually means the architecture or plan missed something — surface, don't loop.

## What auto-routing DOES NOT skip

The skill always pauses for:

- **Scope intent** (only if invocation didn't already provide concrete files).
- **@Ignore master-failing-tests approval** in specify-phase.
- **HIGH-risk refactor approvals** in architect-phase.
- **Architecture approval** at end of architect-phase.
- **Plan approval** at end of plan-phase.
- Any **REQUIRES_APPROVAL** from a subagent.
- Any **architecture-reviewer HIGH finding** that requires user input.
- **PR confirmation** at the end of every pr-phase.

## Manual / step mode

If invoked as `/kmm --step`, pause at every phase boundary with `[continue / abort]`.

## Resume

`/kmm` with no args: if `<repo>/kmm/` has exactly one in-flight scope, resume silently. If multiple are in flight, ask which (one question). If none and no args, print: "No scope specified. Run `/kmm <scope>` with the migration intent."

## Other entry points

For workflows that don't fit `/kmm`'s linear flow:

- **`/kmm-verify`** — re-run completeness audit on a migration directory.
- **`/kmm-audit <pr>`** — read-only principles audit of any KMM migration PR.
- **`/kmm-retro`** — opt-in skill retrospective on a migration.

These run independently — they don't auto-chain into the migration pipeline.

## Constitution check

`/kmm` itself does not run a constitution-check — each phase runs its own.

## Failure modes

- **Scope already exists with same name** — read its phase. If in-flight, resume. If complete (every checkpoint has a PR URL), tell the user; ask whether to start a new scope (different name) or revisit.
- **State detection is ambiguous** (e.g., tasks.md shows in-progress but worktree is on a different branch) — escalate with a one-question state summary.
- **User passed `<scope>` but provided no intent** and no `spec.md` exists yet — proceed to specify-phase's goal-clarity gate. Don't guess.
- **An expected phase file is missing** — surface the error; the skill installation is broken.
