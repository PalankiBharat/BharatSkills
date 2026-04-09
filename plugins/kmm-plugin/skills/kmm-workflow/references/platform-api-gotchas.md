# KMM Platform API Gotchas

APIs that compile on JVM/Android but fail on Kotlin/Native (iOS) or are unavailable in commonMain. Migrator agents MUST check this table before writing commonMain code.

## APIs NOT Available in commonMain

| API | Problem | Replacement | Notes |
|-----|---------|-------------|-------|
| `Dispatchers.IO` | On Native, it's an **extension property** requiring `import kotlinx.coroutines.IO` (not a member like on JVM). Not available on JS/Wasm. | `Dispatchers.IO` with correct import in commonMain (JVM+Native). `expect`/`actual` only if targeting JS/Wasm. | Available since kotlinx-coroutines 1.7.0 (Kotlin 1.8.20+). On Native: real thread pool (up to 64 threads, lazily allocated, no elasticity). Ensure `import kotlinx.coroutines.IO` is present — IDE may not auto-import it on Native. |
| `kotlin.jvm.Volatile` / `@Volatile` | JVM-only annotation | `@kotlin.concurrent.Volatile` | Available since Kotlin 1.8.20. Import `kotlin.concurrent.Volatile`. |
| `@Synchronized` | JVM-only annotation | `kotlinx.atomicfu.locks.SynchronizedObject` + `synchronized(lock) {}` | Requires `kotlinx-atomicfu` dependency. See atomicfu section below. |
| `String.format()` | Java stdlib method, not available on Native | Custom formatter or `kotlin.math` rounding | For decimal formatting: use `kotlin.math.round` or write a `formatDecimal(value, precision)` helper. |
| `MutableList.removeFirst()` | Java 21 `SequencedCollection` method | `removeAt(0)` | `removeFirst()` compiles on JVM 21+ but crashes with `NoSuchMethodError` on JVM 8 targets and is absent on Native. |
| `MutableList.removeLast()` | Java 21 `SequencedCollection` method | `removeAt(lastIndex)` | Same as `removeFirst()`. |
| `System.currentTimeMillis()` | Java stdlib | `Clock.System.now().toEpochMilliseconds()` | Requires `kotlinx-datetime`. |
| `java.util.UUID` | Java stdlib | `kotlin.uuid.Uuid` (Kotlin 2.0+) | Built into Kotlin stdlib 2.0+. For older Kotlin: use `expect`/`actual`. |
| `java.util.concurrent.*` | Java concurrency package | `kotlinx.coroutines.sync.Mutex`, `kotlinx.atomicfu` | `ConcurrentHashMap` → `Mutex`-guarded `MutableMap`. `AtomicInteger` → `kotlinx.atomicfu.atomic(0)`. |
| `java.io.File` | Java IO | `okio` or `expect`/`actual` | Use Okio for multiplatform file operations, or abstract behind `expect`/`actual`. |
| `android.util.Log` | Android-only | Napier (`io.github.aakira:napier`) | `Log.d(tag, msg)` → `Napier.d(msg, tag = tag)`. |
| `android.content.Context` | Android-only | Pass via DI or `expect`/`actual` | Never reference `Context` in commonMain. Inject platform-specific implementations via Koin. |
| `android.content.SharedPreferences` | Android-only | `multiplatform-settings` (`com.russhwolf`) | Wraps SharedPreferences (Android) and NSUserDefaults (iOS). |
| `@VisibleForTesting` | AndroidX annotation | Remove or use `internal` visibility | No commonMain equivalent. If needed for testing, make the member `internal`. |
| `Locale` / `java.util.Locale` | Java stdlib | Platform-specific via `expect`/`actual` | No standard KMM locale API. Use `expect`/`actual` or skip locale-dependent formatting. |
| API status string comparison | Gson `valueOf()` is case-sensitive but matches uppercase API responses. After migrating to kotlinx.serialization, raw string comparisons like `status == "success"` fail when API returns `"SUCCESS"`. | Always use `status.equals("success", ignoreCase = true)` or `status.lowercase()` | Affects any `when(status)` block comparing API response values. |
| Box with scroll + footer overlay | `Box { Column(Modifier.fillMaxHeight().verticalScroll()) { ... }; Footer(Modifier.align(BottomCenter)) }` — scroll gesture intercepts footer touches on iOS/CMP | Use `Column { Column(Modifier.weight(1f).verticalScroll()) { ... }; Footer() }` instead | Android handles z-order touch dispatch differently. On CMP/iOS, the scroll gesture detector on the full-height Column swallows touches on the overlapping footer. |
| `println()` | Output goes to stdout on iOS, NOT captured by `xcrun simctl spawn ... log stream/show`. Invisible for debugging. | Use `Napier.d()` / `Napier.e()` (which uses `NSLog` on iOS) | Always replace `println` debug statements with Napier in shared code. `println` is fine for JVM unit tests but useless for iOS runtime debugging. |
| Extra headers in migrated HTTP clients | Ktor `HttpClientFactory` may add headers (e.g., `platform`, `app_version`) that the original OkHttp client never sent. Backend servers may 500 on unexpected headers. | Diff the exact headers sent by original vs migrated client. Remove any headers not present in the original. | Debug with curl bisection: reproduce the request via curl, remove headers one at a time until the error resolves. Also verify `app_version` sends the version name string (e.g., `"1.2.3"`), not the numeric version code. |
| `DialogProperties.decorFitsSystemWindows` | Android Compose only, not in CMP | Remove the parameter | CMP `DialogProperties` only supports `dismissOnBackPress`, `dismissOnClickOutside`, `usePlatformDefaultWidth`. Android-specific params like `decorFitsSystemWindows` cause compile failure on iOS. |
| SKIE `data object` vs `data class` Swift access | Kotlin `data object` subtypes of sealed classes are accessed via `.shared` property in Swift, not `()` constructor. `data class` subtypes use `()` constructor as normal. Getting this wrong causes compile errors or silent nil values. | `data object Idle : State` → Swift: `State.Idle.shared`. `data class Loaded(val items: List<Item>) : State` → Swift: `State.Loaded(items: [...])` | Applies to ALL sealed class/interface subtypes consumed via SKIE `onEnum(of:)` in SwiftUI. |
| `return` inside composable lambda | In Kotlin, `return` inside a lambda exits the enclosing function, not just the lambda. Inside a `@Composable` lambda (e.g., `Column { ... }`), a bare `return` exits the entire composable function, silently skipping all content that follows. No compile error, no runtime warning — screen renders empty. | Replace `return` with `return@ColumnName` (labeled return), or restructure into `if` blocks. |
| `runBlocking` in commonMain / non-suspend interface with suspend storage | If an interface has non-suspend methods but the storage layer is suspend-only (e.g., DataStore), do NOT bridge with `runBlocking`. On iOS, `runBlocking` on the main thread = deadlock. Any `runBlocking` in commonMain is a potential iOS deadlock. | Make the interface methods `suspend`, or provide a platform-specific synchronous accessor via `expect`/`actual`. |
| CoreFoundation (CF) typed APIs in Kotlin/Native | CF types in K/N interop must use typed CF APIs: `CFDataGetBytePtr()`, `CFDataGetLength()`, `NSData.dataWithBytes()`, `.reinterpret<T>()`, typed output vars (e.g., `CPointerVar<__SecKey>`). Using `as`/`as?` with CF types produces type-erased `Any?`. Using `CFBridgingRelease` risks double-free. | Use `CFAutorelease` or explicit `CFRelease` with ownership tracking. Never cast CF types with `as`/`as?`. |
| Enum/object property initializers | Property initializers in `enum` constants and `companion object` blocks execute at class-load time, not on demand. Platform API calls hidden here crash in commonMain. | Move to lazy properties, call-site evaluation, or androidMain extension functions | Grep enum classes and companion objects for property initializers that reference singletons (`Instance`, `getInstance`), platform APIs, or resource lookups. Standard method-body grep misses these. |
| ObjectBox entity UID change (rename/recreate) | When ObjectBox entity UIDs change, dependent entities (those holding `ToOne`/`ToMany` references to the wiped entity) survive schema migration but contain dangling references. App crashes on accessing stale data. | Add a numbered ObjectBox migration to clear dependent entities and force data re-sync. Null-safe fallbacks are insufficient — the root cause is stale data, not missing null handling. | Affects any entity with `ToOne<WipedEntity>` or `ToMany<WipedEntity>` relations. Check ALL `@Relation` annotations pointing to renamed/recreated entities. |

