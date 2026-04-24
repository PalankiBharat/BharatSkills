# KMM Technology Lookup Protocol

> This reference ships ONLY the lookup protocol — no answers. Library names,
> version numbers, and pattern prescriptions are forbidden here. YOU MUST
> resolve every technology question live, per invocation, per Rule 13.

## Contents

- [When to use this file](#when-to-use-this-file)
- [Lookup protocol per concern](#lookup-protocol-per-concern)
- [Concerns covered](#concerns-covered)

## When to use this file

A subagent uses this file whenever it needs to make a technology choice —
library to adopt, version to pin, pattern to follow. The subagent NEVER
uses training-data knowledge. It follows the protocol below.

## Lookup protocol per concern

For any `Need: <concern>`:

1. context7:
   - `mcp__context7__resolve-library-id(query="<descriptive query>")`
   - `mcp__context7__query-docs(libraryId=<resolved>, query="<specific question>")`
   - Try candidate library names the repo already uses first.
2. WebSearch:
   - Query: `"<concern> Kotlin Multiplatform <current-year>"`
   - Query: `"<concern> commonTest <current-year>"`
   - Prefer JetBrains blog, Kotlinlang Slack archives, kotlinlang.org docs.
3. find-docs skill if the candidate library has published docs.

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
