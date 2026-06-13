# Learnings Ledger — incidents, taxonomy, PR history

The plugin's living memory of what KMM migrations in sniper-v2-android get wrong and right. Mined 2026-06-13 from PRs #311–#439, six worktree retros, and `.kmm/exceptions/`. Entries: evidence → prevention (and where the pipeline enforces it: GUARD / phase doc / rubric / Law rule).

## UPDATE PROTOCOL (how this file stays current — never skip)

- **At every `phase-done`** the orchestrator asks: did this phase surface a durable repo-KMM fact (new trap, seam decision, SDK/klib fact, gradle/QA quirk, review theme)? If yes: append it here or to `repo-profile.md` (dated, with source), commit to the plugin SOURCE repo — `~/dev/claude-code-skills` master, message `knowledge(<slug>): phase <n> — <fact>` — then run `claude plugin update kmm-pipeline` so the installed copy refreshes. The NEXT migration reads it immediately; no sniper PR merge in the way.
- **At ship (phase 7)**: push the accumulated knowledge commits and open a PR on the plugin repo (`gh pr create`) for team review — local master already serves local migrations, the PR shares it.
- Entries are dated hypotheses (Law Rule 7): re-verify version-sensitive ones when the toolchain moves.

## PR history — what shapes cost what (mined 2026-06-13)

| PR | What | Commits | Churn | Open→merge |
|---|---|---|---|---|
| #439 | login → iOS parity (rewrite-heavy, in-repo review docs) | **169** | ~18% rework + ~33% review-response | open 4d+ at mining time |
| #367 | FX Menu foundational types (API-changing, Date→Instant) | 52 | ~40% | **21.8 d** |
| #425 | indicator-template catalog (move + seam) | 21 | 35% | 7.2 d |
| #389 | 202 pure Kotlin types (verbatim FQN-preserving moves, iOS-gated batches) | 10 | 10% | **0.6 d** |
| #378 | holdings business logic | 15 | 31% | 5.2 d |
| #405 | Date↔Instant adapter elimination | 14 | 67% | 4.8 d |
| #311 | 37 regression fixes for #297's login rewrite fallout | — | pure rework of a parent PR | — |

The lesson the pipeline is built on: **#389's shape (verbatim moves, per-batch iOS gates, baselines first) is the 10-commit/0.6-day shape; rewrite-style and API-changing migrations are the 50–170-commit shape.**

## Mistake taxonomy (M1–M15)