## Coroutine Testing Gotchas

| Problem | Symptom | Fix |
|---------|---------|-----|
| `while(true)` polling loop | `runTest` / `advanceUntilIdle()` hangs — loop never becomes idle | Replace `while(true)` with `while(currentCoroutineContext().isActive)` |
| `viewModelScope.launch(Dispatchers.IO)` with test dispatcher | State updates race; assertions fail intermittently | Remove `Dispatchers.IO` from launch; let Ktor manage its own threading |
| Init-block coroutines + `UnconfinedTestDispatcher` | Coroutines leak across tests → intermittent failures after `Dispatchers.resetMain()` | Use `StandardTestDispatcher` + `advanceUntilIdle()`, or cancel ViewModel scope in `@AfterTest` |

**1. `while(true)` polling loops hang `runTest`**

`advanceUntilIdle()` advances the virtual clock until no coroutines are pending. An infinite loop never becomes idle, so the call never returns.

```kotlin
// Before (hangs runTest)
while (true) { delay(5_000); poll() }

// After (cancels cleanly when scope ends)
while (currentCoroutineContext().isActive) { delay(5_000); poll() }
```

**2. Explicit `Dispatchers.IO` bypasses test dispatcher**

`Dispatchers.setMain(UnconfinedTestDispatcher())` only overrides `Main`. A `viewModelScope.launch(Dispatchers.IO)` block runs on a real IO thread — state updates are async and arrive after assertions. For Ktor-based network calls, removing `Dispatchers.IO` is safe; Ktor handles its own dispatcher.

