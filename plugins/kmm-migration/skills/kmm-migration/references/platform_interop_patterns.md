# Platform Interop Patterns

> JetBrains' canonical priority for crossing the platform boundary in shared
> code. Replaces the older 3-step decision tree with the 4-step priority
> from kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html.
> Law 15 applies: pick the canonical pattern, not the easier one. Law 13
> applies for picking specific libraries within each step.

## Contents

- [The 4-step priority — JetBrains canonical](#the-4-step-priority--jetbrains-canonical)
- [iOS integration mechanism — tiered default](#ios-integration-mechanism--tiered-default)
- [Repo-preservation bias](#repo-preservation-bias)
- [Decision recording](#decision-recording)

## The 4-step priority — JetBrains canonical

For every platform-bound class / function the migration touches, walk this
priority TOP-DOWN. Stop at the first step that resolves the case. Do NOT
skip ahead because a lower-priority option seems easier — that is a Law 15
violation.

Source (verbatim): https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html

**Step 1 — Use a multiplatform library.**

If a library already exists that abstracts the concern across platforms,
use it. The researcher resolves the current canonical multiplatform
library for each concern live each invocation per Law 13 — this file
does NOT name specific libraries because library names are version-bound
and change.

This is always the preferred answer when applicable. Adopting an existing
library beats writing your own abstraction in three ways: it's already
maintained, it already works on every target, and it lets your code be
cited as "uses lib X" instead of "uses bespoke abstraction Y."

**Step 2 — `expect` / `actual` function or property (simple cases).**

Use `expect`/`actual` for narrow, primitive-shaped concerns where the
abstraction surface is one or two declarations and the platform behaviour
is genuinely platform-bound. Examples: a single `expect fun
currentTimeMillis(): Long` (if kotlinx.datetime hadn't existed); a single
`expect val isDebugBuild: Boolean`.

`expect`/`actual` is NOT for:
- Anything multi-method, stateful, or with non-trivial lifecycle (use Step 3).
- Wrapping a JVM-only stdlib type just to defer the migration work — that's
  a Law 15 violation. The fix is to replace the JVM type with its multiplatform
  equivalent, not to expect/actual it.
- `expect class` where an interface would do — JetBrains explicitly
  discourages this (Beta opt-in required, signature rigidity, no diamond
  hierarchies).

**Step 3 — Interface in commonMain + platform implementations (complex cases).**

For multi-method, stateful, or lifecycle-bound concerns, declare an
interface in `commonMain` and provide implementations in `androidMain` and
`iosMain`. Wire the implementation in via DI (Step 4) or via a constructor
parameter at the entry point. Examples: a `LogSink` interface (commonMain)
with `AndroidLogcatSink` and `iOSNSLogSink` actuals; a `KeyValueStore`
interface with `SharedPreferencesStore` and `NSUserDefaultsStore`.

This is the most flexible pattern. It scales to any complexity and avoids
the rigidity of `expect class`.

**Step 4 — DI framework — preferred when project already uses one.**

Verbatim from JetBrains: "We recommend continuing to use DI if you already
have it in your project, rather than using the expected and actual functions
manually."

When the project uses Koin / Kodein / Metro / kotlin-inject (researcher
verifies which is current), wire platform implementations of Step-3
interfaces through the DI graph. Do NOT mix `expect`/`actual` and DI for
the same dependency — pick one mechanism per concern.

If the project does NOT use DI, this step is N/A and you're done at Step 3.
Adding DI mid-migration just to satisfy this step is over-engineering
unless the user explicitly approves it.

## iOS integration mechanism — tiered default

Source: https://kotlinlang.org/docs/multiplatform/multiplatform-ios-integration-overview.html

The available iOS integration mechanisms and their stability tiers are
version-bound — the researcher fetches the current page each invocation
per Law 13 and writes the current stability table into
`kmm_migration/findings.md`. This file does NOT pin the table because
JetBrains has been moving things between Stable / Beta / Experimental
fairly often.

**Tiered default for `14_ios_porter` (structural rule, not knowledge):**

1. Inspect the iOS host repo (or directory if monorepo) for a `Podfile`.
2. If `Podfile` present → default to whichever CocoaPods-based mechanism
   the researcher's current stability table marks as Stable (typically
   the local-podspec variant).
3. Else → default to whichever non-CocoaPods mechanism the researcher's
   current stability table marks as Stable AND is "applied by default
   by the IDE plugin" per the docs (typically Direct integration).
4. Researcher overrides with a live-sourced reason (e.g., monorepo
   policy, organisation-mandated mechanism).
5. Any mechanism flagged Beta / Experimental in the researcher's table
   requires user opt-in via `REQUIRES_APPROVAL`. Picking an experimental
   mechanism silently is a Law 15 violation.

## Repo-preservation bias

Keep existing patterns when:
- They compile on KMP (verify with a minimal build probe).
- The researcher confirms via Law-13 lookup that the pattern is not
  abandoned / superseded.

Swap only when:
- The pattern is Android-only and literally incompatible with commonMain.
- The researcher provides a live-sourced successor + a citation.

Repo preservation cannot override Law 15. If the existing pattern is a
Law 15 violation in disguise (e.g., a hand-rolled DI graph because the
team avoided Koin), preserving it is wrong even if it compiles. The
researcher names the canonical alternative; the migrator implements it
or `REQUIRES_APPROVAL` is raised.

## Decision recording

For each platform-bound concern, record in `migration_guide.md`:

- Concern (what platform-bound thing is being abstracted).
- Step taken (1, 2, 3, or 4) with a one-sentence reason.
- Source citation for any library or pattern named (Law 13 / Law 15
  format from `references/knowledge_lookup_protocol.md`).
- File-level prescriptions (which file declares the interface, which
  files declare the actuals, which DI module wires them).

Plans that take a higher-numbered step without justifying why a
lower-numbered step is unsuitable are `ISSUES_FOUND` at plan_critic time.
