# Phase F — Validation

**Purpose.** Prove the migration is structurally sound and behavior-preserving *as far as automated checks can show*, then hand a clean, installable build to Phase G (PR), Phase H (code-review intake), and Phase I (parity QA). Multi-layered automated sanity check: code, docs, build, tests, pre-merge integration — plus a runtime-crash smoke. **Behavioral parity QA is NOT in this phase** — it runs after the PR via the `kmm-qa-autopilot` skill (Phase I). Any blocker here → loop back through the relevant prior phase → re-validate.

**What moved out of Phase F.** The old F.6 user-driven manual-QA gate and F.7 "migration complete" sign-off are gone. Parity QA now happens post-PR, off the PR git diff + heatmap, in a separate skill. Phase F's job is: *does it build on both platforms, are the baselines green, does it integrate with the latest base branch, and does it launch without crashing?* The heatmap is still **drafted** here (F.5) because Phase G embeds it into the PR body and Phase I / autopilot consume it.

**The smoke test stays — as a runtime-crash gate, not a QA walk.** Its only job is to confirm the build installs and runs without crashing, so we don't hand a dead build to autopilot and burn a full parity cycle (two APKs + two emulators + a manual prod login) only to crash on launch. It is not a behavioral walk and does not gate on user-visible behavior.

**Inputs:** all prior session files (`scope.md` through `move.md`, status complete), `project.md`, `searches/`, `git diff <base>..HEAD`, `project.md.git.pr_merge_policy`.

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

