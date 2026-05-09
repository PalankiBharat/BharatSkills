---
description: Completeness audit on a KMM migration directory. Verifies every claim in the plan/architecture/migration-guide is reflected in actual codebase state. Detects false-positive completions. On VERIFY_FAIL, appends remediation tasks to tasks.md. Distinct from /kmm-audit (which is a principles audit on any PR, regardless of skill).
argument-hint: "<scope-name?> [checkpoint-name?]"
---

# /kmm-verify

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

This is the **completeness gate**. It does not just run a build — it cross-references every plan entry, every architecture refactor entry, every checkpoint claim against the actual state of the codebase, looking for false-positive completions (a task marked `[x]` whose work is not actually finished).

When invoked with a checkpoint name, scopes the verify to that checkpoint's files. When invoked without, verifies the whole migration. The `/kmm` orchestrator's verify-phase always passes a checkpoint; users invoking `/kmm-verify` directly typically don't.

The implement-phase (or `/kmm`) must have reported "all tasks complete" for the relevant scope before this command is meaningful. If `tasks.md` still has unchecked items in scope, run those first.

This is **not** the same as `/kmm-audit`. Audit is a read-only principle review of any KMM migration PR (skill-made or not). Verify is a completeness check against the skill's own plan/architecture artifacts. Use audit for PR review; use verify for skill-pipeline validation.

## Inputs

- All artifacts in `<repo>/kmm/<scope>/`
- The worktree at `<repo>/.worktrees/kmm-<scope>/`
- The full codebase as it currently sits

## What you do

### 1. Dispatch the `completeness-verifier` subagent.

```
Dispatch: agents/completeness-verifier.md
Task: Audit the migration for completeness against spec.md, plan.md, migration-guide.md.
      Cross-reference every claim against actual codebase state. Identify false-positive completions.
      Return a structured VERIFY_COMPLETE_PASS or VERIFY_COMPLETE_FAIL report.
Model: sonnet
Mode: read-only (no Write/Edit)
```

The verifier checks:

**Plan vs reality (per file)**
- Does the migrated file exist at the `Target` path declared in `migration-guide.md`?
- Is the original file gone from its `Source` path? (Files should have moved, not been copied.)
- Does the migrated file's actual public API match the `Public API` field byte-for-byte (method names, parameter names, parameter order, return types, visibility)?
- Are claimed `Library swaps` actually applied? Grep proof: no remaining imports of the swapped-out library in the migrated file; ≥1 import of the swapped-in library.
- Are claimed `expect/actual` declarations actually present in `commonMain` (the `expect`) and the relevant platform source set (the `actual`)?
- Are listed `Consumers` updated — i.e., do they import from the new `commonMain` path, not the old Android path?

**Test integrity**
- Does each in-scope file have baseline tests in `shared/src/commonTest/`?
- Does the test count meet or exceed the `Expected tests` field of the migration-guide entry?
- Run the test command from `spec.md`. All baseline tests must be GREEN against the migrated code.
- Compare the current `commonTest/` against the `baseline-locked-sha` from `spec.md`. Any test file modified after lock must have a corresponding `RATIFIED` deviation in `migration-report.md`. Unauthorised modification → `VERIFY_COMPLETE_FAIL`.

**Constitution compliance scan (in scope files only)**
- No `TODO`, `FIXME`, `XXX`, `// HACK`, `// Phase`, `// was X, now Y`, `// removed X` in any migrated source file.
- No `as`, `as?`, `as!` casts.
- No new comments beyond the one-line non-obvious-why exceptions allowed by Constitution §8 (manual review by the verifier — heuristic: comment should explain *why*, not *what*; if the comment paraphrases the next line of code, it is forbidden).
- No `import` from a JVM-only or Android-only package in `commonMain` files.
- No `kotlinx.coroutines` adapter for legacy threading models (RxJava bridges, LiveData bridges, completion-handler bridges) anywhere under `commonMain`.

**Build clean across declared targets**
- Run each compile/test command listed in `plan.md`'s verification section against the worktree.
- Per-target compile must succeed.
- Per-target tests (where the source set has tests) must pass.
- Consumer compile must succeed.

**Deviations consistency**
- Every deviation in `migration-report.md` has a status (`OPEN` / `CLOSED` / `RATIFIED` / `SUPERSEDED`).
- Every `OPEN` deviation has a closure path (text describing how it will be closed).
- For pr-phase to run later, all deviations must be `CLOSED`, `RATIFIED`, or `SUPERSEDED` — but at this step we just count and report.

**Out-of-scope changes**
- Diff the worktree against the baseline locked SHA. Every changed file must be either in the in-scope list, in a consumer list, or be the `@Ignore` patch / a deviation logged in `migration-report.md`.
- Any out-of-scope change not authorised by `migration-report.md` → `VERIFY_COMPLETE_FAIL` with that file listed.

### 2. Read the verifier's report.

The report comes back as either:

```
VERIFY_COMPLETE_PASS: scope=<scope> | files=<N> | tests=<count green> | targets=<list passed>
```

or:

```
VERIFY_COMPLETE_FAIL: scope=<scope>
  ## Failed checks
  - [check-name] file=<path> details=<...>
  - ...
  ## Remediation tasks
  R-1: <description with file:line>
  R-2: <description with file:line>
```

### 3. On `VERIFY_COMPLETE_PASS`:

