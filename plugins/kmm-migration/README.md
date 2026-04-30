# kmm-migration plugin

Next-gen Android → Kotlin Multiplatform migration orchestrator. **Canonical-KMP-first**, baseline-first, 1:1-port, hard quality gates, subagent-driven execution.

**v0.3.0** — major alignment to JetBrains' canonical workflow. User picks scope (feature / module / screen / file); skill follows libs→logic→UI ordering with leaf-first modules; per-file preconditions catch the resource-hardcoding / JVM-API-inlining / dep-papering-over failure modes; migrator self-audit replaces the previous 2-stage reviewer dispatch. Knowledge stays in kotlinlang.org docs — the skill ships behaviours and pointers, not version-bound facts.

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

- **Phase 0 — Bootstrap**: user describes what they want to migrate; `01_codebase_scope_analyzer` reads the codebase and presents scope options (whole feature / module / screen / file) with a recommended default; user picks; the skill creates ONE migration worktree (recorded in `kmm_migration/state.json`).
- **Phase 1 — Baseline**: captures unit tests + screenshot goldens + E2E flows from the OG Android code at the chosen scope. These become the immutable contract migrated code must satisfy. (Gate 1.)
- **Phase 2 — Plan**: `06_researcher` live-sources the technology stack from kotlinlang.org first (Law 15); `07_migration_planner` reads every in-scope file from the actual codebase and writes a zero-ambiguity per-file plan ordered libs→logic→UI leaf-first; `08_plan_critic` runs a single-dispatch audit (spec compliance + ambiguity + ordering). (Gate 2.)
- **Phase 3 — Migrate**: parallel `10_migrator` dispatches per leaf-first batch. Migrator runs preconditions BEFORE the port (resources moved? JVM APIs replaced? deps swapped? Java converted? platform types abstracted?). Migrator runs the comprehensive self-audit checklist BEFORE `STATUS: DONE`. No separate reviewer dispatches. Orchestrator runs a deterministic diff-grep tripwire as backstop. Owns all commits (migrators have `git commit/add/push` denylisted).
- **Phase 4 — Verify**: baseline suites re-run against migrated code, plus a runtime smoke launch (`adb install` + `am start` + logcat scan for `FATAL EXCEPTION`) to catch Hilt / DI crashes that compile-only verification misses. `11_plan_diff_auditor` is the deterministic safety net. (Gate 3 → iOS or defer.)
- **Phase 5 — iOS** (optional): `14_ios_porter` with tiered integration default (Podfile detected → CocoaPods, else Direct integration; SPM/Swift export require user opt-in). Self-audit + diff-grep tripwire same as Phase 3. (Gate 4.)
- **Phase 6 — Closeout**: `15_final_baseline_reverifier` (hard Gate-5 precondition), `16_kmm_focused_final_reviewer` (holistic cross-batch review the per-batch self-audit cannot replace), `17_pr_body_composer` + heatmap, `18_pr_creator` (gh CLI), `19_closeout_reporter`. (Gate 5 → PR approved for merge.)

## Design highlights

- **15 iron laws** with rationalization tables — Law 15 (canonical KMP approach over short-term expedience) is the soul of the skill. Captures the LLM failure modes verbatim ("hardcode the resource string", "inline the JVM regex", "defer the Hilt swap", "hand-roll DI") so subagents self-check before committing the shortcut.
- **Knowledge stays in the docs.** The skill ships behaviours, ordering rules, and pointers — NOT specific library names, version numbers, or FROM → TO tables. Anything version-bound is researcher-resolved from kotlinlang.org per invocation. The skill does not go stale because the knowledge isn't pinned.
- **kotlinlang.org canonical-first.** Law 13 + Law 15 source-priority: kotlinlang.org canonical docs are Priority 0 ahead of context7 for any KMP-shaped question. Entry-point URL list in `references/knowledge_lookup_protocol.md`.
- **Per-file preconditions** (`references/migration_preconditions.md`): R (resources), J (Java→Kotlin), A (JVM-API scrub), D (disqualified deps), P (platform types). Migrator verifies before port; reviewer verifies after.
- **Migrator self-audit replaces 2-stage review.** The migrator runs `references/migrator_self_audit_checklist.md` (30+ mechanical checks) before `STATUS: DONE`. The orchestrator runs `references/orchestrator_diff_grep.md` (no LLM call, ~0 tokens) as a tripwire for dishonest checklists. Saves ~18k tokens and ~3min per feature vs the previous 2-stage reviewer dispatch.
- **Conditional dispatch injection.** Each subagent's `must_read` is computed by the orchestrator at dispatch time based on subagent role × phase × in-scope file classification. A migrator working a screen file gets Compose + resources + JVM-scrub references; a baseline-test-author gets the baseline capture protocol. Tokens stay focused on what's relevant.
- **User-chosen scope.** The user picks feature / module / screen / file at Phase 0; the skill suggests a default based on dependency analysis but never picks. Scope is recorded in `state.json` and honoured by every subagent — the orchestrator never silently expands it.
- **Migration ordering is opinionated** (`references/migration_ordering.md`): libs first → business logic → UI, leaf-first modules within each step. Cited worked example: github.com/kotlin-hands-on/jetcaster-kmp-migration.
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
