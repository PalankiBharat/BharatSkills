# Phase D — KMM-ification

**Purpose.** For files with `Phase D plan: migrate` (per Phase A's plan.md), abstract Android deps via foundation interfaces and `git mv` from `<dest>/androidMain` to `<dest>/commonMain` via surgical, compiler-driven edits. Baselines act as the equivalence contract throughout; any baseline regression mid-migration is a divergence to investigate, not a flake. **Batched by topological layer for speed; commits stay per-file for reviewability.**

Files with `Phase D plan: hold` are not touched in Phase D — they stay in `<dest>/androidMain` with frozen baselines in `<dest>/androidUnitTest`. Their promotion to `commonMain` is deferred to a future session.

**Inputs:** all prior session files (`scope.md`, `plan.md`, `audit.md`, `freeze.md` complete), `project.md`, `coverage.md`, `references/test-discipline/index.md` + relevant per-type files (for any new tests written during foundation work), `references/expect-actual-boundaries.md` (foundation seam patterns + Compose interop guidance for D.0).

---

## Phase-D deep-brief on resume (mandatory mid-phase)

When resuming Phase D mid-execution (especially mid-batch), the `resume_session.py` hook's state report is insufficient on its own — Phase D's per-batch context depends on plan.md decisions, dep order, locked substitutions, open followups, and risk areas that the lightweight hook can't synthesize.

**Mechanism.** Before entering the next batch, dispatch ONE general-purpose subagent (Sonnet) that reads in parallel: `plan.md` (decisions log + risk register + Phase D migration order), `audit.md` (last status flips + B.7 baseline output), `coverage.md` (per-file current status), `phase-d-followups.md` (open Phase D entry-point checklist), and any cached searches in `.kmm/searches/` relevant to upcoming batches. The subagent returns a structured brief — NOT raw file contents — covering:

```
## Phase D resume brief
1. Scope summary (file count, in-scope types, destination module).
2. Resolved decisions (locked library substitutions, paging version, foundation interfaces drafted at D.0).
3. Per-batch status (Batch 1: complete @SHA; Batch 2: in progress, files X/Y done; ...).
4. Next batch (files, layer, dependency direction, any cross-batch deps to watch).
5. Open phase-d-followups.md entries relevant to the next batch.
6. Risk areas from plan.md likely to surface in the next batch.
7. Cached searches available (topic → path) — to consult before deciding, not bulk-loaded.
```

**Why this matters.** Without this brief, the model improvises a recovery pattern each resume (the 400-line ad-hoc recap seen in prior sessions). Codifying the template means the brief is repeatable across users / model versions and predictable in cost (one subagent dispatch, bounded output).

This brief loads ONCE per Phase D resume; subsequent batches within the same resumed session don't re-fetch. The next phase's resume (E) does its own thing.

---

## Sub-phases

### D.0 — Foundation setup + followups review (one-time per session)

First action: **read `phase-d-followups.md`** (populated by Phase B). This is Phase D's entry-point checklist — every Path B deferral, static-service-locator deferral, or post-migration cleanup that Phase B accumulated. Skill scans the open followups and slots them into the per-batch work below: foundation interfaces (e.g., IUserQueryRepository for UserModel.getUcc replacement) land at D.0; Path B baselines land alongside their file's D.1 batch; pure cleanups land at D.2.

**Version re-check at entry (cheap drift guard).** Before any substitution work, re-confirm each locked library version still exists and fits the repo's Kotlin version (per Phase A sub-phase 1). Plans written days earlier drift; this is a `curl`/`dependencyInsight` call against a failure mode that costs hours when it surfaces mid-batch.

**Parallel-batch scope guard applies in Phase D too** (same as Phase B.4): every D.x write-subagent declares the exact file(s) it may touch and is forbidden from `.broken` renames, out-of-scope edits, and edits to build scripts / `gradle.properties` / `local.properties` / `project.md`. The orchestrator runs `git status` between waves. (A prior session had a subagent commit session state into `project.md`, bypassing the diff-confirm gate — the guard + the no-`project.md`-edit rule prevent it.)

Then proceed with per plan.md's `expect`/`actual` and DI plans. Consult `references/expect-actual-boundaries.md` for the seam-pattern rubric (semantic common APIs, thin actuals, interface-over-`expect class` when tests/DI/lifecycle matter, Compose leaf rule).

- **Opus orchestrator** finalizes the consolidation *decision* — which interfaces are shared, which collapse into one, which earn their ≥2-consumer slot. Cross-file synthesis stays on the main thread.
- **Opus subagent (one per consolidated interface)** authors the interface declaration in `commonMain`. High-stakes — every downstream consumer is shaped by this signature, so it's an Opus authoring job, never an orchestrator one. Multiple consolidated interfaces dispatch as **parallel Opus subagents** in one orchestrator turn.
- **Parallel Sonnet subagents** write the `androidMain` and `iosMain` **working `actual` impls** — two platforms = two subagents dispatched in the same turn (independent files, parallel is free). No `NotImplementedError` stubs; done-means-done applies to foundation too.
- **Sonnet subagent** sets up or extends the destination Koin module per plan.md DI plan. Covers both `commonMain` bindings (for files about to migrate) and `androidMain` bindings (for held files that stay platform-specific).
- **Pre-flight: destination module builds clean on BOTH platforms (NON-NEGOTIABLE iOS gate).** Build with all Phase B relocations + the new commonMain foundation, and run — at minimum — `:<dest>:compileKotlinMetadata`, `:<dest>:compileDebugKotlinAndroid`, **and `:<dest>:compileKotlinIosArm64`** (plus the SKIE/framework link if cheap). **The iOS klib compile is mandatory, not optional** — the single biggest time-sink across both prior sessions was a foundation that passed a JVM/Android-only pre-flight and broke iOS a full batch later (the `compileOnly javax.inject` / typealiased-`@Qualifier` thrash). **And force a cold KSP run for the iOS target: `:<dest>:kspKotlinIosArm64 --rerun-tasks`** — KSP cache reuse silently masked an `expect`-contract collapse (`AppDatabaseConstructor`) in a prior session; only a cold run caught it. ~30–60s; saves a full batch of compounded debugging.
- **Haiku subagent** runs gradle build; **Sonnet subagent** addresses any compile errors with Context7 / web-search citations (per SKILL.md Tooling discipline). Subagent failure → another subagent, never the orchestrator picking up the fix.
- Baselines green after foundation (**Haiku subagent** runs full `<dest>/androidUnitTest` suite).
- Commit foundation as a separate atomic change. SHA logged in `migration.md`. **Tick the D.0 foundation-setup task checkbox the moment this log lands** (per SKILL.md State-serialization gate) — don't leave D.0 unchecked while Status advances; that drift is supposed to be prevented at source, not caught by a Phase F resume.

### D.1 — Per-batch KMM-ification + commonMain promotion

Operates on **`migrate`-plan files only**, in plan.md's topological order (leaves first, then layers up). Files in the same layer don't depend on each other → safe to migrate together. **Build cost dominates**; batching reduces gradle invocations dramatically.

**Ordering heuristic — re-group topological batches into dependency-coupled chains when stores are static-facade-constructed.** A store built no-arg via a static facade (not DI-injected) can't migrate alone: it drags its static-facade→repository conversion *and* the consumer VMs that call the facade. Plan.md's per-file topological batches don't survive that ctor-injection coupling — re-group the implicated files into one **dependency-coupled chain** (store + facade→repo + consumer VMs migrated together) and order by chain, not by layer.

**Recon-before-chain (read-only, before authoring each chain).** Dispatch ONE read-only subagent that captures the chain's **verbatim old behavior + its DI/construction map** before any edit. This produced near-perfect specs and clean first-builds in a prior session (one chain compiled with zero compile fixes) — it was the highest-leverage pattern of the phase. Read-only, so it overlaps safely with a sibling chain's build.

For each layer-batch (or dependency-coupled chain) — files committed individually within it:

1. **`git mv` files from `<dest>/src/androidMain/...` to `<dest>/src/commonMain/...`** (Haiku, parallel). Intra-module move. Content preserved bit-for-bit; git rename detection works; history preserved.

2. **Update package declarations** if conventions differ between source sets (Haiku, parallel). Usually a no-op — Kotlin source sets in the same module typically share package namespaces.

3. **Apply known plan.md substitutions before first build** (Sonnet). Predetermined fixes (`Locale.US` → injected `NumberFormatter` interface, `Instant.now()` → `Clock.System.now()`, Moshi adapter → `kotlinx.serialization`, Android-specific imports → commonMain-portable equivalents) applied as part of the move — **eliminates ~half the compile-fix iterations** because predetermined fixes aren't rediscovered via compile errors.

   **Verbatim-old-behavior pre-flight (mandatory for library-substitution / `lib-swap: path-a` files).** Before authoring the substituted version, read the **OLD** implementation's exact behavior and reproduce it literally — never trust a target-shape-only pre-flight. The traps a shape-only read ships are real: HTTP status mapping (`status == 200` *exact*, NOT a 2xx `isSuccess()` helper), try/catch vs exception-propagation, fallback branches, default values, and **exception message strings** (`error(Throwable(s))` surfaces `Throwable.toString()`, `error(s)` surfaces `s` — a folded store can silently drop master's error-message prefix). Both caught real money-flow divergences in a prior session; the message-string drift slipped to human review. Cite the old source path + line for each behavior reproduced, in `migration.md`.

   **Gson → kotlinx.serialization swaps carry their own pre-flight** (full rationale in `references/test-discipline/migration-baselines.md` §"Gson → kotlinx.serialization"). kotlinx is strict where Gson was lenient, so for every DTO/serializer swap: decode through the **one shared lenient `Json`** (`isLenient` + `coerceInputValues` + `ignoreUnknownKeys` + `explicitNulls=false`, no ad-hoc `Json {}`); keep master's **exact wire type** — no `String`→`Double`/`Long` "upgrades"; make every server-decoded field nullable-or-defaulted; **diff every `@SerialName` against master's `@SerializedName` (zero drift)**; surface — never swallow — decode failures.

