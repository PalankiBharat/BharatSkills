# Model / Domain type rules

Loaded for files with `role=model`. Covers data classes, sealed hierarchies, enums, value objects.

Cite as `references/rules/model.md#<rule-id>`.

---

### MOD-01 — Domain models in commonMain, DTOs in data layer
**Severity:** P1
**Pattern:** a model class in `domain/` package mixes JSON-shaped fields with domain fields, or imports `kotlinx.serialization` directly.
**Why:** Domain models should be independent of wire format. Mixing leaks serialization concerns into business code.
**Suggestion:** Separate DTOs (`@Serializable data class UserDto`) in the data layer; map to domain types (`data class User`) at the repository boundary.
**Source:** Industry-standard Clean Architecture; team convention.

### MOD-02 — Sealed hierarchies use data class / object subclasses
**Severity:** P1
**Pattern:** sealed class/interface with non-data class children (regular `class X : Parent`).
**Why:** For iOS consumption via SKIE, data class and object subclasses bridge cleanly to Swift enums with associated values. Regular class subclasses bridge imperfectly.
**Suggestion:** `data class` for state-carrying subclasses, `object` for stateless variants.
**Source:** https://skie.touchlab.co/features/sealed-classes

### MOD-03 — Sealed root without generic type parameter (when iOS-consumed)
**Severity:** P1
**Pattern:** `sealed interface Result<T>` in iOS-exposed code.
**Why:** Generics on sealed root + iOS = bridging hazards. See `ios-readiness.md#i-ready-06`.
**Suggestion:** Specialize the sealed type (`sealed interface UserResult`, `sealed interface PostResult`), or accept the imperfect bridging and document.
**Source:** https://skie.touchlab.co/features/sealed-classes

### MOD-04 — No inline / value classes in public surface
**Severity:** P0
**Pattern:** `@JvmInline value class` or `inline class` in a public type exposed to iOS.
**Why:** Erases to underlying type on the bridge. See `ios-readiness.md#i-ready-01`.
**Suggestion:** Replace with `data class` if a wrapper is genuinely needed, or use the underlying primitive directly.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### MOD-05 — Plain Kotlin enums (no generics, no complex state) when iOS-consumed
**Severity:** P1
**Pattern:** complex enum (parameters, methods, generics) exposed to iOS.
**Why:** SKIE bridges plain enums to real Swift enums. Complex enums lose features or bridge awkwardly.
**Suggestion:** Keep iOS-exposed enums to `name + value` shape. Put behavior in extension functions.
**Source:** https://skie.touchlab.co/features/sealed-classes

### MOD-06 — Equality consistent (`equals`/`hashCode` matched)
**Severity:** P1
**Pattern:** model overrides `equals` but not `hashCode` (or vice versa), or `data class` with a manual `equals` override that ignores fields the constructor declares.
**Why:** Inconsistent equality breaks collections, sets, and is a recurring source of subtle bugs.
**Suggestion:** Use `data class` if equality matches all constructor parameters. Override both if behavior must diverge.
**Source:** https://kotlinlang.org/docs/data-classes.html
