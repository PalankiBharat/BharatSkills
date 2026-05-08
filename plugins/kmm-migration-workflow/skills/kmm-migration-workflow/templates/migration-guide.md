<!-- TEMPLATE: copied to <repo>/kmm/<scope>/migration-guide.md by /kmm-plan -->
<!-- One entry per in-scope file. Lean field set — Callbacks/Serialization only when the file actually has them. -->

# Migration guide — [scope-name]

This file is the contract subagents read during execution. After `/clear`, this is the source of truth for per-file specs — not the conversation.

Every claim in every entry cites `file:line`. "TBD", "if needed", "as appropriate" are rejected by the plan-analyzer.

---

## [FileName].kt

- **Source:** `app/src/main/java/[package]/[FileName].kt`
- **Target:** `shared/src/commonMain/kotlin/[package]/[FileName].kt`
- **Classification:** `migrate-pure` | `migrate-expect-actual` | `delete`
- **Public API** (verbatim from source):
  - `[modifier] fun [name]([param: Type], ...): [ReturnType]`
  - `[modifier] val [name]: [Type]`
  - ...
- **Library swaps:**
  - `[oldLibrary.Class<T>]` → `[newLibrary.Class<T>] v[X.Y.Z]` (verified `[ISO date]`, source `[URL or context7-id]`)
  - ...
  - [if none, write "none"]
- **Platform APIs** (Android/JVM-only APIs in this file with their verified replacements):
  - `[file:line]` `[android API used]` → `[multiplatform replacement; library version verified live]`
  - ...
  - [if none, write "none"]
- **expect/actual:**
  - [each declaration: `expect class Foo` / `expect fun bar()` etc., with the boundary level (1: lib swap; 2: expect/actual; 3: interface+DI) and a one-line justification]
  - [if none, write "none"]
- **Migrate after:** `[FileX].kt, [FileY].kt` | `none`
- **Consumers** (files outside scope whose imports must update):
  - `[ConsumerA].kt` (currently imports `[old path]`; after migration imports `[new path]`)
  - ...
- **Consumer-import policy:**
  - **Same-package case (no import changes needed):** if the file's Kotlin package is unchanged from `app/...` to `commonMain/...` (e.g., `com.example.foo` → `com.example.foo`) AND the consumer module already declares `implementation(project(":shared"))`, then NO consumer import changes are required at the source level. The fully-qualified type name is identical; Kotlin/JVM resolves it via the new module dependency. The migrator's job in this case is only the `git mv` plus build verification.
  - **Different-package case (imports must update):** if the package changes (e.g., the migration restructures namespaces), every consumer's `import` statements must be updated to match the new path.
  - Detect at /kmm-plan time: compare the package declaration in the source file against the package implied by the target path. If they match — same-package case applies; populate this field as `(no import changes — package preserved + :app already depends on :shared)` and skip the import-update task in /kmm-implement.
- **Expected tests:** `[N]` minimum.
  - `test_[methodA]_happy_path`
  - `test_[methodA]_error_when_<condition>`
  - `test_[methodA]_edge_case_<boundary>`
  - `test_[methodB]_initial_state`
  - `test_[methodB]_state_transition_on_<event>`
  - ... [explicit list — at least one per public method, plus error paths and edge cases]
- **Rules** (file-specific constraints; override defaults):
  - DO NOT [combine method X and Y; widen visibility of Z; etc.]
  - [if none, write "none"]
- **Diff specification** (REQUIRED — the migrator's contract; lines not listed here are byte-identical to master):

  ```
  master: <source path>@<baseline-master-sha>
  fetch: git show <baseline-master-sha>:<source-path>

  Remove master:<line N>  `<exact line content from master>`
    → swap: <citation>

  Add after master:<line N> (or "Add to imports block"):
    `<exact line to add>`
    → swap: <citation>

  Modify master:<line N>:
    master:    `<exact master line>`
    migrated:  `<exact migrated line>`
    → swap: <citation>; preserve <name>/<shape>/<position>

  Lines <range>: unchanged (verbatim from master).
  ```

  **Rules for the spec:**
  - Every `Remove`/`Add`/`Modify` line cites a swap from the `Library swaps` or `Platform APIs` field above. No orphan edits.
  - Variable names, parameter names, member names, and visibility from master are PRESERVED unless the name literally encodes the swapped library's name as a token. Bare names STAY.
  - Whitespace, blank lines, brace style, and member order are PRESERVED. Adding constructor params can mechanically force `:` spacing changes — record those as part of the relevant Modify entry.
  - Lines not in the spec are guaranteed byte-identical to master; the migrator may not touch them.
  - At plan time, walk master line-by-line. For each line: either it's unchanged (default; goes into a "Lines X–Y unchanged" range) or it's listed with a swap citation. Every line is accounted for.

### Optional fields (include only when the file has them)

- **Callbacks:** [for files with callback / lambda parameters that consumers wire actions into]
  - `[file:line]` `[callbackName: (Args) -> Unit]` in `[methodName]` → wired by `[ConsumerFile].[handler]`
  - ...
- **Serialization:** [for files that touch JSON]
  - `[file:line]` field `[server name]` ↔ Kotlin `[name]: [type]` `[@SerialName(...)]`, nullable: `[yes/no]`, default: `[value]`
  - ...

---

## [FileNameTwo].kt

[same structure, repeat for every in-scope file]

---

[Add new file entries below. Keep entries in dependency order — files with no in-scope deps first, then their dependents.]
