<!-- TEMPLATE: copied to <repo>/kmm/<scope>/architecture.md by the architect phase -->
<!-- The architect produces this from a clean-code reading of every in-scope file. -->
<!-- This file is the gate to the plan phase: no plan runs without a reviewer-approved architecture.md. -->

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
  - `[file:line]` `[observation, e.g., "AuthSdkHolder wraps AuthSdk with no added behaviour"]` `§structure.no-scaffolding-without-behaviour`
  - `[file:line]` `[observation]` `§<reference>`
  - [one bullet per concern; if `path: surgical`, may be empty or list "no concerns"]
- **Refactors** (only when `path: refactor`):

  #### R-1: [one-line title]

  - **Clean-code violation:** `§<reference>` (from `references/clean-code.md`)
  - **Source citation:** `[file:line range]`
  - **Target shape:** [concrete description — names, member shape, surrounding context. Pseudocode block if necessary.]

    ```kotlin
    // Before (master)
    class AuthSdkHolder(val sdk: AuthSdk) {
        fun get() = sdk
    }

    // After
    // (no holder — consumers reference AuthSdk directly)
    ```
  - **Boundary:** [the file or contiguous block being refactored. MUST stay inside this in-scope file.]
  - **Behaviour-preservation invariant:** [the externally-observable behaviour that must remain identical, expressed as one or more test invariants. Example: "for any caller, replacing `holder.get().login(creds)` with `sdk.login(creds)` produces the same `AuthResult`."]
  - **Test that pins this invariant:** `test_[name]` in the file's `Expected tests` list (must exist in `migration-guide.md`).
  - **Risk:** `LOW` | `MEDIUM` | `HIGH`
  - **User approval:** [for HIGH-risk only — record date and explicit approval]

  #### R-2: [next refactor on this file]

  ...

- **Out-of-reach tech debt** (only if relevant):
  - `[file:line]` `[observation]` — [why out of reach: e.g., "would require pulling `LegacyAuthBridge` into scope; deferred."]

### [FileNameTwo].kt

[same structure]

---

## Cross-file architecture

### Module boundaries

[Does the in-scope unit factor into sub-units in the migrated form? If yes, name each sub-unit and list its files.]

- **`<sub-unit-1>`** — files: `<list>`. Responsibility: [one line, domain language].
- **`<sub-unit-2>`** — files: `<list>`. Responsibility: [one line].

[If the unit is a single module: write "Single module — no sub-unit split."]

### Layering

[Compare source DAG to target DAG. If target differs, list each cross-file relayering as a numbered cross-file refactor with the same six fields as a per-file Refactor.]

- Source DAG (level by level): [text-art]
- Target DAG (level by level): [text-art]
- Cross-file changes (if any): [numbered list]

### Naming model

[If the cross-file architecture renames public types, document the model: which classes/interfaces are renamed, what the domain word is, and why.]

- `[OldName]` → `[NewName]` — domain word: `[word]`. Justification: `§naming.intent-over-mechanism`.
- ...

[If no cross-file renames: write "Source naming preserved."]

### Boundary mechanism per platform-bound dependency

[For each external dependency without a multiplatform replacement, decide the level (Constitution platform-boundary §1–3) and record here. plan-phase operationalises but does not re-decide.]

- `[dependency]` — level: 1 (multiplatform library) / 2 (expect/actual) / 3 (interface + DI). Choice: `[concrete: e.g., "Ktor Client v3.0.3"]`. Justification: [one line].

---

## Behaviour-preservation strategy

[For every Refactor entry above, list the behaviour invariant it must preserve and the baseline test that pins it. The test-capturer will use this list to write tests in commonTest.]

| Refactor | File | Invariant | Test name |
|---|---|---|---|
| R-1 | `<file>` | `<one-line invariant>` | `test_<name>` |
| R-2 | ... | ... | ... |

[If `path: surgical` for every file: write "No refactors — behaviour preservation is automatic via 1:1 port."]

---

## Checkpoint plan

[From the architect phase Step 6. List the sequence of master-mergeable checkpoints. Each checkpoint declares: name, goal, files included, kind of work, expected diff size.]

### CP-1: [name]

- **Goal:** [one-line goal — e.g., "relocate auth files into androidMain and capture commonTest baselines"]
- **Kind:** relocation | swaps | refactor | mixed
- **Files included:** [list]
- **Expected diff size:** [one line — e.g., "5 files moved, 35 tests added"]
- **Master-mergeable:** [yes — [why it's safe to merge in isolation, e.g., "no API change, no library swap, only file relocation"]]

### CP-2: [name]

[same structure]

[If the user picked single-PR at architect-time: only one checkpoint here, named `<scope>`, with all files.]

### Stacking strategy

`stack` (each checkpoint's branch is from the previous) | `unstacked` (each from base; serial merge required)

Default: `stack`. Recorded at architect-time per user choice.

---

## Open questions

[Any decision the user owes before plan-phase. Should be empty after the architect phase Step 5; if not, that's the bug — re-run Step 5.]

[If empty, write "None — architecture is self-contained."]

---

## Constitution check

[populated by the architect phase after architecture-reviewer returns clean]

- §1 Architecture before code: this file exists and is reviewer-approved — [pass/fail]
- §6 Refactor stays in scope: every refactor's boundary is inside its file — [pass/fail]
- §7 Clean-code first: every file has a `path` declaration; every refactor cites a clean-code violation — [pass/fail]
- §13 Checkpoint plan: recorded — [pass/fail]
- Public API preservation: every file's public API is unchanged by its architecture decision — [pass/fail]

`ARCHITECTURE_STATUS: APPROVED` (after user signs off)