4. **Build → fix compile errors loop.**
   - **Haiku subagent** runs gradle, parses errors.
   - **Sonnet subagent** selects routine fixes; **Opus subagent** (not the orchestrator) handles complex substitutions where live-search is needed. The loop is sequential by build dependency, but **each iteration's edit is a dispatched subagent** — the orchestrator never edits the file directly. Subagent failure → another subagent, per SKILL.md NON-NEGOTIABLE.
   - Minimal edit — only what compiler flagged. **Never read-and-rewrite the file** — surgical edits only.
   - Each substitution logged in `migration.md` with citation (Context7 result, web-search result, or plan.md reference per SKILL.md Tooling discipline).
   - Repeat until destination compiles.

5. **Self-review** on any new code (**Sonnet subagent**) per principle #2. Cruft check, KISS, DRY. Notes captured in decisions log.

6. **Targeted baselines** via `--tests` filter for batch files only (Haiku). Run in `<dest>/androidUnitTest`. Must be green. **The final baseline run for each batch uses `--rerun-tasks`** — gradle's UP-TO-DATE caching can produce false-greens on pure-rename batches and source-set moves (a 4-second "BUILD SUCCESSFUL" with everything UP-TO-DATE on a `git mv` batch is the symptom). Intermediate compile-fix iterations omit it (paying cache cost per iteration wastes time); the final verification gets the flag. Pair with `--no-parallel` if `project.md` lists KSP-stability invariants.

   **Migration-exception flow if baseline fails on intentional divergence** (library-substitution semantics, timezone math, JSON ordering, etc.):
   - **Opus** confirms divergence is intentional per plan.md risk register.
   - User signs off.
   - Exception file created at `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` with: what changed, why, risk, sign-off.
   - Baseline edited under the exception reference; commit message includes `[migration-exception <id>]`.
   - Continue.
   
   Otherwise → real bug, investigate.

