# Base rules — always loaded

Every specialist loads this file. Covers KMP-fundamental correctness (expect/actual, type leakage, coroutines, idiomatic Kotlin) — concerns that apply regardless of file role.

Rule IDs are stable; cite as `references/rules/_base.md#<rule-id>`.

Each rule fires deterministically when its pattern is present. No "consider" or "might". Either the pattern is there → finding; or it isn't → silent.

---

## S-EA — expect / actual

### S-EA-01 — expect/actual only when there's a real platform dependency
**Severity:** P1
**Pattern:** an `expect` declaration whose `actual` implementations are identical across platforms (same bodies in `androidMain` and `iosMain`).
**Why:** Per the canonical doc, *"Use expected and actual declarations only for Kotlin declarations that have platform-specific dependencies."* Overuse adds boilerplate and a refactoring tax.
**Suggestion:** Move the implementation to commonMain. If the platform-specific part is small, narrow the expect surface to just the platform call.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html

### S-EA-02 — Prefer interface + DI over `expect class` for business logic
**Severity:** P1 (P2 when Koin is configured — this team does use Koin)
**Pattern:** an `expect class` (or `expect interface` with substantial structure) representing a service, repository, use case, or other business component.
**Why:** Canonical: *"Don't overuse expected and actual declarations – in some cases, an interface may be a better choice because it is more flexible and easier to test."* Interfaces + Koin are testable, support multiple implementations, don't leak platform structure through the type system, and avoid `expect class`'s Beta status.
**Suggestion:** Define an `interface` in commonMain, implement in `androidMain`/`iosMain`, wire via Koin (`expect val platformModule: Module`).
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html (Interfaces in common code)

### S-EA-03 — expect/actual must share package and name exactly
**Severity:** P0
**Pattern:** an `actual` declaration whose package or name doesn't match its `expect`.
**Why:** *"Every actual declaration shares the same package as the corresponding expected declaration."* Mismatch = compile failure.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html

### S-EA-04 — No implementation in expect body
**Severity:** P0
**Pattern:** an `expect fun` or `expect class` member with a body in commonMain (outside the open-interface exception, see S-EA-05).
**Why:** Canonical: *"These declarations can be used in the common code, but shouldn't include any implementation."*
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html

### S-EA-05 — Default bodies allowed only on `open` interface methods
**Severity:** P1
**Pattern:** a default body on an expect member that isn't an open interface method.
**Why:** *"In interfaces, functions in expect declarations cannot have bodies, but their actual counterparts can be non-abstract and have a body. To indicate that common inheritors don't need to implement a function, mark it as open."*
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html

### S-EA-06 — Place actuals in the intermediate source set when shared across siblings
**Severity:** P2
**Pattern:** identical `actual` declarations in `iosX64Main`, `iosArm64Main`, `iosSimulatorArm64Main` that could live in `iosMain`.
**Why:** *"Only iosMain typically contains the actual declarations and not the platform source sets."*
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html

### S-EA-07 — `expect class` is Beta — flag new uses
**Severity:** P2
**Pattern:** new `expect class` declarations.
**Why:** *"Expected and actual classes are in Beta."* Prefer interfaces + DI when the type carries structure.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html

---

## S-TYPE — type leakage / cross-platform compatibility

### S-TYPE-01 — No JVM/Android types in commonMain
**Severity:** P0
**Pattern:** imports in commonMain matching `java.*`, `javax.*`, `android.*`, `kotlin.jvm.*`, or `androidx.*` not on the KMP-published list (see S-TYPE-02).
**Why:** commonMain compiles for all targets including Kotlin/Native. JDK/Android types don't exist on Native. Build fails on iOS.
**Suggestion:** Move to `androidMain`, or replace with a multiplatform equivalent (`kotlinx.datetime` for `java.time.*`, `okio` for `java.io.*`, `kotlinx.io` for streams).
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html

