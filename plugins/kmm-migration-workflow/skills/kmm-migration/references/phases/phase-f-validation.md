# Phase F — Validation

**Purpose.** Prove the migration achieved its stated goal. Multi-layered sanity check: code, docs, build, tests, runtime smoke, manual QA. **User-gated.** Any blocker → loop back through the relevant prior phase → re-validate. Migration is not complete until F is clean AND user signs off.

**Inputs:** all prior session files (`scope.md` through `move.md`, status complete), `project.md`, `searches/`, `git diff main..HEAD`.

---

## Sub-phases

### F.1 — Goal + doc consistency

- **Haiku** runs `git diff main..HEAD --stat`, parses changed files.
- **Sonnet** cross-checks vs `scope.md`:
  - Every in-scope file appears in the diff.
  - No out-of-scope file appears in the diff (scope creep check).
  - API signatures unchanged (sig diff against pre-migration).
- **Haiku** scans all session docs for stale references (e.g., `audit.md` says X is `Augment` but `coverage.md` shows `frozen` without the Augment work recorded).
- **Sonnet** verifies decisions log explains *why* for each significant choice.
- **Migration-exception completeness check** — each baseline edit has a matching `.kmm/exceptions/` entry.
- **Dependency-addition audit** — new library deps introduced, justified, properly versioned, documented in plan.md or project.md.
- **Opus** reviews any mismatches.

### F.2 — Code quality + iOS surface (parallel Sonnet per file)

Per migrated file:
- Clean code adherence — no `*Holder` / `*Manager` cruft.
- DRY / KISS check.
- Idiomatic KMM — cross-check live-search patterns from `plan.md` and project.md conventions.
- Comment / KDoc accuracy post-migration.

Dedicated subagent: **SKIE-generated Swift surface review** for the migrated public API:
- Nullability translates cleanly to Swift optionals.
- No verbose generic gymnastics.
- Names read naturally from Swift.
- Convenience overloads present for Kotlin default-arg methods.

**Opus** for cross-file synthesis review (shared interfaces, DI module).

### F.3 — Build + tests

- **Haiku** runs clean build: `./gradlew clean assemble`.
- All variants compile (Android debug/release; iOS targets per project setup).
- **No new warnings** vs pre-migration baseline (compare warning count).
- **App size delta** reported (KMM concern — shared module adds bytes).
- Full baseline suite in commonTest + iosTest if host supports.
- Full `app/` unit test suite (regression check — pre-existing tests untouched).
- **Visual regression** (Paparazzi/Roborazzi) against pre-migration goldens if UI was indirectly touched.
- **Telemetry parity scan** — analytics events preserved through migrated code paths (Sonnet scans for analytics-relevant changes).
- **Crash-reporting hookup verified** for migrated namespaces (Crashlytics/Sentry still receives from new package paths).
- **Performance regression check** (if project has androidx-benchmark wiring): flag >10% regression on critical paths.
- **Memory regression check** (if instrumentation available): flag baseline-level regressions, especially on iOS (Kotlin/Native memory model differs from JVM).

### F.4 — Pre-merge integration test

- **Haiku** rebases against latest main in a scratch branch.
- Re-runs F.3 (build + tests) on the rebased state.
- Catches merge conflicts and integration regressions before PR opens.
- **Cross-session ripple verification** — did this migration affect files frozen in OTHER active session worktrees? Scan sibling `.kmm/migrations/*/coverage.md`.

If conflicts surface: user resolves; skill assists with diff-confirm.

### F.5 — Smoke test + heatmap generation (in parallel)

**Smoke test (Sonnet):**
- Build APK + install on running emulator (via ADB).
- Walk the captured navigation flow from `scope.md`.
- Verify: no crashes, no obvious behavior changes vs pre-migration.
- Output: screenshots / logs for user verification.

**Heatmap generation (Opus, in parallel):**
- Generate structured QA checklist based on:
  - Phase 0 navigation flow
  - plan.md risk register
  - Per-file behavior surfaces
- For each user-facing flow to verify: steps to reproduce, expected behavior, risk areas to focus on.
- Format: tickable markdown saved as `heatmap.md` (separate file so PR can link it independently of `validation.md`).

### F.6 — Manual QA gate (user-driven)

User exercises the heatmap on a real device or emulator:
- Ticks boxes as flows are verified.
- Records any anomalies found.

**Phase F blocks** until heatmap is fully checked OR all anomalies are resolved.

This is real human time — typically 30+ minutes on a non-trivial migration. The skill waits.

### F.7 — Blocker loop + sign-off

Any failure in F.1–F.6 → **Opus** categorizes:

| Failure type | Loop-back target |
|---|---|
| Missing migration | Phase D fix |
| Scope creep | Phase 0 `update scope` action |
| API drift | Phase D fix |
| Quality issue | Phase D code edit |
| Build / test failure | Investigate, Phase D fix |
| Smoke failure | Phase D fix or hold-back |
| QA-found behavior anomaly | Investigate, Phase D fix or migration-exception (if intentional) |

After fix → **return to F.1, re-validate fully**. No partial re-validation.

When all F passes → user explicit "migration complete" confirmation → `validation.md` status complete.

---

## Outputs

- **`validation.md`** — full validation transcript (status, F-sub-phase results, decisions log)
- **`heatmap.md`** — QA checklist (separate file, PR-linkable)

---

## Phase-specific gates

Beyond universals:

- Every F sub-phase passes (or has documented exception).
- Manual QA heatmap fully checked off by user.
- User **explicit "migration complete" confirmation** before Phase G.
