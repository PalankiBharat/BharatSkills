# Review Criteria

> The per-classification checklists. Every checklist item has a verdict
> (PASS with `path:line` evidence, OR a finding per `finding_schema.md`).
> No silent skips — Law 4.

## Contents

- [Universal preamble](#universal-preamble)
- [`migrated` checklist](#migrated-checklist)
- [`ios_port` checklist](#ios_port-checklist)
- [`nonmigrated` checklist](#nonmigrated-checklist)
- [`baseline` checklist](#baseline-checklist)
- [`build_config` checklist](#build_config-checklist)

## Universal preamble

These checks apply to EVERY file regardless of classification. Run them first.

- [ ] **U1 — Diff is in scope.** The file appears in `state.json.files`. (If not, the orchestrator mis-routed; emit `STATUS: NEEDS_CONTEXT` immediately.)
- [ ] **U2 — No `TODO` / `FIXME` / `XXX` introduced.** Run `git diff <base_sha>..<head_sha> -- <path> | grep -E '^\+.*\b(TODO|FIXME|XXX)\b'` — any match → `STUB_LEFTOVER` finding.
- [ ] **U3 — No build output paths leaked.** No additions under `build/`, `.gradle/`, `generated/`, `node_modules/`. Any match → `BUILD_OUTPUT_LEAKED` (BLOCKER).
- [ ] **U4 — No live-knowledge violations in code or comments.** Any new comment that asserts a KMP fact (`// uses Ktor because ...`, `// the standard pattern is ...`) without a citation must be flagged as `RULE_06_VIOLATION`.

## `migrated` checklist

Reviewer reads BOTH the master version (`git show <base_sha>:<master_path>`) AND the head version (`Read <path>` or `git show <head_sha>:<path>`) before walking the checklist. If `paired_master_path` is `null` in `state.json.files`, the reviewer skips items M1–M6 and notes "no paired master file — brand-new commonMain addition" as the verdict for each, then runs M7–M14.

- [ ] **M1 — API surface preserved.** Every public class, interface, top-level function, top-level property, and companion-object member that exists on master appears in the port with an identical signature: same name, same parameter types and order, same return type, same modifiers (`open` / `final` / `abstract` / `internal` / `public`), same nullability, same generic constraints. Differences → `API_DRIFT` (BLOCKER).
- [ ] **M2 — Control flow preserved.** Every `if` / `when` / `try-catch-finally` / early-return branch on master is present in the port. Walk every public function in master and verify each branch's destination is reachable in the port. Missing branch → `MISSING_LOGIC` (BLOCKER).
- [ ] **M3 — Side-effects preserved.** Every observable side-effect on master is preserved: database writes, network calls (including HTTP method, URL template, headers, body shape), log statements (level + message template), analytics events (event name + property keys), file I/O, broadcast intents, shared-preference writes, navigation events, navigation back-stack manipulation. Use Grep on the master version to enumerate; verify each appears in the port at a semantically equivalent location. Missing or weakened → `MISSING_LOGIC` (BLOCKER); reordered → `PARITY_DRIFT` (BLOCKER) unless the reorder is provably observationally equivalent.
- [ ] **M4 — Defaults and null handling preserved.** Default values on parameters, fallback paths in `?:`, `requireNotNull`/`checkNotNull` calls, lateinit/nullable distinctions, sentinel returns (e.g. `Result.failure(...)`) are identical. Differences → `PARITY_DRIFT` (BLOCKER).
- [ ] **M5 — Concurrency contract preserved.** Coroutine scope (`viewModelScope`, `lifecycleScope`, custom scopes), dispatcher (`Dispatchers.IO` / `.Main` / `.Default`), structured-concurrency primitives (`async`, `launch`, `withContext`, `flowOn`, `coroutineScope`, `supervisorScope`), and threading guarantees match. If the port changes the dispatcher or scope, the change must be justified by a sourced KMP constraint (Law 6). Unsourced change → `PARITY_DRIFT` (MAJOR).
- [ ] **M6 — UI strings, dimens, colors, drawables unchanged.** Any string-resource ID, dimen key, color key, or drawable key referenced by the migrated UI code must point to identical values on master and head. Run Grep on the resource files for every key the port references. Differences → `UI_DRIFT` (MAJOR) unless the change is documented in an `accepted_deltas` entry the user has acknowledged.
- [ ] **M7 — No new dependencies in this file's module.** Inspect the module's `build.gradle.kts` (look up via Glob: `<module-root>/build.gradle.kts`) — no `implementation`, `api`, `testImplementation` line was added without a live source for the dependency. Cross-check against `state.json.files` — if the build file is in the diff, expect a corresponding finding from the `build_config` reviewer. New dep without justification → `DEP_ADDITION` (MAJOR).
- [ ] **M8 — No Android SDK types in `commonMain`.** If the file's path is under `*/commonMain/**`, run `grep -E '^\+.*import android\.' <diff-of-this-file>`. Any match → `PLATFORM_LEAK` (BLOCKER). Also disallow: `Context`, `View`, `Activity`, `Fragment`, `Intent`, `SharedPreferences`, `Bundle`, `Resources`, `PackageManager`, `Application`, `BroadcastReceiver`, `Service`, `ContentResolver`, `Cursor`, `Uri` (when from `android.net`), and any class explicitly typed as belonging to an `android.*` package.
- [ ] **M9 — Interop pattern is `expect/actual` OR `interface + DI`, not both, not improvised.** If the file declares `expect class` / `expect fun` / `expect interface`, verify the corresponding `actual` exists in `androidMain` (and `iosMain` if `ios_port` files exist for this entity). If the file uses an injected interface instead, verify the interface is declared in `commonMain` and the platform implementations are wired via the DI framework the repo uses. Mixed or improvised → `INTEROP_PATTERN_VIOLATION` (MAJOR). For the actual classification of "the right pattern", consult `parity_verification_protocol.md`.
- [ ] **M10 — No new comments / docstrings / multi-line comment blocks introduced.** A diff line starting with `+ //`, `+ /*`, or a new KDoc block is forbidden. Pre-existing comments may remain unchanged; new ones are `STUB_LEFTOVER` if they read like deferrals, `CLEAN_CODE` if they restate the code. Exception: a single-line comment that documents a non-obvious `accepted_deltas` boundary.
- [ ] **M11 — No baseline assets touched by this file's change set.** Cross-check `state.json.files` — there should be no `baseline`-classified file in the same module that this file touches. (The check is a defensive cross-reference; the actual baseline-mod finding is emitted by the `baseline`-classified reviewer.)
- [ ] **M12 — Diff is surgical.** Every changed line in this file traces to either: (a) the move from non-multiplatform Android source root to a multiplatform source set; (b) an interop-pattern boilerplate addition (expect declaration, actual implementation, DI binding); (c) an import re-organization that the move requires; (d) a documented `accepted_deltas` entry. Lines that do none of (a)–(d) → `SCOPE_CREEP` (MAJOR) or `SPECULATIVE_CODE` (MAJOR) depending on whether the line introduces a new abstraction.
- [ ] **M13 — File-reference format correct.** Every finding emitted by this reviewer uses `path:line` format. (Self-check at end of report.)
- [ ] **M14 — Final-status verdict assigned.** The report ends with exactly one `STATUS:` header from the contract.

## `ios_port` checklist

For files under `iosMain/**` (and similar iOS source-set roots).

- [ ] **I1 — Every `expect` declared in `commonMain` for entities in this file's package has a matching `actual`.** Locate the corresponding commonMain expect via Grep on `expect (class|fun|object|interface) <name>`. The actual signature must match the expect signature exactly: same name, same parameter types and order, same return type, same modifiers, same nullability, same generic constraints. Mismatch → `IOS_CONTRACT_MISMATCH` (BLOCKER).
- [ ] **I2 — No Android types imported.** No `import android.*` in iosMain. Any match → `PLATFORM_LEAK` (BLOCKER) (the same category, but the direction is reversed: iOS source set leaking Android code is just as wrong).
- [ ] **I3 — Interop boundary is correct.** Per `parity_verification_protocol.md` § "Swift interop", iOS-facing types that are exposed to Swift consumers must use the documented interop annotations / wrapping. Specifically: no `sealed class` exposed without a Swift-friendly enum wrapper unless the codebase has documented otherwise; no `inline class` exposed; suspend functions exposed only through the documented async wrapping. Violations → `IOS_TYPE_LEAK` (MAJOR).
- [ ] **I4 — Behaviour parity with the iOS native equivalent on master (if pre-existing iOS code is being replaced).** If the PR also removes a `.swift` file that this `iosMain` Kotlin file replaces, walk the removed Swift file's public-API and side-effects and verify the Kotlin actual reproduces them. Differences → `PARITY_DRIFT` (BLOCKER).
- [ ] **I5 — No new comments / docstrings introduced.** Same as M10.
- [ ] **I6 — Diff is surgical.** Same intent as M12, scoped to iosMain.
- [ ] **I7 — File-reference format correct.** Same as M13.
- [ ] **I8 — Final-status verdict assigned.** Same as M14.

## `nonmigrated` checklist

For files in the diff that should arguably not be in this PR — they are not the target of migration. Any change here is suspicious by definition.

- [ ] **N1 — Diff is purely mechanical.** Allowed: import reorderings, package renames, type-alias updates, generated-import changes from a tooling pass, single-line interface-name updates that follow a rename in the migrated module. Forbidden: any logic change, any conditional change, any side-effect addition or removal, any signature change. Logic changes → `SCOPE_CREEP` (MAJOR), or, if the change introduces or modifies behaviour, `PARITY_DRIFT` (BLOCKER).
- [ ] **N2 — No accidental refactor or cleanup.** Trim-trailing-whitespace, format-on-save, "while I'm here" lint fixes, unused-import removals that were not strictly required by the migration → `SCOPE_CREEP` (MAJOR).
- [ ] **N3 — No silent rename.** Symbol or file renames must be part of the migration intent (visible from the migrated counterpart). Otherwise → `SILENT_RENAME` (MAJOR).
- [ ] **N4 — No new comments / docstrings introduced.** Same as M10.
- [ ] **N5 — File-reference format correct.** Same as M13.
- [ ] **N6 — Final-status verdict assigned.** Same as M14.

## `baseline` checklist

For files matching the baseline-asset patterns in `classification_protocol.md`.

- [ ] **B1 — File is unchanged.** Run `git diff <base_sha>..<head_sha> -- <path>` — output must be empty. Any change → `BASELINE_VIOLATION` (BLOCKER). There is no other check; the moment a baseline asset has any modification, the verdict is decided.
- [ ] **B2 — Final-status verdict assigned.** Same as M14.

## `build_config` checklist

For Gradle, version-catalog, Podfile, and Package.swift files.

- [ ] **C1 — No new dependency added without a live source.** Look at every line starting with `+` in the diff that adds a `implementation`, `api`, `testImplementation`, `commonMainImplementation`, `androidMainImplementation`, `iosMainImplementation`, `pod`, or version-catalog entry. For each, the PR must contain a justification in either the PR body OR a comment that cites a context7 / WebSearch result (Law 6). No source → `DEP_ADDITION` (MAJOR).
- [ ] **C2 — Existing dependency removals do not break unmigrated callers.** If the diff removes a dependency that other files in the diff still reference, → `DEP_ADDITION` (MAJOR — wrong category but the closest match; the reviewer flags both removal and the broken caller). For maximum clarity, emit two findings: one `DEP_ADDITION` for the removal, one with a clear description naming the broken caller.
- [ ] **C3 — Version bumps are justified.** Any version change to an existing dependency must have a live-sourced justification (security advisory, KMP-compat requirement, etc.). No source → `DEP_ADDITION` (MAJOR — flag as version-bump variant in description).
- [ ] **C4 — No mixed-source-set dependency leaks.** A `commonMainImplementation` that pulls in an Android-only artifact is a `PLATFORM_LEAK` (BLOCKER).
- [ ] **C5 — KMP plugin / target / source-set configuration changes are minimal.** If the diff modifies `kotlin { ... }`, `sourceSets { ... }`, or `targets { ... }` blocks, every change must trace to either (a) adding a target the migration explicitly extends to, or (b) wiring a source set that the migration introduces. Out-of-scope target additions → `SCOPE_CREEP` (MAJOR).
- [ ] **C6 — No baseline-test runner config silently changed.** If the diff modifies test runner blocks (`paparazzi { ... }`, `roborazzi { ... }`, snapshot tolerance constants, golden-record flags), the change is treated as a `BASELINE_VIOLATION` (BLOCKER) unless an explicit baseline-rebase rationale is in the PR body.
- [ ] **C7 — Final-status verdict assigned.** Same as M14.
