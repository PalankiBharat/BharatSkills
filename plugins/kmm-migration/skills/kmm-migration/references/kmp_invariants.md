# KMP Structural Invariants

> The narrow set of Kotlin Multiplatform rules that are STRUCTURAL — they
> describe the shape of KMP itself rather than the current state of any
> library, target, or API. These are stable enough across Kotlin 1.5+ to
> pre-load.
>
> Anything version-bound — current target tier list, deprecated targets,
> stable/Beta/Experimental status of specific APIs, current Compose
> Multiplatform version cutoffs, current Gradle plugin ids, current default
> hierarchy template behaviour, current Lifecycle / Navigation Maven group
> names, specific FROM → TO library swaps — is NOT in this file. The
> researcher fetches it live each invocation per Law 13 + Law 15.
>
> Canonical source for every claim below: kotlinlang.org docs tree (entry
> points in `references/knowledge_lookup_protocol.md`). If the docs ever
> contradict this file, the docs win (Law 15) — open a finding and update.

`applies_to: [migrator, planner, ios_porter, baseline_author]`
`concerns: [structure, expect-actual, common-main]`

## Contents

- [Source-set placement is disk-determined](#source-set-placement-is-disk-determined)
- [The default hierarchy template is the canonical pattern](#the-default-hierarchy-template-is-the-canonical-pattern)
- [expect / actual signature contract](#expect--actual-signature-contract)
- [The four ways to cross the platform boundary](#the-four-ways-to-cross-the-platform-boundary)
- [Visibility across source sets in the same module](#visibility-across-source-sets-in-the-same-module)
- [Things that are NEVER true in commonMain](#things-that-are-never-true-in-commonmain)
- [Everything else is version-bound](#everything-else-is-version-bound)

## Source-set placement is disk-determined

A file's source set is determined by where the file lives on disk, not by
an annotation on the code. Moving a file from `androidMain/` to
`commonMain/` without first removing its platform imports is a guaranteed
compile failure.

`commonMain/` compiles for every target the module declares. Platform
source sets (`androidMain/`, `iosMain/`, etc.) only compile for their
platform. `commonMain/` cannot import from a platform source set;
platform source sets CAN import from `commonMain/` (the relation is
one-way, downstream → upstream).

Test source sets mirror the same shape: `commonTest`, plus per-platform
test source sets. The exact platform-test source-set names (especially
the Android test split between local-JVM and instrumented) are
version-bound — researcher confirms current naming per invocation.

## The default hierarchy template is the canonical pattern

Kotlin Multiplatform ships a default hierarchy template that creates
intermediate source sets (e.g., one shared `iosMain` between `commonMain`
and the per-arch `iosArm64Main` / `iosSimulatorArm64Main` leaves). The
template is invoked via a single Gradle DSL call (current API:
`applyDefaultHierarchyTemplate()` — verify per invocation; the API has
moved before).

Hand-rolling `dependsOn(...)` chains between source sets disables the
template and emits a warning. Don't do it. If the project pre-dates the
template and uses manual `dependsOn`, the canonical move is to migrate to
the template, not preserve the manual chain.

## expect / actual signature contract

When `expect`/`actual` is the chosen pattern (see [The four ways](#the-four-ways-to-cross-the-platform-boundary)
below for when it is), the contract is:

- `expect` declarations live in `commonMain`. `actual` declarations live
  in a platform source set OR in an intermediate source set (e.g., a
  single actual in `iosMain` covers all `ios*` arch leaves).
- Every target the module compiles for MUST have a reachable `actual`.
  One missing actual fails the build for that target.
- `expect` and `actual` MUST share: fully-qualified name (same package),
  parameter list (names AND types), return type, nullability, generics,
  visibility.
- Default parameter values are declared on the `expect` ONLY — `actual`
  does NOT repeat them.
- Suspend / inline / operator modifiers can all be `expect`/`actual`.
- A `when` expression over an `expect enum` requires an `else` branch
  because actuals on different platforms may add constants the common
  code doesn't see.

The stability tier of `expect class` (vs `expect fun`/`expect val` which
are stable) and any compiler opt-in flag required to use it ARE
version-bound — researcher confirms current status per invocation.

## The four ways to cross the platform boundary

Source: kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html

When shared code needs platform behaviour, JetBrains' canonical priority
(walked top-down, take the first that resolves the case):

1. Use a multiplatform library that already abstracts it.
2. `expect`/`actual` function or property — for simple, narrow cases.
3. Interface in `commonMain` + platform implementations — for complex /
   stateful / lifecycle-bound cases.
4. DI framework — preferred when the project already uses one. JetBrains
   verbatim: "we recommend continuing to use DI if you already have it
   in your project, rather than using the expected and actual functions
   manually."

Do NOT mix `expect`/`actual` with DI for the same dependency.

This priority order is the structural rule. The specific multiplatform
library or DI framework named for any given concern is version-bound and
researcher-resolved.

## Visibility across source sets in the same module

In Kotlin, `internal` is module-scoped. In KMP, `commonMain`,
`androidMain`, and `iosMain` of the same Gradle source-set hierarchy
compile into the SAME module from a visibility standpoint.

Consequence: an `internal` declaration in `commonMain` remains `internal`
across all platform source sets of the same module — it does NOT need
to be widened to `public` when extracted from `androidMain` to
`commonMain`. Reflexively widening on extraction is a frequent
over-correction and a Law 1 violation (surgical changes only).

Sealed-class constructors default to `protected`; they cross source-set
boundaries within the same module without modification.

## Things that are NEVER true in commonMain

Regardless of Kotlin / KMP version, these are forbidden in `commonMain`:

- Java code. `commonMain` is Kotlin-only.
- Imports from `android.*`, `androidx.*` (with one carve-out: certain
  JetBrains-aliased Compose / Lifecycle / Navigation libraries USE the
  `androidx.*` import path even in commonMain. Whether a specific
  `androidx.*` namespace is multiplatform-aliased is version-bound —
  researcher confirms per invocation. The default assumption is "no" —
  treat any `androidx.*` import as suspicious and verify.)
- Imports from `platform.UIKit.*`, `platform.Foundation.*`,
  `platform.darwin.*` (these are iOS-target-only; `commonMain` cannot
  see them).
- Imports from JVM-only packages (`java.*` other than what's been
  multiplatform-aliased into Kotlin stdlib). The exact list of allowed
  vs disallowed `java.*` is version-bound — `references/jvm_api_scrub_list.md`
  encodes the categories the migrator scans for; the researcher resolves
  the current canonical replacement for each hit.
- Reflection that depends on the JVM reflection model (`java.lang.reflect`,
  `Class<T>`-as-Java-type, ServiceLoader). Kotlin's own reflection
  (`kotlin.reflect.KClass`) is multiplatform but limited on Kotlin/Native.

## Everything else is version-bound

Items NOT in this file because they shift between Kotlin / KMP releases
and a pinned value would go stale silently:

- Current Kotlin / KMP Gradle plugin id and apply syntax.
- Current iOS target tier list and which targets are deprecated /
  removed in the user's Kotlin version.
- Current default hierarchy template behaviour (auto-applied vs requires
  explicit invocation; intermediate source-set names).
- Current Compose Multiplatform version + breaking changes per minor
  release.
- Current Lifecycle / ViewModel / Navigation Maven coordinates and
  whether they live under `androidx.*` or `org.jetbrains.androidx.*`.
- Current Compose preview annotation package.
- Current resource handling rules (directory name, generated class name,
  what does and does not have a multiplatform equivalent).
- Stable / Beta / Experimental status of: `expect class`, K2 features,
  Swift export, SPM import, Kotlin/Native memory manager, freezing
  APIs.
- Current named replacement for any FROM JVM construct (`StringBuilder`,
  `Pattern`, `java.io.File`, `java.time.*`, `RxJava`, etc.).
- AGP version compatibility constraints, plugin id renames (AGP 9
  introduced `com.android.kotlin.multiplatform.library`; the researcher
  confirms whether the user's repo is affected).
- iOS integration mechanism stability tiers (Direct / CocoaPods / SPM /
  Swift export).

For all of these, the researcher fetches the current canonical answer
from kotlinlang.org per invocation and writes it into
`kmm_migration/findings.md`. Subsequent migrations on the same project
inherit the `findings.md` table.