7. **iOS check per batch (mandatory, not lightweight-optional)** (Haiku) — compile `commonMain` + `iosMain` for the iOS target (`:<dest>:compileKotlinIosArm64`), and on any batch that touched KSP-generated code (DB/DAO/serializer codegen) run `:<dest>:kspKotlinIosArm64 --rerun-tasks` so cache reuse can't mask an `expect`-contract break. A batch is not done until iOS compiles. Full XCFramework/SKIE link at D.2. **Compile the consuming `:app` module too whenever the batch migrated a type `:app` consumes** (`:app:compileProductionDebugKotlin` or the repo's flavored task) — **a compiling library is not a compiling app.** Member→extension splits and signature changes break cross-package/cross-module call sites a dest-only compile never sees (10 `:app` call sites broke silently for two batches in a prior session before a later chain surfaced them).

8. **Consumer impact check** (Sonnet). Intra-module moves typically don't change FQN — no consumer updates required. **But splitting a member function/property into a platform `extension` is NOT a zero-call-site change:** cross-package callers need an explicit `import` for the new extension, and that import-update is part of the **same unit** as the split — `git grep` every call site, update imports, and verify by compiling the consumers (step 7's `:app` compile), never assume "member→extension is transparent." If the project also has package conventions that differ between source sets, Sonnet drafts the FQN search-replace plan, Haiku applies, diff-confirmed. After any updates, baselines re-green via Haiku gradle run.

9. **Commit per file** via the two-commit cadence (SKILL.md): code commit + audit commit. Autopilot, one-line announcements. Sonnet composes messages. One file (or coherent unit) per code commit.

10. **`coverage.md` + `migration.md` updated** per file — **flip `coverage.md` status `frozen → migrated` the moment the file's code lands in `commonMain`** (and update its Final-code-path column), per the SKILL.md State-serialization gate. This is non-negotiable: both prior sessions left the status column stale at `frozen` through all of Phase D, which would have made Phase E's skip-check wrongly skip. Then update `migration.md` (Haiku structured fields + Sonnet prose). If this file resolved a `phase-d-followups.md` entry, flip that entry's `**Status:**` to `done`.

If iOS check (step 7) fails irrecoverably for a file this session → Phase D plan flip proposed (D.3).

