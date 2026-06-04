# Phase E — Baseline Promotion

**Purpose.** For files whose code reached `<dest>/commonMain` in Phase D (status `migrated`), promote their baseline tests from `<dest>/androidUnitTest/` to `<dest>/commonTest/`. The baselines were written in the KMM-portable stack at Phase B, so the promotion is mechanical (`git mv` + verify). This is the **strongest equivalence verification** — the same baseline tests now run on both JVM and iOS runtimes against the migrated production code.

**Conditional.** If no in-scope file reached `commonMain` by end of Phase D (all `hold`-plan, or all `migrate`-plan flipped to `hold` via D.3), Phase E is skipped entirely — baselines stay in `androidUnitTest` as their final destination this session. A future session can promote when code ripens.

**Inputs:** all prior session files (`scope.md` through `migration.md`, status complete), `project.md`, `coverage.md`.

---

## Sub-phases

### E.0 — Skip check + pre-promotion smokes (Haiku, parallel)

- **E.0.1 — Skip check (cross-checked against `migration.md`, NOT the status column alone).** Determine whether any file reached `commonMain`. Read `coverage.md`'s status column **and cross-check `migration.md`'s per-file entries / commit SHAs** — if they disagree, `migration.md` (what actually happened) wins, and the stale `coverage.md` is reconciled before proceeding. *Both prior sessions opened Phase E with the column stuck at `frozen` for already-migrated files; a literal read would have wrongly skipped Phase E and thrown away the strongest equivalence proof. Phase D's serialization gate should keep the column current now — this cross-check is the backstop.* If — after the cross-check — genuinely no file reached `commonMain`, Phase E is skipped: record "Phase E skipped — no files reached commonMain this session" in `move.md`, proceed to Phase F.

- **E.0.2 — Pre-existing commonTest K/N compile health (E6).** Run `./gradlew :<dest>:compileTestKotlinIosSimulatorArm64` (or equivalent K/N target per project setup) against the **current** `<dest>/commonTest` source set — BEFORE any baselines are moved. The K/N compile (vs the looser JVM compile) catches reflection-based test patterns, K/N-illegal idioms, and singleton-reset reflection in pre-existing tests that would cascade as invisible failure layers post-mv. Report: clean / list of broken files with compile output. Broken pre-existing tests get `@Ignore` quarantine (same Phase B.2 pattern; per `test-discipline/migration-baselines.md` (Quarantine section)). If quarantine applied, commit separately before E.1.

