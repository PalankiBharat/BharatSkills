# KMM Anti-Patterns Audit Checklist

Use this checklist when auditing a KMM migration. Items are ordered by severity within each tier.

## Table of Contents

- [CRITICAL — Must fix immediately (app crash, data loss, security)](#critical--must-fix-immediately-app-crash-data-loss-security)
  - [runBlocking on Main Thread](#runblocking-on-main-thread)
  - [TODO() in Production Code](#todo-in-production-code)
  - [Missing NSFaceIDUsageDescription](#missing-nsfaceidusagedescription)
  - [Hardcoded Secrets](#hardcoded-secrets)
  - [Type Casting (as / as? / as!)](#type-casting-as--as--as)
- [HIGH — Should fix (memory leaks, logic errors, architecture violations)](#high--should-fix-memory-leaks-logic-errors-architecture-violations)
  - [Leaked CoroutineScopes](#leaked-coroutinescopes)
  - [Swift Force Unwrap in KMM Bridge Code (iOS only)](#swift-force-unwrap-in-kmm-bridge-code-ios-only)
  - [Redundant Flow Wrappers with SKIE](#redundant-flow-wrappers-with-skie)
  - [ViewModels in iosMain](#viewmodels-in-iosmain)
  - [Non-Atomic State Updates](#non-atomic-state-updates)
  - [Feature Flag Wiring Gaps](#feature-flag-wiring-gaps)
  - [Koin `single` Scope for ViewModels](#koin-single-scope-for-viewmodels)
  - [Disconnected UI State (iOS only)](#disconnected-ui-state-ios-only)
- [MEDIUM — Should fix (code quality, consistency, maintainability)](#medium--should-fix-code-quality-consistency-maintainability)
  - [Dual Base Classes](#dual-base-classes)
  - [Typography Line Height Not Applied](#typography-line-height-not-applied)
  - [Duplicated Patterns](#duplicated-patterns)
  - [Lost Concurrency](#lost-concurrency)
  - [Hardcoded Strings (Face ID vs Touch ID)](#hardcoded-strings-face-id-vs-touch-id-ios-only)
- [LOW — Nice to fix (cosmetic, expected behavior)](#low--nice-to-fix-cosmetic-expected-behavior)
  - [SourceKit False Positives](#sourcekit-false-positives)
  - [SKIE Build Time Increase](#skie-build-time-increase)
- [Audit Usage Notes](#audit-usage-notes)

---

## CRITICAL — Must fix immediately (app crash, data loss, security)

---

### runBlocking on Main Thread

**What to look for:** `runBlocking { }` called on the main/UI thread or inside a ViewModel constructor or `init {}` block.

**Why it's a problem:** iOS watchdog kills apps that block the main thread for more than 5 seconds. This is a guaranteed production crash — not a hypothetical.

**Where to look:**
- ViewModel constructors and `init {}` blocks
- Ktor HTTP client interceptors (e.g., auth token injection)
- DI module initialization (Koin `startKoin {}` lambdas)

**How to fix:** Replace `runBlocking` with a `suspend` function called from a coroutine scope, or use `withContext(Dispatchers.IO)` inside an already-suspended context. For Ktor interceptors, use an async `TokenProvider` that caches and refreshes the token in a coroutine rather than blocking.

**Code example:**

Bad:
```kotlin
class AuthInterceptor(private val tokenProvider: TokenProvider) : HttpClientPlugin<Unit, AuthInterceptor> {
    override fun install(plugin: AuthInterceptor, scope: HttpClient) {
        scope.requestPipeline.intercept(HttpRequestPipeline.State) {
            val token = runBlocking { tokenProvider.getToken() } // CRASH on iOS
            context.headers.append("Authorization", "Bearer $token")
        }
    }
}
```

Good:
```kotlin
class AuthInterceptor(private val tokenProvider: TokenProvider) : HttpClientPlugin<Unit, AuthInterceptor> {
    override fun install(plugin: AuthInterceptor, scope: HttpClient) {
        scope.requestPipeline.intercept(HttpRequestPipeline.State) {
            val token = tokenProvider.getToken() // suspend function — no blocking
            context.headers.append("Authorization", "Bearer $token")
        }
    }
}

// TokenProvider caches and uses coroutines internally
class TokenProvider {
    private var cached: String? = null
    suspend fun getToken(): String = cached ?: fetchAndCache()
    private suspend fun fetchAndCache(): String { ... }
}
```

---

### TODO() in Production Code

**What to look for:** `TODO()` or `TODO("...")` calls anywhere in reachable code paths.

**Why it's a problem:** `TODO()` throws `NotImplementedError` at runtime — guaranteed crash when that code path is hit.

**Where to look:**
- UseCase implementations that were stubbed during migration
- RemoteStore or LocalStore placeholder methods
- Any class that was scaffolded but not fully implemented

**How to fix:** Either implement the method properly, or if it is intentionally unimplemented, throw a domain-specific error with a clear message (e.g., `throw UnsupportedOperationException("Not available on this platform")`). Never leave `TODO()` in production-shipped code.

---

### Missing NSFaceIDUsageDescription

**What to look for:** The key `NSFaceIDUsageDescription` absent from the iOS app's `Info.plist`.

**Why it's a problem:** On any device with Face ID, attempting to use biometric authentication crashes the app immediately. This is also a guaranteed App Store rejection during review.

**How to fix:** Add the key to `Info.plist` with a user-facing description string explaining why biometrics are used.

```xml
<key>NSFaceIDUsageDescription</key>
<string>Used to securely authenticate your identity.</string>
```

---

### Hardcoded Secrets

**What to look for:** API keys, auth tokens, client secrets, or any credential literal appearing in `build.gradle.kts`, `BuildKonfig` blocks, or Kotlin source files.

**Why it's a problem:** Secrets embedded in source are committed to version control and are also trivially extractable from a release binary using the `strings` command.

**How to fix:** Read secrets from environment variables in `build.gradle.kts` at build time. Never commit actual secret values.

```kotlin
// build.gradle.kts
buildKonfig {
    packageName = "com.example.app"
    defaultConfigs {
        buildConfigField(
            FieldSpec.Type.STRING,
            "API_KEY",
            System.getenv("API_KEY") ?: error("API_KEY environment variable not set")
        )
    }
}
```

---

### Type Casting (as / as? / as!)

**What to look for:** Any use of `as`, `as?`, or `as!` casts anywhere in shared or platform code.

**Why it's a problem:** Silent runtime failures in KMM interop. Kotlin sealed interfaces are not properly exported as Swift protocols, so navigation or state handling that relies on casting is silently swallowed — no crash, just missing behavior. `as!` will crash outright if the cast fails.

**How to fix:** Use polymorphism, generics, protocol conformance, or `is` checks with explicit handling per branch.

**Code example:**

Bad:
```kotlin
fun handle(event: AppEvent) {
    val nav = event as? NavigationEvent ?: return // silently drops non-nav events
    navigate(nav.destination)
}
```

Good:
```kotlin
fun handle(event: AppEvent) {
    when (event) {
        is AppEvent.Navigate -> navigate(event.destination)
        is AppEvent.ShowError -> showError(event.message)
        is AppEvent.Dismiss -> dismiss()
    }
}
```

---

## HIGH — Should fix (memory leaks, logic errors, architecture violations)

---

### Leaked CoroutineScopes

**What to look for:** `CoroutineScope(Dispatchers.IO).launch { }` or `GlobalScope.launch { }` created inline without being stored and cancelled.

**Why it's a problem:** The scope is never cancelled, so coroutines run until the process dies. On iOS, this causes unbounded memory growth — background work accumulates across navigation pushes.

**How to fix:** Tie the scope to the ViewModel lifecycle using `viewModelScope`, or store the scope as a property and cancel it in `onCleared()`.

**Code example:**

Bad:
```kotlin
class UserViewModel : ViewModel() {
    fun loadUser(id: String) {
        CoroutineScope(Dispatchers.IO).launch { // never cancelled
            val user = userRepository.fetch(id)
            _state.value = _state.value.copy(user = user)
        }
    }
}
```

Good:
```kotlin
class UserViewModel : ViewModel() {
    fun loadUser(id: String) {
        viewModelScope.launch {
            val user = userRepository.fetch(id)
            _state.value = _state.value.copy(user = user)
        }
    }
}
```

---

### Swift Force Unwrap in KMM Bridge Code (iOS only)

**What to look for:** The `as!` operator in Swift interop code or bridging layers.

**Why it's a problem:** Crashes at runtime if the cast fails. No recovery.

This is the iOS-specific manifestation of the CRITICAL type-casting rule. In Swift KMM bridge code, force unwraps on framework types are especially dangerous because Kotlin types may be bridged as optionals.

**How to fix:** Use `guard let` with a safe cast and a meaningful fallback or early return.

```swift
// Bad
let vm = container.resolve(UserViewModel.self) as! UserViewModel

// Good
guard let vm = container.resolve(UserViewModel.self) else {
    assertionFailure("UserViewModel not registered in DI container")
    return
}
```

---

### Redundant Flow Wrappers with SKIE

**What to look for:** Custom wrapper classes named `KmmFlow`, `KmmStateFlow`, or `KmmSharedFlow` coexisting with SKIE in the dependencies.

**Why it's a problem:** Two competing flow consumption mechanisms exist simultaneously. Swift consumers may use either path, leading to inconsistent behavior and maintenance confusion.

**How to fix:** Remove the manual wrapper classes entirely. SKIE automatically converts Kotlin Flows to Swift `AsyncSequence` — no wrappers needed.

---

### ViewModels in iosMain

**What to look for:** ViewModel classes placed under `shared/src/iosMain/` instead of `shared/src/commonMain/`.

**Why it's a problem:** Code in `iosMain` cannot be tested in `commonTest` and cannot be reused on Android, defeating the purpose of KMM.

**How to fix:** Move ViewModels to `commonMain`. Use `expect`/`actual` declarations only for the narrow platform-specific pieces (e.g., a platform dispatcher or a platform-specific storage primitive), not the ViewModel itself.

---

### Non-Atomic State Updates

**What to look for:** The pattern `setState(getState().copy(...))` — reading current state and writing a mutation as two separate operations.

**Why it's a problem:** Read-then-write is not atomic. Under concurrent coroutine execution, two coroutines can both read the same stale state, apply independent mutations, and the second write clobbers the first.

**How to fix:** Use an `updateState` helper that holds a mutex across the read-modify-write cycle.

**Code example:**

Bad:
```kotlin
fun incrementCount() {
    setState(getState().copy(count = getState().count + 1)) // race condition
}
```

Good:
```kotlin
fun incrementCount() {
    updateState { current -> current.copy(count = current.count + 1) } // atomic
}

// BaseViewModel helper
protected fun updateState(reducer: (S) -> S) {
    stateMutex.withLock {
        _state.value = reducer(_state.value)
    }
}
```

---

### Feature Flag Wiring Gaps

**What to look for:** Feature flags that are checked in Android routing/navigation code but not present in the equivalent KMM routing logic.

**Why it's a problem:** A feature enabled or disabled by a flag behaves differently per platform — Android respects the flag, iOS ignores it (or vice versa). This is a silent logic divergence, not a crash.

**How to fix:** Audit every feature flag used in Android routing. For each, verify a corresponding check exists in the KMM navigation or routing layer. Add any missing wiring.

---

### Koin `single` Scope for ViewModels

**What to look for:** ViewModels registered with `single { }` instead of `factory { }` in Koin modules.

**Why it's a problem:** A `single` creates one shared instance for the entire app lifetime. When the user navigates back and returns to the same screen, they get the stale ViewModel instance with old state.

**How to fix:** Register all ViewModels with `factory { }` so each navigation push creates a fresh instance.

```kotlin
// Bad
val viewModelModule = module {
    single { UserViewModel(get()) }
}

// Good
val viewModelModule = module {
    factory { UserViewModel(get()) }
}
```

---

### Disconnected UI State (iOS only)

**What to look for:** `@State` variables in SwiftUI views that are mutated by the user but never sent back to the ViewModel.

**Why it's a problem:** UI state diverges from ViewModel state. For example: a checkbox is visually checked by the user, but the ViewModel never receives the action, so the data layer never updates.

**How to fix:** All user-driven state changes must route through `processAction()` on the ViewModel, not just update local `@State`.

```swift
// Bad
@State private var isNotificationsEnabled = false
Toggle("Notifications", isOn: $isNotificationsEnabled)

// Good
Toggle("Notifications", isOn: Binding(
    get: { viewModel.state.isNotificationsEnabled },
    set: { _ in viewModel.processAction(SettingsAction.ToggleNotifications()) }
))
```

---

## MEDIUM — Should fix (code quality, consistency, maintainability)

---

### Dual Base Classes

**What to look for:** Both a `Presenter<State, Effect>` class and a `BaseViewModel<State, Action, Effect>` class existing in the codebase, with different ViewModels extending each.

**Why it's a problem:** Two parallel abstractions with different APIs for the same concept. New developers don't know which to use. Existing code is inconsistent.

**How to fix:** Decide on one (prefer `BaseViewModel`) and migrate all `Presenter` subclasses to it. Delete `Presenter` when the last subclass is migrated.

---

### Typography Line Height Not Applied

**What to look for:** A design token or typography definition that includes `lineHeight`, but SwiftUI `Text` modifiers that do not apply `.lineSpacing(...)`.

**Why it's a problem:** Multiline text won't match Android spacing, causing visual divergence from the design specification.

**How to fix:** When applying a typography style in SwiftUI, also apply the line spacing offset.

```swift
// lineSpacing in SwiftUI is added between lines, not total line height.
// Offset: lineHeight - fontSize
Text(label)
    .font(.system(size: heading.fontSize))
    .lineSpacing(heading.lineHeight - heading.fontSize)
```

---

### Duplicated Patterns

**What to look for:** The same logic block (e.g., debounced loading spinner, error retry logic, pagination state management) copy-pasted across three or more ViewModels.

**Why it's a problem:** Every copy is a divergence risk. Bug fixes and behavior changes must be applied manually to each instance.

**How to fix:** Extract to a shared utility function or extension on `BaseViewModel`.

---

### Lost Concurrency

**What to look for:** Places where Android used `async`/`await` to run operations concurrently, but the KMM migration replaced this with sequential `suspend` calls.

**Why it's a problem:** A silent performance regression. Operations that originally ran in parallel now run in series, potentially doubling load times.

**How to fix:** Use `coroutineScope { }` with `async`/`awaitAll` to restore the original parallelism.

**Code example:**

Bad (sequential):
```kotlin
val profile = userRepository.fetchProfile(userId)
val settings = userRepository.fetchSettings(userId)
val feed = feedRepository.fetchFeed(userId)
```

Good (concurrent):
```kotlin
val (profile, settings, feed) = coroutineScope {
    val profileDeferred = async { userRepository.fetchProfile(userId) }
    val settingsDeferred = async { userRepository.fetchSettings(userId) }
    val feedDeferred = async { feedRepository.fetchFeed(userId) }
    Triple(profileDeferred.await(), settingsDeferred.await(), feedDeferred.await())
}
```

---

### Hardcoded Strings (Face ID vs Touch ID) (iOS only)

**What to look for:** UI strings hardcoded as "Face ID" without checking the device's actual biometry type.

**Why it's a problem:** Touch ID devices display "Face ID" — incorrect and confusing for users.

**How to fix:** Check `LAContext().biometryType` at display time and render the appropriate string.

```swift
import LocalAuthentication

var biometryLabel: String {
    let context = LAContext()
    context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    switch context.biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    case .opticID: return "Optic ID"
    default: return "Biometrics"
    }
}
```

---

## LOW — Nice to fix (cosmetic, expected behavior)

---

### SourceKit False Positives

**What to look for:** Xcode editor showing "No such module 'shared'" or type-not-found errors on KMM-generated types.

**Why it's a problem:** It is not actually a problem. This is a SourceKit indexing issue — the editor's index is stale or incomplete.

**Action:** Ignore these errors. Trust `xcodebuild` command-line output exclusively to determine whether the build actually succeeds. Do not spend time debugging SourceKit errors that do not reproduce on the command line.

---

### SKIE Build Time Increase

**What to look for:** The Kotlin/Native link step taking noticeably longer after SKIE is added (roughly 20–50% longer than before).

**Why it's a problem:** It is not a bug. SKIE instruments the generated Objective-C headers during the link phase, which adds time.

**Action:** This is expected and acceptable. Do not investigate or attempt to work around it unless link times become extreme (e.g., >10 minutes on a standard CI machine).

---

## Audit Usage Notes

- Fix all CRITICAL items before merging to main. No exceptions.
- HIGH items should be fixed in the same sprint as the migration. Create tickets if they cannot be fixed immediately.
- MEDIUM items should be addressed in a follow-up pass before the first production release.
- LOW items are informational. Log them for new team members to avoid confusion, but do not block on them.
