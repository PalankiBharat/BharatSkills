# Phase F — Validation

**Purpose.** Prove the migration achieved its stated goal. Multi-layered sanity check: code, docs, build, tests, runtime smoke, manual QA. **User-gated.** Any blocker → loop back through the relevant prior phase → re-validate. Migration is not complete until F is clean AND user signs off.

**Inputs:** all prior session files (`scope.md` through `move.md`, status complete), `project.md`, `searches/`, `git diff main..HEAD`.

---

## Sub-phases

### F.1 — Goal + doc consistency

- **Haiku** runs `git diff main..HEAD --stat`, parses changed files.
- **Sonnet** cross-checks vs `scope.md` + `plan.md` Phase D plan:
  - Every in-scope file appears in the diff (relocated to `<dest>/androidMain` at minimum; `migrate`-plan files also moved to `commonMain`).
  - No out-of-scope file appears in the diff (scope creep check).
  - API signatures unchanged (sig diff against pre-migration).
- **Haiku** scans all session docs for stale references (e.g., `audit.md` says X is `Augment` but `coverage.md` shows `frozen` without the Augment work recorded).
- **Sonnet** verifies decisions log explains *why* for each significant choice.
- **Migration-exception completeness check** — each baseline edit has a matching `.kmm/exceptions/` entry.
- **Dependency-addition audit** — new library deps introduced, justified, properly versioned, documented in plan.md or project.md.
- **Opus** reviews any mismatches.

### F.2 — Code quality + iOS surface (parallel Sonnet per file)

Per in-scope file (migrated and held):
- Clean code adherence — no `*Holder` / `*Manager` cruft.
- DRY / KISS check.
- Idiomatic KMM — cross-check live-search patterns from `plan.md` and project.md conventions.
- Comment / KDoc accuracy post-migration (per Tooling discipline: one-liner WHY comments only; no WHAT comments).

For `migrated`-status files (now in `commonMain`), additional dedicated subagent: **SKIE-generated Swift surface review** for the migrated public API:
- Nullability translates cleanly to Swift optionals.
- No verbose generic gymnastics.
- Names read naturally from Swift.
- Convenience overloads present for Kotlin default-arg methods.

Held files (`androidMain`) skip the SKIE surface review — they're not exposed to iOS this session.

**Opus** for cross-file synthesis review (shared interfaces, DI module).

### F.3 — Build + tests

- **Haiku** runs clean build: `./gradlew clean assemble`.
- All variants compile (Android debug/release; iOS targets per project setup).
- **No new warnings** vs pre-migration baseline (compare warning count).
- **App size delta** reported (KMM concern — shared module adds bytes).
- Baseline suites green:
  - `<dest>/androidUnitTest` — baselines for held files + any feature-surface baselines that stayed.
  - `<dest>/commonTest` (if Phase E ran) — baselines for promoted files.
  - `<dest>/iosSimulatorArm64Test` (or equivalent, if host supports) — same commonTest baselines on iOS runtime.
