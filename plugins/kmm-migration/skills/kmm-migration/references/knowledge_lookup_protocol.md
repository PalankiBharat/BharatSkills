# Knowledge Lookup Protocol

> The general protocol for Law 13 ("LIVE KNOWLEDGE, NEVER TRAINING-DATA
> KNOWLEDGE") and Law 15 ("CANONICAL KMP APPROACH OVER SHORT-TERM
> EXPEDIENCE"). Use this whenever a subagent needs any external knowledge —
> KMP workflow, library behaviour, API shape, platform nuance, community
> best practice.

## Contents

- [Priority order](#priority-order)
- [KMP-foundational entry-point URLs](#kmp-foundational-entry-point-urls)
- [Source citation format](#source-citation-format)
- [When lookup fails](#when-lookup-fails)

## Priority order

**Priority 0 — kotlinlang.org canonical docs (the "KMP book")**

For any KMP-shaped question — workflow / ordering / project structure /
sourceSet rules / expect-actual / interop pattern / library swap / iOS
integration / Compose Multiplatform / resource handling / target
configuration — the kotlinlang.org canonical documentation tree is the
FIRST place to look, ahead of any other live source. This is the live-source
corollary of Law 15: kotlinlang.org is JetBrains-owned, version-current,
and resolves ambiguity that community sources debate.

Fetch via WebFetch directly against the entry-point URLs listed below, OR
via context7 if it has the page indexed (context7 frequently does — fall
through is fine). The URL stays the canonical citation regardless of which
fetcher delivered it.

**Priority 1 — context7 (third-party library docs)**

For library-specific questions where kotlinlang.org doesn't cover the
specific library (Ktor, SQLDelight, Koin, kotlinx-serialization,
Compose-Multiplatform internals beyond what the landing pages cover):

- `mcp__context7__resolve-library-id(query="<descriptive query>")`
- `mcp__context7__query-docs(libraryId=<resolved>, query="<specific question>")`
- Try candidate library names the repo already uses first.

**Priority 2 — WebSearch / find-docs**

When kotlinlang.org and context7 don't have coverage, or when the question
is community-flavoured (a Kotlinlang Slack thread, a JetBrains blog post,
a KEEP proposal):

- WebSearch with queries including current year + the kotlinlang.org domain
  filter (`site:kotlinlang.org`) before going broader.
- `find-docs` skill when a candidate library/version is known.
- Prefer JetBrains blog, Kotlinlang Slack archives, kotlinlang.org docs,
  KEEPs (in that order) over community blog posts.

**Priority 3 — training data**

ONLY if Priorities 0/1/2 all failed AND the claim is flagged
`⚠ TRAINING DATA — VERIFY BEFORE USE`.

**Tie-breakers within a single question:**

- If kotlinlang.org disagrees with context7 → kotlinlang.org wins (Law 15).
- If context7 disagrees with WebSearch → context7 wins (Law 13).
- If any live source disagrees with training data → live source wins (Law 13).

Every claim goes through this protocol; no exceptions.

## KMP-foundational entry-point URLs

When a subagent needs a kotlinlang.org doc, start from the entry point
nearest to the concern. The full URL inventory was compiled at
2026-04-30; researcher should confirm canonicality each invocation.

**Migration workflow:**
- https://kotlinlang.org/docs/multiplatform/migrate-from-android.html  (THE migration page)
- https://kotlinlang.org/docs/multiplatform/multiplatform-integrate-in-existing-app.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-introduce-your-team.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-upgrade-app.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-update-ui.html

**Project structure / DSL / config:**
- https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-hierarchy.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-advanced-project-structure.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-dsl-reference.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-android-layout.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-project-agp-9-migration.html
- https://kotlinlang.org/docs/multiplatform/supported-platforms.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-compatibility-guide.html

**Sharing patterns / expect-actual / tests:**
- https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-share-on-platforms.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html  (THE 4-step priority)
- https://kotlinlang.org/docs/multiplatform/multiplatform-run-tests.html
- https://kotlinlang.org/docs/multiplatform/compose-test.html

**iOS integration:**
- https://kotlinlang.org/docs/multiplatform/multiplatform-ios-integration-overview.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-direct-integration.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-cocoapods-overview.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-spm-export.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-spm-import.html
- https://kotlinlang.org/docs/multiplatform/multiplatform-privacy-manifest.html
- https://kotlinlang.org/docs/native-objc-interop.html
- https://kotlinlang.org/docs/native-swift-export.html

**Compose Multiplatform:**
- https://kotlinlang.org/docs/multiplatform/compose-multiplatform.html
- https://kotlinlang.org/docs/multiplatform/compose-multiplatform-and-jetpack-compose.html  (package mapping)
- https://kotlinlang.org/docs/multiplatform/compose-multiplatform-jetpack-libraries.html  (Lifecycle/Nav rename)
- https://kotlinlang.org/docs/multiplatform/compose-multiplatform-resources.html  (resource rules)
- https://kotlinlang.org/docs/multiplatform/compose-previews.html  (preview annotation)
- https://kotlinlang.org/docs/multiplatform/compose-viewmodel.html
- https://kotlinlang.org/docs/multiplatform/compose-compiler.html
- https://kotlinlang.org/docs/multiplatform/compose-compatibility-and-versioning.html

**Native / Kotlin idioms:**
- https://kotlinlang.org/docs/native-target-support.html  (tier table)
- https://kotlinlang.org/docs/native-memory-manager.html  (freezing-API purge)
- https://kotlinlang.org/docs/java-to-kotlin-idioms-strings.html  (JVM-API scrub)
- https://kotlinlang.org/docs/visibility-modifiers.html  (internal across source sets)

**Worked example (sample project):**
- https://github.com/kotlin-hands-on/jetcaster-kmp-migration

## Source citation format

Every non-obvious claim cites its source at the point of assertion:

- kotlinlang.org direct: `(source: kotlinlang.org/docs/multiplatform/<page>, fetched <YYYY-MM-DD>)`
- kotlinlang.org via context7: `(source: kotlinlang.org/docs/multiplatform/<page> via context7, fetched <YYYY-MM-DD>)`
- context7 (third-party lib): `(source: context7 libraryId=/org/project, query="…")`
- WebSearch: `(source: <URL>, fetched <YYYY-MM-DD>)`
- find-docs: `(source: find-docs: <library name>)`
- Training data (flagged): `(⚠ TRAINING DATA — VERIFY: <claim>)`

## When lookup fails

If all four priorities fail to produce a confident answer, emit
`STATUS: NEEDS_CONTEXT` with the exact question. Do NOT guess.
