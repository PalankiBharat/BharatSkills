# KMM Architecture Patterns & Gotchas

Quick-reference for Kotlin Multiplatform Mobile patterns and production-proven gotchas. Project-agnostic; use as a checklist and code template source.

---

## Table of Contents

### 1. KMM Architecture Patterns
- [Source Set Structure](#source-set-structure)
- [expect/actual Declarations](#expectactual-declarations)
- [Framework Export (iOS)](#framework-export-ios)
- [ViewModel Pattern](#viewmodel-pattern)
- [DI Pattern (Koin)](#di-pattern-koin)
- [Coroutines](#coroutines)
- [KMM Interface First](#kmm-interface-first)

### 2. Battle-Tested Gotchas
- [iOS Build Environment](#ios-build-environment)
- [SwiftUI Gotchas](#swiftui-gotchas)
- [KMM/Kotlin Gotchas](#kmmkotlin-gotchas)
- [Process Gotchas](#process-gotchas)

---

# 1. KMM Architecture Patterns

---

## Source Set Structure

| Source Set     | Contains                                                              | Platform APIs |
|----------------|-----------------------------------------------------------------------|---------------|
| `commonMain`   | ViewModels, repositories, use cases, models, networking (Ktor), DI   | None          |
| `androidMain`  | Ktor OkHttp engine, Android-specific platform implementations         | Yes           |
| `iosMain`      | Ktor Darwin engine, iOS-specific platform implementations             | Yes           |
| `commonTest`   | Shared tests (kotlin-test + coroutines-test)                          | None          |

**Decision rule: where does this code live?**

- No platform APIs at all → `commonMain`
- Needs Android SDK or iOS framework → use `expect/actual` or inject via DI; put each side in its platform source set
- Tests with no platform I/O → `commonTest` (runs on both JVM and iOS Native)

---

## expect/actual Declarations

### Official JetBrains hierarchy of preference

1. **Dependency Injection (Koin)** — if you already have DI, use it for platform deps too; no `expect/actual` required
2. **Interface + `expect fun` factory** — define a common interface in `commonMain`, write an `expect fun` that returns the platform implementation
3. **`expect actual class`** — only justified when inheriting a platform base class or authoring a framework

> "Using classes in simple cases where interfaces would be sufficient is not recommended." — JetBrains docs

### Pattern 2: Interface + expect fun factory

```kotlin
// commonMain
interface Logger {
    fun log(message: String)
}

expect fun createLogger(): Logger
```

```kotlin
// androidMain
import android.util.Log

actual fun createLogger(): Logger = object : Logger {
    override fun log(message: String) {
        Log.d("App", message)
    }
}
```

```kotlin
// iosMain
actual fun createLogger(): Logger = object : Logger {
    override fun log(message: String) {
        NSLog(message) // println is invisible on iOS — always use NSLog or Napier
    }
}
```

### Pattern 3: expect/actual for platform values

```kotlin
// commonMain
expect val platformName: String

// androidMain
actual val platformName: String = "Android"

// iosMain
actual val platformName: String = "iOS"
```

---

## Framework Export (iOS)

```kotlin
// build.gradle.kts (shared module)
kotlin {
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    targets.withType<org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget> {
        binaries.framework {
            baseName = "Shared"
            isStatic = true
            linkerOpts("-lsqlite3")       // link native libs when needed

            // Make specific deps part of the public framework API
            export(libs.koin.core)
            export(libs.kotlinx.coroutines.core)
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(libs.ktor.client.core)
            implementation(libs.koin.core)        // internal use only
            api(libs.kotlinx.coroutines.core)     // visible to Swift consumers
        }
        androidMain.dependencies {
            implementation(libs.ktor.client.okhttp)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
    }
}
```

**api() vs implementation() rules:**

| Scenario                                             | Use         |
|------------------------------------------------------|-------------|
| Dep's types appear in your public API / Swift surface | `api()`     |
| Dep is used only inside the Kotlin module            | `implementation()` |
| Dep in `framework { export(...) }` block             | Must also be `api()` in sourceSets |

**Warning:** Exporting `kotlinx.coroutines.core` from the framework can cause duplicate symbol linker errors if another KMP module in the same app also exports it. Only export it if your framework is the sole source of coroutines in the binary.

---

## ViewModel Pattern

### BaseViewModel contract

```kotlin
// commonMain
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

abstract class BaseViewModel<State, Action, Effect>(
    initialState: State,
) : ViewModel() {

    private val _state = MutableStateFlow(initialState)
    val state: StateFlow<State> = _state.asStateFlow()

    // extraBufferCapacity = 64 handles burst scenarios (high-frequency UI events).
    // tryEmit() is synchronous — no coroutine allocation, no async gap with state updates.
    private val _effects = MutableSharedFlow<Effect>(extraBufferCapacity = 64)
    val effects: SharedFlow<Effect> = _effects.asSharedFlow()

    private val stateMutex = Mutex()

    protected var currentState: State
        get() = _state.value
        set(value) { _state.value = value }

    // Preferred over currentState setter for concurrent mutations.
    // Holds a mutex across read-modify-write to prevent clobbering.
    protected fun updateState(reducer: (State) -> State) {
        viewModelScope.launch {
            stateMutex.withLock {
                _state.value = reducer(_state.value)
            }
        }
    }

    abstract fun processAction(action: Action)

    protected fun emitEffect(effect: Effect) {
        _effects.tryEmit(effect)
    }
}
```

### Concrete ViewModel example

```kotlin
// commonMain
data class CounterState(val count: Int) {
    companion object {
        fun default() = CounterState(count = 0)
    }
}

sealed interface CounterAction {
    data object Increment : CounterAction
    data object Decrement : CounterAction
}

sealed interface CounterEffect {
    data class ShowToast(val message: String) : CounterEffect
}

class CounterViewModel : BaseViewModel<CounterState, CounterAction, CounterEffect>(
    initialState = CounterState.default()
) {
    override fun processAction(action: CounterAction) {
        when (action) {
            CounterAction.Increment -> updateState { it.copy(count = it.count + 1) }
            CounterAction.Decrement -> {
                if (currentState.count == 0) {
                    emitEffect(CounterEffect.ShowToast("Already at zero"))
                } else {
                    currentState = currentState.copy(count = currentState.count - 1)
                }
            }
        }
    }
}
```

### Platform consumption

```kotlin
// Android (Jetpack Compose)
@Composable
fun CounterScreen(vm: CounterViewModel = koinViewModel()) {
    val state by vm.state.collectAsState()

    LaunchedEffect(Unit) {
        vm.effects.collect { effect ->
            when (effect) {
                is CounterEffect.ShowToast -> Toast.makeText(context, effect.message, Toast.LENGTH_SHORT).show()
            }
        }
    }

    Text(text = "Count: ${state.count}")
    Button(onClick = { vm.processAction(CounterAction.Increment) }) { Text("Increment") }
}
```

```swift
// iOS (SwiftUI)
struct CounterView: View {
    @StateObject private var vm = KoinHelper.shared.counterViewModel()

    var body: some View {
        VStack {
            Text("Count: \(vm.state.count)")
            Button("Increment") {
                vm.processAction(action: CounterAction.Increment())
            }
        }
        // Note: `for await` on a Kotlin Flow requires the SKIE plugin (`co.touchlab.skie`).
        // Without SKIE, Kotlin Flows are not directly consumable as Swift AsyncSequence.
        .task {
            for await effect in vm.effects {
                switch onEnum(of: effect) {
                case .showToast(let e):
                    showToast(e.message)
                case .navigateBack:
                    dismiss()
                }
            }
        }
    }
}
```

---

## DI Pattern (Koin)

### Module setup

```kotlin
// commonMain
val repositoryModule = module {
    single<UserRepository> { UserRepositoryImpl(get()) }  // singleton
    single<ApiClient> { ApiClientImpl(get()) }
}

val viewModelModule = module {
    factory { CounterViewModel() }                         // fresh per nav push
    factory { UserViewModel(get()) }
}
```

```kotlin
// androidMain
val androidModule = module {
    single<PlatformLogger> { AndroidLogger() }
}
```

```kotlin
// iosMain
val iosModule = module {
    single<PlatformLogger> { IosLogger() }
}
```

### iOS KoinHelper (KoinComponent bridge)

```kotlin
// iosMain — single access point for Swift
class KoinHelper : KoinComponent {
    fun counterViewModel(): CounterViewModel = get()
    fun userViewModel(): UserViewModel = get()

    companion object {
        val shared = KoinHelper()
    }
}
```

```swift
// Swift
@StateObject private var vm = KoinHelper.shared.counterViewModel()
```

### Migration from Hilt

| Hilt                                      | Koin equivalent                          |
|-------------------------------------------|------------------------------------------|
| `@HiltViewModel class Foo @Inject constructor(bar: Bar)` | `factory { FooViewModel(get()) }` |
| `hiltViewModel<FooViewModel>()`           | `koinViewModel<FooViewModel>()`          |
| `@Provides @Singleton fun provideBar()`   | `single { BarImpl() }`                   |
| `@Inject lateinit var bar: Bar` (field)   | Pass through constructor; use `get()` in module |

---

## Coroutines

### Rules

- `Dispatchers.Main` — UI updates only
- `Dispatchers.Default` — CPU-bound background work
- **NEVER `runBlocking` on the main thread** — iOS watchdog kills the app after ~5 seconds
- **Never create unscoped `CoroutineScope(Dispatchers.IO).launch { }`** — these leak; always use `viewModelScope`
- Tie every scope to a lifecycle (`viewModelScope` in ViewModels, `lifecycleScope` in Android Activities/Fragments)

**`Dispatchers.IO` in commonMain:** Available with `kotlinx-coroutines-core` 1.7+ on JVM + Native targets. Requires explicit `import kotlinx.coroutines.IO` — it is an extension property on Native, and the IDE may not auto-import it. If the Android source code uses `Dispatchers.IO`, keep using it in commonMain with the correct import. On iOS/Native, `Dispatchers.IO` maps to a background thread pool (up to 64 threads, lazily allocated). Do NOT replace with `Dispatchers.Default` — they serve different purposes.

### Patterns

```kotlin
// Safe: scoped to ViewModel lifecycle
class MyViewModel : ViewModel() {
    fun loadData() {
        viewModelScope.launch {
            val result = withContext(Dispatchers.Default) { repository.fetch() }
            currentState = currentState.copy(data = result)
        }
    }
}
```

```kotlin
// Safe: concurrent work within a single scope
viewModelScope.launch {
    val (users, posts) = coroutineScope {
        val usersDeferred = async { repository.getUsers() }
        val postsDeferred = async { repository.getPosts() }
        usersDeferred.await() to postsDeferred.await()
    }
    currentState = currentState.copy(users = users, posts = posts)
}
```

```kotlin
// WRONG: unscoped, leaks if ViewModel is cleared
CoroutineScope(Dispatchers.IO).launch { repository.fetch() }

// WRONG: blocks main thread on iOS
runBlocking { repository.fetch() }
```

---

## KMM Interface First

Before creating a wrapper class, ask:

1. Does the KMM SDK already expose an interface with equivalent behavior?
2. Is the only difference a name or minor API surface?

If yes to both → use the KMM interface directly (swap import + rename callsites). No wrapper needed.

**Wrapper is only justified when:**
- The interfaces have genuinely different method signatures or semantics
- You need to adapt between incompatible lifecycle models
- The third-party type cannot be used directly in `commonMain` (e.g., it's platform-specific)

```kotlin
// PREFER: use KMM interface directly
import com.example.sdk.DataRepository  // KMM interface already exists

class MyViewModel(private val repo: DataRepository) : BaseViewModel<...>() { ... }
```

```kotlin
// AVOID unless genuinely necessary: wrapper just for name mapping
class MyDataRepository(private val sdkRepo: SdkDataRepository) : DataRepository {
    override fun getData() = sdkRepo.fetchData()  // only difference was the name
}
```

---

## Compose Multiplatform (CMP) Patterns

### State-Based Navigation (replaces NavHost)

AndroidX `NavHost`/`rememberNavController` is not available in CMP. Use a state-based navigation pattern:

```kotlin
// commonMain — screen mapper
@Composable
fun ScreenMapper(state: AppState, onAction: (Action) -> Unit) {
    when (state) {
        is AppState.Home -> HomeScreen(onAction = onAction)
        is AppState.Settings -> SettingsScreen(onAction = onAction)
        is AppState.Detail -> DetailFlow(state, onAction = onAction)
    }
}

// Per-flow sub-navigation uses internal sealed class + remember { mutableStateOf }
@Composable
fun DetailFlow(state: AppState.Detail, onAction: (Action) -> Unit) {
    var subScreen by remember { mutableStateOf<DetailSubScreen>(DetailSubScreen.Overview) }
    when (subScreen) {
        is DetailSubScreen.Overview -> DetailOverview(onNext = { subScreen = DetailSubScreen.Edit })
        is DetailSubScreen.Edit -> DetailEdit(onBack = { subScreen = DetailSubScreen.Overview })
    }
}
```

**Do NOT read `nav_graph.xml`** — it can be 10K+ lines and causes context bloat. The screen mapper only needs the state enum values and existing composable screen names, both available in the shared module.

### expect/actual for Platform-Only Media Libraries

For Android-only media libraries (Lottie, Glide, ExoPlayer), use `expect @Composable fun` in commonMain + `actual` implementations per platform:

```kotlin
// commonMain
@Composable
expect fun PlatformVideoPlayer(url: String, modifier: Modifier)

@Composable
expect fun PlatformLottieAnimation(asset: String, modifier: Modifier)
```

```kotlin
// androidMain — wraps real library
@Composable
actual fun PlatformVideoPlayer(url: String, modifier: Modifier) {
    AndroidView(factory = { ExoPlayerView(it).apply { setUrl(url) } }, modifier = modifier)
}
```

```kotlin
// iosMain — stub or AVPlayer wrapper
@Composable
actual fun PlatformVideoPlayer(url: String, modifier: Modifier) {
    // Stub: show placeholder. Host app can override via Koin if needed.
    Box(modifier = modifier) { Text("Video: $url") }
}
```

This keeps commonMain clean while allowing platform-specific implementations without code duplication across feature files.

---

# 2. Battle-Tested Gotchas

Hard-won learnings from real production KMM migrations. Every item here burned time on a real project. Project-agnostic.

---

## iOS Build Environment

### New Swift Files Need pbxproj Registration
- Every new `.swift` file must be manually registered in the Xcode project file (`project.pbxproj`)
- Required entries: `PBXBuildFile`, `PBXFileReference`, and `PBXGroup`
- Without this: file exists on disk but is NOT compiled. No clear error message — the types just don't exist
- This is the #1 most common iOS build failure for KMM migrations

### pod install After Worktree Setup
- Running `pod install` in the `iosApp/` directory is REQUIRED after:
  - Creating a new git worktree
  - Adding new CocoaPods dependencies
  - Switching branches that modify the Podfile
- `Podfile.lock` is tracked but `Pods/` directory is not
- Missing this causes immediate xcodebuild failure: "framework not found"

### local.properties Must Be Copied to Worktrees
- Each git worktree needs its own `local.properties` file (Android SDK path)
- Not automatically propagated — must be copied manually
- Missing this causes Gradle to fail with "SDK location not found"

### Gradle Configuration Cache Fails in Worktrees
- Git worktrees have a different filesystem root than the main repo
- Gradle's configuration cache stores absolute paths — a cache from the main repo is invalid in a worktree
- Symptom: cryptic serialization errors or `Could not load entry` during configuration phase
- Fix: use `--no-configuration-cache` for ALL Gradle commands in worktrees
- Alternative: delete `.gradle/configuration-cache/` in the worktree before first build

### SourceKit False Positives — Trust xcodebuild
- Xcode/SourceKit frequently shows "No such module 'shared'" or similar errors
- These are IDE indexing false positives — NOT real errors
- `xcodebuild` succeeds regardless
- Rule: NEVER spend time debugging SourceKit errors. Run `xcodebuild` — if it passes, ignore IDE errors

### :shared:build vs :shared:assemble
- `:shared:build` runs tests. If pre-existing tests are failing, it will fail even if your code is fine
- `:shared:assemble` compiles without running tests
- `:shared:linkDebugFrameworkIosSimulatorArm64` compiles iOS framework only
- Use `assemble` or `linkDebugFramework` when pre-existing test failures block build verification

### iOS ATS Blocks Staging HTTP URLs Silently
- Staging HTTP URLs silently blocked by ATS — no crash, buttons do nothing
- Fix: `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` in Info.plist
- Xcode 16: place Info.plist at project root (not inside auto-discovered source dir), set `INFOPLIST_FILE` build setting

### CMP Compose Resources Not Bundled Until pod install Re-run
- `spec.resources = ['build/compose/cocoapods/compose-resources']` references build output
- `generateDummyFramework` + `pod install` = empty resources. Must: (1) full build, (2) re-run pod install, (3) xcodebuild
- Symptom: `MissingResourceException` for fonts/drawables that exist in build output

---

## SwiftUI Gotchas

### Sheet Must Be Dismissed Before Navigation
- If you navigate away while a `.sheet` is presented, the sheet persists to the next screen
- Root cause: SwiftUI does not automatically dismiss sheets when the presenting view navigates
- Fix: Use a `pendingAction` flag + `onDismiss` callback to sequence: dismiss sheet first, THEN navigate

```swift
@State private var pendingNavigation: Destination? = nil
.sheet(isPresented: $showSheet, onDismiss: {
    if let destination = pendingNavigation {
        pendingNavigation = nil
        router.navigate(to: destination)
    }
}) { ... }
```

### UIKit Touch Callbacks Need Main Queue Dispatch
- When using `UIViewRepresentable` with touch delegates (e.g., signature drawing)
- `touchesEnded` callback fires but does not trigger SwiftUI re-render
- Fix: Wrap state update in `DispatchQueue.main.async { }`
- Why: UIKit touch callbacks are on main thread but SwiftUI binding update needs explicit dispatch

```swift
// In UIViewRepresentable Coordinator:
func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    DispatchQueue.main.async {
        self.parent.didFinishDrawing = true  // triggers SwiftUI re-render
    }
}
```

### WKWebView Needs WKUIDelegate for JavaScript window.open()
- Some web pages (e.g., e-sign flows) use `window.open()` for popups
- Without `WKUIDelegate`, WKWebView SILENTLY discards these requests — button appears to do nothing
- Fix: Add `WKUIDelegate` conformance, implement `webView(_:createWebViewWith:)`, set `javaScriptCanOpenWindowsAutomatically = true`

### UIApplication.shared.open() Async Context
- In iOS 16+, `open()` is async
- Inside `.task {}` blocks: needs `await` — `await UIApplication.shared.open(url)`
- Inside sync closures (button actions, sheet callbacks): does NOT need `await`
- Getting this wrong: compile error in one direction, missing await warning in the other

### Keyboard Handling Pattern
- Standard pattern for screens where CTA button should float above keyboard:

```swift
@State private var keyboardHeight: CGFloat = 0
// In body:
.onReceive(Publishers.keyboardHeight) { height in
    keyboardHeight = height
}
.offset(y: -keyboardHeight)
```

- When fixing keyboard issues, audit ALL screens of the same type, not just the one reported

### Racy Fallback Routing
- Never use `asyncAfter`/`DispatchQueue.main.asyncAfter` as a fallback for "if VM doesn't respond in time"
- Race condition: both the VM callback and the timer fallback can fire, causing double navigation
- Fix: Use a proper state machine. If concerned about VM responsiveness, add a timeout to the VM itself

---

## KMM/Kotlin Gotchas

### Enum Case Sensitivity (Serialization AND Cross-Module)
Two distinct failure modes when migrating enums:
1. **Serialization mismatch:** Android sends `"control"`, KMM expects `"CONTROL"` → silent failure. Fix: `@SerialName` annotations or case-insensitive comparison.
2. **Cross-module naming divergence:** Android enum uses `ALL_CAPS`, shared module uses PascalCase. Compiler catches the type mismatch, but `.name` comparison silently fails (`"CALL" != "Call"`). Fix: exhaustive `when` mapping in adapters — never use `.name` for cross-module enum mapping when conventions differ.
- During Phase 2 interface design, document enum naming conventions and plan adapter mappings.

### Lost Concurrency During Migration
- Android code using async/await for parallel uploads can silently become sequential in KMM
- If you see multiple API calls that were concurrent, ensure they remain concurrent:

```kotlin
// WRONG — sequential:
val result1 = api.upload(file1)
val result2 = api.upload(file2)

// RIGHT — concurrent:
coroutineScope {
    val deferred1 = async { api.upload(file1) }
    val deferred2 = async { api.upload(file2) }
    awaitAll(deferred1, deferred2)
}
```

### Data Class Field Additions Break iOS
- Adding fields to a Kotlin data class used in the shared framework (e.g., `UserCredentials`) requires updating Swift call sites
- Swift uses positional constructors for Kotlin data classes — adding a field shifts all positions
- Always check Swift callers after modifying shared data classes

### Multiple Flows on a Single ViewModel
- Some VMs expose both `effect: SharedFlow<Effect>` AND a separate `navigationEvents: SharedFlow<Route?>`
- You MUST subscribe to BOTH separately from Swift
- If you only subscribe to `effect`, you miss ALL navigation events from `navigationEvents`
- Always check the VM for ALL public Flow properties, not just `state` and `effect`

### Backtick Test Names Crash Kotlin/Native
- `` fun `test my behavior`() `` compiles on JVM but CRASHES on Kotlin/Native
- Always use camelCase: `fun testMyBehavior()`
- This is a `commonTest` rule — tests must work on BOTH JVM and Native

### Standalone Enum Serialization Crashes on Native
- Encoding a non-`@Serializable` enum standalone crashes on Kotlin/Native
- Fix: test serialization within the context of a parent `@Serializable` class, not standalone

### expect/actual VMs Can't Be Instantiated in commonTest
- If your ViewModel uses `expect/actual` (e.g., `expect abstract class KMMViewModel`), it can't be directly created in `commonTest`
- Fix: create a test wrapper class in the test directory that extends the VM

### Koin Generic Type Erasure

When two Koin bindings differ only by generic type parameter, JVM type erasure makes them indistinguishable at runtime:

```kotlin
// BAD — both erase to MessageParser<*>, Koin returns whichever was registered first
single<MessageParser<Messages>> { FlatBufferMessageParser() }
single<MessageParser<TradingMessage>> { TradingMessageParser(get()) }

// GOOD — named qualifiers disambiguate
single<MessageParser<Messages>>(named("feed")) { FlatBufferMessageParser() }
single<MessageParser<TradingMessage>>(named("trading")) { TradingMessageParser(get()) }

// Consumers use named qualifiers
single<IFeedWebSocketService> {
    FeedWebSocketServiceImpl(messageParser = get(named("feed")))
}
```

**Rule:** Always use `named()` qualifiers for Koin bindings that differ only by generic type parameter. Koin silently returns whichever was registered first, causing hard-to-debug runtime type mismatches (e.g., feed service receiving trading parser → `ClassCastException` kills message consumer channel → live feed appears frozen).

### Koin module declaration order causes NPE

Top-level `val` Koin modules in Kotlin are initialized in file declaration order. If module A uses `includes(moduleB)` but `moduleB` is declared AFTER `moduleA`, `moduleB` is `null` at init time → `NullPointerException: Module.getIncludedModules() on null`.

**Fix:** Declare included modules BEFORE the parent module, or use `lazy` delegation.

```kotlin
// BAD — loginModule references bottomPanelModule which isn't initialized yet
val loginModule = module { includes(bottomPanelModule) }
val bottomPanelModule = module { ... }

// GOOD — bottomPanelModule declared first
val bottomPanelModule = module { ... }
val loginModule = module { includes(bottomPanelModule) }
```

### expect class + actual typealias Modality Mismatch
- `expect class` cannot be satisfied by `actual typealias` when the aliased type has different modality (e.g., an open/abstract Android class). Compiler reports: "actual and expect declarations have different modalities."
- Fix: Use `actual class` with an internal wrapper field instead of `actual typealias` for Android SDK types.
- Preferred: Use DI injection (Koin) or interface + `expect fun` factory to avoid the modality problem entirely.

---

## Process Gotchas

### Always Audit Routing After Building Screens
- A screen can be fully implemented — correct layout, correct state handling — but not wired in navigation
- After building any screen, always check: is it reachable? Is the `Destination` case in `Router`? Is it in `RootView`'s `navigationDestination`?
- The most common "it doesn't work" bug is a missing navigation wire, not a code bug

### iOS VMs May Be Simpler Than Android VMs
- Don't assume iOS and Android VMs are identical
- iOS often has: fewer routes, different edge cases, simpler error handling
- Always parity-check the VM before building the screen — read the actual implementation

### Reference Legacy Code Without Checkout
- Use `git show <base-branch>:<path>` to read legacy code without checking out the branch
- Substitute the actual branch name (e.g., `master`, `main`, or your project's default branch)
- Keeps the worktree clean while still having access to the original implementation

### Field Additions Require Cross-Platform Check
- Any field added to a shared data class or interface must be checked on BOTH platforms
- Android: do existing callers pass the new field?
- iOS: Swift positional constructors — does the new field break existing call sites?

### Cross-Platform Koin Binding Verification
- After registering a VM in the shared Koin module, verify ALL its constructor dependencies have bindings in BOTH platform modules (`androidBridgeModule` AND `iosBridgeModule`)
- Missing bindings on one platform cascade — one missing dep crashes ALL VM resolution on that platform via Koin startup failure
- Pattern: Android builds/runs first, so Android Koin bindings get verified implicitly. iOS Koin is only tested at the very end. Missing iOS-side bindings are the #1 source of iOS runtime crashes after migration.
- Post-migration check: for each constructor parameter of a newly registered VM, grep `di.kt` + platform DI modules to confirm a binding exists on both platforms. Report any MISSING bindings immediately.

### Adapter Preparation: Placement and Field Audit
When writing Android adapters that wrap app-module classes for shared interfaces:
1. **Placement:** Adapters importing app-module types cannot live in `shared/src/androidMain/` (compiles as `shared` module, can't depend on `app`). Place them in `app/src/main/java/.../bridge/<feature>/`.
2. **Field audit:** Cross-reference every shared interface property against the wrapped class in Phase 2. If any required field is `private`, add a public getter BEFORE writing the adapter.

### Pre-Existing Test Failures Are Not Your Problem
- If tests were failing BEFORE your changes, they are not your responsibility
- Use `:shared:assemble` instead of `:shared:build` to bypass pre-existing test failures
- Document pre-existing failures so they are not confused with regressions