- **M1 Behavior loss in rewrite-style screens** — dropped analytics, experiment cohorts, testTags, one-shot nav effects, `BackHandler`, typography (7 blockers #439; 37 post-merge fixes #311). Prevention: observable-surface machine-diff, zero-loss or waiver → qa lane 5; rubric §1.
- **M2 Wire-format/schema breaks** — ObjectBox `type` change under unchanged `uid` → data wipe → mass logout (#367); Gson→kotlinx drops five leniencies silently. Prevention: GUARD blocks objectbox-models edits; frozen-fixture round-trip tests (real payloads: missing-key/unknown-enum/explicit-null) → rubric §3; boundary types never change, domain converts at the edge.
- **M3 CancellationException swallowed** — `catch (e: Exception)` in Retrofit→Ktor conversions, 5 identical blockers (#396). Prevention: GUARD; rubric §4.
- **M4 K/N portability assumed** — `String.format`, JVM `Locale`, reflection, backtick test names with `,()./[]<>` (#389/#425/#439; `Dispatchers.IO` is actually portable — see the round-2 correction; escaping-exception fatality → kn-fatal-coroutine, round-3). Prevention: per-batch `compileKotlinIosArm64` + `compileTestKotlinIosSimulatorArm64` (phase-4); GUARD on test names; rubric §2/§4.
- **M5 Session artifacts committed** — `.kmm/` state, `.broken` stubs, review docs, comment-stripping commits needed later (#425 `f765547e96` 713 deletions). Prevention: git-exclude at preflight; GUARD comments/.broken; rubric §13.
- **M6 Tests silenced to go green** — 14 files renamed `.kt.broken` (#367), `@Ignore` without rationale. Prevention: GUARD; rubric §2.
- **M7 Seam over-engineering** — Supertrend colour seam: FOUR designs, right answer was two commonMain constants (#425 chain `d681e40b9b`→`c185041d34`). Prevention: plan requires stated per-platform runtime difference per seam (phase-3); rubric §10.
- **M8 Package-renaming "moves"** — ~234 consumer imports rewritten then fully reverted (#367); Kotlin allows package ≠ directory. Prevention: Law Rule 2 (FQN verbatim); qa lane 9 asserts consumer-import delta = 0.
- **M9 Master-merge regressions** — merges silently uncompiled frozen baselines / dropped imports (#367/#425/#439). Prevention: post-merge full re-gate incl. baselines-EXECUTED assert (phase-7 step 1).
- **M10 Dependency hygiene** — alpha shipped to prod path (#425 blocker), `-local` coordinate committed, catalog bypassed (#415). Prevention: GUARD (pre-release versions, raw coordinates); rubric §12.
- **M11 Silent fallback defaults** — throwing `parseColor` became silent black; bad resource → silent White (#415/#425/#439). Prevention: new fallback requires non-fatal log → rubric §4.
- **M12 Release/link-only failures** — R8 missing-class, release-only Hilt break, framework-link SKIE errors invisible at klib stage (#439 `5f33764eb6`, `01a5d12fb3`). Prevention: qa lane 4 (`assembleProductionRelease`); phase-4 exit xcodebuild smoke; R8 duplicate-class on split files → `@file:JvmName` (reports retro).
- **M13 Scope creep / collateral edits** — unrelated refactors, whitespace noise, deleted investigation logs ("don't remove these logs" — #405). Prevention: GUARD (log deletions); files ⊆ step inventory check (phase-4); rubric §13.
- **M14 Clock/timezone drift** — `Clock.System.now()` unpinnable by baselines; IST hardcoded over system zone (#367/#405). Prevention: GUARD (wall clock in commonMain); rubric §5.
- **M15 Re-typing instead of moving** — `%s` rendered literally, wrong drawables, dropped `imePadding`, duplicate HTTP headers (#439/#311). Prevention: Law Rules 1/3 (verbatim moves, whitelist hunks); rubric §9.

## Session incidents not subsumed above (each: trap → prevention)

- **KSP/iOS warm-cache masking** — warm `compileKotlinIosArm64` reused KSP output, missed an expect-object contract violation (watchlist). Cold path = scoped `clean` + compile at phase-4 exit (`--rerun-tasks` banned here).
- **Staged-rename revert data loss** — `git checkout -- <path>` on a staged rename restored the PRE-migration blob (login). Snapshot (`git stash push`) then revert whole commits (phase-4; migrator brief).
- **Fabrication after failed Read** — orchestrator narrated a "broken scaffold" from a nonexistent path (login). Law Rule 7 corollary: failed Read → re-verify (`git ls-files`) → surface.
- **Plan self-contradiction** — same file in two batches surfaced as a mid-execute blocker (positions-orders). Topological self-check at phase-3.
- **Phantom library versions** — GitLive 2.5.0 planned, never existed; Room 3.0 package rename missed (watchlist). Verify version existence + ABI fit via Maven metadata before the plan names it (phase-2).
- **Cross-module `internal` accessors** — commonTest in `:shared` can't see `internal` members of `:sniper-library`; two false-start fixes before a public accessor (watchlist). Check module boundary before choosing the test seam.
- **Robolectric coupling** — VMs calling compose-resources `getString()` directly are untestable on JVM without Robolectric; inject a string-resource provider (reports).
- **Compose-resources traps** — `Font()` in commonMain typography cascades `@Composable` into VMs (35 call sites broken; use expect/actual FontFamily); `R.string`→`Res.string` needs positional `%1$s` (literal `%s` rendered to users) (reports).
- **Version skew on new androidMain deps** — `:shared` compiled lottie 5.2.0, `:app` resolved 6.1.0 → runtime `NoSuchMethodError` (reports). `dependencyInsight` both modules; pin to `:app`'s resolved version.
- **Gradle `--tests` wildcards** — match class prefixes, not file names; multi-class files silently match nothing (positions-orders). Enumerate FQ class names.
- **Coverage/status drift** — phase docs' status columns rot; git + journal are authoritative (watchlist). Encoded in state.md reconciliation.
- **Stale cross-session notes** — "UiEventBus blocks XCFramework" was disproven by actually running the link (login-ios track). Notes are hypotheses; re-verify infra claims before acting.

## Round-2 incidents (worktree-docs mining, 2026-06-13)

- **Shared Ktor client Json lacks `coerceInputValues`** — stores needing Gson parity (unknown-enum→null) must decode via a per-store `Json {}` from `bodyAsText()`, not `body<T>()`; funds consolidated this as `fundsJson` (funds `.kmm/project.md`, migration.md L47-48). Widening the SHARED client's Json is forbidden — it changes every store's semantics.
- **Unknown-enum→null needs BOTH `coerceInputValues` AND a nullable field** — missing the nullability silently flips null→throw (funds exceptions 2026-06-03/05). Pin per-field fixtures (missing key / unknown enum / explicit null) against the OLD engine before the swap — baselines authored against the NEW/strict engine let two real regressions reach runtime QA (funds) — and document the contract at the field (`status: X? = null`).
- **Per-service response asymmetries are baseline material** — withdrawal returns 503 with a message ONLY for one business case while 400/500 mean plain failure; the asymmetry must be pinned as assertions before the Ktor store is written (funds exception 2026-06-04).
- **`Dispatchers.IO` on Kotlin/Native is an extension property** — the misleading `it is internal in Dispatchers` compile error just means the file lacks `import kotlinx.coroutines.IO` (corrected 2026-06-13; earlier sessions misdiagnosed it as non-portable). Prefer injecting a `CoroutineDispatcher` anyway for testability (PagingSource precedent). Platform exceptions still need wrapping into sealed results at the boundary — Android exception types don't exist on iOS.
- **Cross-module smart-casts break when a type moves modules** — fix is a local `val` binding at the consumer, named in the plan (P&O migration.md L108; #425 precedent).
- **Static accessor → injected repository is an EXPECTED milestone**, not creep: companion `get()/empty()` self-instantiation blocks moves; plan it as its own whitelisted step with DI rewiring (funds coverage.md, P&O ChecksumRepository ctor reshape).
- **SharedFlow watcher leak** — `map.remove(key)` without cancelling the watcher coroutine launched at subscribe keeps replay buffers alive forever (marketpulse SDK OOM investigation). Any auto-unsubscribe pattern: cancel on remove, verify via heap diff under stress.
- **Pre-existing-break discovery is a step-zero workflow** — compile the test source sets FIRST, quarantine pre-existing failures (via `@Ignore` + tracking here; the old `.broken`-rename route is guard-banned), THEN write baselines; keeps "pre-existing vs introduced" provable (P&O retro B.2).
- **`--rerun-tasks` nuance** — the repo-wide guard ban (mechanism + why: repo-profile Gradle gotchas) has ONE proven exception: past sessions ran it successfully on `:sniper-library` test tasks only. Everywhere else, cold-verify via scoped `clean` + re-run.
- **iOS klib compile belongs in PRE-flight** — metadata + Android compiles passing while `iosArm64` fails was discovered one batch late (P&O retro D.0). Phase 0 records the pre-migration green state of all four compile targets so later failures are attributable.

## Plan shapes that worked (from real plan/coverage/audit docs)

- **Coverage registry** for >10-file migrations: table in plan.md — file | step | status | frozen/final SHA — flipped only at orchestrator verify time (funds coverage.md had 28 auditable rows).
- **Plan header sections**: Locked decisions (substitutions settled at planning, never re-derived mid-execute) · Risk register (per-file) · Rejected improvements (scope boundary for reviewers) (P&O plan.md).
- **Dependency-chain batching**: a store + its consumers + its DI provider travel in ONE step when consumers hand-construct the store; three independent store-chains = three independent steps (funds replan 2026-06-03).
- **Four-target gate per batch**: `:shared:compileDebugKotlinAndroid` + `:shared:compileKotlinMetadata` + `:shared:compileKotlinIosArm64` + `:app:compileProductionDebugKotlin` — the app compile catches cross-module call-site breaks pre-CI (P&O retro).
- **Mutation audit of baselines**: per baseline class, one deliberate mutation → watch it go red → restore → green; proves the baseline can actually catch breakage (P&O audit.md, 17 classes). Spot-check ≥3 representative classes on normal migrations; full audit when stakes are high.
- **No mocks for persistence**: in-memory real backends (Room inMemoryDatabaseBuilder / SQLDelight in-memory driver / MapSettings) — mock/prod divergence shipped a production break in sesame.
- **Amendments, not rewrites**: blocker/exception records grow by dated appended amendments preserving the original reasoning (funds exception files).

## SDK migrations (sesame / marketpulse — different rules than app-repo migrations)

Single-module KMP shape publishing multiple artifacts (no `:shared`/`:app` split) · hand-rolled singleton DI (`Sesame.instance`), expect/actual authored IN the SDK · `initialize()` must be idempotent (called repeatedly per session; header providers read prefs at request time, not build time) · one version field in the catalog publishes all artifacts · after publish, curl each artifact URL for HTTP 200 before bumping the consumer (Nexus lag causes silent resolution hangs) · public API additions are expect + both actuals + tests, TDD, version bump LAST.

## Round-3 incidents (open-PR mining incl. #439's 134-finding review, 2026-06-13)

- **kn-fatal-coroutine — the #1 new class**: an exception escaping `viewModelScope.launch {}` / `LaunchedEffect` is FATAL on Kotlin/Native but swallowed on JVM — passes Android QA, field-crashes iOS. 10 of #439's 12 review blockers were this (unguarded `client.post`, `body()` outside the try, DataStore reads, suspend seams in LaunchedEffect). Canon: `safeLaunch` on the shared `KMMViewModel` (precedent `136c036d78`; rethrows CancellationException, maps the rest); repos return sealed errors. GUARD blocks raw `viewModelScope.launch` in commonMain. Corollary: a SupervisorJob scope without a CoroutineExceptionHandler crashes BOTH platforms when a retry body throws (B9).
- **Callback→suspend double-resume**: `BiometricPrompt.onAuthenticationFailed` is non-terminal (fires per wrong finger); resuming a one-shot `suspendCancellableCoroutine` there crashes "Already resumed" on the wrong-then-right-finger flow (B1). Pair every bridge with `invokeOnCancellation` cleanup (leaked prompt N13).
- **Sanitizer byte-parity**: hardcoding post-sanitized Firebase event names diverges from running the REAL raw Android strings through the REAL sanitizer (`v2__phone_number_verified` double underscore; `mobile_number`→`mobilenumber` on re-sanitize) (B4). Drift tests must encode raw→sanitized pairs via the actual mapper.
- **`mobilenetworkingsdk` `toMap()` Gson wire trap (#414)** — mechanism + canon ("name DTO props as the wire name") live in repo-profile → In-house SDKs. Incident: `trackableName` instead of `trackable_name` → HTTP 400 → blank screen. Prevention beyond the standing rule: verify against the real `toMap()` failing-test-first.
- **Migrated storage seams must read the ORIGINAL on-disk path AND tolerate unknown persisted enums** — #439 re-prompted already-accepted users by pointing a moved seam at a NEW key; #413 launch-crashed (`f788df97`) on a persisted enum the new code didn't recognize. Prevention: keep the exact original path/key, decode persisted enums leniently, and seed a baseline fixture from a PRE-migration on-disk store (the upgrade-in-place case fresh-install baselines never exercise).
- **Timber→Napier "portability" swap silently deleted observability (N10)** — zero compile signal, because Napier calls are no-ops until a base Antilog is wired (standing fact + current state: repo-profile → Logging). Verify a base is registered before relying on shared logs.
- **iOS CMP composition-root traps**: per-screen dependency factories leaked 10 Darwin HttpClients (one NSURLSession each), created duplicate active DataStores on one file (latent IllegalStateException), and built VMs outside the composition so `onCleared` never fires (OTP countdown survives screen pop). Canon (#439 §1 fixes): ONE composition root (`LoginDependencies` pattern) behind Swift `@State`; VMs created inside `ComposeUIViewController { viewModel { … } }`.
- **Flavor-coordinate duplicate-class clash**: `:app` and `:shared` resolving different finance artifacts per variant broke ONLY the staging release build; `:app` must depend on the flavor-aware base module so both resolve identically (#445).
- **A verification gate can be silently dead**: an orphaned ruleset block had broken `:app:detektTask` — "detekt clean" was a no-op for weeks; fixing it surfaced ~69 pre-existing violations (#439). Assert the gate executed (non-zero analyzed files), not just exit 0.
- **Concurrency-primitive swaps change latency, not just safety**: ConcurrentHashMap fast-path → single Mutex serialized every cache HIT behind any in-flight fetch on a login-gated screen (N9) — an instant-feel violation. Snapshot-under-short-lock or atomic reads.
- **Android-only androidx artifacts hide in commonMain deps** (`androidx.lifecycle.viewmodel.ktx` sat there working-for-Android, dead-for-iOS until pod wiring surfaced it, #435). Audit commonMain dependency blocks before iOS consumption.
- **Open-PR scope collision**: with ~10 open kmm/* branches, the same file gets moved by two PRs (`AddFundsProbeRepositoryImpl` in #426 AND #439); renames don't auto-merge — whoever lands second eats conflicts. Preflight checks open kmm/* PRs for file-set overlap and surfaces it at G1.
- **Behavior-loss needs its own review pass (distinct from M1)**: after #439's 134-finding review, a SECOND pass purely for dropped-invisible-behavior found 7 *additional* blockers beyond M1's set (cohort gating, funnel events, testTags, nav effects, `skipRiskDisclosure`). One generic pass is not enough for rewrite-style diffs.

## Recurring research topics (pre-load these clusters in phase 2)

Serializer-swap leniency · joda→kotlinx-datetime week-year/timezone/locale · Retrofit→Ktor timeout/exception mapping · DI-symbol portability (KSP/K-N) · paging in KMP · SKIE Flow/suspend consumption shapes · test source-set bootstrap · exception types across module boundaries · seam options for an androidism (expect/actual vs constructor injection) · a dependency's iOS-klib availability · Compose-MP vs SwiftUI for a screen given Punch precedent · gradle/source-set mechanics + codegen-plugin multi-module constraints.

## Positive patterns (what the 0.6-day PR did right)

- Verbatim `git mv` batches, FQN preserved, zero consumer-import changes — advertised in the PR description as the review contract (#389, #425 followed).
- iOS compile gate run per batch, not at PR end; iOS-incompatible files reverted out of scope immediately rather than patched in place (#389 `5ee830da`).
- Baselines promoted to commonTest in the SAME PR as the move, proving logic parity on both targets (#425).
- PR description enumerates mechanical edits + per-behavior equivalence evidence (byte-identical round-trip test cited) — review becomes verification, not archaeology (#425).
- Small PRs scoped to one layer of one feature merge in days; "foundational types for everything" PRs (#367) bleed for weeks.
- Typealias bridge at the old path keeps out-of-scope consumers untouched during an extraction; delete it in a follow-up (#378).
- Reverts are data: #389 tabulated all 38 reverted files by cause in the PR body — that table became the K/N portability trap list.
- Mechanical sweeps: pre-filter by transitive import purity, batch by archetype (enums → sealed → data → objects → interfaces), one commit per batch (#389: 2,297 surveyed → 240 candidates → 202 moved in 0.6 days).
- One finding = one TDD commit with the finding ID in the subject (`B4`, `S-17`) — greppable audit trail (#439).
- PR-body contract: what-changed / user-impact ("None" with exceptions NAMED) / risk areas ranked P0–P2 with mitigations / QA heatmap rows citing the pinning test file / platform-split test counts (#425).
