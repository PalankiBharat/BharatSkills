# iOS readiness rules

Loaded for any commonMain or `*Main` source set change under `:shared`. **On migration PRs, any finding with `iOS_blocking: true` is auto-promoted to P0** — migration's purpose is iOS consumption; "we'll fix iOS later" defeats the migration.

Cite as `references/rules/ios-readiness.md#<rule-id>`.

---

## I-READY — Swift/ObjC consumption hazards

### I-READY-01 — Inline/value classes in public iOS-exposed API
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** `kotlin.Result<T>`, any user `value class` / `inline class`, or `Duration` (some Kotlin versions) in public API of a class/file exported via the iOS framework.
**Why:** Inline classes are unsupported in interop — they erase to the underlying type. `Result<List<User>>` → Swift sees `Any?`. The async completion handler's separate `Error?` parameter doubles the confusion.
**Suggestion:** Regular sealed class with `Success(value: T)` and `Failure(error: ApiError)` variants. Keep `Result` internal.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (mappings: "Inline classes — Unsupported")

### I-READY-02 — Generic interfaces / generic functions in iOS-exposed API
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** public `interface Foo<T>` or top-level `fun <T> bar(...)` exported to iOS.
**Why:** Obj-C generics work on classes and collections only. Generic interfaces and generic functions lose type parameters at the bridge — Swift sees `AnyObject` with forced casting everywhere.
**Suggestion:** Expose a generic *class*, or specialize for the concrete type iOS needs. For Flow specifically, SKIE preserves generics; check I-SKIE-03.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### I-READY-03 — Prefer generic *classes* over generic interfaces for iOS-consumed types
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** a generic interface where a generic class would serve.
**Why:** Class generics survive the Obj-C bridge; interface generics don't.
**Suggestion:** If the type needs iOS consumption and abstraction isn't strictly required, use a class. If abstraction is needed, expose a concrete generic class wrapper.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### I-READY-04 — Public iOS-exposed `suspend` missing `@Throws`
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** public `suspend fun` in iOS surface that can throw, without `@Throws(...)` annotation.
**Why:** Per canonical: only `@Throws`-declared exceptions propagate to the Swift completion handler's `Error?` parameter. Others cause program termination.
**Suggestion:** `@Throws(Throwable::class)` or narrower.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Errors and exceptions)

### I-READY-05 — Complex enums (generics, behavior) in iOS-exposed surface
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** `enum class` exposed to iOS that carries generic parameters, complex constructor logic, or methods with platform-specific implementations.
**Why:** SKIE bridges plain enums to real Swift enums transparently. Complex enums confuse the bridge and may need workarounds.
**Suggestion:** Keep iOS-exposed enums simple (name + plain values). Move complex behavior to extension functions or a separate non-exposed class.
**Source:** https://skie.touchlab.co/features/sealed-classes and https://kotlinlang.org/docs/native-objc-interop.html (Enums)

### I-READY-06 — Sealed hierarchies designed for SKIE bridging
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** new `sealed class` or `sealed interface` in iOS-exposed surface that uses generic type parameters in the sealed root, or has children that aren't simple data classes/objects.
**Why:** SKIE generates parallel Swift enums for sealed types, enabling exhaustive switch. Complex sealed hierarchies (generic roots, classes as children) may bridge imperfectly.
**Suggestion:** Keep sealed children as `data class` or `object`. Avoid generic type parameters on the sealed root if iOS consumes it. If generics are required, validate the SKIE-generated Swift output before merging.
**Source:** https://skie.touchlab.co/features/sealed-classes

### I-READY-07 — Singleton access in iOS code uses `.shared` / `.companion`
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** iOS Swift code accesses Kotlin `object` or `companion object` via `MyObject()` constructor pattern.
**Why:** Per canonical: *"`MySingleton()` in Swift has been deprecated."* The current pattern is `MyObject.shared` and `MyClass.companion`.
**Suggestion:** `MyObject.shared.x`, `MyClass.companion.x`, or `MyClass.Companion.shared.x`.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Kotlin singletons)

### I-READY-08 — Top-level functions/properties in iOS-consumed surface
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** new top-level `fun` or `val`/`var` in commonMain consumed from iOS.
**Why:** Top-level Kotlin declarations become `<FileName>Kt.funcName()` in Swift. Ugly, leaks file name into API.
**Suggestion:** Place on a class with `companion object` if a logical owner exists, or annotate with `@ObjCName(swiftName = "...")` to control the bridged name.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Top-level functions and properties)

### I-READY-09 — Collection conversion cost on hot paths
**Severity:** P2 (P3 if not hot) | **iOS_blocking:** false
**Pattern:** public API exposes `Map`/`List`/`Set` to iOS in code identified as a hot path (called per frame, per scroll, per pixel, in tight loops).
**Why:** Kotlin collections cross Kotlin → Obj-C → Swift, getting copied at each step. Cheap occasionally, costly in hot loops.
**Suggestion:** In hot paths, expose `NSArray`/`NSDictionary`/`NSSet` directly to skip the Swift-side copy, or batch-emit fewer collections.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Collections)

