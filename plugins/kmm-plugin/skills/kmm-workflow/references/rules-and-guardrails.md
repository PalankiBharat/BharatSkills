# Rules and Guardrails

Consolidated reference combining guardrails, escalation protocol, and audit checklist for KMM workflow agents.

---

## Table of Contents

1. [Core Guardrails (inject into all agent prompts)](#1-core-guardrails-inject-into-all-agent-prompts)
2. [Escalation Protocol](#2-escalation-protocol)
   - [REQUIRES_APPROVAL](#requires_approval)
   - [Never Work Around Blockers With Hacks](#never-work-around-blockers-with-hacks)
   - [When to Escalate Technical Blockers](#when-to-escalate-technical-blockers)
   - [3-Strike Error Protocol](#3-strike-error-protocol)
   - [KMM-Specific Escalation Triggers](#kmm-specific-escalation-triggers)
3. [Audit Checklist by Severity](#3-audit-checklist-by-severity)
   - [CRITICAL — Must fix immediately](#critical--must-fix-immediately-app-crash-data-loss-security)
   - [HIGH — Should fix](#high--should-fix-memory-leaks-logic-errors-architecture-violations)
   - [MEDIUM — Should fix](#medium--should-fix-code-quality-consistency-maintainability)
   - [LOW — Nice to fix](#low--nice-to-fix-cosmetic-expected-behavior)
   - [Audit Usage Notes](#audit-usage-notes)

---

## 1. Core Guardrails (inject into all agent prompts)

> **Inject this entire section verbatim into every agent prompt system block. ~500 tokens.**

**1:1 MECHANICAL PORT.** THE rule. Only Android→KMM specifics change. Any behavioral change → REQUIRES_APPROVAL.

- **REQUIRES_APPROVAL.** Any change altering observable behavior → stop and present: (1) The problem — what you found and why it matters, (2) Options — each with detailed explanation, pros/cons, long-term implications, (3) Recommended option — biased toward correctness and long-term maintenance, NEVER toward speed or convenience, (4) Why — explain the recommendation reasoning. Wait for user choice.
- **Every decision in files.** After /clear, only files survive. Never leave decisions only in chat.
- **No type casting.** Never use `as`, `as?`, `as!` in Kotlin or Swift. Use polymorphism, generics, protocol conformance, or `is` checks instead.
- **kotlinx.serialization only.** Never use Gson or Moshi in shared/common code.
- **`sealed interface`, not `sealed class`.** Prefer `sealed interface` for KMM discriminated unions.
- **Ktor only.** Never use Retrofit or OkHttp in `commonMain`. Use Ktor client.
- **Koin 4 only.** Never use Hilt or Dagger in shared code. Use Koin 4 for DI.
- **`kotlinx-datetime` only.** Never use `java.time` or platform date APIs in `commonMain`.
- **`StateFlow` only.** Never use `LiveData` in shared/KMM code.
- **No `runBlocking` on the main thread.** Use structured concurrency; `runBlocking` only in tests or background entry points.
- **`expect`/`actual` for platform-specific code.** Never use `#ifdef`, runtime platform checks, or conditional imports as a substitute.
- **One collector per SharedFlow/Channel.** When migrating NavHost-based screens to state-machine navigation, ensure only ONE composable collects from each `SharedFlow`/`Channel`. Child composables must NOT have their own effect collectors if a parent already collects. Multiple concurrent collectors on `SharedFlow(replay=0)` silently swallow effects — this compiles fine but breaks at runtime.
- **Preserve original default values.** When porting `remember { mutableStateOf(X) }` calls (or equivalent state initialization), verify the default value `X` matches the original exactly. A `true`↔`false` flip is a behavioral change that REQUIRES_APPROVAL.
- **Context-first.** Before modifying any file, read the target, all its dependencies (imports, interfaces, base classes), and all its consumers. Never modify with partial context.
- **Escalate unclear failures — never suppress.** If a build fails and the cause is unclear: stop, present the problem, list options with pros/cons, give a recommendation, wait for the user. Never add no-op stubs or use `--no-verify` / `@Suppress` to force a pass.
- **Completion promise required.** Every agent must emit a completion promise string as its last output. No promise = work not accepted.
- **Tests are immutable after baseline.** Once the orchestrator runs baseline and tests pass, test files must not be modified. If tests fail after migration, fix the migration.
- **API signature parity.** Migrated KMM code must have identical method signatures to Android — same method names, parameter names, parameter order, return types.
- **Always use latest docs.** Use Context7, `/find-docs`, or web search for library APIs, versions, and patterns. Never rely on training data — it may be outdated.
- **Latest stable deps.** When adding new dependencies, check the latest stable version via live docs, not training data.
- **No "Shared" prefix** on class/file names in commonMain. Keep names natural (e.g., `LoginViewModel` not `SharedLoginViewModel`).
- **Host app DI stays untouched.** When migrating a library SDK consumed by a host app with its own DI framework (Hilt, Dagger): keep the host app's DI as-is. Add Koin alongside for the SDK's types only. Bridge via a small module. Do NOT propose removing the host app's DI framework.

---

## 2. Escalation Protocol

There are two distinct escalation mechanisms:

- **REQUIRES_APPROVAL** — for behavioral decisions (combining, splitting, signature changes, logic changes). These are correctness issues, not technical failures.
- **3-Strike** — for technical failures (build errors, test failures, runtime crashes). These require diagnosis and repair.

Both mechanisms require stopping and presenting a full analysis to the user. Neither allows silent workarounds.

---

### REQUIRES_APPROVAL

Any change that alters observable behavior requires explicit user approval.

**Triggers:**

- Combining two methods into one (or splitting one into many)
- Changing a method signature (parameter names, types, order, or return type)
- Adding or removing behavior not present in the original Android code
- Changing error handling strategy (swallowing exceptions, changing error types)
- Any "improvement" or "simplification" of the original logic

**Decision Presentation Format:**

Stop and present to the user in this exact format:

1. **The problem** — what you found in the source code and why it creates a decision point. Be specific: which file, which method, what the exact conflict is.
2. **Options** — 2-4 concrete options, each with:
   - What it involves (specific code changes)
   - Pros — including long-term maintenance implications
   - Cons — including risk of introducing bugs or diverging from Android behavior
3. **Recommended option** — biased toward correctness and long-term maintainability. NEVER recommend the fastest or most convenient option if it trades off correctness. If correctness and speed conflict, always recommend correctness.
4. **Why** — explain your reasoning. What would a senior engineer who maintains this codebase for 5 years prefer?

Wait for the user to choose before writing any code.

**Batching:**

During autonomous execution (no user at keyboard), batch REQUIRES_APPROVAL items at phase boundaries — not one-by-one. At the end of each phase, present all accumulated decision points together. Do not pause execution mid-phase for a single REQUIRES_APPROVAL unless it blocks the entire phase.

---

### Never Work Around Blockers With Hacks

When the plan or requirements specify how something should work, implement it as specified. If you hit a blocker that makes the specified approach seem impossible, STOP and escalate — do not invent workarounds to keep the build green. Specifically:

- **No stubs or placeholder implementations** — don't create empty/mock implementations just to satisfy the compiler
- **No technology substitutions** — don't swap a specified dependency for a "simpler" alternative (e.g., using an in-memory store instead of SQLDelight because you think it won't work on the target platform)
- **No feature omissions** — don't skip or simplify specified behavior to avoid a hard problem
- **No silent downgrades** — don't weaken types, remove nullability constraints, or broaden error handling to make things compile

---

### When to Escalate Technical Blockers

If implementing a task as specified would require something you're unsure about (platform support, library compatibility, API availability), stop and present the user using the REQUIRES_APPROVAL format:

1. **The problem** — what you're trying to do, what's blocking it, and why it's not straightforward
2. **Options** (2-4), each with:
   - What it involves
   - Pros and cons
   - Long-term implications
   - Your confidence it will work
3. **Recommended option** — biased toward correctness and long-term maintenance over speed
4. **Why** — your reasoning

Wait for the user to choose before proceeding.

---

### 3-Strike Error Protocol

Before escalating a technical failure, make up to 3 attempts with distinct approaches. Track every attempt in FINDINGS.md under "Issues Encountered" and in PROGRESS.md.

- **Attempt 1 — Diagnose:** Try the obvious fix. If it fails, read the error carefully and diagnose the root cause before attempting again.
- **Attempt 2 — Different approach:** Change strategy based on what you learned. Do not retry the same thing. Consult docs, check related files, try an alternative implementation path.
- **Attempt 3 — Rethink:** Step back and question your assumptions about the problem. Re-read the relevant plan section and FINDINGS.md. Try a fundamentally different approach.
- **After 3 failures — Escalate:** Present the user with all three attempts, what failed in each, and your current best hypothesis. Never attempt a 4th variation silently.

The goal of 3 strikes is to avoid both giving up too early and spinning indefinitely. Each attempt must represent a materially different approach — not a minor variation.

**PROGRESS.md format:**

```
- [~] Task 3.2: Wire expect/actual for PlatformLogger
  - Attempt 1: Used typealias — failed, typealias not allowed for expect class with function bodies
  - Attempt 2: Used abstract expect class — failed, iOS actual requires open, not abstract
  - Attempt 3: Refactored to interface + platform impl — SUCCEEDED
```

---

### KMM-Specific Escalation Triggers

#### Dependency Not in dependency-map.md

If a dependency needed for migration is not listed in `dependency-map.md` (or the equivalent FINDINGS.md Dependency Map), do not guess at a replacement. Either:

- **Search docs first** — check the library's official KMM/CMP compatibility page and record findings in FINDINGS.md under "Research"
- **Escalate to user** — if the compatibility status is unclear or no KMM alternative is documented, stop and present options

Never assume a library is KMM-compatible without verification.

#### expect/actual Unclear

If the correct shape of an `expect`/`actual` declaration is ambiguous (e.g., should it be a class, interface, typealias, or object; what belongs in common vs. platform), do not guess. Present the user with:

- The specific declaration in question
- 2-3 concrete options for how to structure it
- Trade-offs for each (e.g., testability, iOS interop, API surface)
- Your recommendation

Wait for the user to decide before writing any expect/actual code.

#### SKIE Interop Issue

If an interop issue arises related to Swift/Kotlin interface exposure (e.g., generics not visible in Swift, suspend functions not bridged, flows not exposed):

1. **Check `skie-interop.md` first** — the reference may already document the correct SKIE annotation or configuration for this pattern
2. If the answer is there, apply it and record in FINDINGS.md
3. If `skie-interop.md` does not cover the case, escalate to the user with the specific interop failure, what you've tried, and what SKIE docs say (record the docs excerpt in FINDINGS.md before escalating)

Never suppress an interop issue by changing the API shape without user approval.

#### Tests Fail After Migration and Cause Is Unclear

If tests fail after a migration step and the cause is not immediately obvious:

- **STOP.** Do not continue to the next task.
- Do not suppress, skip, or comment out the failing tests.
- Do not mark the task `[x]` in PROGRESS.md.
- Record the failure in FINDINGS.md under "Issues Encountered."
- Apply the 3-Strike Error Protocol to diagnose the root cause.
- If all 3 attempts fail to resolve the failure, escalate with full context: which test, what error, what you tried, your current hypothesis.

Test failures are signal. Suppressing them destroys the value of the test suite and violates the non-negotiable rule: **the codebase is always in a verified, buildable, passing state at every checkpoint.**

---

## 3. Audit Checklist by Severity

Use this checklist when auditing a KMM migration. Items are ordered by severity within each tier.

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

**Why it's a problem:** Crashes at runtime if the cast fails. No recovery. This is the iOS-specific manifestation of the CRITICAL type-casting rule — in Swift KMM bridge code, force unwraps on framework types are especially dangerous because Kotlin types may be bridged as optionals.

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

### Empty Lambda Callbacks

**What to look for:** Callback parameters (`onClick`, `onSubmit`, `onDismiss`, any `() -> Unit` parameter) with default `= {}` that are never overridden by the parent composable.

**Why it's a problem:** The button/control compiles and renders correctly but does nothing when tapped. This is the most common form of silent unwiring during screen migration — the user only discovers it during manual testing.

**Where to look:**
- Migrated Compose screens — especially child composables that accept callback lambdas
- Parent composables that instantiate child components — check whether all callbacks are passed

**How to fix:** Trace the callback chain from declaration to call site. Wire the missing action from the parent composable to the appropriate ViewModel action. If the action is unclear, escalate via REQUIRES_APPROVAL rather than leaving the empty lambda.

**Code example:**

Bad:
```kotlin
@Composable
fun WithdrawalsScreen(
    onOpenWhatsapp: (String) -> Unit = {} // dead button — never passed from parent
) {
    Button(onClick = { onOpenWhatsapp(supportNumber) }) {
        Text("Need Help?")
    }
}
```

Good:
```kotlin
@Composable
fun WithdrawalsScreen(
    onOpenWhatsapp: (String) -> Unit // no default — parent MUST pass it
) {
    Button(onClick = { onOpenWhatsapp(supportNumber) }) {
        Text("Need Help?")
    }
}

// Parent:
WithdrawalsScreen(
    onOpenWhatsapp = { number -> viewModel.processAction(OpenWhatsapp(number)) }
)
```

---

### Multiple SharedFlow Collectors

**What to look for:** More than one composable or SwiftUI view collecting from the same `SharedFlow(replay=0)` or `Channel`.

**Why it's a problem:** Only one collector receives each emission. When multiple composables independently collect from the same SharedFlow, effects are silently split between them — some effects go to collector A, some to collector B, and the user sees inconsistent behavior. This compiles and looks correct but breaks at runtime.

**Where to look:**
- NavHost-based screens migrated to state-machine navigation
- Parent composables that collect effects AND child composables that also collect from the same flow
- SwiftUI views with multiple `.task {}` blocks collecting the same flow

**How to fix:** Ensure only ONE composable/view collects from each SharedFlow/Channel. Child composables should receive effects via parameters from the parent, not through their own collectors.

**Code example:**

Bad:
```kotlin
// Parent collects
LaunchedEffect(Unit) {
    viewModel.effects.collect { effect -> handleEffect(effect) }
}

// Child ALSO collects from the same flow — effects are split!
@Composable
fun ChildScreen(viewModel: MyViewModel) {
    LaunchedEffect(Unit) {
        viewModel.effects.collect { effect -> handleChildEffect(effect) }
    }
}
```

Good:
```kotlin
// Only parent collects
LaunchedEffect(Unit) {
    viewModel.effects.collect { effect ->
        when (effect) {
            is ParentEffect -> handleEffect(effect)
            is ChildEffect -> childEffectHandler(effect)
        }
    }
}

// Child receives effects via parameter
@Composable
fun ChildScreen(onEffect: (ChildEffect) -> Unit) { ... }
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