Before printing PASS, **auto-close structured deviations** to remove the OPEN-deviation friction the user would otherwise hit at pr-phase. Auto-close is deterministic — driven by structured closure types, not heuristic interpretation.

For each deviation in `migration-report.md` with status `OPEN`, read its `Closure` field. The field is a structured object per `templates/migration-report.md` § "Closure types":

| Type | Auto-close check |
|---|---|
| `grep:zero` | `grep -rE <pattern> <scope>` returns no matches |
| `grep:present` | `grep -rE <pattern> <scope>` returns ≥1 match |
| `binding:present` | grep finds `single\|factory\|scoped.*<TypeName>` in `<module>` |
| `test:exists` | the test fqn parses to a `@Test` function in the relevant test file |
| `commit:present` | `git log --grep=<fragment>` returns ≥1 commit |
| `manual` | NEVER auto-close. Stay `OPEN` until user changes status. |

For each `OPEN` deviation:

- If the closure type is structured AND the check passes: update status to `CLOSED`, populate `Closed-by:` with `auto-closed by /kmm-verify on <ISO>: <type> check returned <result>`. Commit `migration-report.md`.
- If the closure type is structured AND the check fails: stay `OPEN`. Note in the verifier's PASS report.
- If the closure type is `manual` OR malformed: stay `OPEN`. Note in the verifier's PASS report.

**Never** interpret free-form text closure paths as auto-closeable. Either the deviation has a structured closure type or it stays `OPEN` for manual closure. Under-closing is the safe failure mode; over-closing breaks deviation-log integrity.

Then:
- Print the summary to the user. Include the count of auto-closed deviations and any remaining `OPEN`.
- Run the constitution check (below).
- If reached via the `/kmm` chain, advance automatically to pr-phase. Print: `── pr (<checkpoint>) ──`. The pr-phase will pause for final user confirmation — that's the only remaining gate.
- If invoked directly (`/kmm-verify`), tell the user: "Migration verified complete. Re-run `/kmm` to advance to the pr-phase." and stop.

If any deviation remains `OPEN` after auto-close attempts, advance to pr-phase anyway — pr-phase will refuse and surface the issue, giving the user a chance to manually close or RATIFY.

### 4. On `VERIFY_COMPLETE_FAIL`:

- Append the `Remediation tasks` to `tasks.md` under a new heading `## Phase E: Remediation (round <N>)`.
- Each remediation task carries the same metadata block format as Phase D tasks (subagent: `migrator`, source/target, etc.).
- Print the failed checks to the user.
- Tell the user: "Verification failed. <N> remediation tasks added to tasks.md. Re-run `/kmm` to apply them, then verify will re-run automatically."
- Constitution check (still required — this is a real command boundary).

The user is then expected to re-run `/kmm` (which will pick up the new tasks via implement-phase and re-trigger verify-phase). Loop until `VERIFY_COMPLETE_PASS`.

There is no maximum number of rounds. Each round narrows the gap. If progress stalls (same task reported across multiple rounds), the orchestrator escalates: "Round N has the same failures as round N-1. Investigate or revise scope."

### 5. Constitution check.

- Touched: §2 (verifier reads source of truth), §4 + §5 (verifier never relies on training data — it greps actual code), §6 (out-of-scope changes detected), §7 (clean-code-first decisions enforced via architecture-vs-reality diff), §8 (baseline test integrity verified, refactor invariants pinned), §9 (TODO/comment/cast scan), §10 (canonical-pattern scan; scaffolding-without-behaviour scan), §13 (checkpoint master-mergeability when scoped to a checkpoint).
- Pass/fail:
  - `[ ]` `completeness-verifier` returned a valid `VERIFY_COMPLETE_*` token
  - `[ ]` On PASS: every check listed above is green
  - `[ ]` On FAIL: every failed check has a corresponding remediation task in `tasks.md`
  - `[ ]` `tasks.md` is committed
- On fail: STOP. Report which checks failed.

### 6. Next step.

- On PASS: "Migration verified complete. Re-run `/kmm` to advance to pr-phase."
- On FAIL: "Re-run `/kmm` to apply the <N> remediation tasks; verify re-runs automatically."

## Why this command exists

Claude has a documented tendency to mark tasks complete when work is partially done. The verify gate is the structural defence: it does not trust the checkboxes; it checks the codebase. The cycle of `verify → fix → verify` continues until the codebase actually matches the plan, not just the task list. This is non-negotiable per Constitution §8 (verification gate) — a migration that "looks done" but isn't is exactly the failure mode this command exists to catch.

`/kmm-verify` is the user-facing form. The same logic also runs automatically inside `/kmm` between implement and pr phases (per checkpoint).

## What you do NOT do

- Do not write code yourself. Even fixes for trivial verifier findings are dispatched as remediation tasks.
- Do not silently close a deviation. `OPEN` → `CLOSED` requires user approval, recorded in `migration-report.md`.
- Do not skip the verifier just because the build is green. Build green ≠ migration complete; the verifier checks plan-vs-reality structural claims that the build cannot.

## Failure modes

- **Verifier returns malformed token** — refire once with explicit instruction to emit exactly one `VERIFY_COMPLETE_*` token. If it fails twice, escalate.
- **A remediation task is itself ambiguous** — the verifier should produce a `file:line`-cited task. If it produces vague text, refire the verifier with the instruction "every remediation task must cite file:line".
- **Stall (same failure across rounds)** — escalate to user: this means the underlying plan is wrong. Revisit `plan-phase` for the affected files.
