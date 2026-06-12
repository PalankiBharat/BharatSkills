# sniper-v2-android — KMM Repo Profile

THE project-knowledge home for KMM migrations. Lives in the plugin (not the target repo) so a knowledge update is usable by the NEXT migration the moment it lands on the plugin repo's master — never blocked behind a sniper PR merge. Update protocol: see `learnings.md` header. Plugin source checkout: `~/dev/claude-code-skills/plugins/kmm-pipeline` (the punchhq-skills marketplace points at the local repo). Every entry carries a verification date where it matters — entries are hypotheses to re-verify when toolchain versions move (Law Rule 7).

Provenance: ported 2026-06-13 from sniper's `.kmm/project.md` (grown over the 2026-05/06 migration sessions) + in-repo inspection.

## Modules

- `:app` — `com.android.application`. Main Android app. Not KMM-enabled. Flavored production/staging.
- `:app:monitoring` — `com.android.library`. Out-of-scope for migrations.
- `:shared` — `kotlin("multiplatform")` + `androidLibrary`. THE KMM module. SKIE enabled. Room schema lives here. CocoaPods framework `shared` (dynamic, `baseName = "shared"`), `podfile = ../Punch/Podfile`.
- `:sniper-library` — `kotlin("multiplatform")` + `com.android.library`. KMM module. SKIE Flow/Suspend interop **disabled** for its package.
- `:annotation-processor`, `:baselineprofile`, `:appium-tests` — out-of-scope.

iOS does NOT directly consume `:sniper-library` — only through `:shared`. `:shared` depends on `:sniper-library`.

## iOS app (Punch) — in this repo

