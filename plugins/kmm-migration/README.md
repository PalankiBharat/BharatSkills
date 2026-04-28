# kmm-migration plugin

Next-gen Android → Kotlin Multiplatform migration orchestrator. Baseline-first, 1:1-port, hard quality gates, subagent-driven execution.

## Self-contained

No external skill dependencies. Install and use standalone.

## Invoke

```
/kmm-migration <feature-name> [--from-branch <branch>]
```

Examples:

```
/kmm-migration login
/kmm-migration profile --from-branch main
```

## What the skill does

- **Phase 0 — Bootstrap**: creates ONE migration worktree (recorded in `kmm_migration/state.json`), or resumes an existing migration.
- **Phase 1 — Baseline**: captures unit tests + screenshot goldens + E2E flows from the OG Android code. These become the immutable contract migrated code must satisfy. (Gate 1.)
- **Phase 2 — Plan**: `06_researcher` live-sources the technology stack via context7; `07_migration_planner` writes per-file plan; `08_plan_critic` + `09_plan_reviewer` audit. (Gate 2.)
- **Phase 3 — Migrate**: parallel `10_migrator` dispatches per batch; orchestrator owns all commits (migrators have `git commit/add/push` denylisted) and runs a post-dispatch scope-allowlist check against the in-scope file list before reviewing. Two-stage code review (spec compliance + code quality) after each batch.
- **Phase 4 — Verify**: baseline suites re-run against migrated code, plus a runtime smoke launch (`adb install` + `am start` + logcat scan for `FATAL EXCEPTION`) to catch Hilt / DI crashes that compile-only verification misses. `11_plan_diff_auditor` is the deterministic safety net. (Gate 3 → iOS or defer.)
- **Phase 5 — iOS** (optional): `14_ios_porter` + iOS parity. (Gate 4.)
- **Phase 6 — Closeout**: `15_final_baseline_reverifier` (hard Gate-5 precondition), `16_kmm_focused_final_reviewer` (holistic KMM review), `17_pr_body_composer` + heatmap, `18_pr_creator` (gh CLI), `19_closeout_reporter`. (Gate 5 → PR approved for merge.)

## Design highlights

- **14 iron laws** with rationalization tables (the anti-patterns the laws catch, stated verbatim so subagents self-check).
- **Zero hardcoded library prescriptions** — Rule 13 "Live knowledge" requires every technology decision to be live-sourced via context7 at invocation time.
- **Opus orchestrator never edits code.** All labour in Sonnet/Haiku subagents; status contract enforced.
- **One worktree per migration** — recorded in `state.json`, validated by `state_inspector` on resume.
- **Named escape hatches** for Laws 1 (seam insertion) and 2 (baseline rebase), both user-gated.

## Files produced at the target repo root

```
kmm_migration/
├── state.json
├── findings.md                      # decision journal, persists across features
├── baseline/<feature>/              # immutable after Phase 1
├── plans/<feature>_migration_guide.md
├── progress/<feature>_progress.md
├── pr/<feature>/{body.md, heatmap.md, pr_url.txt}
└── reports/<feature>/               # every subagent's report
```

All git-tracked, committed, reviewable on remote.

## Authoring checklist

Run the bundled validator to verify structural compliance:

```
./skills/kmm-migration/tests/validate_authoring_checklist.sh
```

Expected: `authoring checklist ALL PASS`.

## Pressure scenarios

18 RED adversarial scenarios across Laws 1, 2, 9, 12, 13, 14 — `tests/pressure_scenarios/`. Run manually per `tests/how_to_run.md` across Haiku / Sonnet / Opus before release.