### I-READY-10 — Mutable Kotlin collections exposed expecting iOS mutation
**Severity:** P1 | **iOS_blocking:** true
**Pattern:** public API returns `MutableList`/`MutableMap`/`MutableSet` to iOS with the expectation iOS will mutate.
**Why:** `NSMutableSet` and `NSMutableDictionary` aren't auto-converted *from* Swift to Kotlin Mutable*. Mutations from Swift on the bridged type don't propagate back. Also, `NSMutableString` is copied when passed to Kotlin.
**Suggestion:** If iOS needs to mutate, define an explicit mutation API on the Kotlin side. Don't return mutable collections across the bridge.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Collections)

### I-READY-11 — Internal-only API exported in the iOS framework
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** public Kotlin declarations that are internal-only to the shared module but exported to iOS, bloating the framework surface.
**Why:** Lean iOS framework surface reduces autocomplete noise and prevents iOS from accidentally depending on internals.
**Suggestion:** `internal` modifier (module-private) for module-internals, or `@HiddenFromObjC` if the declaration must stay visible to other Kotlin modules but not to iOS.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Hide Kotlin declarations from Objective-C and Swift)

### I-READY-12 — Awkward auto-translated names in iOS surface
**Severity:** P3 | **iOS_blocking:** false
**Pattern:** Kotlin names that translate to awkward Swift/Obj-C names (verb-suffix collisions, framework-prefixed types in shared API).
**Why:** Auto-translation can produce names that grate against Swift conventions, hurting iOS DX.
**Suggestion:** `@ObjCName(swiftName = "BetterName")` on the declaration, parameters, etc.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Change declaration names)

### I-READY-13 — Missing KDoc on iOS-exposed public API
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** public Kotlin declaration in iOS surface with no KDoc comment.
**Why:** When `-Xexport-kdoc` is enabled, KDoc translates to Obj-C documentation comments that show up in Xcode autocompletion. Without it, iOS developers see undocumented symbols.
**Suggestion:** Add a KDoc block. Verify `-Xexport-kdoc` is enabled on the framework binary.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Provide documentation with KDoc comments)

### I-READY-14 — Function-type parameters box primitives in iOS hot paths
**Severity:** P2 (P3 if not hot) | **iOS_blocking:** false
**Pattern:** public API takes a lambda with primitive parameter types (e.g., `(Int) -> Unit`) called per frame / per item in a tight loop.
**Why:** *"In the case of function types, primitive types are mapped to their boxed representation."* Boxing per-call cost adds up in hot paths.
**Suggestion:** Batch the work, or expose a non-functional API that consumes the items directly.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Function types)

### I-READY-15 — Use of newer platform-class APIs in shared without availability checks
**Severity:** P1 | **iOS_blocking:** true
**Pattern:** shared code (in `iosMain` actuals especially) references a platform class (UIKit/Foundation) that exists only on iOS ≥ X without availability handling.
**Why:** *"Whenever you use an Objective-C class in the Kotlin source, it's marked as a strongly linked symbol. The crash happens even if symbols were never used. Symbols might be unavailable on a particular device or OS version."*
**Suggestion:** Wrap such usage in a Swift/Obj-C helper that performs `@available` / `respondsToSelector:` checks; expose to Kotlin via expect/actual.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Strong linking)

---

## I-SKIE — correct SKIE structure

### I-SKIE-01 — SKIE Gradle plugin applied in the shared module
**Severity:** P0 (if iOS consumes coroutines/Flow/sealed) | P1 otherwise | **iOS_blocking:** true
**Pattern:** `shared/build.gradle.kts` lacks `id("co.touchlab.skie")` in the `plugins { }` block, but the shared module exposes Flow, suspend, or sealed types to iOS.
**Why:** SKIE is a compiler plugin. Without `id("co.touchlab.skie")` applied, none of SKIE's features fire — no Flow→AsyncSequence, no sealed→enum, no real `async`/`await` for suspend. The iOS surface silently degrades.
**Suggestion:** Apply the plugin: `plugins { id("co.touchlab.skie") version "<version>" }`.
**Source:** https://skie.touchlab.co/intro

### I-SKIE-02 — SKIE version compatible with project's Kotlin version
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** SKIE version in `build.gradle.kts` outside the supported range for the project's Kotlin version.
**Why:** SKIE supports a sliding window of Kotlin versions (typically last two feature releases plus their incremental releases). Mismatch causes install-time failure or feature silently disabled.
**Suggestion:** Research current SKIE↔Kotlin compatibility via Context7 (query `co.touchlab.skie`) or the SKIE intro page. Pin a version in the supported window.
**Source:** https://skie.touchlab.co/intro