### D.2 — Integration verification + followups close (after all batches)

- **Haiku** runs full baseline suite (`<dest>/androidUnitTest`). Green required.
- **Haiku** assembles full XCFramework. Clean — no SKIE warnings.
- **Sonnet** runs deferral grep across all migrated files (`TODO`, `FIXME`, `HACK`, suspect `@Suppress`). Clean required.
- **Opus** reviews `migration.md` for completeness — every `migrate`-plan file has every sub-step done, every substitution cited.
- **`phase-d-followups.md` close-out**: every entry with `Status: open` either flips to `done` (resolved this phase) or gets explicit rationale appended for why it's deferred to a future session (rare — most should close). Open entries surviving Phase D become Phase G PR-body "Out-of-scope follow-ups".

Any failure → not done. Investigate, fix, or flip affected file to `hold` with user approval (see D.3).

### D.4 — Phase D retro
Amend `retro.md` with `## Phase D — KMM-ification (captured YYYY-MM-DD)`. Five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate).

### D.3 — Phase D plan flip (`migrate` → `hold`) — if invoked during D.1 or D.2

For a file initially marked `migrate` that proves unmigratable cleanly this session:

- **Opus** confirms `migrate` → `hold` flip is the right call (vs. extending session, escalating, or pursuing migration-exception).
- User confirms.
- The file's **Phase B relocation commit stays** — code is correctly in `<dest>/androidMain`, that's its valid hold position.
- Any Phase D commits for this file (commonMain mv, partial substitutions) are reverted via `git revert`.
- `plan.md` Phase D plan flips `migrate` → `hold` for this file (rationale captured in decisions log).
- `coverage.md` for this file: status stays `frozen`; Phase D plan column flips to `hold`; final code path = `<dest>/androidMain/...`.
- Phase D continues with remaining `migrate`-plan files.

A flip is **not a session abandonment** — it's a per-file deferral. The rest of the session proceeds normally.

---

## Output: `migration.md`

Living document. Contains:

- Header (status, per-file task checklist)
- Foundation setup log (D.0 — interfaces created, DI module, commit SHA)
- Per-file entries (one per `migrate`-plan file):
  - Old path (`<dest>/androidMain/...`) → new path (`<dest>/commonMain/...`)
  - Compile errors encountered + resolutions (with Context7 / web-search citations)
  - Self-review notes
  - iOS-consumability check result (compile, SKIE warnings, Swift surface notes)
  - Consumer impact summary (typically no-op for intra-module move)
  - Commit SHA
- Held files summary (one line per `hold`-plan file: "Phase D plan: hold per plan.md — code stays in `<dest>/androidMain/...`")
- Integration verification (D.2) — full suite + framework results
- Phase D plan flips (D.3) — files flipped `migrate` → `hold`, rationale
- Migration-exceptions invoked (with links to `.kmm/exceptions/`)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase C complete (`freeze.md` status = complete; detekt enforcement live).
- **D.0 foundation pre-flight passed the iOS klib compile + cold KSP run** (`compileKotlinIosArm64` + `kspKotlinIosArm64 --rerun-tasks`), not just JVM/Android.
- Every locked library version re-confirmed to exist + fit the repo's Kotlin version at D entry.
- Every `migrate`-plan file moved via **`git mv` then edit** — never read-rewrite-replace.
- **Every Gson→kotlinx.serialization DTO swap preserves master's exact wire types, decodes through the one shared lenient `Json`, keeps every server-decoded field nullable-or-defaulted, and passes a `@SerialName ↔ @SerializedName` zero-drift diff** (migration-baselines.md §"Gson → kotlinx.serialization"). Type "upgrades" are out of scope — a separate PR with its own BE verification.
- Baselines green at every commit boundary (with exception refs for sanctioned divergences).
- iOS check passes per batch (`compileKotlinIosArm64`; cold `kspKotlinIosArm64 --rerun-tasks` on KSP-touching batches); full XCFramework/SKIE at D.2 — before status flips `frozen` → `migrated`.
- **Consuming `:app` module compiles per batch when it consumes a migrated type** (flavored `:app:compileProductionDebugKotlin`), and any member→extension split updated its call-site imports in the same unit — a dest-only compile is not sufficient.
- **`coverage.md` flipped `frozen → migrated` as each file's code reaches `commonMain`** (State-serialization gate) — never left stale for Phase E.
- Parallel-batch scope guard observed (declared files only; `git status` between waves).
- **No new `TODO` / `FIXME` / stub / deferral** introduced in any migrated file. (Pre-existing such items in held files are out of scope — they didn't move.)
- Self-review documented for any new code.
- D.2 integration check passes before Phase E.
- Held files (`Phase D plan: hold`) have **no Phase D commits**; their relocation from Phase B is their final state this session.
