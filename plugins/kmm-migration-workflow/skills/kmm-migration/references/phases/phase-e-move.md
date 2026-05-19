# Phase E — Baseline Promotion

**Purpose.** For files whose code reached `<dest>/commonMain` in Phase D (status `migrated`), promote their baseline tests from `<dest>/androidUnitTest/` to `<dest>/commonTest/`. The baselines were written in the KMM-portable stack at Phase B, so the promotion is mechanical (`git mv` + verify). This is the **strongest equivalence verification** — the same baseline tests now run on both JVM and iOS runtimes against the migrated production code.

**Conditional.** If no in-scope file reached `commonMain` by end of Phase D (all `hold`-plan, or all `migrate`-plan flipped to `hold` via D.3), Phase E is skipped entirely — baselines stay in `androidUnitTest` as their final destination this session. A future session can promote when code ripens.

**Inputs:** all prior session files (`scope.md` through `migration.md`, status complete), `project.md`, `coverage.md`.

---

## Sub-phases

### E.0 — Skip check + pre-promotion commonTest health (Haiku)

- **Skip check.** Read `coverage.md`: if no row has status `migrated`, Phase E is skipped. Skill records "Phase E skipped — no files reached commonMain this session" in `move.md` and proceeds to Phase F.
- **Pre-promotion commonTest health check** (if Phase E proceeds). Quick compile check on `<dest>/commonTest`. Report: clean / N broken (file list). Broken pre-existing tests are **quarantined via `@Ignore`** (same pattern as Phase B step B.2; per `test-discipline/migration-baselines.md` (Quarantine section)), not fixed here. If quarantine applied, commit separately before E.1.

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

**Strongest equivalence verification** — same baseline tests now running on the iOS runtime, against the migrated code.

If host doesn't support iOS testing (non-macOS dev machine): skill flags this clearly — full local verification is incomplete. **User decides handling** — test on a Mac, defer until team has access. Skill does not auto-defer to CI.

### E.5 — Update coverage.md

For each baseline promoted: file status flips `migrated` → `promoted`; `Final baseline path` field filled with the commonTest path. Silent write per SKILL.md Diff-confirm scope (`migrations/` writes are not gated).

For files whose baselines stayed in androidUnitTest (held files, or feature-surface baselines tied to mixed migrate+hold features), no change — status remains `frozen` or `migrated`; `Final baseline path` stays at the androidUnitTest path.

### E.6 — Write move.md

- **Haiku** fills structured sections (file moves table, test counts, commit SHA, quarantine summary if E.0 applied).
- **Sonnet** writes prose: any commonTest issues encountered, iOS test results, feature-surface baseline promotion decisions.
- Living document, finalized at E.6 with status complete.
- Final commit follows two-commit cadence (SKILL.md): code commit (the `git mv`) + audit commit (`move.md` + `coverage.md`). Autopilot.

### E.7 — Phase E retro
Amend `retro.md` with `## Phase E — Baseline Promotion (captured YYYY-MM-DD)`. Five-bullet structure. User can skip with `skip retro`. Skipped if Phase E itself was skipped (no `migrated` files).

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