### S-TYPE-02 — Verify androidx artifact has KMP publication before importing from commonMain
**Severity:** P1
**Pattern:** `androidx.*` import in commonMain.
**Why:** Only specific androidx artifacts are KMP-published (notably `androidx.lifecycle:lifecycle-viewmodel`, `androidx.annotation`, `androidx.collection`, `androidx.paging`). Most are not. Non-KMP androidx in commonMain breaks the iOS build.
**Suggestion:** Verify against the Android KMP support matrix. If absent, move to `androidMain`.
**Source:** https://developer.android.com/kotlin/multiplatform (Jetpack libraries with KMP support)

### S-TYPE-03 — Generic interfaces and generic functions erase on the Obj-C bridge
**Severity:** P0 (when iOS consumes the API)
**Pattern:** public `interface` or top-level `fun` in commonMain that is generic (`<T>`) and is exported to iOS.
**Why:** Obj-C supports generics on classes and collections only. Generic interfaces and generic functions lose type parameters at the bridge — Swift sees `AnyObject`. Silent API weakening on iOS.
**Suggestion:** Expose a generic *class* (class generics survive), specialize for the concrete type iOS needs, or use SKIE Flow bridging when the case is a Flow specifically.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### S-TYPE-04 — Inline / value classes in public surface erase to underlying type
**Severity:** P0 (when iOS consumes the API)
**Pattern:** public API exposes `kotlin.Result<T>`, any user `value class` / `inline class`, or `Duration` (in some Kotlin versions) to iOS.
**Why:** Inline classes are erased to their underlying type on the Obj-C bridge. `Result<List<User>>` becomes `Any?` in Swift. The async completion handler's separate `Error?` parameter compounds the confusion.
**Suggestion:** Use a regular sealed class (e.g. `sealed interface ApiResult<out T> { ... }`) for public surface. Keep `Result` internal.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (mappings table: "Inline classes — Unsupported")

---

## S-CORO — coroutines, dispatchers, scopes

### S-CORO-01 — Inject dispatchers; don't hardcode `Dispatchers.X` in shared code
**Severity:** P1
**Pattern:** a shared-code class/function that directly references `Dispatchers.IO`/`Default`/`Main` rather than receiving a `CoroutineDispatcher` (or `CoroutineContext`) via constructor or parameter.
**Why:** Hardcoded dispatchers prevent test substitution and platform-specific tuning.
**Suggestion:** Constructor parameter, production default from the Koin module.
**Source:** https://kotlinlang.org/docs/coroutine-context-and-dispatchers.html

### S-CORO-02 — No unscoped CoroutineScope without a lifecycle anchor
**Severity:** P1
**Pattern:** `CoroutineScope(Dispatchers.X)` constructed in a long-lived shared class with no cancellation path tied to a consumer lifecycle.
**Why:** Unscoped coroutines leak. Structured concurrency requires every scope has an owner that cancels it. Android uses `viewModelScope`; iOS must wire cancellation manually.
**Suggestion:** Use `androidx.lifecycle.ViewModel`'s `viewModelScope` (team convention) or accept a `CoroutineScope` parameter so the consumer owns lifecycle.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-mobile-concurrency-and-coroutines.html

### S-CORO-03 — Public `suspend` exposed to iOS that can throw must declare `@Throws`
**Severity:** P0
**Pattern:** a public `suspend fun` callable from iOS that does I/O, parsing, or otherwise can throw, lacking `@Throws(...)` annotation.
**Why:** Per canonical: *"`suspend` functions without `@Throws` propagate only `CancellationException`. Other Kotlin exceptions reaching Swift/Objective-C are considered unhandled and cause program termination."* Most common KMM iOS crash.
**Suggestion:** `@Throws(Throwable::class)` (or narrower) on any suspend in iOS-exposed API.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Errors and exceptions)

### S-CORO-04 — Flow exposed to iOS without SKIE or KMP-NativeCoroutines wrapper
**Severity:** P1
**Pattern:** a `Flow<T>` returned from public API consumed by iOS, with neither SKIE plugin applied (see `ios-readiness.md#i-skie-01`) nor a KMP-NativeCoroutines wrapper.
**Why:** Plain Kotlin `Flow` is awkward from Swift — generic erasure + no cancellation handle. Canonical solutions are SKIE (team choice) or KMP-NativeCoroutines.
**Suggestion:** Verify SKIE is configured. If not, configure it or wrap the Flow before exposure.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-upgrade-app.html and https://skie.touchlab.co/features/flows