**Every F.2 review-subagent prompt hard-instructs: diff each finding against `origin/master` FIRST.** Code carried **verbatim from master** is flag-not-fix (behavioral equivalence — Principle #1), **never** a migration BLOCKER, no matter how it reads. Without this, subagents over-flag pre-existing carried code as migration-introduced (NEFT→gpay "BLOCKER", nested-DTO visibility, `var accountId`), and each false positive costs a main-thread `git show origin/master` round-trip to dismiss.

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
  - `<dest>/iosSimulatorArm64Test` (or equivalent, if host supports) — same commonTest baselines on iOS runtime. **Requires a provisioned + booted simulator device** (see F.5 note) — a cold/missing sim yields a misleading "Xcode does not support simulator tests" error, not a code failure.
- Full `:app/src/test/` unit test suite (regression check — pre-existing tests untouched apart from Phase B import updates).
  - **Baseline against the MERGE-BASE (fork point), not `origin/<base>`.** `origin/master` may itself be non-compiling or red — diffing against it manufactures phantom regressions. Use `git merge-base HEAD origin/<base>` as the comparison point. **If the base can't compile its tests, replicate the branch's known compile-exclusions on the baseline before diffing** so it's apples-to-apples (a prior session found both `origin/master` and the fork-base failed `:app:compileProductionDebugUnitTestKotlin`, so the suite was non-compilable *before* this branch — only after replicating the exclusion did a clean HEAD-vs-fork diff prove 0 regressions). Generalize this "the baseline may itself be broken" handling.
  - **When the full suite hangs on a pre-existing pathological test, bound the run** to the enumerated failing/relevant set + a structural diff argument — don't fight a hang that predates the branch (one app test pegged a worker at ~100% CPU for 27 min with no output). Pair with the gradle timeout-with-grace wrapper (SKILL.md Tooling discipline) so a hang can't run for hours.
- **Confirm tests actually executed (not cached).** "BUILD SUCCESSFUL" is emitted on an `UP-TO-DATE` no-op too. For each test task above, read `build/test-results/<task>/*.xml` and confirm the testsuite ran with the expected `tests` count and `failures=0` (per SKILL.md Tooling discipline). A green that never ran is not a green.
- **Visual regression** (Paparazzi/Roborazzi) against pre-migration goldens if UI was indirectly touched.
- **Telemetry parity scan** — analytics events preserved through migrated code paths (Sonnet scans for analytics-relevant changes).
- **Crash-reporting hookup verified** for migrated namespaces (Crashlytics/Sentry still receives from new package paths).
- **HTTP client timeout parity verification** (if Phase A's sub-phase 1.5 produced a per-service timeout table). Smoke a representative endpoint per service from the table; observe real `tookMs` and timeout behavior via network capture (per project's HTTP-inspection capability). Confirm each service's effective timeout matches plan.md. Empty timeout install or default values where higher was specified surface here, not in QA — these are P0-class failures. Failure → loop back to D.
- **HTTP client server-registration verification** (if Phase A's sub-phase 1.5 produced a server-registration table). For each new/changed host in the table, fire the smoke endpoint and confirm the request actually reaches the intended backend (non-500, expected response shape). A missing host registration in the shared client config object surfaces as 500s or DNS resolution failures here. Failure → P0; loop back to D.
- **Performance regression check** (if project has androidx-benchmark wiring): flag >10% regression on critical paths.
- **Memory regression check** (if instrumentation available): flag baseline-level regressions, especially on iOS (Kotlin/Native memory model differs from JVM).

### F.4 — Pre-merge integration test

**Choose merge vs rebase from the repo's PR-merge policy — do not default to rebase.** Read `project.md.git.pr_merge_policy`:
- **`squash` (the common case)** → simulate integration with `git merge origin/<base>` in a scratch branch. A squash-merge collapses the whole branch into one commit on the base, so the *merged tree* is what ships — a merge is the true simulation. **A rebase is wrong here**: it replays every intermediate commit, so a file the branch *relocated* collides with the base's edit at the *old* path, producing spurious conflicts that will never occur on the actual squash-merge.
- **`rebase`** → simulate with rebase.
- **`merge`** → simulate with merge.

**Detect conflicts with the same operation that will integrate.** `git merge-tree --write-tree` validates a *merge*, not a *rebase* — in a prior session it reported clean while the actual rebase conflicted. Use the chosen operation for both detection and simulation; never a proxy.

- Re-run F.3 (build + tests) on the integrated state, including the JUnit-XML execution check.
- **Cross-session ripple verification** — did this migration affect files frozen in OTHER active session worktrees? Scan sibling `.kmm/migrations/*/coverage.md`.
- **Post-integration leak check** — after the merge, diff the integrated tree against pre-merge for the migrated source sets (`commonMain`/`commonTest`); 3-way merge + rename detection can silently carry the base's same-path edits onto relocated files. Confirm zero leak.
- A scratch worktree needs gitignored build config copied in before it configures (`local.properties`, flavor `google-services.json`, `keystore.properties`); auto-copy from the primary worktree and run a quick `:app:help` configure check before the long build.

If conflicts surface: user resolves; skill assists with diff-confirm. Recon first (cheap `merge`/divergence/sibling-ripple scan) **before** launching the expensive full build — don't blind-build a conflicted or leaky integration.

### F.5 — Runtime-crash smoke + heatmap draft (in parallel)

**Smoke test (Sonnet subagent) — runtime-crash gate only, NOT a behavioral walk.**
- **Check `adb devices` FIRST.** If no device/emulator is connected, surface it and boot one *before* building — never discover "no device" after a ~15-min build. (Emulator binary may not be on PATH; project.md records the AVD names + path.)
- Build the ProductionRelease APK (the shipped, R8-minified artifact — never Debug; debug skips R8 and false-greens serialization migrations) and install on the device.
- Launch the app; confirm it **starts and does not crash** (crash-only logcat scoped to the app PID). Login/OTP-gated deep walks are user territory — the smoke does not attempt them. **The launch smoke cannot exercise post-login serialization paths**, so R8/ProductionRelease serialization runtime parity (the kotlinx keep-rule + decode behavior on real payloads) is **explicitly deferred to Phase I parity QA** — a crash-free launch is not evidence of serialization parity.
- **Navigation discipline:** if the subagent navigates at all, it **must use the structured-tap CLI** and is **forbidden from back-gesture walking** (back-gestures exit the app and invalidate the check). If the tap CLI isn't available, the agent **screenshots and reports** — it does not fumble the device.
- Output: launch confirmation + crash-free logcat (or the crash, if any). Goal met = installs + launches + no crash.

**Heatmap draft (Opus subagent, in parallel).**

Drafted as a **pre-QA checklist** that Phase G embeds into the PR body and Phase I / `kmm-qa-autopilot` consume. Result column starts `TBD` and is **never** pre-filled — it is filled during the post-PR parity QA (Phase I), not here.

**Primary source: `journeys.md`.** Each row in the heatmap maps directly to one entry in the journey catalog. The Opus subagent reads `journeys.md` (produced by Phase A) and renders one heatmap row per journey, carrying a pointer to that journey's frozen golden reference (the `golden/<journey>/` directory under the session's migration root). diff-derived behavior discovery is no longer the primary source here — it lives in Phase A as the coverage cross-check that validates `journeys.md` is complete.

Format (tickable markdown saved as `heatmap.md`):

| Journey | User does | Expects to see | Golden ref | Result |
|---|---|---|---|---|
| <journey name from journeys.md> | <action from journeys.md> | <expected output from journeys.md> | `golden/<journey>/` | TBD |
| ... | ... | ... | ... | TBD |

### F.6 — Blocker loop

Any failure in F.1–F.5 → **Opus** categorizes:

| Failure type | Loop-back target |
|---|---|
| Missing migration | Phase D fix |
| Scope creep | Phase 0 `update scope` action |
| API drift | Phase D fix |
| Quality issue | Phase D code edit |
| Build / test failure | Investigate, Phase D fix |
| Smoke crash | Phase D fix, or Phase D plan flip to `hold` via D.3 |
| Integration conflict / leak | Resolve in F.4; re-run |

**Re-validation scope after fix — depends on fix surface area:**

- **Surgical fix (≤5 LOC, single file, no new types / methods / public-API signatures):** re-run F.3 (build + tests, incl. JUnit-XML execution check) + F.5 smoke. **Skip** F.1 (goal/doc consistency unchanged), F.2 (code quality, single-file is trivially reviewable), F.4 (pre-merge integration — only if the base moved since the last F.4). Example: changing a single timeout literal, fixing one off-by-one, swapping one constant.
- **Non-surgical fix (≥6 LOC, multiple files, new identifiers introduced, or behavioral diff beyond the immediate fix):** return to F.1, re-validate fully. No partial re-validation.

Skill announces which scope it's using before re-running, with one-line justification (e.g., *"Surgical: 1-line socket timeout swap, re-running F.3 + F.5 only"*). User can override with `re-run fully` or `re-run targeted`. **The threshold is mechanical, derivable from the diff** — not a judgment call to be made under fatigue.

When all F passes → `validation.md` status complete → proceed to Phase G (PR). **There is no manual-QA sign-off here** — parity QA is Phase I, post-PR. (Provenance note: also run the exception-provenance check now, so orphan exceptions surface before Phase G composes the body — see phase-g.)

### F.7 — Phase F retro
Amend `retro.md` with `## Phase F — Validation (captured YYYY-MM-DD)`. Five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate).

---

## Outputs

- **`validation.md`** — full validation transcript (status, F-sub-phase results, decisions log)
- **`heatmap.md`** — QA checklist (separate file, PR-linkable)

---

## Phase-specific gates

Beyond universals:

- Every F sub-phase passes (or has documented exception).
- Test green-ness is confirmed via JUnit-XML execution + counts, not "BUILD SUCCESSFUL" alone.
- F.4 integration uses the operation dictated by `project.md.git.pr_merge_policy` (merge for squash-merge repos), and conflict detection uses that same operation.
- Smoke confirms the ProductionRelease build installs + launches **crash-free**; `heatmap.md` is drafted with `TBD` cells and never pre-filled (it's filled during Phase I parity QA).
- `validation.md` status `complete` before Phase G. **No manual-QA sign-off gate** — parity QA is Phase I, post-PR.
