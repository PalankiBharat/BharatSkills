# Build file rules

Loaded for files with `role=build`. Covers `build.gradle.kts`, `settings.gradle.kts`, `gradle/libs.versions.toml`, `Podfile`, `Package.swift`.

Cite as `references/rules/build.md#<rule-id>`.

---

### B-01 — Versions in `libs.versions.toml`, not hardcoded
**Severity:** P2
**Pattern:** dependency version hardcoded in `build.gradle.kts` (e.g., `implementation("io.ktor:ktor-client-core:2.3.7")`) instead of catalog reference (`libs.ktor.client.core`).
**Why:** Hardcoded versions across modules drift. Version catalog gives a single source of truth.
**Suggestion:** Add to `libs.versions.toml` and reference via `libs.<alias>`.
**Source:** https://docs.gradle.org/current/userguide/platforms.html

### B-02 — Dependencies placed in the correct source set
**Severity:** P0
**Pattern:** Android-only dependency added to `commonMain.dependencies { }` block, or iOS-only dependency added to `commonMain` (e.g., adding `androidx.compose` to commonMain).
**Why:** commonMain compiles for iOS — non-KMP deps will fail the iOS build. iOS-only deps in commonMain pollute Android builds.
**Suggestion:** Place Android deps in `androidMain.dependencies { }`, iOS-specific in `iosMain.dependencies { }`, only KMP-published artifacts in commonMain.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-add-dependencies.html

### B-03 — SKIE plugin applied if iOS consumes shared coroutines/Flow/sealed
**Severity:** P0 (with iOS impact)
**Pattern:** `:shared/build.gradle.kts` lacks `id("co.touchlab.skie")` in `plugins { }` but the shared module exports Flow, suspend, or sealed types.
**Why:** Without the plugin, none of SKIE's iOS-friendly transformations fire. See `ios-readiness.md#i-skie-01`.
**Suggestion:** `plugins { id("co.touchlab.skie") version "<version>" }`.
**Source:** https://skie.touchlab.co/intro

### B-04 — Same Kotlin version across modules
**Severity:** P1
**Pattern:** different `kotlin("multiplatform")` or `kotlin("jvm")` plugin versions in different modules' `build.gradle.kts`.
**Why:** Mixed Kotlin versions cause weird incompatibilities (especially with compiler plugins like SKIE).
**Suggestion:** Pin Kotlin version in root `build.gradle.kts` or `libs.versions.toml`; apply uniformly.
**Source:** https://kotlinlang.org/docs/releases.html

### B-05 — iOS framework export configuration in shared module
**Severity:** P1
**Pattern:** new exported transitive dependency in iOS framework without `export(...)` in the `framework { }` block; or `isStatic = true/false` flipping unexpectedly.
**Why:** Transitive types used in the public API need explicit `export` to be visible to iOS. Framework type (static vs dynamic) affects link behavior and binary size.
**Suggestion:** Add `export(libs.x.y)` for dependencies whose types appear in public API. Document framework-type changes.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-build-native-binaries.html
