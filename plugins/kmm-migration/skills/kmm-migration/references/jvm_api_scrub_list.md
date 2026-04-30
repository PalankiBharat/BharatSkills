# JVM-Only Construct Scrub Protocol

> Files moving to `commonMain` cannot import JVM-only types. The migrator
> runs this protocol against every file in scope BEFORE the port (Precondition
> A in `references/migration_preconditions.md`); the reviewer re-runs it
> against the diff. Surviving JVM-only constructs in `commonMain` are a
> Law 15 violation regardless of compile status.
>
> **This file does NOT ship a FROM → TO table.** The specific multiplatform
> replacement for any given JVM-only construct is current docs knowledge —
> JetBrains updates it; pinning it here would go stale silently. The
> researcher resolves the current canonical replacement live each invocation
> from the URLs below, per Law 13 + Law 15.
>
> Canonical sources to fetch live:
> - https://kotlinlang.org/docs/java-to-kotlin-idioms-strings.html
> - https://kotlinlang.org/docs/multiplatform/multiplatform-share-on-platforms.html
> - https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html

## Contents

- [The scrub protocol](#the-scrub-protocol)
- [Categories to scrub for](#categories-to-scrub-for)
- [Forbidden shortcuts](#forbidden-shortcuts)
- [Output schema](#output-schema)
- [Where the table lives](#where-the-table-lives)

## The scrub protocol

Per file in the in-scope list:

1. **Grep for category indicators.** Scan the file's imports and identifiers
   for any construct in any category below.
2. **For each hit, look up the current canonical replacement** via the
   researcher's protocol (`references/knowledge_lookup_protocol.md`).
   Priority 0 (kotlinlang.org) is the source. The researcher writes the
   discovered FROM → TO mapping into `kmm_migration/findings.md` for this
   migration so subsequent files in the same batch reuse it.
3. **Apply the canonical replacement.** Never invent your own — if
   kotlinlang.org's recommendation is non-obvious or surprising, use it
   anyway. Surprise is exactly when training-data knowledge is wrong.
4. **Record the mapping** in the per-file precondition report:
   `kmm_migration/reports/<feature>/<batch>_preconditions.md`.

If a hit cannot be resolved (the docs are silent or the recommended
replacement is itself Beta/Experimental and the user hasn't approved
opt-in), emit `STATUS: PRECONDITION_BLOCKED` and surface the question to
the user. Do NOT silently pick a workaround.

## Categories to scrub for

These are the categories of JVM-only constructs the migrator must scan
for. The list is structural (it identifies WHAT to look for); the specific
replacement for each construct is researcher-resolved per invocation.

- **Filesystem and IO**: any reference to `java.io.*`, `java.nio.*`,
  `java.nio.file.*`. Also `Path`, `File`, `BufferedReader`,
  `FileInputStream`, etc.
- **Concurrency primitives**: `java.lang.Thread`, `java.lang.Runnable`,
  `java.util.concurrent.*` (`Executor`, `Future`, `CountDownLatch`,
  `ConcurrentHashMap`), `volatile`, `synchronized` blocks.
- **Reflection**: `java.lang.reflect.*`, `Class<T>` (the Java reflection
  variant — Kotlin's `KClass<T>` is multiplatform), `ServiceLoader`.
- **Date and time**: `java.time.*` (Instant, LocalDate, Duration, ZoneId,
  ZonedDateTime, OffsetDateTime), `java.util.Date`, `java.util.Calendar`.
- **Strings, regex, formatting**: JVM `StringBuilder` (the JVM-aliased one;
  Kotlin's stdlib `StringBuilder` IS multiplatform — the issue is the
  `java.lang.StringBuilder` import line), `String.format(...)`,
  `java.util.regex.Pattern`/`Matcher`.
- **Streams collection ops**: `java.util.stream.Stream`,
  `java.util.stream.Collectors`, `parallelStream()`.
- **System properties / clock**: `System.getProperty(...)`,
  `System.currentTimeMillis()`, `System.nanoTime()`,
  `System.getenv(...)`.
- **UUID**: `java.util.UUID`.
- **Logging frameworks**: `java.util.logging.*`, `org.slf4j.*`, Timber
  (Android-only).
- **Reactive**: RxJava (`Observable`, `Single`, `Flowable`,
  `Completable`).
- **Test idioms**: `org.junit.*`, `org.junit.jupiter.*`, JVM-only mock
  frameworks (Mockito, MockK), Robolectric (which stays in
  `androidUnitTest` and never moves to `commonTest`).
- **Object utilities**: `java.util.Objects` (`hash`, `equals`,
  `requireNonNull`), `java.util.Arrays` (most members are platform-only).
- **Collections JVM-specifics**: `Collections.unmodifiableList`,
  `Collections.synchronizedMap`, `EnumSet`, `EnumMap`, `WeakHashMap`,
  `LinkedHashMap` *as java type*.

## Forbidden shortcuts

These are the canonical failure modes — the migrator must NOT do any of
them, and the reviewer must catch any that slipped through:

- **Wrapping a JVM construct in expect/actual to "defer" the work.**
  expect/actual is for genuine platform-bound behaviour, not for
  unfinished ports. The reviewer rejects any expect/actual whose signature
  directly maps to a single JVM stdlib type.
- **Inlining a JVM-only call's logic by hand.** ("Java's Stream supports
  parallel — I'll just write a for-loop, close enough.") Subtle
  semantics get lost.
- **Adding a `// TODO: replace before iOS port` comment.** Law 09 — no
  new TODOs. Either replace now or `PRECONDITION_BLOCKED`.
- **Importing the JVM type and using `actual typealias` to "make it
  multiplatform".** Typealiases to platform types belong in `androidMain`
  actual files, NOT in commonMain. The grep catches the import line.
- **Bridging RxJava through a `kotlinx-coroutines-rxN` adapter inside
  commonMain.** The adapter is for the Android edge to non-migrated
  callers, not for shared code. Shared code uses `Flow` / `StateFlow`
  directly.

## Output schema

Per file, the migrator records in
`kmm_migration/reports/<feature>/<batch>_preconditions.md`:

```markdown
### File: <path>

#### Precondition A — JVM-only construct scrub

| Hit (FROM construct) | Researcher-resolved replacement | Source citation |
|---|---|---|
| <import or call> | <multiplatform equivalent> | <kotlinlang.org URL + fetch date> |

Verdict: PASS | PRECONDITION_BLOCKED
```

If multiple files in the batch hit the same FROM construct, the resolution
is recorded once in `findings.md` and cross-referenced from each file's
report — the researcher does not re-resolve per file.

## Where the table lives

The actual FROM → TO table for the current invocation lives in the
researcher's `kmm_migration/reports/<feature>/research_notes.md` and the
running `kmm_migration/findings.md`. Subsequent migrations on the same
project inherit the findings table (until JetBrains updates the docs and
the researcher refreshes it). This is intentional: the skill stays a
behavioural shell; the knowledge stays in the docs and in per-project
findings.
