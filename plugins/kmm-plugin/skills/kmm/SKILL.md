---
name: kmm
description: >
  KMM migration expert. ALWAYS invoke for KMM migrations, Swift/iOS screens, SKIE interop,
  KMM audits, module setup, deps, debug flows, or bugfixes. Do not attempt these directly — use this skill first.
argument-hint: "[migrate|assess|swift-screen|interop|audit|setup|deps|debug|bugfix] [path]"
---

## Quick Start

- **Migrating a file?** → `/kmm migrate <file-path>`
- **Writing an iOS screen?** → `/kmm swift-screen <android-screen-path>`
- **Planning a whole module?** → Use `/kmm-workflow` instead
- **Debugging a flow?** → `/kmm debug <feature-name>`
- **All subcommands:** migrate, assess, swift-screen, interop, audit, setup, deps, debug, bugfix

## Reference Files

- `references/migration-workflow.md` — 10-step TDD migration workflow
- `references/android-to-swiftui.md` — Component mapping guide (Compose/XML → SwiftUI)
- `references/skie-interop.md` — Swift/SKIE interop patterns
- `references/audit-checklist.md` — Anti-pattern checklist by severity
- `references/battle-tested-gotchas.md` — Known production gotchas
- `references/dependency-map.md` — Android → KMM library replacements
- `references/kmm-patterns.md` — KMM patterns quick-reference

## Core Principles

You encode battle-tested patterns from real migrations — not theoretical advice.

These three non-negotiable principles govern ALL sub-workflows. Violating any of them is a
failure, regardless of whether the build passes.

### 1. TDD Migration — Tests Prove Behavioral Parity

- Write characterization tests FIRST against Android (source) code in `commonTest`
- Stage Android code in `androidMain` so `commonTest` can target it
- Tests define the behavioral contract. Green baseline = tests are correct
- Migrate code to `commonMain`. Same tests must pass
- If tests fail after migration → **fix the migration, NEVER the tests**
- Tests only change if the API surface itself genuinely changes (e.g., callback → suspend).
  In that case: adapt the test call-site but assert identical behavioral outcomes.
  Document with `// API-CHANGE: <reason>` comment
- **NEVER** modify tests to fake a pass
- **NEVER** add stubs, `@Ignore`, `@Suppress`, or suppress tests to make them green
- Hard pass only. Tests are the proof that business logic survived migration intact

### 2. Android = Source of Truth — Replicate, Don't Improve

- The job is migration, not improvement. Zero behavioral changes. Zero UI changes
- Clean code formatting is acceptable (consistent naming, removing dead code)
- Logic and UI structure remain 100% untouched
- If Android code has a bug, migrate the bug. Report it separately
- No "I think this is better" changes. No "while we're here" refactors
- **API signature parity:** Migrated KMM code must have identical method signatures — same
  method names, parameter names, parameter order, return types. The Android API surface IS
  the KMM API surface. Android app is in production — matching signatures means Android-side
  wiring after migration is minimal (just swap import path and DI provider), no method renames,
  no parameter changes. Less change on Android = less risk to prod
- **Signature mismatch in existing KMM code:** If a KMM version exists but has different API
  signatures than Android, update the KMM signatures to match Android. Android is prod, Android wins
- **Rewrite over patch (80% rule):** If a KMM file exists but is less than ~80% in parity
  with Android source (different signatures, missing methods, divergent logic), rewrite from
  scratch based on Android source of truth. Wire both platforms, run TDD tests, clean up old files

**Audit scope vs migration scope:** Core Principle 2 (migrate bugs as-is) applies during `/kmm migrate` — the goal is behavioral parity, not improvement. `/kmm audit` operates separately — it finds KMM-specific anti-patterns (runBlocking on main, leaked scopes, type casting) that are NEW issues introduced by or specific to the multiplatform context, not bugs that existed in the Android source.

### 3. Honest Verification — Escalate, Don't Fake

- If a build fails and you can't determine the cause → STOP
- Present to user: problem → possible solutions with pros/cons → your recommendation as
  KMM expert → why