**3. `UnconfinedTestDispatcher` leaks init-block coroutines**

`UnconfinedTestDispatcher` runs coroutines eagerly (no scheduling delay). ViewModel init-block launches execute immediately and may still be running when `@AfterTest` calls `Dispatchers.resetMain()`, corrupting the dispatcher state for subsequent tests. Switch to `StandardTestDispatcher` so coroutines only advance when explicitly driven, or cancel the ViewModel's coroutine scope in `@AfterTest`.

## atomicfu Setup

When replacing `@Synchronized` or `java.util.concurrent` atomics, you MUST add the `kotlinx-atomicfu` dependency during Phase 2 (SCAFFOLD):

```kotlin
// build.gradle.kts — shared module
kotlin {
    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:atomicfu:0.23.2")
        }
    }
}
```

**Usage pattern:**

```kotlin
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

class ThreadSafeCache : SynchronizedObject() {
    private val cache = mutableMapOf<String, Any>()

    fun get(key: String): Any? = synchronized(this) { cache[key] }
    fun put(key: String, value: Any) = synchronized(this) { cache[key] = value }
}
```

## commonTest Setup

During Phase 2 (SCAFFOLD), the `commonTest` source set MUST be configured with test dependencies:

```kotlin
// build.gradle.kts — shared module
kotlin {
    sourceSets {
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
        }
    }
}
```

Without this, `@Test` annotations resolve to `NonExistentClass` and kapt/ksp fails on the entire module.

## Napier Initialization

Napier MUST be initialized at app startup on EACH platform. Without initialization, all `Napier.d()`, `Napier.e()`, etc. calls are **silently no-ops** — no crash, no warning, just missing logs. This makes debugging impossible.

**Android** (`Application.onCreate()`):
```kotlin
import io.github.aakira.napier.DebugAntilog
import io.github.aakira.napier.Napier

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Napier.base(DebugAntilog())
    }
}
```

**iOS** (`AppDelegate` or app entry point):
```swift
import shared // or your framework name

@main
struct MyApp: App {
    init() {
        NapierKt.debugBuild() // or call a Kotlin helper that initializes Napier
    }
}
```

**Kotlin helper (commonMain):**
```kotlin
fun debugBuild() {
    Napier.base(DebugAntilog())
}
```

Verify Napier initialization BEFORE relying on log output for debugging. If logs are empty during a debug loop, check initialization first.

## String Formatting Helper

For `String.format("%.Nf", value)` replacement in commonMain:

