# Plan Review Criteria

> Criteria for `08_plan_critic` (rule compliance) and `09_plan_reviewer`
> (spec quality). Two different lenses.

## Contents

- [plan_critic checklist](#plan_critic-checklist)
- [plan_reviewer checklist](#plan_reviewer-checklist)

## plan_critic checklist

Run against `kmm_migration/plans/<feature>_migration_guide.md`:

1. All 14 laws respected in the plan.
2. Every file classified (commonMain / androidMain / iosMain / platform-
   interface).
3. Every Android-only API has a replacement strategy.
4. Replacement strategies live-sourced per Rule 13.
5. No rule-1-violating refactor proposed.
6. No silent renames.
7. Full baseline coverage claimed with paths.
8. Every external claim has a context7 / WebSearch source citation.
9. Worktree branch name matches convention.
10. Batch sizes fit context budget (≤5 files per batch).

## plan_reviewer checklist

Run against the same plan — spec-quality lens:

1. No placeholders — no `TBD`, `TODO`, `implement later`.
2. No vague "add error handling", "handle edge cases" without specifics.
3. No "similar to entry N" — content repeated.
4. Every code-involving entry has actual code examples, not prose.
5. No references to undefined types, functions, or files.
6. Every per-file entry is actionable by a migrator without clarification.
7. Ambiguity in any row → BLOCK, not PASS.

Revision policy: max 2 cycles with `07_migration_planner`; after that,
escalate with `REQUIRES_APPROVAL`.
