<!-- TEMPLATE: copied to <repo>/kmm/<scope>/architecture.md by the architect phase -->

# Migration architecture — [scope-name]

## Goal

[one paragraph: the user's stated goal verbatim from spec.md, plus a one-line statement of the target architecture: "the migrated unit will be structured as <module-shape> with <key-pattern>; tech debt addressed: <list>."]

## Constitution version

This architecture is governed by `kmm-migration-workflow/constitution.md` v[VERSION] as of [DATE].

## Per-file architecture

[one entry per in-scope file]

### [FileName].kt

- **Source:** `app/src/main/java/[package]/[FileName].kt`
- **Path:** `surgical` | `refactor` | `out-of-reach`
- **Intent (one sentence, domain language):** [e.g., "holds a user's authenticated session and refreshes it on demand"]
- **Shape concerns** (`file:line` — observation — `§reference`):
  - `[file:line]` `[observation]` `§<reference from constitution §7>`
  - [if `path: surgical`, may be empty or "no concerns"]
- **Refactors** (only when `path: refactor`):

  #### R-1: [one-line title]

  - **Clean-code violation:** `§<reference>` (e.g., `§structure.no-scaffolding-without-behaviour`)
  - **Source citation:** `[file:line range]`
  - **Target shape:** [concrete description — names, member shape. Pseudocode block when helpful: `// Before` master block, `// After` migrated block.]
  - **Boundary:** [the file or contiguous block being refactored. MUST stay inside this in-scope file.]
  - **Behaviour-preservation invariant:** [the externally-observable behaviour that must remain identical, expressed as a test invariant.]
  - **Test that pins this invariant:** `test_[name]` (must exist in `migration-guide.md` Expected tests)
  - **Risk:** `LOW` | `MEDIUM` | `HIGH`
  - **User approval:** [for HIGH-risk only — record date and explicit approval]

  #### R-2: ...

- **Out-of-reach tech debt** (only if relevant):
  - `[file:line]` `[observation]` — [why out of reach: e.g., "would require pulling LegacyAuthBridge into scope; deferred."]

### [FileNameTwo].kt

[same structure]

---

## Cross-file architecture

### Module boundaries

- **`<sub-unit>`** — files: `<list>`. Responsibility: [one line, domain language].

[If single module: "Single module — no sub-unit split."]

### Layering

- Source DAG (level by level): [text-art]
- Target DAG (level by level): [text-art]
- Cross-file changes (if any): [numbered list]

### Naming model

- `[OldName]` → `[NewName]` — domain word: `[word]`. Justification: `§naming.intent-over-mechanism`.

[If no renames: "Source naming preserved."]

### Boundary mechanism per platform-bound dependency

- `[dependency]` — level: 1 (multiplatform library) / 2 (expect/actual) / 3 (interface + DI). Choice: `[concrete]`. Justification: [one line].

---

## Behaviour-preservation strategy

| Refactor | File | Invariant | Test name |
|---|---|---|---|
| R-1 | `<file>` | `<one-line invariant>` | `test_<name>` |

[If `path: surgical` for every file: "No refactors — behaviour preservation is automatic via 1:1 port."]

---

## Smoke test

Per Constitution Verification §8 — runtime gate before any checkpoint merges. The JVM variant is mandatory; the instrumented variant is opt-in per scope.

### JVM smoke (mandatory)

- **Test class FQN:** `<consumer.package>.<scope>SmokeTest`
- **Test source set:** `:<consumer-module>/src/test/kotlin/<consumer.package>/<scope>SmokeTest.kt`
- **Gradle task:** `./gradlew :<consumer-module>:test --tests "<consumer.package>.<scope>SmokeTest"`
- **Types to resolve from DI** (one entry per migrated public type whose runtime wiring matters):
  - `<package>.<TypeA>` — happy-path call: `instance.<methodA>(<argA>)`
  - `<package>.<TypeB>` — happy-path call: `instance.<methodB>()`
- **DI bootstrap:** [name of the Koin/DI module(s) the test loads, e.g., `appModule`, `<scope>Module`]

### Instrumented smoke (opt-in)

[Set to `none` if not used. Use when the migrated feature has Android-platform-specific runtime behaviour the JVM smoke can't exercise (e.g., Context-bound init, Android-only crypto provider).]

- **Status:** `enabled` | `none`
- **Test class FQN:** `<consumer.package>.<scope>InstrumentedSmokeTest`
- **Test source set:** `:<consumer-module>/src/androidTest/kotlin/...`
- **Gradle task:** `./gradlew :<consumer-module>:connectedDebugAndroidTest --tests "<fqn>"`

---

## Checkpoint plan

### CP-1: [name]

- **Goal:** [one-line goal]
- **Kind:** relocation | swaps | refactor | mixed
- **Files included:** [list]
- **Expected diff size:** [one line]
- **Master-mergeable:** yes — [why it's safe to merge in isolation]

### CP-2: [name]

[same]

[If single-PR mode: only one checkpoint, named `<scope>`, with all files.]

### Stacking strategy

`stack` (each checkpoint's branch is from the previous) | `unstacked` (each from base; serial merge required)

Default: `stack`.

---

## Open questions

[Should be empty after architect-phase Step 4. If empty: "None — architecture is self-contained."]

---

## Constitution check

- §1 Architecture before code: this file exists and is reviewer-approved — [pass/fail]
- §6 Refactor stays in scope: every refactor's boundary is inside its file — [pass/fail]
- §7 Clean-code first: every file has a `path` declaration; every refactor cites a clean-code violation — [pass/fail]
- §13 Checkpoint plan: recorded — [pass/fail]
- Verification §8 Smoke test: JVM smoke spec declared (types + methods + Koin module); instrumented opt-in resolved — [pass/fail]
- Public API preservation: every file's public API is unchanged — [pass/fail]

`ARCHITECTURE_STATUS: APPROVED` (after user signs off)
