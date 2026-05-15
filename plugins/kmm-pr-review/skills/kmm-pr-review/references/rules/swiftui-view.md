# SwiftUI view rules

Loaded for files with `role=swiftui-view`. The iOS consumer of shared KMP code.

Cite as `references/rules/swiftui-view.md#<rule-id>`.

---

### SV-01 — Consumes shared Flow via `for await` (SKIE) or properly-wrapped subscription
**Severity:** P1
**Pattern:** SwiftUI view manually subscribes to a shared Kotlin `Flow` using a custom `collect`/callback wrapper when SKIE is configured in the project.
**Why:** SKIE generates `SkieSwiftFlow<T>` (AsyncSequence). Idiomatic consumption: `for await item in flow` inside a `Task` or `.task` modifier.
**Suggestion:** `.task { for await item in viewModel.state { ... } }` for collection, with cancellation flowing from Task.
**Source:** https://skie.touchlab.co/features/flows

### SV-02 — Singletons accessed via `.shared` / `.companion`
**Severity:** P2
**Pattern:** Swift code accesses Kotlin `object` or `companion object` via the deprecated `MyObject()` constructor pattern.
**Why:** Per canonical: *"`MySingleton()` in Swift has been deprecated."*
**Suggestion:** `MyObject.shared`, `MyClass.companion`, `MyClass.Companion.shared`.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Kotlin singletons)

### SV-03 — Sealed types matched via `onEnum(of:)` for exhaustive switch
**Severity:** P2
**Pattern:** Swift switch on a Kotlin sealed type uses `is` checks or always includes a `default:` case.
**Why:** SKIE generates `onEnum(of:)` for exhaustive switching. Using `is`-checks loses exhaustiveness; Swift compiler can't catch a missing case after a new sealed child is added.
**Suggestion:** `switch onEnum(of: result) { case .success(let s): ... case .failure(let f): ... }`.
**Source:** https://skie.touchlab.co/features/sealed-classes

### SV-04 — `Task` / `.task` for shared async, lifecycle-bound
**Severity:** P1
**Pattern:** SwiftUI view starts a long-running async operation in `init`, `onAppear` without cancellation, or stores a `Task` that isn't cancelled on view disappear.
**Why:** Untied async work continues after the view goes away — wastes work, can crash on captured-self use after free.
**Suggestion:** `.task { ... }` modifier — auto-cancels on view disappear. Or store `@State var task: Task<...>?` and explicitly cancel in `.onDisappear`.
**Source:** https://developer.apple.com/documentation/swiftui/view/task(priority:_:)

### SV-05 — No `as!` / `as?` / `is` on `SkieKotlin___Flow`
**Severity:** P0
**See:** `references/rules/ios-readiness.md#i-skie-09` — same rule, same source. This entry exists so the SwiftUI specialist can flag it from the iOS-consumer side; the iOS-readiness rule covers the Kotlin/shared side. If both fire on the same Swift file, the aggregator keeps SV-05 (closer to the consumption point) and drops I-SKIE-09 via `references/derivative-map.md`.
