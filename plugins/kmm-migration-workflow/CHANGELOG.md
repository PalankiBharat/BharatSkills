# KMM Migration Workflow — Changelog

## v3.1.0 — 2026-05-10 — Mandatory smoke test gate

- **New Verification §8 — Smoke test.** Every checkpoint must pass a JVM smoke test before its PR can open. The smoke boots the DI graph, resolves every migrated public type declared in `architecture.md § Smoke test`, and invokes one happy-path public method on each. Catches runtime issues compile + unit tests don't (missing Koin bindings, `expect/actual` mismatches, init-order crashes). Instrumented `androidTest` variant is opt-in per scope.
- **architect-phase** declares the smoke shape (test FQN, DI modules, types-to-resolve, methods). `architecture-reviewer` blocks on a missing or incomplete smoke spec.
- **test-capturer** gains `mode: smoke` — writes the JVM smoke test (and instrumented if enabled) once per scope, runs it against the staged form pre-T-LOCK.
- **tasks.md** gains `T-SMOKE` (one per scope, in the first capture-bearing checkpoint) and `SMOKE-RUN` (one per checkpoint with Phase D tasks, after all migrate tasks).
- **completeness-verifier** gains Check 4a: smoke test passes (mandatory JVM, opt-in instrumented).
- **pr-phase** PR body's Verification section reports JVM and instrumented smoke results.

Rationale: prevention against runtime breakage. The compile + unit-test gate catches ~80% of bugs; the remaining ~20% (DI wiring, init order, platform `actual` selection) only surface when code actually runs. A mandatory smoke before every checkpoint merge keeps that 20% from landing on master.

## v3.0.0 — 2026-05-09 — Lean pass

Lean rewrite. Behaviour-preserving cuts driven by the prevention>cure principle the constitution itself states.

- Removed `agents/structural-verifier.md` and `agents/plan-analyzer.md`. The `architecture-reviewer` is the prevention pass at design time; the `completeness-verifier` is the single end-of-checkpoint check. Per-file diff-checks and re-validation passes were cure-shaped.
- Removed `references/clean-code.md` (merged into constitution §7).
- Removed `references/plain-language.md` (folded into orchestration-protocol "Communication style").
- Removed mid-flight retry loops (3-strike refire) and `Phase E: Remediation tasks` auto-loop. Mechanical failures now escalate to the user immediately — retrying a failing subagent is cure for missing prevention.
- Removed auto-dispatch of `skill-retrospector` at end of every migration. It is now opt-in via `/kmm-retro`.
- Removed full-suite runtime master health sweep at specify-phase. Compile-only is mandatory; runtime is opt-in. `/kmm-verify` runs scope-focused tests anyway, so the full sweep wasted ~5–10 min per migration without proportional value.
- Compressed every file. Constitution 206→~120 lines, SKILL 135→~80, phase files 200–300 each → ~80 each. Same rules, less prose.

## v2.2.0 — 2026-05-09 — Plain language

§15 — Plain language. Artifacts, prompts, PR bodies, commit messages are written so a busy reviewer can skim and understand them on the first read.

## v2.1.0 — 2026-05-09 — Proportionality + clock-bound clause

- §14 — Proportionality. Trivial migrations (≤3 files, no expect/actual, no cross-file refactors, swaps already-declared) route through a fast-path that collapses workflow ceremony while preserving every structural protection.
- §8 expanded — clock-bound code without an injection seam: master-untestability of clock-bound public APIs is recognised as a structural gap. Behaviour-preservation tests for hidden branches are introduced post-migration alongside an architecture-approved seam-creating refactor.
