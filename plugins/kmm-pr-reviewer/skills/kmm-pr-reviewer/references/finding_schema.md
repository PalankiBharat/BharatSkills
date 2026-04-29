# Finding Schema

> Every finding emitted by a per-file reviewer or surviving the triager
> uses this exact shape. The approval presenter and the comment poster
> both parse this format.

## Contents

- [Severity levels](#severity-levels)
- [Categories](#categories)
- [Markdown shape](#markdown-shape)
- [Required fields](#required-fields)
- [Examples](#examples)

## Severity levels

| Level | Meaning | Posting behaviour |
|---|---|---|
| `BLOCKER` | The PR cannot merge as-is — there is a parity break, missing logic, scope violation, or baseline mod. | If any approved finding is BLOCKER, the GitHub review is posted with `event: REQUEST_CHANGES`. |
| `MAJOR` | Real regression risk or significant code-quality issue, but not a hard merge blocker. | Posted as `event: COMMENT` (unless a BLOCKER is also approved). |
| `MINOR` | Small parity or quality issue worth flagging but not load-bearing. | `event: COMMENT`. |
| `NIT` | Nit-pick — naming, formatting, defensive comment removal. May not warrant an inline comment; can fold into the summary. | `event: COMMENT`. |

The triager re-classifies severity after dedup. Per-file reviewers may emit any severity; their classification is a starting point.

## Categories

Each finding has exactly one category:

| Category | When to use | Severity floor |
|---|---|---|
| `MISSING_LOGIC` | A branch, side-effect, log line, analytics call, default value, or null-check on master is absent in the port. | BLOCKER |
| `PARITY_DRIFT` | Logic exists on both sides but produces different observable behaviour (different default, swapped order, changed return). | BLOCKER |
| `API_DRIFT` | Public signature changed (name, params, return type, modifiers, visibility). | BLOCKER |
| `UI_DRIFT` | String resource, dimen, color, drawable, or accessibility metadata changed without baseline rebase. | MAJOR |
| `SCOPE_CREEP` | A file outside the migration target was modified with non-mechanical edits. | MAJOR |
| `DEP_ADDITION` | A new dependency was added without a live-sourced justification. | MAJOR |
| `PLATFORM_LEAK` | An Android SDK type (`Context`, `View`, `android.*`) appears in `commonMain`. | BLOCKER |
| `INTEROP_PATTERN_VIOLATION` | `expect/actual` and `interface + DI` are mixed for the same entity, or an improvised pattern is used. | MAJOR |
| `BASELINE_VIOLATION` | A baseline artifact was modified (PNG, WebP, golden JSON, tolerance constant). | BLOCKER |
| `STUB_LEFTOVER` | A `TODO`, `FIXME`, `XXX`, or stub function was introduced. | MINOR |
| `SILENT_RENAME` | A file or symbol was renamed without the rename being part of the migration intent. | MAJOR |
| `BUILD_OUTPUT_LEAKED` | A path under `build/`, `.gradle/`, or `generated/` appears in the diff. | BLOCKER |
| `IOS_CONTRACT_MISMATCH` | An `iosMain` actual does not match the corresponding `commonMain` `expect` signature. | BLOCKER |
| `IOS_TYPE_LEAK` | `iosMain` exposes UIKit/Foundation types into Swift consumers in a way that breaks the documented interop pattern. | MAJOR |
| `CLEAN_CODE` | Naming, function size, abstraction-level, or formatting issue. | MINOR or NIT |
| `RULE_06_VIOLATION` | A claim in the PR body, comments, or code asserts a KMP fact without a live source. | MINOR |
| `SPECULATIVE_CODE` | A new utility, flag, or abstraction was added that has no caller in the diff. | MAJOR |
| `UNTESTED_DELTA` | An accepted-delta is documented but no test on the migrated side covers it. | MINOR |

## Markdown shape

Findings live in three files in this order: `per_file/<path>.md`, `triager_report.md`, `findings_pending_approval.md`. The shape is identical in all three; the approval file additionally has a checkbox prefix.

### In `per_file/*.md` and `triager_report.md`

```markdown
### Finding F<N>
- **Severity:** BLOCKER | MAJOR | MINOR | NIT
- **Category:** <one of the categories above>
- **Path:** `<path>:<line>` at `<head_sha>`
- **Master ref:** `<master_path>:<line>` at `<base_sha>` (omit if not applicable)
- **Diff excerpt:**
  ```diff
  <verbatim git diff -U3 chunk that contains the finding>
  ```
- **Description:** <one-paragraph factual description of the gap>
- **Suggested fix:** <one-line suggested fix if obvious; omit if not>
```

### In `findings_pending_approval.md`

```markdown
- [x] **<SEVERITY> · <CATEGORY>** · `<path>:<line>`
  > <finding body — this is the proposed comment text the user will edit>
  >
  > **Suggested fix:** <one-line suggested fix>
```

The user edits this file in place: untick `[x]` to drop, edit the blockquote to change the proposed comment text, delete the entire bullet to remove from the run.

## Required fields

A finding without all of the following is rejected by the triager:

- Severity (one of the four levels).
- Category (one of the listed categories).
- Path with `:line` suffix at `head_sha`.
- For categories `MISSING_LOGIC`, `PARITY_DRIFT`, `API_DRIFT`, `IOS_CONTRACT_MISMATCH`: a master-ref `path:line` at `base_sha`.
- Diff excerpt (verbatim).
- Description (one paragraph, no editorialising — Law 10).

The suggested-fix line is optional. If the fix is non-obvious, omit it rather than guess.

## Examples

### MISSING_LOGIC (BLOCKER)

```markdown
### Finding F3
- **Severity:** BLOCKER
- **Category:** MISSING_LOGIC
- **Path:** `shared/src/commonMain/kotlin/com/app/login/LoginViewModel.kt:42` at `head_sha=a1b2c3d`
- **Master ref:** `app/src/main/java/com/app/login/LoginViewModel.kt:38` at `base_sha=def456`
- **Diff excerpt:**
  ```diff
  -        analytics.track("login_attempt", mapOf("source" to source))
           val result = repository.login(credentials)
  ```
- **Description:** The master version dispatches an analytics event `login_attempt` immediately before the network call. The port omits this dispatch. The side-effect is silently dropped.
- **Suggested fix:** Add `analytics.track("login_attempt", mapOf("source" to source))` before `repository.login(credentials)`.
```

### PLATFORM_LEAK (BLOCKER)

```markdown
### Finding F7
- **Severity:** BLOCKER
- **Category:** PLATFORM_LEAK
- **Path:** `shared/src/commonMain/kotlin/com/app/session/SessionStore.kt:7` at `head_sha=a1b2c3d`
- **Diff excerpt:**
  ```diff
  +import android.content.SharedPreferences
  ```
- **Description:** `commonMain` imports `android.content.SharedPreferences`. Android SDK types are forbidden in shared code; the correct pattern is an `expect class` or an injected interface with platform-specific implementations.
- **Suggested fix:** Replace with an `expect class KeyValueStore` declared in `commonMain` and `actual` implementations in `androidMain` (SharedPreferences) and `iosMain` (NSUserDefaults).
```

### BASELINE_VIOLATION (BLOCKER)

```markdown
### Finding F1
- **Severity:** BLOCKER
- **Category:** BASELINE_VIOLATION
- **Path:** `shared/src/androidUnitTest/snapshots/LoginScreenLight.png` at `head_sha=a1b2c3d`
- **Diff excerpt:**
  ```diff
  Binary files differ
  ```
- **Description:** A baseline screenshot golden has been re-recorded as part of this PR. Per Law 9, baseline artifacts are immutable mid-migration; pixel-rendering changes must be addressed by fixing the migration to match the baseline, not by re-recording the baseline. If the migration genuinely changes intended UX, the change must go through a separate `escape_hatch_rebase_baseline` operation with explicit user approval.
- **Suggested fix:** Revert the snapshot to the master version. If the migration intentionally changes UX, raise a separate baseline-rebase request with the rationale and a live source.
```