- `Punch/Punch.xcworkspace` (+ `Punch.xcodeproj`, `Podfile`: `pod 'shared', :path => '../shared'`, lottie-ios, LaunchDarkly; platform iOS 16.0).
- SwiftUI shell: `Punch/Punch/PunchApp.swift` imports `shared`; `Screens/` holds only `PlaceholderView.swift` on master as of 2026-06-13.
- **iOS UI strategy (established by #439, unmerged)**: feature screens are Compose Multiplatform in `:shared` commonMain `ui/`, hosted from Swift via `ComposeUIViewController` (generic `ComposeScreen` wrapper, `LoginFlowView` precedent); ONE composition root per flow (`LoginDependencies` pattern) behind Swift `@State`; VMs created inside the composition (`viewModel { … }`) so `onCleared` fires. Shared VMs use the `safeLaunch` primitive on `KMMViewModel` (raw `viewModelScope.launch` is K/N-fatal on escaping exceptions).
- The native `Finance.framework` (SciChart-based, the `finance` cinterop) comes from CocoaPods via the app, NOT from gradle — this is why standalone `:shared:linkPod*` fails (see Gradle gotchas).

## Source-sets

Both `:shared` and `:sniper-library` have `commonMain`, `androidMain`, `iosMain`, `commonTest`; `:shared` adds `androidUnitTest`; `:sniper-library` adds `androidTest` + legacy `test/`. No iosX64Main / iosArm64Main splits.

## DI — Hilt + Koin coexist

- **Hilt 2.56** — `:app` (full graph) and `:shared` (kapt processor — KSP doesn't support Hilt in KMP modules). `@HiltViewModel` for app-side VMs. App-side bindings concentrated in `app/src/main/java/com/marketpulse/sniper/vte/di/{RepositoryProvider,UseCaseProvider,ProviderModule}.kt`.
- **Koin 3.5.6** — `:app` and `:shared` (`koin-core` in commonMain). Used for commonMain bindings where Hilt KSP doesn't reach.
- **Convention:** common code defines interfaces; concrete impls bound Android-side via Hilt `@Provides` in `app/`. Pure commonMain wiring uses Koin DSL.
- **Hard rule: no Hilt symbols in commonMain.** Constructor params only. Verified the hard way (positions-orders retro): `@Qualifier` extraction to commonMain failed twice — Dagger's annotation processing (KSP in `:app`) doesn't follow expect/actual typealiases, and javax.inject has no Kotlin/Native artifact (`:shared` itself runs Hilt via kapt). Canon: qualifiers + Hilt symbols stay in `:app`; commonMain classes annotation-free; disambiguate in `@Provides` factories.

## Persistence

- **ObjectBox 4.2.0** — `:app` (entitlement cache, watchlist). Not KMM-friendly. The gradle plugin is SINGLE-MODULE: it generates `MyObjectBox` only for the module it's applied to; 75+ `:app` entities preclude applying it to `:shared` (watchlist retro). Storage strategy (platform-owned vs shared Room) is a scoping-time architecture decision, never a mid-execute pivot.
- **Room 2.7.0-beta01** — `:shared`, KMP-flavor (`schemaDirectory("$projectDir/schemas")`). `AppDatabase.kt` in commonMain currently a stub package declaration.
- **DataStore** — both shared modules. **SharedPreference** — `:sniper-library` legacy wrapper `com.marketpulse.sniper.library.localstores.SharedPreference` (Android-only). No SQLDelight.
- `app/objectbox-models/default.json` is GUARD-frozen during migrations — editing it caused the #367 mass-logout (learnings M2).

## Networking

- **Ktor 2.3.11** (per `gradle/libs.versions.toml`) — primary client in both shared modules. Drift: `app/build.gradle:5` hardcodes Ktor 2.2.2.
- **Retrofit 2.9.0** — legacy in `:app`; `compileOnly` stub in `:sniper-library`. No new Retrofit code.
- **BuildKonfig 0.15.1** — both shared modules. Base-URL constants at `shared/build.gradle.kts` (`CACHE_API_URL`, `CDN_API_URL`, `API_URL`, `SUPER_API_URL`, `BIFROST_API_URL`, `MUNIM_API`, `HULK_API`, `EDITH_API`, …). Two namespaces: `:shared` → package `com.marketpulse.sniper.punch`, accessor `BuildKonfig.FIELD`; `:sniper-library` → package `com.marketpulse.sniper.library`, object `Config`, accessor `Config.FIELD`.
- **Convention (CLAUDE.md):** RemoteStores take `baseUrl: String` in the constructor; route paths in a separate `*Routes.kt`.
- **Shared Ktor `HttpClient` timeout — `socketTimeoutMillis = 30_000L`** (`:shared/.../provideHttpClient`). Was unset (OkHttp 10s default) until the Reports migration surfaced silent 10s-timeout-then-fake-500s on slow Munim queries. Any RemoteStore migrating off Retrofit MUST verify the pre-migration `mystique/RetrofitBuilder` per-service timeout ≤ this value.

## In-house SDKs (verify per-type before relying — klib linkdata beats docs)

- **`marketpulsesdk` v2.0.9 — KMP, already `api(libs.marketpulsesdk)` in `:shared` commonMain.** Types under `com.marketpulse.marketpulsesdk.*` (`models.Duration`, `IMultiChannelLiveFeedUseCase`, `Scrip`, `ScripFeedModel`) resolve in commonMain + iOS klib with no wiring. Per-type iOS availability check: `~/.gradle/caches/.../marketpulsesdk-iosarm64/<ver>/*.klib` → `default/linkdata/package_*` (verified 2026-06-03: `models.Duration`/`Duration.Preset` present in 2.0.9).
- **`mystique_kmm_sdk` v1.0.3** — shared Ktor plugin (`MystiqueConfiguration` + `MystiqueConstants` in `:shared`) registers known hosts (HULK, EDITH, MUNIM), rewrites URLs, attaches auth per-host. **Rule: every RemoteStore moving from `:app` Retrofit (`mystique/RetrofitBuilder`) to shared Ktor MUST register its host in `MystiqueConfiguration` — missing this routes via `fallbackDns` and 500s every request.**
- **`mobilenetworkingsdk` — IS KMP** (iosArm64/iosX64/iosSimulatorArm64 klibs exist; was once misclassified Android-only from docs — positions-orders retro; verify any such claim via gradle `dependencyInsight --dependency <dep>` on an iOS-target configuration, or klib presence in `~/.gradle/caches`). **Wire trap**: its `toMap()` serializes request DTOs with Gson — kotlinx `@SerialName` is ignored; the Kotlin property name goes on the wire (#414 HTTP-400 incident). Name request-DTO properties as the wire names.
- **`sniper_kmm_sdk` / `sniper_kmm_sdk_staging`** — declared in the catalog, no consumers in build files.
- **`finance-android-production`** — Android-only chart SDK; ignore for KMM.
- **`finance` (`org.bitbucket.marketpulse:finance`) — KMM finance SDK, `api(libs.finance)` in `:shared` commonMain.** iOS klib exposes ONLY `com.marketpulse.finance.chart`; `finance.core` etc. are androidMain-only. Known: `finance.core.IndicatorSource` androidMain-only ≤1.1.96, relocated to commonMain in `1.1.96.alpha22` (`DataSourceId` return stays androidMain — `toDataSourceId()` split into an androidMain extension). `finance.contract.study.StudyKeys` IS iOS-available. (Klib facts inherited undated from the legacy profile — re-verify via the linkdata procedure before relying.) Finance SDK source: `/Users/mohitsoni/AndroidStudioProjects/finance-android-sdk/finance` (read source, never decompile jars).

## Serialization

`kotlinx.serialization` 1.8.0 — `@Serializable` widespread in commonMain; protobuf module available in both shared modules.

## Logging

Napier is the shared logger but NO `Napier.base(Antilog)` registration exists anywhere (2026-06-13) — Napier calls are silent no-ops on BOTH platforms until one is wired. Relevant to any Timber→Napier swap, not just iOS.

## SKIE 0.10.10

`:shared` only. Default group: `FlowInterop`+`SuspendInterop` ENABLED; group `com.marketpulse.sniper.library`: both DISABLED; group `com.marketpulse.sniper.vte.view.UiEventBus`: both DISABLED. Implication: `:sniper-library`-namespace code surfaces to iOS WITHOUT Flow→AsyncSequence/suspend→async wrappers; `com.marketpulse.sniper.punch.*` gets SKIE wrappers — choose the destination module accordingly. SKIE generates code at framework-LINK time: klib compile alone misses a class of SKIE errors (e.g. object+suspend collision, SKIE #131) — the Xcode workspace build is the real link gate here.

## Toolchain (2026-06)

Kotlin 2.1.10 · AGP 8.11.1 · KSP 2.1.10-1.0.30 · kotlinx-coroutines 1.10.1 · Compose 1.10.0 / compiler 2.1.10 · ObjectBox 4.2.0 · SKIE 0.10.10 · compileSdk 34 / minSdk 26.

Known version ceilings while Kotlin stays on 2.1.x (sesame-sdk verified 2026-06): Room KMP 2.8.0+ requires Kotlin 2.2.0+ klibs (pin ≤2.7.x); BuildKonfig 0.18+ leaks Kotlin 2.3.x stdlib metadata into published artifacts (pin 0.17.0). Record any new ceiling here with the why — ceilings get re-bumped by accident otherwise.

## Conventions (CLAUDE.md-derived, enforced in migrations)

ViewModels free of Android framework deps · Hilt for Android DI, no manual instantiation · strict Repository pattern, remote ≠ local · `BuildKonfig.*` for base URLs, paths in `*Routes.kt` · Turbine + `kotlinx-coroutines-test` (MockK only in JVM-bound tests — NEVER in migration baselines headed to commonTest) · no nullable types without explicit handling · no emojis in source · package paths preserved verbatim on cross-module moves.

## Git & worktrees

- Base branch `master` (verify at runtime: `git symbolic-ref refs/remotes/origin/HEAD`). PR merge policy: **squash** — simulate integration with `git merge origin/<base>` (+ `git merge-tree`), never rebase published work.
- Stacked migrations happen (e.g. indicator-templates PR'd into `kmm/kotlin-2.2.21-upgrade`, not master) — surface the real base at scoping.
- Worktree template: `../<repo-name>-<branch-suffix>/`, `kmm/` prefix dropped (branch `kmm/reports-business-logic` → `../sniper-v2-android-reports-business-logic`).
- Branch commits style: `[Kmm - <Feature>] - If applied, this commit will <effect>`; squash titles on master: `feat(kmm): …`.

## Verification commands

- Build: `./scripts/build-production.sh` · Install: `./scripts/install-production.sh`
- Unit tests: `:app:testProductionDebugUnitTest` (app is flavored — the unflavored `:app:testDebugUnitTest` is NOT a real task). The `:shared` android unit-test task name is not pinned here yet — discover via `./gradlew :shared:tasks --group verification` and record it on first use.
- Static analysis: `./gradlew detekt ktlintCheck` or `./scripts/detekt.sh`.
- Baseline-stack enforcement: `:app:detektBaselines` (ForbiddenImport + `punch.BaselineDenylistRule` via `detekt/customRules.jar`, config `detekt/detektBaselines.yml`; scope: `sniper-library/src/test`, `shared/src/androidUnitTest`, `shared/src/commonTest`; excludes legacy `**/sniper/sniper/library/**`). Rebuild the jar by uncommenting `':customRules'` in settings.gradle → `:customRules:jar` → copy → re-comment. Holdings session added `:app:detektBaselineTests` (scope `shared/src/commonTest/.../vte/baseline`, config `app/detektBaselineTests.yml`) — co-exists, no overlap.
- Device interaction: `android` CLI / phone-driver skill — never raw `adb shell input tap`.
- Always verify tests RAN via JUnit XML (`app/build/test-results/<task>/*.xml`, `tests`/`failures` attrs), not console output.

## Gradle gotchas (this repo / this host)

- **`--rerun-tasks` FAILS the build** — forces KMP strict checkers (`kmpPartiallyResolvedDependenciesChecker`) which error on the flavored android variants of `marketpulsesdk`+`finance` in `:shared` commonMain (`Unresolved platforms: [android, android]`) despite `missingDimensionStrategy`. Cold-path alternative: scoped `clean` + compile.
- **No coreutils `timeout`/`gtimeout` on this host** — wrap gradle in background tasks with watchdog ceilings instead.
- **Never `cd` before `./gradlew`** — invoke `<abs-repo>/gradlew -p <abs-repo> …` (CWD-independent).
- **`:shared:linkPodDebugFrameworkIosArm64` fails standalone** (`ld: framework 'Finance' not found` — Finance.framework comes from the app's pods). Gradle-side iOS gate = `:shared:compileKotlinIosArm64` (+ `compileTestKotlinIosSimulatorArm64`); the FULL link gate = `pod install` + `xcodebuild build` of `Punch/Punch.xcworkspace`. A/B-confirmed pre-existing 2026-06-03.
- **One gradle build at a time across ALL worktrees** — daemon/build-dir contention produces stuck workers and missing JUnit XML (login retro: 3 daemons hard-stopped).
- A pre-existing pathological test in `:app:testProductionDebugUnitTest` can hang at 100% CPU indefinitely — ceilings mandatory.