### I-SKIE-03 — iOS code consumes Flow via SKIE's AsyncSequence, not manual collect wrappers
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** iOS Swift code uses a manual `KotlinxCoroutinesCoreFlow.collect(...)` wrapper for a Flow that SKIE would expose as `SkieSwiftFlow<T>` (project has SKIE configured per I-SKIE-01).
**Why:** SKIE generates `SkieSwiftFlow<T>` (implements `AsyncSequence`) preserving the type argument. The idiomatic Swift consumption is `for await x in flow` — manual collect wrappers reintroduce the problems SKIE solved (type erasure, no cancellation, callback-style).
**Suggestion:** `for await item in flow { ... }` inside a `Task` or `.task` modifier; cancellation flows from the Task.
**Source:** https://skie.touchlab.co/features/flows

### I-SKIE-04 — Nullable Flow types: `Flow<T?>` and `Flow<T>` are not interchangeable
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** iOS code treats `SkieSwiftFlow<T>` and `SkieSwiftOptionalFlow<T>` as the same type (or casts between them with `as`).
**Why:** Per canonical: *"`Flow<Int>` is mapped to `SkieSwiftFlow<Int>`, but `Flow<Int?>` is mapped to `SkieSwiftOptionalFlow<Int>`. These two types of classes do not inherit from each other."* Cross-casting with `as` is a runtime crash; SKIE replaces types at compile time, not runtime.
**Suggestion:** Use the conversion constructors (non-optional → optional). Match the Kotlin signature's nullability exactly on the Swift side.
**Source:** https://skie.touchlab.co/features/flows

### I-SKIE-05 — `@SealedInterop.Disabled` accidentally turned off for iOS-needed sealed types
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** a sealed class/interface annotated `@SealedInterop.Disabled` but consumed from iOS.
**Why:** SKIE's sealed support generates the wrapping Swift enum and `onEnum(of:)` function — the only path to exhaustive switching on sealed types from Swift. Disabling it for an iOS-needed type drops back to a default-required switch.
**Suggestion:** Remove the `@Disabled` annotation. If it was added intentionally, document why.
**Source:** https://skie.touchlab.co/configuration/sealed

### I-SKIE-06 — Sealed children export configuration
**Severity:** P1 | **iOS_blocking:** false
**Pattern:** sealed type with `@SealedInterop.EntireHierarchyExport.Disabled` whose children aren't otherwise module-exported.
**Why:** Default is `EntireHierarchyExport = true`, exporting all public sealed children to Obj-C even from non-exported modules. Disabling can leave Swift unable to access some children.
**Suggestion:** Leave the default unless there's a specific reason. Verify all children Swift needs are reachable.
**Source:** https://skie.touchlab.co/configuration/sealed

### I-SKIE-07 — SKIE annotations on Kotlin code without the annotations dependency
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** `@SealedInterop.*`, `@FlowInterop.*`, or other SKIE annotations imported in a source set without `co.touchlab.skie:configuration-annotations` declared as a dependency for that source set.
**Why:** Annotations import would fail to resolve — build error. If the build somehow succeeds with the annotation silently ignored, the configuration silently no-ops.
**Suggestion:** Add `implementation("co.touchlab.skie:configuration-annotations:<version>")` to the source set's dependencies.
**Source:** https://skie.touchlab.co/configuration/

### I-SKIE-08 — Reliance on SKIE default arguments without explicit enable
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** iOS Swift code calls Kotlin functions assuming defaults work (without passing all parameters) on a project where default arguments aren't explicitly enabled.
**Why:** Default arguments are disabled by default (deprecated implementation; has build-time and binary-size costs). Without enabling, Swift must pass every parameter.
**Suggestion:** Either enable explicitly (Gradle + dependency) and document the trade-off, or update Swift call sites to pass every parameter.
**Source:** https://skie.touchlab.co/features/default-arguments

### I-SKIE-09 — iOS uses `as?` / `as!` / `is` on `SkieKotlin___Flow` types
**Severity:** P0 | **iOS_blocking:** true
**Pattern:** Swift code using `as!`, `as?`, or `is` on the SKIE-bridged `SkieKotlinFlow`, `SkieKotlinStateFlow`, etc.
**Why:** Per canonical: *"SKIE replaces Flows only during compile time, not in runtime. Therefore, it's not possible to use `as!`, `as?` or `is` with `SkieKotlin___Flow` — it may result in unpredictable behavior or a runtime crash."* Exception: immediately after a conversion constructor.
**Suggestion:** Remove the cast. If type narrowing is genuinely needed, restructure to receive the right type from Kotlin.
**Source:** https://skie.touchlab.co/features/flows

### I-SKIE-10 — Mixing SKIE and KMP-NativeCoroutines for the same boundary
**Severity:** P2 | **iOS_blocking:** false
**Pattern:** project uses SKIE *and* also wraps the same Flow/suspend with KMP-NativeCoroutines on the iOS side.
**Why:** Double-wrapping creates two cancellation paths, two type bridgings, and inevitable confusion about which is canonical. SKIE alone covers the typical use case; mixing is rarely intentional and usually a leftover from migration.
**Suggestion:** Pick one. For new code, SKIE per project convention. Remove the redundant wrapper.
**Source:** https://skie.touchlab.co/ + https://github.com/rickclephas/KMP-NativeCoroutines