- If the decision is obvious and assessable from the codebase, take it and move on
- If it requires judgment → escalate to user
- **NEVER** fix builds "just to pass" verification
- **NEVER** suppress errors, skip tests, or add no-op stubs
- **NEVER** use `--no-verify`, `@Suppress`, `@Ignore`, or equivalent to bypass failures

---

## Context-First Rule

Before touching ANY code in any sub-workflow:

1. Read the target file AND all files it depends on (imports, interfaces, base classes)
2. Read all files that consume/call the target (who uses this? how? what will break?)
3. Understand the dependency chain: what does this file need? what needs this file?
4. Understand the behavioral contract: what does this code do? edge cases? invariants?
5. If anything is unclear or ambiguous → ask the user before proceeding
6. Only start modifying code when you have full understanding of ins and outs

Modifying code with partial context leads to broken callers, missed edge cases, and subtle
regressions. Understanding everything first means changes are precise and complete.

---

## Subcommands

### `/kmm migrate <file-or-directory>`

Migrate Android-only Kotlin code to KMM commonMain with full behavioral parity.

**References:** `references/migration-workflow.md`, `references/kmm-patterns.md`, `references/dependency-map.md`

**Workflow — copy and track:**

- [ ] Read target file AND all files it depends on (imports, interfaces, base classes)
- [ ] Read all consumers of the target (who calls this? what will break?)
- [ ] Check if a KMM version already exists in `:shared`
  - ≥80% parity with Android → patch it
  - <80% parity → rewrite from scratch based on Android source
- [ ] Stage Android code in `androidMain` so `commonTest` can target it
- [ ] Write characterization tests in `commonTest` against the staged Android code
- [ ] **Baseline** — run tests: green = tests are correct; if red, fix tests before continuing
- [ ] Migrate code to `commonMain` + apply dependency swaps (reference `dependency-map.md`)
- [ ] **Re-test** — run tests: if red, fix the migration NEVER the tests
- [ ] Wire both platforms (Android + iOS consume shared code) + delete old Android-only copy
- [ ] Run `/kmm audit` on migrated code
- [ ] **Build verify** — Gradle + shared framework + iOS (3 platforms must pass)

If blocked at any step → STOP, escalate to user: problem → options with pros/cons → recommendation → why.

---

### `/kmm assess <module-path-or-feature-name>`

Assess a module for KMM migration — discover files, classify, map dependencies, determine order.

**References:** `references/dependency-map.md`

**Workflow — copy and track:**

- [ ] **Find anchors** — grep for obvious directories and files matching the feature name
  - Ask user: "Are these the right starting points? Any other names for this feature?"
  - (e.g., "login" code may also live under "account", "auth", "otp", "biometric")
- [ ] **Crawl imports recursively** — from every anchor file, follow imports
  - Before adding a file, check its fanout: how many other features import it?
    - Fanout ≤ 2 → feature-specific → add to list
    - Fanout ≥ 3 → shared infrastructure → stop, flag as external dep
  - This naturally finds files in "wrong" directories without alias guessing
- [ ] **Reverse grep** — for every discovered file, grep who imports it from outside the set
  - These are consumers (Router, DI modules, etc.) that need updating after migration
- [ ] **Cross-module check** — check `:shared/commonMain`, `:shared/iosMain`, `:shared/androidMain`
  for already-migrated versions; compare parity (≥80% patch, <80% rewrite)
- [ ] **Present → Confirm → Verify** — show complete file list grouped by layer; user confirms
  - Verify: every confirmed file's feature-specific deps are in the list, no feature-named
    files silently excluded, DI provides nothing missing from list
- [ ] **Classify** each discovered file:
  - `migrate-pure` — pure Kotlin, no Android deps (data classes, interfaces, pure logic)
  - `migrate-swap` — needs library replacement (Retrofit → Ktor, etc.; reference `dependency-map.md`)
  - `migrate-expect-actual` — needs expect/actual pattern (platform-specific behavior)
  - `platform-stay` — stays on Android (Activities, Fragments, Compose UI, XML layouts);
    if a screen, note as `/kmm swift-screen` reference in iOS Screen Work section
  - `wire-only` — DI modules, navigation — rewiring only, not migration
