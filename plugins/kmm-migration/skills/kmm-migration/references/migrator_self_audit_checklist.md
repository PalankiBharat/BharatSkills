# Migrator Self-Audit Checklist

> The migrator runs this checklist as the LAST step of every dispatch
> before emitting `STATUS: DONE`. Every item must tick with cited
> evidence (file:line). Any failed item flips the verdict to
> `STATUS: ISSUES_FOUND` — the migrator fixes in the same dispatch and
> re-runs the checklist. Three failed cycles on the same item escalates
> per the three-strike protocol.
>
> This checklist replaces the previous two-stage reviewer pattern
> (`spec_compliance_reviewer` + `code_quality_reviewer`). Reason: the
> migrator already has the full context (it just wrote the code, knows
> the migration_guide entry, knows the in-scope files); spawning fresh
> reviewers means re-reading the diff, the plan, and every reference
> from scratch — wasted tokens and wasted wall-time. The migrator's
> self-audit is mechanical (every check is verifiable from the diff +
> the plan) and stays inside the active context. Holistic cross-batch
> review still happens at Phase 6 via `16_kmm_focused_final_reviewer`.

`applies_to: [migrator, ios_porter]`
`concerns: [self-audit, completion-criterion]`

## Contents

- [How to run the checklist](#how-to-run-the-checklist)
- [Section 1 — Plan compliance](#section-1--plan-compliance)
- [Section 2 — Preconditions verified](#section-2--preconditions-verified)
- [Section 3 — Surviving-shortcut grep](#section-3--surviving-shortcut-grep)
- [Section 4 — Build / test green](#section-4--build--test-green)
- [Section 5 — Surgical-change discipline](#section-5--surgical-change-discipline)
- [Section 6 — Reporting honesty](#section-6--reporting-honesty)
- [Output schema](#output-schema)
- [Failure handling](#failure-handling)

## How to run the checklist

1. Complete the migration work for the dispatched batch.
2. Run every section below in order. Each section has explicit checks
   with concrete grep / git / build commands.
3. For each check, record: the command run, the output observed (or
   "no output" / "match count: N"), and the verdict (PASS / FAIL).
4. Any FAIL → flip the dispatch verdict to `ISSUES_FOUND`, list the
   failing items, fix them in the same dispatch, re-run the checklist.
5. All sections PASS → emit `STATUS: DONE` with the checklist
   transcript appended to the dispatch report.

The checklist is mechanical, not subjective. If a check requires
judgment, that's a sign it's the wrong check — surface as
`STATUS: NEEDS_CONTEXT` rather than guessing.

## Section 1 — Plan compliance

The dispatched batch must satisfy the specific `migration_guide` entries
named in the dispatch prompt. Nothing more, nothing less.

| # | Check | How to verify |
|---|---|---|
| 1.1 | Every in-scope file in the dispatch's file list shows changes in the diff. | `git diff --name-only` against the dispatch file list — no missing files. |
| 1.2 | No file outside the dispatch's file list is modified. | `git diff --name-only` ∩ in-scope list = `git diff --name-only` (no out-of-scope changes). Single exception: same-batch resource files moved per Precondition R, which the dispatch should have authorised. |
| 1.3 | Every migration_guide entry assigned to this batch is satisfied by a concrete file change cited in the diff. | For each entry, name the file:line in the diff that satisfies it. |
| 1.4 | No migration_guide entry from a future batch was started. | Check that the diff does not touch files outside this batch's slice of the leaf-first ordering. |

## Section 2 — Preconditions verified

Per `references/migration_preconditions.md`, every file in scope has had
preconditions R / J / A / D / P verified. The migrator's own precondition
report (`reports/<feature>/<batch>_preconditions.md`) must exist and
must show every file PASS or `PRECONDITION_BLOCKED` (and the blocked
ones must be addressed before this checklist runs).

| # | Check | How to verify |
|---|---|---|
| 2.1 | The precondition report file exists for this batch. | `ls reports/<feature>/<batch>_preconditions.md`. |
| 2.2 | Every in-scope file appears in the precondition report. | Cross-reference the dispatch's file list against the report's file headings. |
| 2.3 | No file's precondition verdict is `PRECONDITION_BLOCKED` at the time of `DONE`. | Grep the report for `PRECONDITION_BLOCKED`. If any survive, the migrator should have stopped — `ISSUES_FOUND`. |
| 2.4 | Each precondition's evidence (file:line) is in the report — not generic prose. | Spot-check 1 file's precondition entries for concrete citations. |

## Section 3 — Surviving-shortcut grep

The migrator runs deterministic greps against the diff to catch the
canonical failure modes. Each grep returns 0 matches for PASS.

| # | Check | Grep command (run against the diff or against the migrated files) |
|---|---|---|
| 3.1 | No hardcoded string literal in a Compose `Text(...)` call (Precondition R). | Custom — for each migrated `.kt` file containing `androidx.compose.material*` imports, grep for `Text\(\"[^"]+"` (literal). PASS = no hits OR every hit is justified in the precondition report (e.g., format string assembled from `Res.string.foo`). |
| 3.2 | No `R.string.` / `R.drawable.` / `R.dimen.` / `R.plurals.` / `R.color.` survives in any commonMain file. | `git diff -- 'src/commonMain/**/*.kt'` then grep `R\.\(string\|drawable\|dimen\|plurals\|color\)\.`. 0 matches. |
| 3.3 | No literal `.dp` / `.sp` value in a commonMain composable that came from a `dimen` resource without a `Dimens` (or equivalent) declaration. | Spot check: for each migrated composable, if the precondition report mentioned `R.dimen.*`, ensure either `Dimens.foo` is referenced OR the literal is justified in the precondition report. |
| 3.4 | No JVM-only import survives in any commonMain file. | `git diff -- 'src/commonMain/**/*.kt'` then grep `^import \(java\.\|javax\.\|org\.junit\.\)`. 0 matches. |
| 3.5 | No `freeze()` / `ensureNeverFrozen()` / `@SharedImmutable` / `FreezableAtomicReference` introduced (these are deprecated under the new memory manager). | Grep for those tokens in added lines. 0 matches. |
| 3.6 | No `// TODO` / `// FIXME` / `// XXX` / `// HACK` introduced in migrated code (Law 09). | `git diff` then grep `^\+.*// \(TODO\|FIXME\|XXX\|HACK\)`. 0 matches. |
| 3.7 | No `expect class` declared without the project's documented opt-in flag (researcher confirms per invocation if the flag is still required). | Grep for `^expect class` in added lines. If hits exist, verify the project's Gradle config has the current opt-in flag enabled. |
| 3.8 | No `actual typealias` to a JVM-only or Android-only platform type appears in `commonMain`. (Typealiases to platform types belong in platform `actual` sites.) | Grep `commonMain` for `actual typealias`. 0 matches expected — if any exist, that's a misplaced actual. |
| 3.9 | No widened visibility on extraction-to-commonMain (Law 1). For each `internal` declaration in the OG file that became `public` in the migrated file, the migrator must justify the widening in the precondition report (external consumer named). | Compare visibility modifiers in the diff for declarations that changed source-set. |
| 3.10 | No `androidx.compose.ui.res.*` imports in commonMain (the Android-only resource accessors don't compile in commonMain). | `git diff -- 'src/commonMain/**/*.kt'` then grep `^import androidx\.compose\.ui\.res\.`. 0 matches. |
| 3.11 | No new `RxJava` / `io.reactivex.*` import in any migrated file (the swap should have replaced these per Precondition D). | Grep added lines for `^import io\.reactivex\.` or `^import rx\.`. 0 matches. |
| 3.12 | No silent baseline modification (Law 02). | `git diff -- '**/snapshots/' '**/screenshots/' '**/goldens/' 'kmm_migration/baseline/'`. Empty diff. |

## Section 4 — Build / test green

| # | Check | How to verify |
|---|---|---|
| 4.1 | Project compiles for every target the module declares. | `./gradlew compile<Target>KotlinMetadata`, `./gradlew compile<Target>KotlinAndroid`, `./gradlew compileKotlinIosArm64`, etc. — minimum, the targets in scope for this migration. Capture exit code 0. |
| 4.2 | Baseline unit tests still GREEN against the migrated code. | `./gradlew <feature>:test` (or per-target) — capture pass/fail counts. Equal to baseline counts. |
| 4.3 | Baseline screenshot tests still GREEN within tolerance. | The recorded screenshot runner — exit 0. |
| 4.4 | No new compiler warnings introduced in the touched files (Law 1 surgical changes). | Diff `gradle build` warning output. New warnings = `ISSUES_FOUND`. |

## Section 5 — Surgical-change discipline

Law 1 (1:1 port + surgical changes) enforced mechanically.

| # | Check | How to verify |
|---|---|---|
| 5.1 | No reformatting / re-indenting / brace-style changes outside lines the migration logically required. | `git diff` review — every changed line traces to a migration_guide entry. |
| 5.2 | No "while-I'm-here" import reordering, comment cleanup, or naming improvements. | Same diff review — every change has a migration purpose. |
| 5.3 | No new abstractions / helper classes / utility functions introduced beyond what the spec named. | Grep added lines for `class `, `fun `, `object ` declarations. Each one must be in the migration_guide. |
| 5.4 | No new dependencies added to `build.gradle.kts` beyond what the migration_guide named. | `git diff -- '**/build.gradle.kts'` against the plan's dependency-changes section. |

## Section 6 — Reporting honesty

| # | Check | How to verify |
|---|---|---|
| 6.1 | The dispatch report names every file changed, with a one-line purpose per file. | The report's "files modified" section length = `git diff --name-only` length. |
| 6.2 | The dispatch report cites at least one piece of evidence (file:line, command + output, citation URL) for every claim it makes. | Grep the report for unsupported assertions ("works correctly", "should be fine", "looks good"). 0 matches. |
| 6.3 | If anything was deferred / left incomplete / blocked, it is named in the report — not omitted. | Self-check — would a reviewer reading just the report and the diff get the same picture? |
| 6.4 | The checklist transcript itself is appended to the report (this section's output). | Verify presence. |

## Output schema

The migrator appends the checklist transcript to the dispatch report:

```markdown
### Self-audit checklist — <batch>

#### Section 1 — Plan compliance
- 1.1 PASS — diff covers every in-scope file (evidence: <git diff output>)
- 1.2 PASS — no out-of-scope changes (evidence: …)
- 1.3 PASS — entries satisfied: <table>
- 1.4 PASS — …

#### Section 2 — Preconditions verified
- 2.1 PASS — report at reports/<feature>/<batch>_preconditions.md
- 2.2 PASS — all 5 in-scope files present
- 2.3 PASS — 0 PRECONDITION_BLOCKED entries
- 2.4 PASS — spot-check confirmed citations

#### Section 3 — Surviving-shortcut grep
- 3.1 PASS — 0 hardcoded literals (grep output: …)
- 3.2 PASS — 0 R.* matches in commonMain
- ...

#### Section 4 — Build / test green
- 4.1 PASS — compileMetadata / compileAndroid / compileIos all exit 0
- 4.2 PASS — 24/24 unit tests green (baseline: 24/24)
- ...

#### Section 5 — Surgical-change discipline
- ...

#### Section 6 — Reporting honesty
- ...

Verdict: STATUS: DONE
```

## Failure handling

`ISSUES_FOUND` is normal — fix and retry. The migrator does NOT escalate
on first failure. Three distinct failure cycles on the same item
(genuinely the same item, not a new failure each time) crosses the
three-strike protocol → escalate to `debug_investigator`.

If the checklist surfaces a problem the migrator can't fix in scope
(e.g., a dep swap that requires touching files outside the dispatch
file list), emit `STATUS: PRECONDITION_BLOCKED` instead of `ISSUES_FOUND`
and let the orchestrator route the unblocking sub-task.

The orchestrator, on receiving `STATUS: DONE`, does NOT re-run the
checklist (that would defeat the point). It does run a tiny
deterministic sanity-grep — the diff against a SHORT list of "must
never appear" patterns — to catch dishonest checklists. The grep is
defined in `references/orchestrator_diff_grep.md` (Haiku-cheap, no LLM
needed). If the sanity-grep finds a violation, the orchestrator
overrides the migrator's verdict and re-dispatches with the violation
in the prompt.
