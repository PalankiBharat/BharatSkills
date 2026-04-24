# Code Review Criteria

> Two lenses run per code-producing dispatch: spec compliance then code
> quality. This file codifies both.

## Contents

- [Do not trust the producer's report](#do-not-trust-the-producers-report)
- [spec_compliance procedure](#spec_compliance-procedure)
- [code_quality checklist per phase](#code_quality-checklist-per-phase)

## Do not trust the producer's report

The producer subagent may have finished suspiciously quickly. Their report
may be incomplete, inaccurate, or optimistic. Reviewers verify by reading
the actual git diff, NOT by reading the producer's report.

## spec_compliance procedure

1. `BASE_SHA = worktree base`, `HEAD_SHA = current HEAD`.
2. `git diff --stat BASE..HEAD` for file-level scope check.
3. `git diff BASE..HEAD` for line-level.
4. For each file in diff: was it in the spec? matches spec? else
   SCOPE_CREEP / DRIFT.
5. For each file in spec: is it in diff? else MISSING_WORK.
6. Scan diff for:
   - TODO / FIXME / XXX → STUB_LEFTOVER
   - New deps in build files → DEP_ADDITION
   - File renames not in spec → SILENT_RENAME
   - Modifications under `kmm_migration/baseline/**` → BASELINE_VIOLATION
     (BLOCKER)
   - Sourceless "we use X" claims in the producer's report →
     RULE_13_VIOLATION
   - Adjacent-line edits outside authorized lines → SURGICAL_VIOLATION
   - New utility functions / flags / abstractions not in spec →
     SPECULATIVE_CODE

## code_quality checklist per phase

### Phase 1b (baseline_unit)
- Tests use only libraries in tech_stack_snapshot.md.
- Tests are characterization (no new logic assertions beyond OG).
- File paths match inventory.

### Phase 1c (baseline_screenshot)
- Framework setup uses tech_stack_snapshot.
- Goldens recorded under baseline/<feature>/.
- No modifications to OG UI code.

### Phase 1d (baseline_e2e)
- Flow files use locked conventions.
- Flows green against OG APK attached to report.

### Phase 3 (migrator)
- Rules 1-14 compliance.
- Platform interop pattern matches research_notes.md.
- No new deps (Rule 4).
- No new comments (Rule 9).
- path:line format (Rule 11).
- Simplicity: no speculative abstractions, no config flags outside spec,
  no defensive handling of impossible scenarios.
- Surgical: every changed line traces to a migration_guide entry.

### Phase 5 (ios_porter)
- Swift-interop wiring matches research_notes.md.
- iosMain actuals match androidMain interface contracts.
- No Android types leaked into shared code.

### escape-hatch seam
- Extra strict: one file, interface-only, zero behaviour change.

### escape-hatch rebase_baseline
- Extra strict: only baseline artifacts changed; envelope change justified
  and sourced.