- [ ] Map internal dependencies between discovered files
- [ ] Map external dependencies — flag any not in KMM/commonMain as blockers
- [ ] List consumers (from reverse grep) that need import updates after migration
- [ ] Determine migration order — bottom-up by dependency
- [ ] Identify library replacements — cross-reference against `dependency-map.md`
- [ ] Identify risks — platform APIs, circular deps, external blockers
- [ ] Completeness check — classified count = discovered count, no gaps
- [ ] Write ASSESSMENT.md — Summary, Migration Phases, Library Replacements, iOS Screen Work,
  DI Rewiring, External Deps, Consumers, Risks, Completeness Check, Files Excluded
- [ ] User confirms assessment before any migration begins

---

### `/kmm swift-screen <android-screen-path>`

Write a SwiftUI screen from any Android screen reference with 100% fidelity.

**References:** `references/android-to-swiftui.md`, `references/skie-interop.md`

**Workflow — copy and track:**

- [ ] Read the Android screen fully (Compose, Fragment+XML, Activity+XML, or mixed)
- [ ] Read `references/android-to-swiftui.md` — component mapping guide
- [ ] Read `references/skie-interop.md` — Swift/SKIE patterns for state and effects
- [ ] Map every component to its SwiftUI equivalent
  - Match layout structure exactly (list vs grid, spacing, colors, typography, padding values)
  - Match variable and function names
  - If Android has 16dp padding, Swift has 16pt padding
  - No auto-improvements. No "I think this looks better" changes
  - Only adapt platform idioms (NavigationStack vs NavHost)
- [ ] Wire state and effects — use `for await` in `.task` blocks
- [ ] Replicate every conditional UI branch — empty state, error state, loading skeleton,
  permission denied, etc. — not just the happy path
- [ ] Wire navigation via Router + RootView — same destinations triggered by the same user actions
- [ ] Register new `.swift` files in `project.pbxproj`
- [ ] **Build verify** — xcodebuild must pass

If blocked at any step → STOP, escalate to user: problem → options with pros/cons → recommendation → why.

---

### `/kmm interop`

Reference guide for consuming KMM code from Swift via SKIE.

**Workflow — conditional:**

1. Receive question about SKIE/Swift interop pattern
2. Read `references/skie-interop.md`
3. If question is covered by the reference:
   - Provide the correct pattern + working code example
4. If question is NOT covered:
   - Fetch latest SKIE docs via Context7 (`resolve-library-id` → `query-docs`)
   - Provide correct pattern + working code example

---

### `/kmm audit <path>`

Audit KMM code for anti-patterns, auto-fix, and re-verify builds.

**References:** `references/audit-checklist.md`, `references/battle-tested-gotchas.md`

**Workflow — copy and track:**

- [ ] Read `references/audit-checklist.md` — full anti-pattern list by severity
- [ ] Read `references/battle-tested-gotchas.md` — known production gotchas
- [ ] Scan every file in the target path against every checklist item
- [ ] Categorize all findings by severity (CRITICAL / HIGH / MEDIUM / LOW)
- [ ] Auto-fix everything that can be safely fixed without behavioral change
- [ ] **Build verify** — Gradle + shared framework + iOS must pass after auto-fixes
- [ ] Escalate any issues requiring user decision: problem → options with pros/cons → recommendation → why

---

### `/kmm setup`

Bootstrap a new KMM module from scratch.

**References:** `references/kmm-patterns.md`, `references/skie-interop.md`

**Workflow — copy and track:**

- [ ] Read `references/kmm-patterns.md` — module structure and source set patterns
- [ ] Read `references/skie-interop.md` — SKIE configuration (if SKIE is needed)
- [ ] Create module directory structure
- [ ] Configure source sets: `commonMain`, `androidMain`, `iosMain`, `commonTest`
- [ ] Configure framework export (static, correct targets)
- [ ] Configure SKIE if needed (refer to skie-interop.md for config)
- [ ] **Build verify** — Gradle build + `linkDebugFrameworkIosSimulatorArm64` must pass

---

### `/kmm deps <library-name>`

Find KMM-compatible replacement for an Android-only library.

**Workflow — conditional:**

