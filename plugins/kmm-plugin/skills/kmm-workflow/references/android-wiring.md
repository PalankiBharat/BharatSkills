# Android Wiring Reference

Complete protocol for wiring the Android platform after shared module migration: imports, DI,
deletions, parallel execution strategy, build, and runtime verification.

Runs AFTER all shared code migration phases are checkpointed. BEFORE iOS.

---

## Pre-Wire: Read Wiring Manifests

Before starting, read every FILE_VERIFIED output from Phase 3 (stored in PROGRESS.md).
For each file with `breaking` != "none": these call sites need updating — follow the documented changes.
For each file with `di-bindings` != "none": these Koin bindings need adding to the Android DI module.
For each file with `wiring-notes` != "standard": follow the specific import change instructions.
Do not rediscover — use the manifest.

## Table of Contents

1. [Wire Android Protocol](#1-wire-android-protocol)
   - 1.0 [Pre-Wire Analysis](#10-pre-wire-analysis)
   - 1.1 [Update Imports in Android Consumers](#11-update-imports-in-android-consumers)
   - 1.2 [Update DI (Hilt → Koin)](#12-update-di-hilt--koin)
   - 1.3 [Delete Original Android Files](#13-delete-original-android-files)
   - 1.4 [Consumer Wrapper Pattern](#14-consumer-wrapper-pattern)
   - 1.5 [HTTP Client Behavioral Parity](#15-http-client-behavioral-parity)
   - 1.6 [Lifecycle Method Verification](#16-lifecycle-method-verification)
2. [Parallel Execution](#2-parallel-execution)
3. [Build & Test](#3-build--test)
4. [Runtime Verification](#4-runtime-verification)
   - 4.1 [appium-mcp (primary)](#41-appium-mcp-primary)
   - 4.2 [adb (fallback)](#42-adb-fallback--log-capture-only)
   - 4.3 [Napier Log Tag Filtering](#43-napier-log-tag-filtering)
   - 4.4 [Debug Protocol](#44-debug-protocol)
5. [Crash Patterns](#5-crash-patterns)
6. [REQUIRES_APPROVAL Triggers](#6-requires_approval-triggers)

---

## 1. Wire Android Protocol

**Goal:** Switch the Android app module from its original Android-only source files to the newly
migrated shared module. All consumers updated, originals deleted, Android build passes, app
verified working.

### 1.0 Pre-Wire Analysis

Before starting consumer wiring, enumerate ALL breaking type changes from the SDK migration:

| Old SDK Type | New SDK Type | Propagation |
|-------------|-------------|-------------|
| `OldClass` | `NewClass` | N files, method signatures + field types |
| `java.util.Date` (in SDK methods) | `kotlinx.datetime.Instant` | N call sites need conversion |
| `OldInterface` | `NewInterface` | N DI bindings + N constructor params |

This table drives the wiring work breakdown. "Update imports" underestimates when types actually changed — the real work is type propagation through consumer code (method signatures, field types, generic parameters, DI bindings).

### 1.1 Update Imports in Android Consumers

For every file listed under "Consumers" in migration-guide.md:
- Update imports to point to shared module. For most files, call sites don't change (signatures are identical per the 1:1 behavioral port rule). EXCEPTION: when migration-guide.md documents a Breaking Change for this file (e.g., callback→suspend conversion), update call sites as documented. The breaking change was approved during planning — apply it now.
- Dispatch parallel Haiku agents if consumer count > 5 (see Section 2)

**Import aliases for dual-VM screens:** During the transition window when both a Hilt ViewModel and a Koin (shared) ViewModel share the same class name, use Kotlin import aliases to avoid compilation errors:

```kotlin
import com.example.shared.vm.LoginViewModel as SharedLoginViewModel
import com.example.android.vm.LoginViewModel as HiltLoginViewModel
```

Aliases are temporary — remove them when the Hilt VM is deleted. Never leave aliases in the final post-migration state.

**Pager composable tab routing:** When a shared composable uses `HorizontalPager` with multiple tab types (e.g., Positions/Orders/Holdings), and multiple nav routes render the same composable for different tabs, each route MUST pass the correct `initialTab` parameter. Hardcoding a default tab means other tabs silently render the wrong content.

```kotlin
// BAD — Holdings route shows Positions content
Route.HoldingsRoute -> { ExpandedPositionsBook() } // defaults to Positions tab

// GOOD — each route specifies its tab
Route.PositionsRoute -> { ExpandedPositionsBook(initialTab = TabOption.Positions(0)) }
Route.HoldingsRoute -> { ExpandedPositionsBook(initialTab = TabOption.Holdings(0)) }
```

### 1.2 Update DI (Hilt → Koin)

- Wire shared module classes into the Android Koin module (`androidApp/src/.../di/`)
- Remove Hilt bindings for migrated classes
- Add Koin `single { }` or `factory { }` declarations for shared classes
- If the project uses Hilt throughout: flag as REQUIRES_APPROVAL before changing DI framework

**Decorator equivalence (not just binding existence):** For each `single<Interface>`, trace the original Hilt `@Provides` chain and replicate the decorator wrapping order. Static koin-binding-check.py only verifies that a binding exists — it cannot catch decorator collapse.

```kotlin
// Hilt chain: UserRepositoryDecorator wraps UserLocalStore
@Provides fun provideUserRepo(store: UserLocalStore): UserRepository =
    UserRepositoryDecorator(store)

// Koin — WRONG: decorator stripped, binds raw store
single<UserRepository> { UserLocalStore(get()) }

// Koin — CORRECT: decorator order preserved
single<UserRepository> { UserRepositoryDecorator(UserLocalStore(get())) }
```

For every migrated binding: (1) read the Hilt `@Provides` method, (2) count decorator layers, (3) ensure Koin replicates the same chain.

### 1.3 Delete Original Android Files

Before deleting each file:
```bash
grep -r "OriginalClassName" androidApp/src/ --include="*.kt" -l
```
Confirm all usages now point to shared. If any remain → update them first.

Then delete. Do not defer deletions — stale files cause ambiguous imports.

If deletion would break a non-migrated consumer (consumer is `platform-stay` or outside scope):
→ REQUIRES_APPROVAL: present options (migrate consumer now, keep original alongside shared,
use typealias)

**@Entity Shadow Deletion — var→val Transition**

When an Android `@Entity` class (with mutable `var` fields) shadows a shared `data class` (with immutable `val` fields), deleting the @Entity makes the shared `val` version active. All direct field mutations (`model.field = "new"`) become compile errors requiring `.copy()` refactoring.

**Before deleting an @Entity shadow class:**
1. Grep for `{className}.{field} =` mutation patterns in the codebase
2. Count mutation sites — each needs `.copy()` conversion
3. If >10 mutation sites, plan as a dedicated sub-task in PROGRESS.md, not a side effect of deletion

This is mechanical but high-volume in ViewModels that directly mutate model state.

### 1.4 Consumer Wrapper Pattern

When the consumer app has a wrapper class (e.g., `ScripRepository`) that delegates to the SDK's interface:

**DO:** Keep the wrapper implementing the consumer's own interfaces. Inject the SDK interface as a dependency.
```kotlin
class ScripRepository(
    private val scripStore: ScripStore,  // SDK interface, injected
    private val scripLocalStore: ScripLocalStore
) : GetChartFromScripRepository, GetScripListRepository {  // Consumer interfaces only
    // Delegates to scripStore for SDK queries
}
```

**DON'T:** Make the wrapper implement the SDK interface directly.
```kotlin
// BAD — forces implementing all 18+ abstract methods as boilerplate pass-throughs
class ScripRepository(...) : ScripStore {
    override fun get(scripId: Long) = scripLocalStore.get(scripId)  // boilerplate
    override fun getFromIsin(isin: String) = scripLocalStore.getFromIsin(isin)  // boilerplate
    // ... 16 more
}
```

If consumers need the full SDK interface, inject `ScripStore` directly — don't wrap it.

### 1.5 HTTP Client Behavioral Parity

When Ktor replaces OkHttp/Retrofit in the shared module, compile-time parity is not sufficient — these behaviors are invisible to the type checker. Perform a behavioral audit against the original client:

| Behavior | Original | Ktor equivalent | Verified? |
|---|---|---|---|
| Retry count + backoff | `OkHttp.Interceptor` or `Retrofit` | `HttpRequestRetry { retryOnException(...) }` | [ ] |
| Auth header injection | `Interceptor.chain.request().addHeader(...)` | `appendIfNameAbsent` (not `append` — `append` adds duplicates) | [ ] |
| Session expiry callback | `onSessionExpired { ... }` lambda | Non-no-op, calls platform session-expiry mechanism | [ ] |
| Content encoding | `GzipRequestBody` / `Accept-Encoding` | `ContentEncoding` plugin | [ ] |
| Logging level | `HttpLoggingInterceptor.Level.BODY` | `LogLevel.ALL` / `LogLevel.HEADERS` | [ ] |
| Connect/read/write timeouts | `OkHttpClient.Builder` timeout | `HttpTimeout { ... }` plugin | [ ] |

**Auth header — use `appendIfNameAbsent`, not `append`:**
```kotlin
// BAD — adds duplicate Authorization headers on retry
headers.append(HttpHeaders.Authorization, "Bearer $token")

// GOOD — idempotent
headers.appendIfNameAbsent(HttpHeaders.Authorization, "Bearer $token")
```

**Session expiry — logged-in guard:**
Wire `onSessionExpired` so it only fires when the user has a non-empty token. A 401 during login means wrong credentials, not an expired session — firing session-expiry on login 401 logs the user out before they are ever logged in.

```kotlin
onSessionExpired = { token ->
    if (token.isNotEmpty()) {
        sessionManager.expireSession()
    }
    // else: login 401 — ignore, let the caller surface the error
}
```

A no-op `onSessionExpired = {}` is a silent contract break — the app never logs users out on token expiry.

### 1.6 Lifecycle Method Verification

After rewiring navigation, verify that all lifecycle trigger methods still fire correctly. Navigation refactors are the #1 source of "data doesn't load" bugs — not because the code is wrong, but because the initialization call never executes.

**Check each migrated screen for:**
- `onLaunch()` / `init {}` / `LaunchedEffect(Unit)` — does the initial data load still trigger?
- `onResume()` / `DisposableEffect` — does the refresh-on-return still fire?
- `onCleared()` / `DisposableEffect(onDispose)` — does cleanup still run?

**Common failure patterns:**
- Screen moved from Fragment to Composable but `onLaunch()` was only called in `onViewCreated()` — now never fires
- NavHost recomposition triggers `LaunchedEffect(Unit)` multiple times (use a stable key)
- Parent composable collects effects that previously triggered child `onResume()` — child no longer refreshes

**Verification:** For each migrated screen, trace the data loading path from navigation entry to first API call. If ANY step in the chain is broken, the screen renders with empty/stale data — no crash, just missing content.

---

## 2. Parallel Execution — Wiring Team

Phase 4 runs as part of the "wiring-team" created by the orchestrator. The "android-wirer" teammate (Sonnet, tmux pane) owns all Android wiring work and fires sub-agents for maximum parallelism.

### Sub-Agent Dispatch Pattern

The android-wirer reads the execution blueprint from PLAN.md and fires sub-agents for ALL independent tasks simultaneously:

```
android-wirer (Sonnet, tmux pane):
  PARALLEL BATCH 1 — file operations:
    1 Sonnet sub-agent: DI wiring (Hilt→Koin module rewrite)
    N Haiku sub-agents: consumer import rewiring (one per consumer file, ALL parallel)
    [DI wiring and consumer rewiring are independent — run simultaneously]
  
  PARALLEL BATCH 2 — verification (after batch 1 completes):
    Haiku sub-agent: stub audit + empty lambda audit
    Haiku sub-agent: koin-binding-check.py
    [Both independent — run simultaneously]
  
  Message orchestrator: "Android file ops done, request build"
  Message ios-coordinator: "Confirmed bindings: [FooRepository, BarViewModel, ...]"
```

### Consumer Import Rewiring (Haiku Sub-Agents)

**Always parallel** — every consumer file gets its own Haiku sub-agent regardless of count. No threshold (the old "count > 5" condition is removed). Even 3 consumers benefit from 3x parallelism.

Each Haiku sub-agent receives:
- The consumer file path
- The old import prefix (e.g., `com.app.auth`)
- The new import prefix (e.g., `shared.auth`)
- Constraint: only modify import statements, no logic changes

Returns: `DONE: <file> | imports_changed: N`

### Inter-Agent Messaging

The android-wirer participates in the wiring-team and communicates with the ios-coordinator:

| From | To | Message | When |
|------|-----|---------|------|
| android-wirer | orchestrator | "Android file ops done, request build" | After all sub-agents complete |
| android-wirer | ios-coordinator | "Confirmed bindings: [list]" | After DI wiring verified |
| ios-coordinator | android-wirer | "LoginVM.state is StateFlow, not SharedFlow — fix?" | If API mismatch found |
| android-wirer | orchestrator | "REQUIRES_APPROVAL: <decision>" | If behavioral change needed |

### Build Ownership

The android-wirer NEVER runs `./gradlew` or `xcodebuild`. After file operations complete, it messages the orchestrator to run the build. The orchestrator owns the Gradle lock.

```
android-wirer: "All file ops complete, 12 consumers rewired, DI module updated"
orchestrator: runs ./gradlew build → reports BUILD_PASS or BUILD_FAIL
android-wirer: if BUILD_FAIL → fires Sonnet debugger sub-agent per failure
```

---

## 3. Build & Test

```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Failures:
- Check findings.md Known Fixes first
- 3-strike rule: max 3 distinct approaches → escalate if still failing
- Never repeat the same failed fix

**Summary Table** (fill before Appium automated flows):

| File | Promised API | Actual API | Verify | Tests |
|------|-------------|------------|--------|-------|
| LoginRepository.kt | login(email,pwd):Result | ... | PASS | PASS |

Present to user before proceeding to Appium automated flows.

**Custom Codegen + Maven Publish:** If the SDK has custom Gradle codegen tasks that produce source files, the `dependsOn` matcher must include `sourcesJar` tasks — not just `compile*Kotlin` and `kapt*`. Maven publish runs `sourcesJar` tasks which also need codegen output. Missing this causes `publishAllPublicationsToMavenRepository` to fail with implicit dependency errors.

```kotlin
// build.gradle.kts — ensure codegen runs before sourcesJar
tasks.matching { it.name.contains("SourcesJar") }.configureEach {
    dependsOn(codegenTask)
}
```

**After Wire Android checkpoint:** proceed to per-screen verification, then appium-mcp E2E per `appium-mcp-testing.md`, then manual test. See SKILL.md for phase ordering.

Update PROGRESS.md checkpoint. PLAN.md status block updated.

---

## 4. Runtime Verification

Launch the app after wiring to catch KMM-specific runtime crashes before handing off to manual
testing.

**Primary tool:** appium-mcp
**Fallback:** adb — for log capture only

For debugging failures found during verification, follow the structured debug loop in
`references/agent-prompts/debugger.md`. Do not attempt ad-hoc fixes — use the debug loop.

### 4.1 appium-mcp (primary)

Uses migration-guide.md as the test plan. See `appium-mcp-testing.md` for full protocol.

1. Create appium-mcp Android session targeting `$ANDROID_SERIAL`
2. For each screen in migration-guide.md (platform-stay files):
   a. Navigate using vision-based element finding
   b. Verify all elements from Callbacks field are present
   c. Test interactive elements (tap, type, verify results)
   d. Screenshot for 3-build comparison
3. Blockers (OTP, payment): pause and ask user
4. Delete session when complete

For flows with login requirements: navigate through login flow using vision-based finding. appium-mcp handles CMP Compose text fields natively — no keycode workarounds needed.

### 4.2 adb (fallback — log capture only)

```bash
# Clear logs, launch, capture errors
adb -s $ANDROID_SERIAL logcat -c
adb -s $ANDROID_SERIAL shell am start -n <package>/<activity>
adb -s $ANDROID_SERIAL logcat -d *:E | grep -E "FATAL|AndroidRuntime|KoinApplication|ClassCastException|IllegalStateException|NullPointerException"
```

### 4.3 Napier Log Tag Filtering

When debugging a specific screen, use Napier log tags for efficient filtering:

```bash
# Filter by debug tag (set during debug loop instrumentation)
adb -s $ANDROID_SERIAL logcat -s "DebugLoginScreen"

# After fix confirmed, remove Napier instrumentation before committing
```

### 4.4 Debug Protocol

1. Build and install: `./gradlew :app:assembleDebug && adb -s $ANDROID_SERIAL install -r <apk>`
2. Run appium-mcp E2E on affected screens
3. If crash detected: capture logs (4.2), dispatch debugger agent (3-strike), fix, rebuild
4. If clean: proceed to 3-build comparison, then manual test
5. Max 3 debug iterations → escalate to user with full stacktraces and findings

---

## 5. Crash Patterns

Common KMM runtime crash signatures to look for in logs:

1. **SKIE type mismatch** — see `kmm-architecture.md` Gotchas: SKIE Nested Dot Notation

2. **Missing Koin definition** — see `kmm-architecture.md` Gotchas: Cross-Platform Koin Binding Verification

3. **Coroutine scope issues** — `JobCancellationException`, `IllegalStateException: Module with
   the Main dispatcher`
   - Root cause: coroutine launched on wrong scope, or Main dispatcher not initialized before use
   - Fix: ensure platform coroutine dispatcher is initialized before Koin starts; use
     `Dispatchers.Main.immediate` where needed

4. **Missing expect/actual** — `kotlin.NotImplementedError`
   - Root cause: `expect` declaration has no matching `actual` for the target platform
   - Fix: add the missing `actual` in `androidMain` or `iosMain`

5. **Threading violations** — `IllegalStateException: Must be called on the main thread`
   - Root cause: shared code calling a platform API off the main thread
   - Fix: wrap the call in `withContext(Dispatchers.Main)` or use `@MainThread` dispatching in the VM

6. **Frozen object mutation** (legacy memory manager) — `InvalidMutabilityException`
   - Root cause: mutable state shared across threads under the old K/N memory model
   - Fix: ensure `kotlin.native.binary.memoryModel=experimental` is set, or restructure to avoid
     cross-thread mutation

7. **Duplicate route registration** — API requests cancelled with `CancellationException: StandaloneCoroutine was cancelled`
   - Root cause: Both `bottomSheet(route.key)` and `composable(route.key)` registered for the same route. First-registered (bottomSheet) wins → screen opens as dismissible sheet → VM scope cancelled on dismiss → API requests fail silently
   - Symptom: Screen shows empty data, no crash, API logs show `CancellationException`
   - Fix: grep for duplicate route keys in NavGraph before wiring: `grep -r "Route.XxxRoute.key" app/src/ | grep -E "bottomSheet|composable"`
   - Delete old route registrations when migrating screens from bottomSheet to composable

8. **Hilt scope mismatch** — `cannot be provided without an @Provides-annotated method`
   - Root cause: `SharedBridgeEntryPoint` is `@InstallIn(SingletonComponent)` but the type is provided in `@InstallIn(ViewModelComponent)`. Parent components can't see child component bindings.
   - Fix: Either (a) move the `@Provides` to a `@InstallIn(SingletonComponent)` module with `@Singleton` scope, or (b) expose the type's raw dependencies via the entry point and construct it manually in `initializeKoin()`.
   - Watch for: any use case or repository that is `@InstallIn(ViewModelComponent)` but needed by shared Koin modules at singleton scope.

---

## 6. REQUIRES_APPROVAL Triggers

- DI framework change (Hilt → Koin) affects files outside migration scope
- Deletion would break a non-migrated consumer
- Import update requires a signature change (means migration was not 1:1 — re-verify)
- Any Android-specific behavior change not covered in migration-guide.md