- Full `:app/src/test/` unit test suite (regression check — pre-existing tests untouched apart from Phase B import updates).
- **Visual regression** (Paparazzi/Roborazzi) against pre-migration goldens if UI was indirectly touched.
- **Telemetry parity scan** — analytics events preserved through migrated code paths (Sonnet scans for analytics-relevant changes).
- **Crash-reporting hookup verified** for migrated namespaces (Crashlytics/Sentry still receives from new package paths).
- **HTTP client timeout parity verification** (if Phase A's sub-phase 1.5 produced a per-service timeout table). Smoke a representative endpoint per service from the table; observe real `tookMs` and timeout behavior via network capture (per project's HTTP-inspection capability). Confirm each service's effective timeout matches plan.md. Empty timeout install or default values where higher was specified surface here, not in QA — these are P0-class failures. Failure → loop back to D.
- **HTTP client server-registration verification** (if Phase A's sub-phase 1.5 produced a server-registration table). For each new/changed host in the table, fire the smoke endpoint and confirm the request actually reaches the intended backend (non-500, expected response shape). A missing host registration in the shared client config object surfaces as 500s or DNS resolution failures here. Failure → P0; loop back to D.
- **Performance regression check** (if project has androidx-benchmark wiring): flag >10% regression on critical paths.
- **Memory regression check** (if instrumentation available): flag baseline-level regressions, especially on iOS (Kotlin/Native memory model differs from JVM).

### F.4 — Pre-merge integration test

- **Haiku** rebases against latest main in a scratch branch.
- Re-runs F.3 (build + tests) on the rebased state.
- Catches merge conflicts and integration regressions before PR opens.
- **Cross-session ripple verification** — did this migration affect files frozen in OTHER active session worktrees? Scan sibling `.kmm/migrations/*/coverage.md`.

If conflicts surface: user resolves; skill assists with diff-confirm.

### F.5 — Smoke test + heatmap generation (in parallel)

**Smoke test (Sonnet subagent):**
- Build APK + install on running emulator (via ADB).
- Walk the captured navigation flow from `scope.md`.
- Verify: no crashes, no obvious behavior changes vs pre-migration.
- Output: screenshots / logs for user verification.

**Heatmap generation (Opus subagent, in parallel with smoke test):**

Drafted as a **pre-QA checklist**, not a post-QA summary. Result column starts empty; user fills it during F.6.

Sources:
- Phase 0 navigation flow
- plan.md risk register
- Per-file behavior surfaces (focus on `migrate`-plan files; held files unchanged at observable level since their code didn't move from `androidMain`)

Format (tickable markdown saved as `heatmap.md`):

| Surface | Observable | Result |
|---|---|---|
| <user-facing flow> | <expected behavior, risk area to watch> | TBD |
| ... | ... | TBD |

Skill **presents `heatmap.md` to the user before F.6 starts** and never pre-fills the Result column. Post-hoc summaries of QA outcomes belong in `validation.md`, not `heatmap.md`.

### F.6 — Manual QA gate (user-driven)

**Precondition:** `heatmap.md` (from F.5) is open and presented to the user with `TBD` Result cells. F.6 cannot start until this is true.

User exercises the heatmap on a real device or emulator:
- **Fills in each Result cell** (pass / fail / anomaly note) as flows are verified.
- Records any anomalies found.

**Phase F blocks** until every Result cell has a value AND all anomalies are resolved (or filed as follow-ups with user sign-off).

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
| Smoke failure | Phase D fix, or Phase D plan flip to `hold` via D.3 |
| QA-found behavior anomaly | Investigate, Phase D fix or migration-exception (if intentional) |

**Re-validation scope after fix — depends on fix surface area:**

- **Surgical fix (≤5 LOC, single file, no new types / methods / public-API signatures):** re-run F.3 (build + tests) + F.5/F.6 smoke + the heatmap row(s) that exercise the fix's surface. **Skip** F.1 (goal/doc consistency unchanged), F.2 (code quality, single-file is trivially reviewable), F.4 (pre-merge integration — only if the merge target moved since the last F.4). Example: changing a single timeout literal, fixing one off-by-one, swapping one constant.
- **Non-surgical fix (≥6 LOC, multiple files, new identifiers introduced, or behavioral diff beyond the immediate fix):** return to F.1, re-validate fully. No partial re-validation.

Skill announces which scope it's using before re-running, with one-line justification (e.g., *"Surgical: 1-line socket timeout swap, re-running F.3 + F.6 only"*). User can override with `re-run fully` or `re-run targeted`. **The threshold is mechanical, derivable from the diff** — not a judgment call to be made under fatigue.

When all F passes → user explicit "migration complete" confirmation → `validation.md` status complete.

### F.8 — Phase F retro
Amend `retro.md` with `## Phase F — Validation (captured YYYY-MM-DD)`. Five-bullet structure. User can skip with `skip retro`. User-steering log section is especially load-bearing here — F.6 is human-driven and friction often surfaces verbally.

---

## Outputs

- **`validation.md`** — full validation transcript (status, F-sub-phase results, decisions log)
- **`heatmap.md`** — QA checklist (separate file, PR-linkable)

---

## Phase-specific gates

Beyond universals:

- Every F sub-phase passes (or has documented exception).
- `heatmap.md` presented to user with `TBD` Result cells **before** F.6 starts; skill never pre-fills Result column.
- Manual QA heatmap fully filled in by user (every Result cell has a value).
- User **explicit "migration complete" confirmation** before Phase G.
