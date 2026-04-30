# Per-File Migration Preconditions

> A file is not migration-ready until every precondition below is satisfied.
> The migrator verifies these BEFORE moving any code into `commonMain`.
> The reviewer verifies these AFTER the move and FAILS spec compliance if any
> precondition was bypassed via hardcoding, inlining, or a comment-out hack.
>
> This file exists because the canonical failure mode of an LLM-driven KMP
> migration is "make it compile by any means" — hardcoding resource strings,
> inlining JVM-only APIs, papering over Hilt with hand-rolled wiring. Each
> precondition closes one of those shortcuts. Every precondition below is
> a Law 15 application: canonical KMP approach, never short-term expedience.
>
> Scope respect: every precondition runs only against files in the user-chosen
> scope (whole feature / module / screen / file — recorded in `state.json`).
> The orchestrator does NOT silently expand scope to satisfy a precondition;
> if a precondition requires touching out-of-scope files (a string resource
> used by the in-scope screen but defined in a parent module's `strings.xml`),
> the migrator raises `STATUS: PRECONDITION_BLOCKED` and the orchestrator
> raises `REQUIRES_APPROVAL` to ask the user whether to expand scope or
> defer.

## Contents

- [Why per-file, not per-phase](#why-per-file-not-per-phase)
- [Precondition R — Resources moved before screen moves](#precondition-r--resources-moved-before-screen-moves)
- [Precondition J — Java converted to Kotlin](#precondition-j--java-converted-to-kotlin)
- [Precondition A — JVM-only APIs replaced](#precondition-a--jvm-only-apis-replaced)
- [Precondition D — Disqualified deps swapped](#precondition-d--disqualified-deps-swapped)
- [Precondition P — Platform types abstracted](#precondition-p--platform-types-abstracted)
- [Verification protocol](#verification-protocol)
- [Failure handling](#failure-handling)

## Why per-file, not per-phase

A whole-app prerequisite check before Phase 1 sounds tidy but it doesn't catch
the actual failure: a single file whose resources got hardcoded, whose JVM APIs
got inlined, whose Hilt got hand-rolled. The skill is feature-by-feature and
batch-by-batch — the unit of failure is the file, so the unit of guard must be
the file.

The migrator runs through these preconditions for every file in the in-scope
list before writing a line of `commonMain` code. The reviewer re-runs them
against the diff. A precondition that was silently violated in the migrated
output is a Law 1 (1:1 port) violation regardless of whether the code compiles.

## Precondition R — Resources moved before screen moves

A composable / view file moves to `commonMain` only after every resource it
references has moved to `composeResources/` and every reference has switched
from `R.*` to `Res.*`.

Source: https://kotlinlang.org/docs/multiplatform/migrate-from-android.html
+ https://kotlinlang.org/docs/multiplatform/compose-multiplatform-resources.html

**Specifically:**

- Resource directory rename: `src/main/res/` → `src/commonMain/composeResources/`.
  Subfolder structure changes — see the canonical resources page for the
  current `composeResources/<qualifier>-<type>/` layout.
- Generated class rename: `R` → `Res`. References switch from
  `R.string.foo` to `Res.string.foo`, `R.drawable.bar` to `Res.drawable.bar`,
  `R.plurals.baz` to `Res.plurals.baz`.
- Composable accessors: `stringResource(R.string.foo)` becomes
  `stringResource(Res.string.foo)`. `painterResource(R.drawable.bar)` becomes
  `painterResource(Res.drawable.bar)`. `Res.string.*` is a `StringResource`
  type; the composable accessors take that, not an integer ID.
- **`R.dimen.*` has NO direct equivalent.** Migrate `dimensionResource(R.dimen.padding_md)`
  by either (a) hard-coding `12.dp` if the value is a single-purpose constant,
  OR (b) declaring an `object Dimens { val paddingMd = 12.dp }` in
  `commonMain`. NEVER hardcode silently — the reviewer flags any literal
  `.dp` / `.sp` value that came from a `dimen` resource as a Law-1 violation
  unless `Dimens` (or equivalent) was explicitly introduced.

**Forbidden shortcuts (these are exactly what an LLM does under pressure):**

- Inlining a string from `strings.xml` directly as a literal in the composable
  ("Welcome" instead of `stringResource(Res.string.welcome)`).
- Inlining a colour, dimen, or drawable name as a literal.
- Commenting out the resource reference and leaving a TODO.
- Importing `androidx.compose.ui.res.stringResource` (the Android-only
  variant) and pretending it works in `commonMain` — it doesn't, and the
  build error pushes Claude toward the literal-inlining shortcut.

**Migrator obligation:** before touching the screen file, the migrator emits
a sub-task list of every resource the file references and confirms each has
been moved. If any are still in `res/`, the migrator either moves them in the
same dispatch (when ≤ 5 strings/dimens/drawables) OR raises
`STATUS: PRECONDITION_BLOCKED` so the orchestrator dispatches a resource-move
batch first.

**Reviewer obligation:** the spec_compliance_reviewer greps the migrated file
for: any string literal in a `Text(...)` call, any literal `.dp` / `.sp` /
hex colour, any `R.` reference, any `androidx.compose.ui.res.*` import. Each
match is a verdict `ISSUES_FOUND` with citation file:line and the rule above.

## Precondition J — Java converted to Kotlin

A file moves to `commonMain` only if it is already Kotlin and every
non-Kotlin file it depends on (transitively, via direct imports) has been
converted to Kotlin OR is explicitly scoped to remain in `androidMain`.

Source: https://kotlinlang.org/docs/multiplatform/migrate-from-android.html
("the `commonMain` source set ... can't contain Java code") + Java→Kotlin
idioms at https://kotlinlang.org/docs/java-to-kotlin-idioms-strings.html.

**Migrator obligation:** for the in-scope file list, the migrator runs
`grep -l 'class .* {' --include='*.java' <feature-paths>`. Any hits trigger
the precondition. The migrator either converts in the same dispatch
(`Code → Convert Java File to Kotlin File` if running interactively, or
direct rewrite when not) OR raises `PRECONDITION_BLOCKED`.

**Forbidden shortcut:** writing the Kotlin equivalent inline in the
migrated file while leaving the original Java file in place. That hides the
Java without removing it.

## Precondition A — JVM-only APIs replaced

A file moves to `commonMain` only after every JVM-only API call has been
replaced with its multiplatform equivalent. Reference table is
`references/jvm_api_scrub_list.md` — the migrator MUST run that scrub on the
file before the port and the reviewer MUST re-run it on the diff.

Source: https://kotlinlang.org/docs/java-to-kotlin-idioms-strings.html

The scrub list covers: `StringBuilder`, `String.format`, `Pattern`/`Matcher`,
`Stream`/`Collectors`, `System.getProperty("line.separator")`, Java text
blocks, `java.util.UUID`, `java.io.File`, `java.time.*`,
`java.util.concurrent.*` primitives, `Objects.hash()`. See the scrub list
file for the full table with FROM → TO.

**Forbidden shortcut:** wrapping a JVM-only call in `expect`/`actual` to
"defer" the work. `expect`/`actual` is for genuine platform-bound
behaviour, not for "I haven't ported this yet." The reviewer rejects any
`expect`/`actual` whose signature directly maps to a single JVM-stdlib
type — that's a deferral, not a port.

## Precondition D — Disqualified deps swapped

A file moves to `commonMain` only if every library it imports is
KMP-compatible (or has been replaced by its KMP-compatible equivalent).

**This file does NOT name specific FROM → TO library swaps.** Library
names (Koin / Mokkery / Coil 3 / Room ≥ 2.7.0 / etc.) are version-bound
and JetBrains updates them — pinning them here would go stale silently.
The researcher resolves the current canonical KMP-compatible alternative
for each disqualified concern live each invocation per Law 13 + Law 15.

The CONCERN categories the migrator scans for (the "FROM" axis):

- **Dependency injection.** Any DI framework that is JVM-only.
- **Async / reactive.** Any reactive framework whose primary types
  don't have multiplatform builds.
- **Test runner / assertions.** Any test framework whose annotations
  / runner are JVM-only.
- **Date and time.** Any usage of `java.time.*` or `java.util.Date` /
  `Calendar`.
- **Networking.** Any HTTP / WebSocket library that is JVM-only.
- **Persistence / ORM.** Any database library whose driver is JVM-only.
- **Image loading.** Any image library that is Android-only.
- **Serialization.** Any serializer that is JVM-only.
- **RSS / feed parsing, PDF, charting, etc.** Any specialty library that
  was picked when the project was Android-only.

For each concern hit, the researcher fetches the current canonical
KMP-capable alternative from kotlinlang.org (entry-point URL list in
`references/knowledge_lookup_protocol.md`) and records the FROM → TO
mapping in `kmm_migration/findings.md`. Subsequent files in the same
migration inherit the mapping.

**Migrator obligation:** before touching a file, scan its imports for the
concern categories above. If a hit's mapping is not yet in `findings.md`,
raise `PRECONDITION_BLOCKED` and the orchestrator dispatches the
researcher to resolve it. Once resolved, the migrator either does the swap
in the same dispatch (when small) OR `PRECONDITION_BLOCKED` again so the
orchestrator routes a swap batch first.

**Forbidden shortcut:** keeping the FROM import and adding a `// TODO:
migrate to <X>` comment. The migrated file does not move until the swap
is complete OR the file is explicitly descoped to `androidMain` (logged
in `accepted_deltas`). NEVER hand-roll the FROM library's behaviour in
`commonMain` (e.g., writing a fake DI graph instead of using whatever
DI framework the researcher named).

## Precondition P — Platform types abstracted

A file moves to `commonMain` only if no Android-platform type or Apple-platform
type is referenced in its body. Specifically forbidden in `commonMain`:
`android.*`, `androidx.*` (except multiplatform-aliased Compose runtime under
`androidx.compose.*`), `platform.UIKit.*`, `platform.Foundation.*`,
`java.io.File`, `platform.Foundation.NSUUID`.

Source: https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html
+ https://kotlinlang.org/docs/multiplatform/multiplatform-share-on-platforms.html

When platform behaviour is genuinely needed, JetBrains prescribes this
priority (verbatim from connect-to-apis.html), in order:

1. **Use a multiplatform library** that already abstracts it.
2. **expect/actual function or property** for simple cases.
3. **Interface in common code + platform implementations** for complex cases.
4. **DI framework — preferred when project already uses one**: "we recommend
   continuing to use DI if you already have it in your project, rather than
   using the expected and actual functions manually."

**Forbidden shortcut:** using `expect class` where an interface would
suffice. JetBrains explicitly discourages this. Also, mixing `expect`/`actual`
with DI for the same dependency.

## Verification protocol

Migrator dispatch prompt MUST include the verbatim line:

> Before any file in your in-scope list is moved, run preconditions R, J, A,
> D, P from `references/migration_preconditions.md`. For each file, write
> `kmm_migration/reports/<feature>/<batch>_preconditions.md` recording the
> verdict per file per precondition with evidence. If any precondition fails,
> emit `STATUS: PRECONDITION_BLOCKED` with the file list and required
> sub-task — do NOT attempt the port.

Reviewer dispatch prompt (spec_compliance_reviewer) MUST include:

> Re-run preconditions R, J, A, D, P from `references/migration_preconditions.md`
> against the migrated diff. Any precondition violated in the produced code
> (hardcoded resource, inlined JVM API, hand-rolled DI, leftover Java import,
> Android type in commonMain) is `ISSUES_FOUND` regardless of compile status.
> Cite file:line for every violation.

## Failure handling

`PRECONDITION_BLOCKED` is a normal status, not a strike. The orchestrator
routes the blocking sub-task (resource move, Java conversion, dep swap, JVM-API
replacement, platform-type abstraction) and re-dispatches the original
migrator with the same in-scope file list once the precondition is satisfied.

Three distinct precondition blocks for the same file count as a strike per
the three-strike protocol — at that point the file is escalated to
`debug_investigator` to determine whether it can be ported at all in this
batch shape, or needs to be deferred / refactored / scoped out.
