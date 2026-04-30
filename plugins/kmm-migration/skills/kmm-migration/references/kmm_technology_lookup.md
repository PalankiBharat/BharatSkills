# KMM Technology Lookup Protocol

> This reference ships ONLY the lookup protocol — no answers. Library names,
> version numbers, and pattern prescriptions are forbidden here. YOU MUST
> resolve every technology question live, per invocation, per Rule 13.

## Contents

- [When to use this file](#when-to-use-this-file)
- [Canonical first-stop — official KMP docs](#canonical-first-stop--official-kmp-docs)
- [Lookup protocol per concern](#lookup-protocol-per-concern)
- [Concerns covered](#concerns-covered)

## When to use this file

A subagent uses this file whenever it needs to make a technology choice —
library to adopt, version to pin, pattern to follow. The subagent NEVER
uses training-data knowledge. It follows the protocol below.

## Canonical first-stop — official KMP docs

For any KMP-foundational question (project structure, sourceSet hierarchy,
expect/actual idioms, Gradle plugin setup, Compose Multiplatform basics,
Kotlin/Native interop, target configuration, default vs explicit hierarchy
template), the official Kotlin Multiplatform documentation tree is the
canonical source of truth and the FIRST place to look — even before the
generic context7 step below. Reason: kotlinlang.org docs are JetBrains-owned,
versioned to current Kotlin/KMP, and resolve ambiguity that community sources
debate.

Entry points (the researcher fetches via context7 OR WebFetch, depending on
what the subagent has indexed):

- Get-started landing — https://kotlinlang.org/docs/multiplatform-get-started.html
- KMP overview — https://kotlinlang.org/docs/multiplatform.html
- Project structure & sourceSets — https://kotlinlang.org/docs/multiplatform-discover-project.html
- Hierarchical project structure / default template — https://kotlinlang.org/docs/multiplatform-hierarchy.html
- expect/actual declarations — https://kotlinlang.org/docs/multiplatform-expect-actual.html
- Targets & target configuration — https://kotlinlang.org/docs/multiplatform-dsl-reference.html
- Compose Multiplatform — https://www.jetbrains.com/lp/compose-multiplatform/

Citation format when the official docs are the source:

`(source: kotlinlang.org/docs/<page>, fetched <YYYY-MM-DD>)`

Falling through to context7 / WebSearch is the right move when:

- The question is library-specific (Ktor, SQLDelight, Koin, kotlinx.serialization,
  Compose Multiplatform internals beyond the landing page).
- The question is about a third-party library's KMP support status.
- The official docs page does not answer the specific question after one read.

Falling through to context7 is also fine when context7 already has
kotlinlang.org docs indexed — it can resolve faster than a raw WebFetch. But
the official URL stays the canonical citation regardless of which fetcher
delivered it.

## Lookup protocol per concern

For any `Need: <concern>`:

1. **Official KMP docs** (if the concern is KMP-foundational — see list above):
   - context7 with `libraryId` resolving to kotlinlang.org/Kotlin docs, query
     scoped to the multiplatform tree, OR
   - WebFetch directly against the entry-point URL nearest to the concern.
2. **context7 — third-party libraries**:
   - `mcp__context7__resolve-library-id(query="<descriptive query>")`
   - `mcp__context7__query-docs(libraryId=<resolved>, query="<specific question>")`
   - Try candidate library names the repo already uses first.
3. **WebSearch**:
   - Query: `"<concern> Kotlin Multiplatform <current-year>"`
   - Query: `"<concern> commonTest <current-year>"`
   - Prefer JetBrains blog, Kotlinlang Slack archives, kotlinlang.org docs.
4. **find-docs skill** if the candidate library has published docs.

Record in `kmm_migration/reports/<feature>/research_notes.md`:

- Question: <exact question asked>
- Answer: <decision>
- Source: <context7 library ID + query, or URL>
- Version: <if relevant>
- Alternatives considered: <brief>

## Concerns covered

The concerns the `researcher` must resolve live at Phase 2a include
(non-exhaustive — discover the full set from the feature inventory):

- KMP-compatible mocking in `commonTest`
- KMP-compatible screenshot testing (commonTest, androidTest, iosTest)
- KMP-compatible E2E testing (cross-platform flows)
- Networking (Android, iOS engines)
- Persistence (multiplatform DB)
- Serialization
- DI (which framework, which compiler plugin)
- Navigation (Compose Multiplatform)
- ViewModel / state holder sharing
- Platform-specific code pattern (interface + DI vs expect/actual)
- Swift interop for iOS (SwiftUI consumers)
- Packaging for iOS distribution

For each concern, the `researcher` follows the protocol above and records
findings. No concern is answered from training data.
