# Live Knowledge Protocol

> Codifies Law 6. Every KMM-related claim a reviewer or triager makes is
> sourced live at invocation time. KMP evolves faster than training data;
> "I remember" is never a citation.

## Contents

- [The iron rule](#the-iron-rule)
- [Priority order](#priority-order)
- [What counts as a "claim"](#what-counts-as-a-claim)
- [How to cite a source in a finding](#how-to-cite-a-source-in-a-finding)
- [Rationalization table](#rationalization-table)

## The iron rule

**NO KMM-RELATED CLAIM WITHOUT A LIVE CITATION.**

If a reviewer asserts "this is the standard pattern for X in KMP" or "library Y does Z", the assertion must include a citation from a live source consulted in this dispatch. Training-data assertions are forbidden unless explicitly flagged `⚠ TRAINING DATA — VERIFY` and used only when live sources actively failed.

## Priority order

When a reviewer needs to verify a KMP fact, sources are consulted in this order:

| Priority | Source | Tool | When to use |
|---|---|---|---|
| 1 | context7 docs | `mcp__context7__resolve-library-id` then `mcp__context7__query-docs` | First. Always. For any library, framework, or platform-API claim. |
| 2a | `find-docs` skill | the `find-docs` skill (auto-invoked or via Skill tool) | When context7 returned nothing or returned an unrelated library. The skill is purpose-built to retrieve authoritative, current documentation. |
| 2b | Web search | `WebSearch` | Broader exploratory search — official blogs, KEEP proposals, GitHub issues, release notes. |
| 2c | Specific URL fetch | `WebFetch` | When the reviewer already knows the exact authoritative URL (e.g. JetBrains kotlinx-coroutines docs page) and wants to read it verbatim. |
| 3 | Training data, flagged `⚠ TRAINING DATA — VERIFY` | n/a | Only if 1 and 2 returned nothing. The reviewer reports the assumption explicitly and notes that the user should verify. |

Skipping a priority level is a Law 6 violation. "I checked context7 and it didn't have it" is a valid step only if the reviewer also tried `find-docs` and `WebSearch` — all three are part of priority 1+2.

## Common KMM lookups during a review

These are the fact-shapes a reviewer typically needs to verify mid-review. The lookup tool is suggested, but the reviewer always starts at context7.

| Lookup | Suggested query |
|---|---|
| Is library `X` available in `commonMain` for KMP target `Y`? | `mcp__context7__resolve-library-id` with `X`, then `query-docs` for "supported platforms" or "kmp targets". |
| What's the current recommended pattern for `expect class` with constructor params? | context7 → `kotlin-multiplatform-mobile` → query-docs for "expect class constructor". Fallback: `WebSearch "kotlin multiplatform expect class constructor 2026"`. |
| Is `Dispatchers.IO` available in `commonMain` as of kotlinx-coroutines `<version>`? | context7 → `kotlinx.coroutines` → query-docs for "Dispatchers.IO commonMain". Fallback: `find-docs` with "kotlinx-coroutines Dispatchers.IO commonMain availability". |
| What's the current Roborazzi tolerance default? | context7 → `roborazzi` → query-docs for "tolerance". |
| Does Ktor support `wasmJs` target as of 3.x? | context7 → `ktor` → query-docs for "wasmJs target". |
| Is the migration's choice of DI framework still community-recommended? | `WebSearch "kotlin multiplatform DI 2026 site:kotlinlang.org OR site:github.com"`. Cross-check what the repo actually uses. |
| What's the right way to expose `sealed class` to Swift today? | context7 → `kotlin-multiplatform-mobile` → "swift interop sealed class". Fallback: `find-docs "kotlin native swift interop sealed class wrapper"`. |

If the reviewer cannot find authoritative coverage for the fact at hand after exhausting priorities 1 and 2, the finding either:

- Drops the claim entirely (the gap can be described without the claim), OR
- Emits the claim with the explicit `⚠ TRAINING DATA — VERIFY` flag and surfaces this as a Law-06 caveat in the finding body.

## What counts as a "claim"

A claim is any statement the reviewer makes that depends on knowledge of a library, framework, KMP target behaviour, or interop pattern. Examples:

- "The standard KMP HTTP library is Ktor" → claim. Cite or do not assert.
- "`expect class` declarations cannot have constructors" → claim. Cite.
- "Coroutines `Dispatchers.IO` is available in `commonMain`" → claim. Cite.
- "Roborazzi tolerance default is 0.01f" → claim. Cite.
- "This DI framework supports `commonMain`" → claim. Cite.
- "The migration should use `expect/actual` here" — implicit claim about which pattern is correct. Cite the parity_verification_protocol guidance OR a context7 result.

Statements about the *diff itself* are not claims that need live citations:

- "Master defines `LoginViewModel.login(): Result<User>`" — observable fact, just cite the master `path:line`.
- "The port omits the analytics call" — observable fact, cite both versions.

## How to cite a source in a finding

When a finding's evidence rests on a live-knowledge source, the description includes a one-line citation:

```markdown
- **Description:** The port uses `kotlinx-coroutines.flow.Flow` in `commonMain` to expose state to iOS. Per [Kotlin/KMP coroutines guide v1.7.x via context7](https://kotlinlang.org/docs/coroutines-overview.html — fetched 2026-04-29), `Flow` is not directly Swift-friendly without an explicit `kotlinx-coroutines-swift` bridge. The port omits the bridge.
```

The citation includes:

- A human-readable name for the source.
- The URL or context7 library ID.
- The fetch date in ISO format (so a future reader can tell if the citation might have aged out).

## Rationalization table

| Thought | Reality |
|---|---|
| "I know `expect class` works that way" | You remembered. Verify via context7 — the language has evolved. |
| "Everyone uses Ktor for KMP networking" | Sourceless. Check context7 + the repo's actual choice. |
| "The `commonTest` source set always includes `kotlin.test`" | Sourceless. Check context7 — Kotlin Multiplatform plugin defaults change. |
| "I'll just look it up later if anyone challenges the finding" | Later is not now. Cite at the time the finding is emitted. |
| "context7 returned nothing useful, so I'll just go with what I remember" | Drop to priority 2 (WebSearch). Only fall to training data after both higher priorities fail, and flag the assertion. |