1. Receive Android library name (e.g., "Retrofit", "Hilt", "SharedPreferences")
2. Check `references/dependency-map.md` for a known mapping
3. If library IS in the map:
   - Provide the KMM-compatible replacement
   - Provide before/after migration code example
4. If library is NOT in the map:
   - Search docs via Context7 (`resolve-library-id` → `query-docs`) or web search
   - Provide correct KMM-compatible replacement + before/after code example
   - Add the new mapping to `references/dependency-map.md`

---

### `/kmm debug <feature-or-flow>`

Add tagged debug logs to trace a flow, analyze output, fix the issue, clean up.

**Workflow — copy and track:**

- [ ] Read target file/flow; trace full execution path
  (ViewModel → UseCase → Repository → RemoteStore); identify all touch points
- [ ] Generate a unique filter tag (e.g., `[Debug-LoginFlow]`)
- [ ] Add debug log statements at key points — logs are additive only, zero logic modifications:
  - ViewModel: action received, state transitions, effect emissions
  - UseCase: method entry/exit, input params, result
  - Repository: API call params, response, errors
  - Decision points: which if/when branch was taken
  - Format: `[Debug-{Tag}] {ClassName}.{methodName}: {description} | {key=value}`
  - Platform: Napier or `println` with tag in commonMain
  - Never log sensitive data (tokens, passwords, PII) — use redacted placeholders
  - Include input params and output/result so user can trace data flow
- [ ] User runs app — reproduces the issue, filters logcat/console by tag
- [ ] User shares filtered log output
- [ ] Analyze logs — identify root cause
- [ ] Apply fix following core principles; **build verify** before asking user to test
- [ ] User confirms fix works
- [ ] Cleanup — ask user: "Issue resolved? Should I remove all `[Debug-{Tag}]` logs?"
  - On confirmation: grep for tag, remove all matching log lines
  - **Build verify** — confirm build passes after cleanup

---

### `/kmm bugfix`

Fix a bug found during manual testing and capture the learning for future migrations.

**Workflow — copy and track:**

- [ ] Read the affected code path; trace the full execution flow
- [ ] Identify root cause: what went wrong and why
- [ ] Apply fix following core principles
- [ ] **Build verify** — run platform builds to confirm fix compiles
- [ ] Capture in MANUAL_TESTING.md (if a gameplan directory exists):
  - Symptoms: what the user observed
  - Root cause: what went wrong technically
  - Fix: what was changed and why
  - Files affected: exact paths
  - Category: navigation | state | UI | data | platform-specific | timing
- [ ] Propose graduation — draft an entry for the appropriate reference file:
  - Runtime/behavioral bug → `references/battle-tested-gotchas.md`
  - New pattern discovered → `references/kmm-patterns.md`
  - Library-specific gotcha → `references/dependency-map.md`
  - Present to user: "Should this be added to [file] for future migrations?"
- [ ] If approved: add the entry to the reference file immediately

---

## Common Behavior

All subcommands follow these rules:

- **Context-first:** Gather full context before modifying anything (see Context-First Rule above)
- **Read CLAUDE.md:** Before doing work, read the project's CLAUDE.md and any existing conventions
- **Fetch on demand:** When encountering something not covered by baked-in references, fetch
  latest docs via Context7 (`resolve-library-id` → `query-docs`) or web search
- **No type casting:** Never use type casting in Kotlin (`as`, `as?`) or Swift (`as`, `as?`, `as!`) — use polymorphism, generics, protocol conformance, or `is`/`is` checks
- **Android is truth:** Replicate behavior exactly, don't improve
- **Escalate when blocked:** Present problem → solutions with pros/cons → recommendation → why.
  Take obvious decisions, escalate non-obvious ones
- **One question at a time:** Never batch multiple questions

---

## Post-flight Check

After ANY subcommand completes:
- [ ] Gradle build passes: `./gradlew :app:compileProductionDebugKotlin`
- [ ] Shared framework links: `./gradlew :shared:linkDebugFrameworkIosSimulatorArm64`
- [ ] iOS build passes (xcodebuild)
- [ ] All tests pass (no `@Ignore`, no stubs)
- [ ] No debug logs left behind
- [ ] No old Android copies remain (dead code deleted)
- [ ] API signatures match Android source exactly
