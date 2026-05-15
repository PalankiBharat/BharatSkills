# New file in commonMain — necessity gate

Loaded for files with `change_type=NEW AND surface=SHARED_COMMON`. Runs as the master-grounded specialist's lens (necessity mode). Asks: *should this file exist, and is it KMP-canonical?*

The specialist has master-baselines loaded — it can scan for similar files, sibling files in the same package, files matching the same role suffix.

Cite as `references/rules/new-commonmain-file.md#<rule-id>`.

---

### NC-01 — Is the file really needed?
**Severity:** P1
**Pattern:** a new file whose primary class/function does work that an existing master file (same package, same role) already covers — wholly or in significant part.
**Why:** New files multiply maintenance surface. If existing code does ≥70% of the new code's job, the new code should extend the existing file or call it, not duplicate.
**Suggestion:** Identify the master file that overlaps. Choose: (a) add the new behavior to the existing file as functions/extensions; (b) refactor the existing file's logic into a shared helper and call from both; (c) document why a separate file is genuinely needed (different lifecycle, different dependency surface, different test isolation).
**Source:** Industry-standard DRY + https://kotlinlang.org/docs/coding-conventions.html (Source file organization) + master is authoritative.

### NC-02 — Is it KMM-canonical?
**Severity:** P1
**Pattern:** the new file's structure deviates from canonical KMP patterns. Examples: `expect class` for business logic instead of interface+Koin; bare class instead of using lifecycle ViewModel for screen-scoped state; hand-rolled Flow wrapper where SKIE would handle it.
**Why:** Canonical patterns are documented because they solve known problems (testability, iOS friendliness, lifecycle, refactor safety). Deviation needs justification.
**Suggestion:** Refactor toward the canonical pattern. Cite the specific JetBrains doc the new code diverges from.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html + https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html

### NC-03 — Could this be an extension function on an existing type?
**Severity:** P2
**Pattern:** a new class with a single small responsibility that operates primarily on one input type (the type is in master), with empty or trivial state.
**Why:** Canonical: *"Use extension functions liberally. Every time you have a function that works primarily on an object, consider making it an extension function accepting that object as a receiver."*
**Suggestion:** `fun ExistingType.newBehavior(): T = ...` in a top-level file, scoped via visibility modifier.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Extension functions)

### NC-04 — Public API minimal? Explicit visibility + types?
**Severity:** P2
**Pattern:** new public declarations without explicit visibility modifier, or public declarations whose return type is inferred (expression body without annotated type).
**Why:** *"Always explicitly specify member visibility. Always explicitly specify function return types and property types."* Shared modules are libraries from the consumer's view.
**Suggestion:** Add explicit `public`/`internal`/`private` and explicit return types. Default to `internal` when the symbol isn't part of intended shared API.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Library API recommendations)

### NC-05 — All imports KMP-compatible
**Severity:** P0
**Pattern:** new file imports `java.*`, `javax.*`, `android.*`, `kotlin.jvm.*`, or non-KMP `androidx.*`.
**Why:** Same as `_base.md#s-type-01` / `s-type-02` — commonMain compiles for iOS.
**Suggestion:** Replace with KMP equivalents (`kotlinx.datetime`, `okio`, `kotlinx.io`), or move to `androidMain`.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html + https://developer.android.com/kotlin/multiplatform

### NC-06 — commonTest counterpart exists
**Severity:** P1
**Pattern:** new file in commonMain whose behavior is non-trivial (branching, computation, side effects) but the PR doesn't add a corresponding test file in `commonTest`.
**Why:** Shared code runs on every platform; a regression multiplies across surfaces.
**Suggestion:** Add a test file with at minimum one test per public function and one per branch in branching logic.
**Source:** Team convention; https://kotlinlang.org/api/core/kotlin-test/

### NC-07 — Package fits existing structure
**Severity:** P1
**Pattern:** new file's package doesn't match conventions visible in master's adjacent files.
**Why:** Inconsistent packaging makes discovery harder and signals the author may not have understood the existing layer split.
**Suggestion:** Compare against sibling files in master. Move to the matching layer package.
**Source:** Master is authoritative; team convention.

### NC-08 — Naming follows team convention
**Severity:** P2
**Pattern:** new file's class/function/file name diverges from naming patterns in master's adjacent files.
**Why:** Inconsistent naming makes the codebase harder to navigate.
**Suggestion:** Inspect adjacent files. Match the team's suffix and verb conventions.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (naming) + master is authoritative.

### NC-09 — iOS consumer exists or PR documents why not
**Severity:** P1
**Pattern:** new file in commonMain whose only call sites (in this PR's diff) are Android consumer code; no iOS consumer change references the new symbol; PR description doesn't explain.
**Why:** A file moved to commonMain "for sharing" but consumed only by Android hasn't delivered the sharing value. Either iOS is using a parallel implementation (drift) or the iOS update is missing.
**Suggestion:** Add the iOS consumer change in this PR, or have the PR description explicitly link the follow-up issue/PR.
**Source:** Migration intent.

### NC-10 — Could the same outcome be achieved by editing an existing file?
**Severity:** P2
**Pattern:** the new file has ≤30 lines of substance and could plausibly live as additions to an existing file in the same package.
**Why:** Smaller new-file surface = less drift over time. Canonical: *"Placing multiple declarations (classes, functions, or top-level properties) in the same Kotlin source file is welcome if these declarations are closely related to each other semantically."*
**Suggestion:** Add the declarations to an existing related file.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Source file organization)

### NC-11 — Generic erasure check (overlaps `ios-readiness.md#i-ready-02` for emphasis on NEW files)
**Severity:** P0
**Pattern:** new file in commonMain exposes generic interfaces or generic functions to iOS.
**Why:** Generic interface/function loses type info at the Obj-C bridge. New code shouldn't introduce this hazard.
**Suggestion:** Use generic class, specialize, or use SKIE-bridged types (Flow).
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### NC-12 — Sealed hierarchies bridge cleanly via SKIE
**Severity:** P1
**Pattern:** new file introduces a `sealed class` or `sealed interface` that iOS will consume, with subclasses that are *classes* (not data classes/objects) or with a generic parameter on the sealed root.
**Why:** SKIE generates the parallel Swift enum + `onEnum(of:)` function — works smoothly for data class / object children with no generic root.
**Suggestion:** Make subclasses `data class` / `object`. Avoid generics on the sealed root if iOS consumes it.
**Source:** https://skie.touchlab.co/features/sealed-classes