```kotlin
fun Double.formatDecimal(precision: Int): String {
    val factor = 10.0.pow(precision)
    val rounded = kotlin.math.round(this * factor) / factor
    val parts = rounded.toString().split(".")
    val intPart = parts[0]
    val decPart = (parts.getOrElse(1) { "0" }).padEnd(precision, '0').take(precision)
    return "$intPart.$decPart"
}

// Usage: value.formatDecimal(2) instead of String.format("%.2f", value)
```

## Duplicate Class Resolution

When migrating a file from `src/main/java/` to `shared/src/commonMain/`:

- `commonMain` compiles into ALL platform targets, including Android
- If the original `src/main/java/` file still exists with the same package + class name, the Android compilation sees TWO declarations → hard compiler error
- The original MUST be deleted (or moved to a backup location outside the source set) BEFORE any compile or test step

This is NOT optional — duplicate declarations are a hard build failure, not a warning.

## Gradle Task Name Ambiguity (Product Flavors)

When a KMM module has Android product flavors, Gradle generates multiple compile tasks per flavor. Using ambiguous task names like `./gradlew :module:compileDebugKotlin` fails with "task is ambiguous."

**Fix:** Use fully qualified task names: `compileStagingDebugKotlinAndroid`, `testStagingDebugUnitTest`.

**Discovery:** Run `./gradlew :module:tasks --all | grep -i compile` to find exact task names before running builds.

## Kotlin `object` Method Name `init*` → Swift `doInit*`

Kotlin/Native maps Kotlin names to ObjC selectors. When a method name starts with `init` (reserved in Swift/ObjC), the compiler prefixes `do`.

| Kotlin | Swift |
|--------|-------|
| `KoinHelper.initKoin(config, delegate)` | `KoinHelper.shared.doInitKoin(config:scripPersistenceDelegate:)` |

Applies to ANY method starting with `init`: `initialize()` → `doInitialize()`, `initSession()` → `doInitSession()`.

**Fix:** Rename the Kotlin method (e.g., `startKoin()`) or document the `do` prefix.

## Kotlin `Result<T>` Returns `Any?` in Swift — Cast Fails Silently

`Result<T>` is an inline class. In K/N ObjC interop, it's boxed as `Any?`. SKIE converts `suspend fun` to `async throws`, but return type is still `Any?`.

| Kotlin | Swift (SKIE) | Problem |
|--------|-------------|---------|
| `suspend fun get(): Result<Model>` | `func get() async throws -> Any?` | `result as? Model` → nil |

**Fix:** Create a Kotlin helper that unwraps: `fun getSingle(): Model? = repo.get().getOrNull()`

**Do NOT** cast `Any?` in Swift — it will always be nil.

## Xcode 16+ `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` Breaks ObjectBox

New Xcode 16+ projects default to `@MainActor` isolation (Swift 6). This breaks ObjectBox's `EntityInspectable` and `__EntityRelatable` protocol conformance.

**Fix:** `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` in build settings. Check BEFORE first iOS build.

## KMM Framework `CFBundleIdentifier` Rejected Without Explicit `bundleId`

Default `Info.plist` sets `CFBundleIdentifier` to module name with underscores. Xcode rejects this when embedding.

**Fix:**
```kotlin
binaries.framework {
    baseName = xcfName
    binaryOption("bundleId", "com.example.sdk")
}
```
Apply to ALL iOS targets.

## KAPT `_` Keyword Conflict in Worktrees

KAPT (Kotlin Annotation Processing Tool) in some Kotlin versions treats `_` as a reserved keyword in property setters. This manifests as a build error in worktrees or CI where clean builds run from scratch.

**Symptom:** `'_' is a reserved keyword` or `name expected` error in generated code referencing `set(_){}`.

**Fix options:**
1. Add compiler argument: `freeCompilerArgs += "-Xno-new-java-annotation-targets"` in `build.gradle.kts`
2. In manual code: use `set(value){}` instead of `set(_){}` for unused setter parameters

```kotlin
// build.gradle.kts
tasks.withType<KotlinCompile> {
    compilerOptions {
        freeCompilerArgs.add("-Xno-new-java-annotation-targets")
    }
}
```

This is most commonly encountered when creating fresh worktrees where the Gradle cache doesn't mask the issue.
