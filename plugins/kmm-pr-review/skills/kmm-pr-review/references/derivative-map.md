# Derivative finding map

When a "root" rule fires, certain other findings are downstream effects of the same problem. Shipping them all as peer findings drowns the report and gives the false impression of multiple independent issues. The aggregator collapses derivatives under their parent.

The aggregator applies these rules **after** dedupe and **before** report rendering. A derivative finding is not deleted; it's *attached* to its parent in the parent's report block as "derivative effects observed."

## Maps

### I-SKIE-01 (SKIE Gradle plugin not applied)
**Derivatives suppressed (when parent fires):**
- I-SKIE-03 — manual Flow.collect wrappers in iOS (these are the *only* way to consume Flow without the plugin)
- I-SKIE-04 — nullable Flow type confusion (the SkieSwift*Flow types don't exist without the plugin)
- I-SKIE-09 — runtime casts on `SkieKotlin___Flow` (those types only exist with the plugin)
- B-03 — build.gradle.kts missing `id("co.touchlab.skie")` (this IS the parent, just located in the build file)

**Rationale:** Fix the parent and these become impossible. Listing them as peer P0/P1 findings is noise.

**Report style:** Show I-SKIE-01 with a sub-section "Derivative effects (will resolve once parent is fixed): N findings across these files…" — list briefly.

### M-CLEANUP-01 (old Android-only file not deleted post-migration)
**Derivatives suppressed:**
- Any finding emitted against the new commonMain file that's also flagged against the old Android file with `attribution: pre-existing`. The duplicate findings come from the file living in two places.
- Hilt-related findings on the old file (M-CLEANUP-02 etc.) — they'll vanish when the file is deleted.

**Rationale:** The old file shouldn't be reviewed at all once the migration completes. Findings against it are documentation, not action items.

**Report style:** Show M-CLEANUP-01 with "N findings against the old Android-only file will resolve when it is deleted."

### M-PARITY-01 (migrated class has no iOS consumer call site)
**Derivatives suppressed:**
- Any I-READY-* / I-SKIE-* finding on the new shared file that would only matter at the iOS consumption point. When no iOS consumer exists, these are theoretical until iOS adoption.

**Rationale:** iOS readiness rules apply to iOS-exposed surfaces. If iOS isn't consuming yet, the readiness findings are still valid but the urgency drops.

**Report style:** Show M-PARITY-01 with "N iOS-readiness findings on the migrated file are not blocking until the iOS consumer is wired."

### S-CORO-05 (legacy freeze/Worker patterns)
**Derivatives suppressed:**
- Any `kotlinx.atomicfu` recommendation on the same lines — already covered by the parent suggestion.

### NC-05 / NC-11 (canonical pointers)
The rule bodies of NC-05 and NC-11 explicitly mark themselves as duplicates of S-TYPE-01 and I-READY-02 respectively. If both fire on the same line, keep the more specific NC-* one (it adds the "new file" context) and drop the base rule for that line.

## Format the aggregator uses

When emitting a parent with derivatives:

```
**[<path>:<line>]** <parent rule summary>

**Why:** <why>

**Suggestion:** <suggestion>

**Source:** <source>

**Attribution:** <attribution> (specialists: <…>; confidence: <…>)

**Derivative effects:** Fixing this resolves N other findings:
- [<other_path>:<line>] I-SKIE-03 — manual Flow.collect wrapper
- [<other_path>:<line>] I-SKIE-04 — SkieSwiftFlow type confusion
- …
```

Suppressed derivatives are removed from their normal severity buckets. The "Derivative effects" sub-list appears under the parent.

## When NOT to collapse

- If the derivative finding has `attribution: pre-existing` and the parent has `attribution: pr-induced` (or vice versa) — keep both, the user should know the master had the symptom independently.
- If the derivative finding cites a different file from the parent's expected scope (e.g., I-SKIE-09 in a file that doesn't import the parent's module) — keep both.
- If the parent fires with `confidence: low` — don't suppress; the parent might be wrong.
