# KMM Patterns Reference

Quick-reference for Kotlin Multiplatform Mobile patterns. Project-agnostic; use as a checklist and code template source.

## Table of Contents

- [Source Set Structure](#source-set-structure)
- [expect/actual Declarations](#expectactual-declarations)
  - [Official JetBrains hierarchy of preference](#official-jetbrains-hierarchy-of-preference)
  - [Pattern 2: Interface + expect fun factory](#pattern-2-interface--expect-fun-factory)
  - [Pattern 3: expect/actual for platform values](#pattern-3-expectactual-for-platform-values)
- [Framework Export (iOS)](#framework-export-ios)
- [ViewModel Pattern](#viewmodel-pattern)
  - [BaseViewModel contract](#baseviewmodel-contract)
  - [Concrete ViewModel example](#concrete-viewmodel-example)
  - [Platform consumption](#platform-consumption)
- [DI Pattern (Koin)](#di-pattern-koin)
  - [Module setup](#module-setup)
  - [iOS PresenterProvider (KoinComponent bridge)](#ios-presenterprovider-koincomponent-bridge)
  - [Migration from Hilt](#migration-from-hilt)
- [Coroutines](#coroutines)
- [KMM Interface First](#kmm-interface-first)

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

---

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
        println(message) // maps to NSLog on iOS
    }
}
```

---

### Pattern 3: expect/actual for platform values

```kotlin
// commonMain
expect val platformName: String
```

```kotlin
// androidMain
actual val platformName: String = "Android"
```

```kotlin
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
abstract class BaseViewModel<State, Action, Effect>(
    initialState: State,
) : ViewModel() {

    private val _state = MutableStateFlow(initialState)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _effects = MutableSharedFlow<Effect>(extraBufferCapacity = 16)
    val effects: SharedFlow<Effect> = _effects.asSharedFlow()

    protected var currentState: State
        get() = _state.value
        set(value) { _state.value = value }

    abstract fun processAction(action: Action)

    protected fun emitEffect(effect: Effect) {
        viewModelScope.launch { _effects.emit(effect) }
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
            CounterAction.Increment -> currentState = currentState.copy(count = currentState.count + 1)
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

### iOS PresenterProvider (KoinComponent bridge)

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

**`Dispatchers.IO` in commonMain:** Available with `kotlinx-coroutines-core` 1.7+. If the Android source code uses `Dispatchers.IO`, upgrade the coroutines version to 1.7+ and keep using `Dispatchers.IO` in commonMain — Android is the source of truth, don't change dispatchers unnecessarily. On iOS, `Dispatchers.IO` maps to a background thread pool which is appropriate for I/O-bound work (network, disk). This is a safety net: upgrading the version is a one-time cost that avoids changing every dispatcher call site during migration.

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