### S-CORO-05 — Freeze / Worker / `ensureNeverFrozen` patterns are legacy
**Severity:** P2 (P3 if just comments)
**Pattern:** references to `.freeze()`, `ensureNeverFrozen()`, `kotlin.native.concurrent.AtomicReference`, `Worker`, `kotlin.native.concurrent.*`.
**Why:** Legacy memory manager. New memory manager (default since Kotlin 1.7.20) removed freezing. This code is either obsolete or working around a non-problem.
**Suggestion:** Remove or replace with `kotlinx.atomicfu` for atomics. Plain state for non-shared mutable.
**Source:** https://kotlinlang.org/docs/native-memory-manager.html

---

## S-CLEAN — idiomatic Kotlin (always-on subset)

Full clean-code rules on NEW files live in `new-file-clean-code.md`.

### S-CLEAN-01 — Prefer property over no-arg function when cheap and pure
**Severity:** P2
**Pattern:** `fun isEmpty(): Boolean = items.size == 0` — no-arg function that doesn't throw, is cheap, returns the same result for the same state.
**Why:** Canonical: *"Prefer a property over a function when the underlying algorithm: Does not throw. Is cheap to calculate. Returns the same result over invocations if the object state hasn't changed."*
**Suggestion:** `val isEmpty: Boolean get() = items.size == 0`.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Functions vs. properties)

### S-CLEAN-02 — Use extension functions for utility logic on a type
**Severity:** P2
**Pattern:** a class whose methods take their primary subject as a parameter (e.g., `class StringUtils { fun isValidEmail(s: String) }`).
**Why:** *"Every time you have a function that works primarily on an object, consider making it an extension function accepting that object as a receiver."*
**Suggestion:** `fun String.isValidEmail(): Boolean = ...` (top-level, scoped via visibility modifier).
**Source:** https://kotlinlang.org/docs/coding-conventions.html

### S-CLEAN-03 — Public API: explicit visibility + explicit return type
**Severity:** P2
**Pattern:** public `fun foo() = bar.baz()` in commonMain — implicit return type on a public declaration.
**Why:** *"Always explicitly specify member visibility. Always explicitly specify function return types and property types (to avoid accidentally changing the return type when the implementation changes)."* Shared modules are libraries from consumers' perspective.
**Suggestion:** `public fun foo(): ReturnType = ...` or restrict with `internal`/`private` if not API.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Library API recommendations)

### S-CLEAN-04 — Throwing exceptions for routine error paths in shared code
**Severity:** P1
**Pattern:** `throw IllegalArgumentException(...)` or similar used to signal an expected error path (not an invariant violation).
**Why:** Exceptions in shared code propagate through the iOS bridge (see S-CORO-03), creating asymmetric error handling. For routine errors, a sealed result type is safer and more iOS-friendly.
**Suggestion:** `sealed interface ApiResult<out T> { data class Success<T>(val value: T) : ApiResult<T>; data class Failure(val error: ApiError) : ApiResult<Nothing> }`.
**Source:** https://kotlinlang.org/docs/exceptions.html + interop concerns in https://kotlinlang.org/docs/native-objc-interop.html

### S-CLEAN-05 — Mutable shared state without a concurrency model
**Severity:** P1
**Pattern:** `var` on shared singletons accessed from coroutines without `Mutex`, `atomicfu`, or `StateFlow`.
**Why:** New memory manager allows mutable shared state but races still happen. Manifests differently on iOS vs Android, both bugs.
**Suggestion:** `MutableStateFlow` for observable state, `Mutex.withLock { }` for compound updates, `atomicfu` for single-value atomics.
**Source:** https://kotlinlang.org/docs/native-memory-manager.html and https://github.com/Kotlin/kotlinx-atomicfu

---

## When the rule isn't here

If you see something suspicious not covered:

1. Context7 → query the relevant library
2. Web search filtered to tier-1 sources in `references/canonical-sources.md`
3. No authoritative source → drop the finding. Note in the report appendix.

Never fabricate rules. Never defer with "unsure".
