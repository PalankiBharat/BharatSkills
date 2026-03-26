# SKIE Swift Interop Reference

SKIE (Swift Kotlin Interface Enhancer) improves the Swift API generated from Kotlin/Native, replacing clunky wrapper types with idiomatic Swift constructs. This reference covers setup, core patterns, and production-hardened gotchas.

## Table of Contents

- [Setup](#setup)
- [StateFlow/SharedFlow → AsyncSequence](#stateflowsharedflow--asyncsequence)
- [Sealed Classes → Swift Enums](#sealed-classes--swift-enums)
- [Suspend Functions → async throws](#suspend-functions--async-throws)
- [Protocol Conformance Gotcha (CRITICAL)](#protocol-conformance-gotcha-critical)
- [Kotlin Enums → Swift Enums](#kotlin-enums--swift-enums)
- [Gotchas (Battle-Tested)](#gotchas-battle-tested)
  - [Nullable Effects Guard](#nullable-effects-guard)
  - [UIApplication.shared.open(url) — Async Context Rules](#uiapplicationsharedopenurl--async-context-rules)
  - [import Combine Must Be Preserved](#import-combine-must-be-preserved)
  - [Build Time](#build-time)
  - [Version Coupling](#version-coupling)
  - [Nested Dot Notation for Sealed Subtypes](#nested-dot-notation-for-sealed-subtypes)
  - [Multiple Flows on a ViewModel](#multiple-flows-on-a-viewmodel)
- [Quick Reference](#quick-reference)

---

## Setup

```kotlin
// build.gradle.kts (shared module or root)
plugins {
    id("co.touchlab.skie") version "0.10.10"
}
```

**Blocking prerequisites:**
- Gradle 8.8+ is required. Check with `./gradlew --version` before adding SKIE. Older Gradle versions will fail silently or with cryptic errors.
- No additional dependencies are needed. SKIE automatically instruments all exported Kotlin code.

**Optional: per-function annotations**

```kotlin
// build.gradle.kts
dependencies {
    commonMainImplementation("co.touchlab.skie:configuration-annotations:0.10.10")
}
```

Use `@SealedInterop.Enabled`, `@FlowInterop.Enabled`, etc. to opt in/out per declaration when the global defaults aren't appropriate.

---

## StateFlow/SharedFlow → AsyncSequence

SKIE automatically converts `StateFlow<T>` and `SharedFlow<T>` to Swift `AsyncSequence`. No wrappers, no Combine bridges.

### State observation

```swift
.task {
    for await state in viewModel.state {
        self.state = state
    }
}
```

### Effect observation (nullable SharedFlow)

```swift
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        // handle non-nil effect
    }
}
```

**Rules:**
- `.task {}` attaches to a SwiftUI view and auto-cancels when the view disappears. No manual `cancel()` call needed.
- Use **separate** `.task {}` blocks for state and effect flows. Each block runs as an independent async loop. Combining them into one block means the second loop never starts — the first loop runs forever.
- `.task(id:)` restarts the async block when `id` changes. Use this when you need to restart observation on a key change.

---

## Sealed Classes → Swift Enums

SKIE converts Kotlin sealed classes into exhaustive Swift enums via the `onEnum(of:)` function.

### Object variants (no associated data)

```swift
// Kotlin: object Exit : Effect()
switch onEnum(of: effect) {
case .exit:
    dismiss()
}
```

### Data class variants (with properties)

```swift
// Kotlin: data class ShowError(val message: String) : Effect()
switch onEnum(of: effect) {
case .showError(let e):
    showAlert(e.message)
}
```

### Nested sealed classes

```swift
switch onEnum(of: effect) {
case .navigate(let nav):
    switch onEnum(of: nav) {
    case .toHome:
        router.push(.home)
    case .toDetail(let d):
        router.push(.detail(id: d.id))
    }
}
```

**No `default` case needed.** The compiler enforces exhaustiveness. If you add a new sealed subclass in Kotlin, Swift will produce a compile error at every switch site — which is the desired behavior.

**Subtypes use nested dot notation.** SKIE generates `Effect.NavigateToNext`, not flat `NavigateToNext`. This applies to both effect handling and action dispatching.

---

## Suspend Functions → async throws

Kotlin `suspend` functions are exposed as Swift `async throws` functions directly.

```swift
Task {
    do {
        let result = try await viewModel.loadData()
        self.items = result
    } catch {
        self.errorMessage = error.localizedDescription
    }
}
```

**Cancellation is propagated.** Cancelling the Swift `Task` also cancels the underlying Kotlin coroutine — structured concurrency works across the boundary.

---

## Protocol Conformance Gotcha (CRITICAL)

When a Swift class conforms to a Kotlin interface (protocol) that contains `suspend` functions, SKIE **prefixes the overriding method with `__`**.

```kotlin
// Kotlin
interface BiometricHandler {
    suspend fun isEnabled(): Boolean
    fun label(): String
}
```

```swift
// Swift — generated protocol
class SwiftBiometricHandler: BiometricHandler {
    // suspend fun → prefixed with __ and returns KotlinBoolean
    func __isEnabled() async throws -> KotlinBoolean {
        return KotlinBoolean(bool: await checkBiometrics())
    }

    // non-suspend fun → original name, native Swift type
    func label() -> String {
        return "Face ID"
    }
}
```

This is intentional SKIE design to avoid naming conflicts with the generated async wrapper. Non-suspend functions keep their original names and use native Swift types. Do not rename `__isEnabled` — the Kotlin runtime looks it up by that exact symbol.

The `__` prefix applies ONLY to suspend functions themselves, not to non-suspend functions in the same interface. These are two separate SKIE mechanisms — the `__` prefix for suspend functions in protocols and the `__` prefix for Kotlin-backed enum types are unrelated.

---

## Kotlin Enums → Swift Enums

SKIE converts Kotlin enums to Swift enums for exhaustive switching.

```swift
// Exhaustive switch — no default needed
switch occupation {
case .privateSector:
    label = "Private"
case .publicSector:
    label = "Public"
}
```

**Accessing Kotlin enum properties or methods** requires converting back to the Kotlin enum first:

```swift
let description = Occupation.privateSector.toKotlinEnum().description()
```

The original Kotlin enum is accessible in Swift with a `__` prefix (`__Occupation`). The SKIE-generated Swift enum is the unqualified name (`Occupation`).

**Note:** The `__` prefix on Kotlin-backed enum types (e.g., `__Occupation`) is a separate SKIE mechanism from the `__` prefix applied to suspend functions in protocol conformances. They are unrelated despite using the same prefix.

**Conversion helpers:**
- `swiftEnum.toKotlinEnum()` — Swift → Kotlin
- `kotlinEnum.toSwiftEnum()` — Kotlin → Swift

---

## Gotchas (Battle-Tested)

### Nullable Effects Guard

`SharedFlow<Effect?>` can and does emit `nil`. Without a guard, iterating over the flow will pass nil to handlers expecting a non-nil value, causing unexpected behavior or a runtime crash if force-unwrapped downstream.

```swift
// ALWAYS do this
for await effect in viewModel.effect {
    guard let effect = effect else { continue }
    handleEffect(effect)
}

// NEVER do this — will pass nil to handlers expecting a non-nil value, causing unexpected behavior or a runtime crash if force-unwrapped downstream
for await effect in viewModel.effect {
    handleEffect(effect) // effect is Effect? here
}
```

### UIApplication.shared.open(url) — Async Context Rules

`UIApplication.shared.open(_:)` is async on iOS 16+. The rule depends on where the call lives:

```swift
// Inside .task {} — NEEDS await
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        if case .openUrl(let e) = onEnum(of: effect) {
            await UIApplication.shared.open(e.url)  // required
        }
    }
}

// Inside synchronous closure (button action, sheet callback) — NO await
Button("Open") {
    UIApplication.shared.open(url)  // no await — sync context
}
```

Adding `await` in a sync context breaks compilation. Omitting it in an async context also breaks compilation. Match the call style to the surrounding context.

### import Combine Must Be Preserved

When removing old `KmmFlow` / `CombineWrapper` subscriptions during a SKIE migration, do not remove `import Combine` if the file still uses Combine elsewhere (e.g., `Publishers.keyboardHeight`, `.sink`, `.store(in:)`).

```swift
// Keep this even after removing KmmFlow subscriptions
import Combine  // still needed for Publishers.keyboardHeight

// If you remove it, keyboard handling silently stops working —
// no compile error because the keyboard publisher extension
// may be defined in another file
```

Check all usages of Combine in the file before removing the import.

### Build Time

SKIE adds approximately 20–50% to the Kotlin/Native link step. This is expected and not a bug.

- First build after adding SKIE is the slowest.
- Incremental builds are significantly faster.
- CI pipelines should account for this in timeout budgets.

### Version Coupling

SKIE 0.10.10 supports Kotlin **2.0.x through 2.x — check the SKIE GitHub releases page for exact version compatibility before upgrading**.

When upgrading Kotlin, check SKIE compatibility first at [touchlab.co/skie](https://touchlab.co/skie) or the GitHub releases page. An incompatible combination produces link-time failures that can be hard to diagnose.

Pin the SKIE version explicitly — do not use version ranges or `+` wildcards.

### Nested Dot Notation for Sealed Subtypes

Sealed class subtypes in Swift use nested dot notation, not flat names.

```swift
// CORRECT
viewModel.onEvent(event: LoginEvent.SubmitOtp(otp: pin))

// WRONG — does not compile
viewModel.onEvent(event: SubmitOtp(otp: pin))
```

The same applies to effect handling:

```swift
switch onEnum(of: effect) {
case .navigateToNext:   // Effect.NavigateToNext in Kotlin
    router.push(.next)
}
```

### Multiple Flows on a ViewModel

Some ViewModels expose more than one reactive flow (e.g., a primary `effect: SharedFlow<Effect?>` and a secondary `navigationEvents: SharedFlow<Route?>`). Both must be subscribed to independently.

```swift
// Subscribe to both — missing one means missing navigation events
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        handleEffect(effect)
    }
}
.task {
    for await route in viewModel.navigationEvents {
        guard let route = route else { continue }
        handleRoute(route)
    }
}
```

If you only subscribe to `effect` and navigation uses `navigationEvents`, the screen will appear broken with no error or log output.

---

## Quick Reference

| Kotlin type | Swift type (SKIE) | Access pattern |
|---|---|---|
| `StateFlow<T>` | `AsyncSequence` | `for await x in vm.state` |
| `SharedFlow<T?>` | `AsyncSequence` | `for await x in vm.effect` + guard |
| `sealed class` | `enum` (via `onEnum`) | `switch onEnum(of: x)` |
| `suspend fun` | `async throws func` | `try await vm.op()` |
| `enum class` | Swift enum | `switch x` / `.toKotlinEnum()` |
| interface w/ suspend | Swift protocol | override as `func __name() async throws` |
