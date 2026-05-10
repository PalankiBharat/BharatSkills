---
description: Completeness audit on a KMM migration directory. Verifies every claim in the plan/architecture/migration-guide is reflected in actual codebase state. Detects false-positive completions. Distinct from /kmm-audit (which is a principles audit on any PR, regardless of skill).
argument-hint: "<scope-name?> [checkpoint-name?]"
---

# /kmm-verify

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

The **completeness gate**. Cross-references every plan entry, every architecture refactor entry, every checkpoint claim against the actual state of the codebase, looking for false-positive completions.

When invoked with a checkpoint name, scopes verify to that checkpoint's files. Without, verifies the whole migration. The `/kmm` orchestrator's verify-phase always passes a checkpoint; users invoking `/kmm-verify` directly typically don't.

`tasks.md` must have all in-scope items checked before this command is meaningful.

This is **not** the same as `/kmm-audit`. Audit is a read-only principle review of any KMM migration PR. Verify is a completeness check against the skill's own plan/architecture artifacts.

## Inputs

- All artifacts in `<repo>/kmm/<scope>/`
- The worktree at `<repo>/.worktrees/kmm-<scope>/`

## Steps

### 1. Dispatch `completeness-verifier`

```
Dispatch: agents/completeness-verifier.md
Task: Audit migration completeness against spec.md / plan.md / migration-guide.md.
      Cross-reference every claim against actual codebase state.
      Return VERIFY_COMPLETE_PASS or VERIFY_COMPLETE_FAIL.
Model: sonnet
Mode: read-only
```

Checks: plan-vs-reality (per file), test integrity, diff-spec match, refactor invariants pinned, constitution compliance scan, build clean across declared targets, checkpoint master-mergeability (when scoped), deviations consistency, out-of-scope changes, spec.md / tasks.md consistency.

### 2. On `VERIFY_COMPLETE_PASS`

Auto-close structured deviations to remove `OPEN`-deviation friction at pr-phase. Auto-close is deterministic — driven by structured closure types, not heuristic interpretation.

For each deviation in `migration-report.md` with status `OPEN`, read its `Closure` field per `templates/migration-report.md` § "Closure types":

| Type | Auto-close check |
|---|---|
| `grep:zero` | `grep -rE <pattern> <scope>` returns no matches |
| `grep:present` | `grep -rE <pattern> <scope>` returns ≥1 match |
| `binding:present` | grep finds `single\|factory\|scoped.*<TypeName>` in `<module>` |
| `test:exists` | the test fqn parses to a `@Test` function in the relevant test file |
| `commit:present` | `git log --grep=<fragment>` returns ≥1 commit |
| `manual` | NEVER auto-close. Stay `OPEN`. |

For each `OPEN` deviation:
- Structured AND check passes: status → `CLOSED`, populate `Closed-by:` with `auto-closed by /kmm-verify on <ISO>: <type> check returned <result>`. Commit `migration-report.md`.
- Structured AND check fails: stay `OPEN`. Note in PASS report.
- `manual` OR malformed: stay `OPEN`.

Never interpret free-form text closure paths. Under-closing is the safe failure mode.

Then:
- Print summary including count of auto-closed and any remaining `OPEN`.
- Run constitution check.
- If reached via `/kmm` chain, advance to pr-phase. `── pr (<checkpoint>) ──`.
- If invoked directly, print "Migration verified complete." and stop.

If any deviation remains `OPEN` after auto-close, advance to pr-phase anyway — pr-phase will refuse and surface.

### 3. On `VERIFY_COMPLETE_FAIL`

Escalate to the user with the full gap list. Do **not** auto-generate remediation tasks and re-run implement-phase.

A fail at this point usually means the architecture or plan missed something — the architecture-reviewer's prevention pass should have caught it. Auto-replanning hides the upstream gap.

Print:
- The failed checks.
- The identified gaps (file:line + description).
- "Verification failed. Review the gaps; if they're real, surface to the user as scope amendments / planning gaps. Re-run `/kmm` after deciding the path forward (revise architecture, revise plan, or descope)."

### 4. Constitution check

Touched: §2, §4 + §5, §6, §7, §8, §9, §10, §13.

Checklist:
- `[ ]` `completeness-verifier` returned a valid `VERIFY_COMPLETE_*` token
- `[ ]` On PASS: every check is green; auto-close attempts logged
- `[ ]` On FAIL: gaps surfaced to user; no auto-remediation triggered

### 5. Next

- On PASS: "Migration verified complete. Re-run `/kmm` to advance to pr-phase."
- On FAIL: Gaps surfaced. User decides next move.

## Why this command exists

Claude has a documented tendency to mark tasks complete when work is partially done. The verify gate is the structural defence: it does not trust the checkboxes; it checks the codebase. Per Constitution §8.

## What you MUST NOT do

- Do not write code yourself. Even fixes for trivial verifier findings need to be surfaced as planning gaps.
- Do not silently close a deviation. `OPEN` → `CLOSED` requires either structured auto-close OR user approval recorded in `migration-report.md`.
- Do not skip the verifier just because the build is green. Build green ≠ migration complete.
- Do not auto-generate remediation tasks on FAIL. A fail means the architecture or plan missed something — surface, don't loop.

## Failure modes

- **Verifier returns malformed token** — escalate to user with output.
- **A gap is itself ambiguous** — re-dispatch the verifier with the instruction "every gap must cite file:line".