- **E.0.3 — Pre-mv K/N portability smoke for files being promoted (E1, E2).** For each baseline test file slated for promotion (every file whose corresponding production file is `migrated`):
  - **E.0.3a — Scratch-dir K/N compile (Haiku, parallel per file).** Copy the file content to a scratch location compiled by `compileTestKotlinIosSimulatorArm64` AS-IF it were already in commonTest (without performing the git mv). Compile. Failures surface K/N-illegal patterns — backtick-quoted test names with certain chars, JVM-only imports (`java.*`/`javax.*`/`android.*`), **bare `kotlin.assert(` (K/N gates it behind `@OptIn(ExperimentalNativeApi)`; unusable in common — swap to `kotlin.test.assertTrue`)**, reflection that doesn't survive K/N — **while the file is still at `androidUnitTest` status `migrated`**. **Run the real scratch K/N compile, not an import-grep** — bare `kotlin.assert(` is invisible to a grep and only surfaced at the iOS compile *after* a git mv in a prior session, forcing an extra fix + commit cycle on an already-moved file.
  - **E.0.3b — Verifier subagent (Sonnet) for any BLOCKED files.** First-pass K/N compile output can over-flag (e.g., flagging imports that are actually fine once the file is in commonTest because the source-set transitively closes the import). For every file the scratch compile flagged as BLOCKED, dispatch a Sonnet verifier that re-examines the failure mode against the file's current content + the actual compile output. The verifier confirms or denies the block. Only verifier-confirmed BLOCKED files are demoted or fixed; scanner-only-flagged files proceed to E.1 normally.
  - **For verifier-confirmed blockers:** fix in `androidUnitTest`, then commit fixes BEFORE E.1's mv so E.1's promotion commit stays a pure `git mv`. **These edits DO need a migration-exception.** The `frozen_baseline_guard` hook blocks `migrated`-status baselines too (its `FROZEN_STATUSES` = `frozen` / `migrated` / `promoted`) — not only `frozen` — so even a behavior-preserving portability edit is blocked without one. Use a **single umbrella exception** `.kmm/exceptions/<date>-phase-e-test-portability.md` covering all such edits; **amend its `Authorizes.baseline-edit` list** (append-only) for files surfaced later in the phase. And per SKILL.md Migration-exception process, the orchestrator confirms that exception is in place **before** dispatching any subagent to make the edit (the hook doesn't fire on subagent tool calls).
  - **Module-boundary + feasibility check BEFORE offering the user any fix options (per SKILL.md verify-before-offering).** When a blocker is a reflection/visibility issue (e.g., a test reads an `internal`/`final`-class member), self-verify each candidate fix is actually feasible *before* presenting it: a cross-module `internal` accessor is useless to a `commonTest` in a *different* module; a `final` class can't be subclassed for a fake; K/N has no reflection. *A prior session's N1 fix cost three user decision rounds because each option's infeasibility surfaced only after a subagent tried it.* Pre-filter to compiler-feasible options; run the portability smoke first so options are grounded.

**Bundle the promote-scope call into ONE decision.** When `commonTest` lacks test libs the to-be-promoted baselines import (ktor-mock, turbine, kotlinx-serialization, etc.) and/or some files need verifier-confirmed portability edits, present a single choice (per SKILL.md Decision routing): **promote-all** (wire the missing `commonTest` deps + apply the portability edits under one umbrella exception) **vs promote-only-clean** (move the no-dep-no-edit files now, defer the rest to a future session). State the tradeoff plainly — promote-all buys full JVM+iOS equivalence on every baseline this session; promote-only-clean ships a partial iOS proof. Don't serialize this as per-file dep/edit questions.

### E.1 — Move via `git mv` (Haiku, parallel)

For each baseline test file whose corresponding production file has status `migrated`:
- `git mv <dest>/src/androidUnitTest/.../XTest.kt <dest>/src/commonTest/.../XTest.kt`
- Intra-module move. Content preserved bit-for-bit. History tracked.

Baselines for `hold`-plan files (or `migrate`-files flipped to `hold` via D.3) **stay in androidUnitTest** — they're not promoted.

**Feature-surface baselines:** only promote if every file the baseline exercises reached `commonMain`. If the feature spans a mix of `migrated` + `held` files, the baseline depends on `androidMain` types and **stays in androidUnitTest** — flagged in `move.md`, promotion deferred to a future session.

### E.2 — Update package declarations (Haiku, parallel)

Usually a no-op — Kotlin source sets in the same module typically share package namespaces. If conventions differ, update accordingly.

### E.3 — Run tests in commonTest on JVM (Haiku)

`./gradlew :<dest>:testDebugUnitTest` or `:<dest>:jvmTest` (per project setup). All promoted tests must be green.

If anything fails: **Sonnet** investigates. Common causes:
- Stack edge case slipped past Phase B audit (Truth import, JUnit rule that wasn't caught).
- commonTest source-set dep missing.
- Test references a fixture or helper that didn't migrate alongside it.

Fix via surgical edit (per Tooling discipline: `git restore` for revert; never read-and-rewrite). If unfixable cleanly → demote the file's baseline back to androidUnitTest, flag in `move.md`, surface to user as Phase B audit gap for a follow-up session. (This is rare — implies Phase B audit missed something.)

### E.4 — Run tests in iosTest if host supports (Haiku)

`./gradlew :<dest>:iosSimulatorArm64Test` or equivalent target per profile. All promoted tests must be green.

**Requires a provisioned + booted simulator DEVICE — not just installed runtimes.** A missing/cold sim yields a misleading *"Xcode does not support simulator tests for ios_simulator_arm64"* error that looks like a code/SDK problem but isn't. Pre-create and boot one before the run (`xcrun simctl create <name> <devicetype> <runtime>` then `xcrun simctl boot <name>` + `bootstatus`). The sim name is a per-repo fact → `project.md`. (Recurring across both prior sessions' E and F.)

**Strongest equivalence verification** — same baseline tests now running on the iOS runtime, against the migrated code.

If host doesn't support iOS testing (non-macOS dev machine): skill flags this clearly — full local verification is incomplete. **User decides handling** — test on a Mac, defer until team has access. Skill does not auto-defer to CI.

### E.5 — Update coverage.md

For each baseline promoted: file status flips `migrated` → `promoted`; `Final baseline path` field filled with the commonTest path. Silent write per SKILL.md Diff-confirm scope (`migrations/` writes are not gated).

For files whose baselines stayed in androidUnitTest (held files, or feature-surface baselines tied to mixed migrate+hold features), no change — status remains `frozen` or `migrated`; `Final baseline path` stays at the androidUnitTest path.

### E.6 — Write move.md

- **Haiku subagent** fills structured sections (file moves table, test counts, commit SHA, quarantine summary if E.0 applied).
- **Sonnet subagent** writes prose: any commonTest issues encountered, iOS test results, feature-surface baseline promotion decisions.
- Living document, finalized at E.6 with status complete.
- Final commit follows two-commit cadence (SKILL.md): code commit (the `git mv`) + audit commit (`move.md` + `coverage.md`). Autopilot.

### E.7 — Phase E retro
Amend `retro.md` with `## Phase E — Baseline Promotion (captured YYYY-MM-DD)`. Five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate) — except when Phase E itself was skipped (no `migrated` files), in which case the retro notes the skip.

---

## Output: `move.md`

- Header (status, tasks)
- E.0 — skip check result (proceeded / skipped with reason) + pre-promotion commonTest quarantine (if any)
- File moves table (old path `<dest>/androidUnitTest/...` → new path `<dest>/commonTest/...`); separate row for baselines that stayed in androidUnitTest with rationale
- commonTest JVM run result (test count, all green)
- iosTest run result — or "deferred, host doesn't support iOS testing" with explicit user acknowledgment
- coverage.md updates summary (which files flipped to `promoted`; which stayed at prior status)
- Commit SHA
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase D complete (`migration.md` status = complete, integration verified).
- Skip check evaluated at E.0 — if no `migrated`-status file, Phase E records skipped and exits.
- Pre-promotion commonTest quarantine applied to all broken pre-existing tests (none deferred).
- All promoted baselines green in `<dest>/commonTest` on JVM.
- All promoted baselines green in iosTest (or explicit user acknowledgment of host limitation).
- `coverage.md` updated with `promoted` status per promoted file.

---

## Post-session (outside Phase E, after PR merge)

After the PR merges to main:
- Skill offers `git worktree remove <path>` for cleanup. User confirms (this is destructive — removes the worktree directory).
- Branch `kmm/<feature>-<depth>` can be deleted (or kept as audit-trail tag).
