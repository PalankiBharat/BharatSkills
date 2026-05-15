# New-file clean code

Loaded for any `change_type=NEW` file (any surface). Where Kotlin canonical docs cover a topic, cite them. Where they don't, **the team's master code is the authority** — verify a rule fires by comparing against the team's existing patterns. If master consistently violates a rule (e.g., master functions average 50 lines), the team convention overrides; demote or drop the finding.

Cite as `references/rules/new-file-clean-code.md#<rule-id>`.

---

### NF-CLEAN-01 — Cyclomatic complexity / nesting depth
**Severity:** P1
**Pattern:** functions in the new file with >3 nested levels of `if`/`when`/`for`/`try`, OR cyclomatic complexity > 10 (each `if`/`when` arm / `&&` / `||` / `catch` adds 1).
**Why:** Deep nesting and high complexity make functions hard to reason about. Especially relevant for shared code, where both Android and iOS pay the cognitive cost.
**Suggestion:** Extract sub-functions. Convert nested `if` chains to `when` with guard conditions or early returns.
**Source:** Industry standard; verify against master first — if master code consistently nests deeper, demote.

### NF-CLEAN-02 — Duplication against master (DRY)
**Severity:** P0 (clear duplicate) | P1 (substantial overlap)
**Pattern:** new file's function/class body matches an existing master file (same package or same role) by ≥70% line-similarity, or reimplements logic clearly visible in master.
**Why:** Duplicate logic diverges over time and creates two sources of truth. Master is the team's accepted authority.
**Suggestion:** Reuse the existing implementation. If the existing one needs adjustment to fit, refactor it to take a parameter or split into composable functions.
**Source:** Industry standard; master is authoritative.

### NF-CLEAN-03 — Single Responsibility / file size
**Severity:** P1
**Pattern:** new file >300 lines, or new class with >7 public methods/properties without a clear cohesion story.
**Why:** Kotlin canonical: *"file size remains reasonable (no more than a few hundred lines)."* High public-method counts on a single class signal mixed responsibilities.
**Suggestion:** Split by responsibility — separate file per cohesive concern.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Source file organization)

### NF-CLEAN-04 — YAGNI (no speculative abstraction)
**Severity:** P1
**Pattern:** new `interface` with a single `Impl` class, no test fake declared, no platform-specific implementations, and no documented future use.
**Why:** Speculative abstractions cost cognitive load without paying for themselves. Kotlin allows postponing — a class can become an interface later via straightforward refactoring.
**Suggestion:** Use the concrete class. Introduce the interface when a second implementation actually appears.
**Source:** Industry standard.

### NF-CLEAN-05 — Naming
**Severity:** P0 (`Util`/`Helper`/`Manager`/`Wrapper` with no meaningful intent) | P2 (other naming weaknesses)
**Pattern:** new class with a generic suffix (`*Util`, `*Helper`, `*Manager`, `*Wrapper`, `*Handler`, `*Service` when it's not really a service) without justification from team conventions. Or: function name that doesn't read as a verb phrase.
**Why:** Canonical: *"avoid meaningless words like 'Util' for naming files."* These names usually signal displaced responsibility.
**Suggestion:** Rename around the domain concept the class actually represents. For pure utility, prefer top-level / extension functions in a domain-named file.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Source file names and Naming rules)

### NF-CLEAN-06 — File name matches primary class
**Severity:** P2
**Pattern:** new `.kt` file with a single top-level class whose name doesn't match the file name; or file with multiple unrelated declarations and a generic name like `Utils.kt`.
**Why:** Canonical: *"If a Kotlin file contains only one class, it must be named like the class. If the file contains several classes or has only top level declarations, choose a name that describes what the file contains."*
**Suggestion:** Rename file to match the primary class, or rename file to describe what it contains.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Source file names)

### NF-CLEAN-07 — Function length
**Severity:** P1
**Pattern:** new function body >30 lines (excluding signature, braces, blank lines).
**Why:** Long functions resist understanding. Verify against master — if master averages comparable lengths, demote to P3 or drop.
**Suggestion:** Extract logical blocks into named helper functions. Each extracted function should have a verb-phrase name that describes what it does.
**Source:** Industry standard; master is authoritative.

### NF-CLEAN-08 — Parameter count
**Severity:** P1
**Pattern:** new function with >5 parameters.
**Why:** Many parameters are hard to remember; iOS consumers especially suffer because Swift requires explicit argument labels and default arguments don't survive the bridge by default.
**Suggestion:** Group related parameters into a data class. Distinguish required vs optional via DI or sensible defaults.
**Source:** Industry standard; intersects with `ios-readiness.md#i-skie-08`.

### NF-CLEAN-09 — Boolean flag parameter
**Severity:** P2
**Pattern:** new function with a `Boolean` parameter named like a switch (`isStrict`, `skipCache`, `useNewMode`).
**Why:** Boolean flags often signal "this function does two things". Call sites read as `f(true, false)` with no context.
**Suggestion:** Split into two functions with descriptive names, OR replace the flag with a sealed type / enum that documents the modes.
**Source:** Industry standard; corroborate with master.

### NF-CLEAN-10 — Magic numbers / strings in business logic
**Severity:** P2
**Pattern:** numeric literals (not in {0, 1, -1, 2}) or string literals appearing inline in business logic without a named constant.
**Why:** Magic literals hide intent and resist search.
**Suggestion:** Extract to `private const val` (or `companion object` for class-scoped) with a name that describes the meaning, not the value.
**Source:** Industry standard.

### NF-CLEAN-11 — Premature optimization without rationale
**Severity:** P3
**Pattern:** new code uses micro-optimizations (manual unrolling, `@JvmField` for non-JVM, low-level bit tricks) without a comment explaining why.
**Why:** Without measurement, optimization adds complexity for unclear benefit.
**Suggestion:** Remove the optimization, or add a comment with the measurement justifying it.
**Source:** Industry standard.

### NF-CLEAN-12 — Explicit visibility + types
**Severity:** P2
**See:** `references/rules/_base.md#s-clean-03` — the rule and rationale are identical. This entry exists to remind the master-grounded specialist to apply it on NEW files (where it has the most leverage). If both fire on the same declaration, keep this one (`NF-CLEAN-12`) and drop `S-CLEAN-03`; the aggregator's derivative collapse handles this automatically via the NC-* / cross-reference rule in `references/derivative-map.md`.
