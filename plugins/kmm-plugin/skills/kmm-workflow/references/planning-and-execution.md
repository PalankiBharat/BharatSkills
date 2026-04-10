# Planning and Execution Reference

This file is the combined reference for both plan structure and iterative execution in KMM workflow migrations.

## Table of Contents

1. [Two-Phase Model](#two-phase-model)
2. [Output Files](#output-files)
3. [PLAN.md: Pure Data Header](#planmd-pure-data-header)
4. [PLAN.md: STATUS Block](#planmd-status-block)
5. [PLAN.md: Title, Context, and Decisions](#planmd-title-context-and-decisions)
6. [PLAN.md: Build Verification Template](#planmd-build-verification-template)
7. [PLAN.md: Plan Presentation](#planmd-plan-presentation)
8. [Execution Blueprint](#execution-blueprint)
9. [Workflow Phases Overview](#workflow-phases-overview)
10. [Phase 1: PLAN (BLOCKING)](#phase-1-plan-blocking)
11. [Phase Template: Shared Migration](#phase-template-shared-migration)
12. [Per-File Migration Loop](#per-file-migration-loop)
13. [Wire Android Phase](#wire-android-phase)
14. [Wire iOS Phase](#wire-ios-phase)
15. [Parallel Execution](#parallel-execution)
16. [Agent Execution Strategy](#agent-execution-strategy)
17. [PROGRESS.md Template](#progressmd-template)
18. [migration-guide.md Structure](#migration-guidemd-structure)
19. [findings.md Structure](#findingsmd-structure)
20. [Summary Table Step](#summary-table-step)
21. [Compact Format](#compact-format)
22. [Plan Quality Rules](#plan-quality-rules)
23. [Safeguards and Key Risks](#safeguards-and-key-risks)
24. [Session Completion](#session-completion)
25. [Version Compatibility Protocol](#version-compatibility-protocol)
26. [API 500 Debug Protocol](#api-500-debug-protocol-curl-bisection)

---

## Two-Phase Model

Two-phase separation: PLAN captures every decision in files. EXECUTE consumes those files with minimal context. `/clear` is the boundary — only files survive it.

After planning is complete, tell the user:

- **Before /clear:** Write a handoff doc to `<gameplan>/handoff-phase-1.md` (10-20 lines max):
  ```markdown
  ## Handoff: Phase 1 → Phases 2-3
  ### Decided: <key decisions — library choices, DI strategy, navigation architecture>
  ### Risks: <known issues for execution — complex files, uncertain deps, performance concerns>
  ### Remaining: <what's left — any deferred decisions, user inputs needed>
  ### Files: <count of files to migrate, dependency levels, estimated parallel batches>
  ```

```
Planning complete. Run /clear then:

/kmm-workflow → pick Continue
```

Do NOT auto-clear. The user decides when to clear.

---

## Output Files

Every migration produces exactly these four files in `~/dev/gameplans/<module-name>/`:

| File | Purpose | Created by |
|------|---------|-----------|
| `PLAN.md` | Phases, status block (hooks read first 15 lines), rules | Planning phase |
| `PROGRESS.md` | Checkpoint tracking — created with empty checkboxes during planning, filled during execution | Planning phase |
| `migration-guide.md` | Per-file migration spec consumed by agents | Planning phase |
| `findings.md` | Reusable knowledge: known fixes, gotchas, verified library versions | Planning phase, updated during execution |

All four files are committed to the gameplan directory. After `/clear`, these files are the entire source of truth.

---

## PLAN.md: Pure Data Header

PLAN.md is a **pure data file** — it contains WHAT to migrate, not HOW to migrate it. Workflow instructions live in SKILL.md and reference files (the single source of truth for execution methodology). This separation ensures that when the skill is updated, older plans remain compatible — the new skill version applies its own workflow to the existing plan data.

The header records the skill version that created the plan:

```
<!-- KMM-PLAN v1 | skill: 6.5.0 | module: <module-name> -->
```

This enables version compatibility: when a newer skill version loads an older plan, it can detect missing data fields and upgrade them without rewriting existing decisions or progress.

**PLAN.md must NEVER contain:**
- Agent dispatch instructions ("dispatch Sonnet agent", "fire Haiku sub-agent")
- Workflow rules ("1:1 MECHANICAL PORT", "escalate after 3 failures")
- Reference file loading instructions ("read agent-protocol.md before starting")
- Phase execution methodology (ordering, parallelism patterns)

These all live in SKILL.md and reference files, which evolve with skill updates.

---

## PLAN.md: STATUS Block

The first 10 lines of PLAN.md are injected by hooks on every message and before every Write/Edit. Structure these lines as a compact data summary — status only, no workflow instructions:

```
<!-- KMM-PLAN v1 | skill: 6.5.0 | module: <module-name> -->
<!-- STATUS: Phase N of M | <phase-name> | <status> -->
<!-- NEXT: <what needs to happen next — WHAT, not HOW> -->
<!-- VERIFY: <project-specific build command> -->
<!-- CHECKPOINT: <last checkpoint commit or "none yet"> -->
<!-- DEVICE: android=<emulator-serial> | ios=<simulator-UDID> -->
## KMM Migration: <module-name>
```

Update the STATUS comments after every phase completes. The NEXT field describes the outcome needed ("Migrate Level 1 files"), not the method ("dispatch Sonnet migrator agents").

---

## PLAN.md: Title, Context, and Decisions

- `# [Title]` — what the plan is for (e.g., "Migrate :networking module to KMM")
- `## Context` — what we're doing, why, current state, definition of done
- `## Decisions Made` — starts empty, filled during Q&A and execution

---

## PLAN.md: Build Verification Template

- The verification step(s) the user specified
- Runs at EVERY checkpoint before committing
- ALL must pass before a checkpoint commit is allowed — no exceptions
- **CRITICAL:** Build commands MUST use verified Gradle task names from Task 1.13 — NEVER write build commands based on assumptions. Wrong task names (e.g., `compileReleaseKotlinIosArm64` instead of `compileKotlinIosArm64`) waste a full build cycle and require manual correction.

---

## PLAN.md: Plan Presentation

After writing PLAN.md, present a **concise summary** in chat — not the full file:
- Title and one-line context
- Each phase as a one-liner with task count (e.g., "Phase 2: Data layer migration (8 tasks)")
- Total phases and tasks
- Key risks or open items (if any)
- An **iOS Functional Coverage section** listing: (a) what is fully functional on iOS after this migration, (b) what is stubbed/deferred on iOS. Present proactively — do not wait for the user to ask.

Tell the user where the full PLAN.md is if they want to review details. Wait for approval before proceeding to Phase 1.

---

## Execution Blueprint

During Phase 1 planning, PLAN.md includes an execution blueprint table that annotates every task with its parallelism potential. Team members read this table to know exactly what to parallelize — no guessing.

```markdown
## Execution Blueprint
| # | Task | Files | Parallel? | Deps | Teammate | Status |
|---|------|-------|-----------|------|----------|--------|
| 2.1 | Create interfaces | InterfaceA.kt, InterfaceB.kt, InterfaceC.kt | YES (3) | none | scaffolder-1 | pending |
| 3.1a | Migrate Level 0 batch A | A.kt, B.kt, C.kt | YES (3) | none | migration-coord-L0-a | pending |
| 3.1b | Migrate Level 0 batch B | D.kt, E.kt | YES (2) | none | migration-coord-L0-b | pending |
| 3.2 | Verify Level 0 | A.kt–E.kt | YES (5) | each blocked by its 3.1 file | (Haiku sub-agents of coordinators) | pending |
| 3.3 | Migrate Level 1 | F.kt, G.kt | YES (2) | F→A,B; G→C | migration-coord-L1 | pending |
| 4.1a | Rewire consumers batch A | 6 files | YES (6) | none | android-wirer-1 | pending |
| 4.1b | Rewire consumers batch B | 6 files | YES (6) | none | android-wirer-2 | pending |
| 4.2 | Wire DI | koinModule.kt | NO | none | android-wirer-di | pending |
| 5A.1 | iOS screens | Login, Settings, Profile | YES (3) | none | ios-coordinator-1 | pending |
| 5B.1 | iOS navigation | Router.swift | NO | 4.2 | ios-coordinator-1 | pending |
```

### Per-File Dependency Tracking

The blueprint tracks **per-file dependencies** (not per-level). If F.kt depends only on A.kt and B.kt (from Level 0), then F.kt can start as soon as A and B are verified — even while C.kt, D.kt, E.kt are still in progress at Level 0.

Dependencies come from migration-guide.md's "Migrate after" field. The blueprint Deps column encodes specific file dependencies, enabling early-start optimization by team members.

### Parallelism Annotations

The Parallel? column tells team members exactly how many sub-agents to fire:
- `YES (N)` — fire N sub-agents simultaneously, one per file
- `NO` — single agent, sequential
- `PARTIAL (N of M)` — N files are independent, remaining M have internal deps

Team members read this column and fire sub-agents accordingly. No LLM judgment needed for parallelism decisions — it's pre-computed during planning.

### Teammate Assignment

During Phase 1 planning, the blueprint groups files into **batches of 5-8** and assigns each batch a named teammate. This is mandatory — the orchestrator reads the Teammate column at dispatch time.

**Rules:**
- Each DAG level is split into batches of 5-8 files. A level with 12 files gets 2 batches (6+6), not 1 batch of 12
- Teammate names follow the pattern: `<role>-<level>-<letter>` (e.g., `migration-coord-L0-a`, `migration-coord-L0-b`)
- All teammates for the same DAG level are independent — the orchestrator spawns them in ONE message for true parallelism
- Consumer rewiring and screen migration follow the same batching pattern
- The Teammate column tells the orchestrator exactly how many `Agent()` calls to make and what to name each one

---

## Workflow Phases Overview

The canonical phase sequence for every migration:

```
Phase 1: PLAN (BLOCKING)
  ── /clear (mandatory) ──
Phase 2: SCAFFOLD                     — create KMM module skeleton, expect/actual stubs
Phase 3: SHARED CODE MIGRATION (TDD)  — per-file, bottom-up dependency order
  ── /clear (mandatory) ──
Phase 4: WIRE ANDROID                 — imports, DI, delete originals, build, runtime verify, Appium flows, manual test
Phase 5: WIRE iOS                     — UI screens, navigation, Koin iOS, build, runtime verify, Appium flows, manual test
```

Wire Android and Wire iOS are always distinct named phases, always in that order. Appium automated flows and manual testing are embedded in each Wire phase.

**Mandatory /clear points** are shown above. Phase 3 (shared code migration) is the heaviest phase — per-file TDD loops, agent outputs, and debug traces can bloat context by 300K+ tokens. Clearing before wiring prevents stale-reference errors. After each `/clear`, run `/kmm-workflow` → Continue to resume from the last checkpoint. The orchestrator MUST stop after these phases — do not continue without clearing.

Phase boundaries are drawn **by architectural layer** — not by arbitrary task count. If a single layer is very large, split into sub-phases (e.g., 3A, 3B) by sub-component.

---

## Phase 1: PLAN (BLOCKING — executed before migration begins)

- **Task 1.1:** Create `~/dev/gameplans/<module-name>/` directory.
- **Task 1.2:** Create worktree: `git worktree add .claire/worktrees/<module-name> <base-branch> -b feature/<module-name>`. Copy `local.properties` to the worktree. Record the worktree path in PLAN.md. All subsequent file creation and edits happen in the worktree.
- **Task 1.3:** Write PLAN.md (with self-documenting header) to the gameplan directory.
- **Task 1.4:** Write PROGRESS.md to the gameplan directory with empty checkboxes for every task — filled during execution.
- **Task 1.5:** Write migration-guide.md using the template in `references/agent-prompts/migration-guide-template.md` — one entry per file.
- **Task 1.6:** Write findings.md with assessment data (see findings.md Structure below).
> **Parallel research batches:** Tasks 1.7-1.9 form Batch 1 (4 independent Haiku sub-agents fired by the "researcher" team member). Tasks 1.11-1.12 form Batch 2 (2 Haiku sub-agents). Each batch runs simultaneously; batches are sequential. The researcher team member collects results and returns structured data to the orchestrator for merging into plan files.

- **Task 1.7:** Read every source file in scope. Identify every API endpoint the module calls. Record request/response shapes in findings.md. (parallelizable — Haiku sub-agent, Batch 1)
- **Task 1.7b:** Create a gameplan-scoped Android emulator (`avdmanager create avd -n <gameplan-name> ...`) and iOS simulator (`xcrun simctl create <gameplan-name> ...`) — or reuse existing ones matching the gameplan name. Boot them, record serials in PLAN.md header (`<!-- DEVICE: android=<serial> | ios=<UDID> -->`). Verify appium-mcp is available. Do NOT use the reserved `master-build` AVD (emulator-5556) for gameplan work. (parallelizable — Haiku sub-agent, Batch 1)
- **Task 1.8:** Verify platform navigation architecture — read the actual Android `Router.kt`/`NavHost` and iOS `AppRouter`/`Coordinator` to determine how each platform handles navigation. Record the verified architecture in findings.md. Do NOT assume navigation patterns — verify them before writing Wire phases. (parallelizable — Haiku sub-agent, Batch 1)
- **Task 1.9:** Verify SDK availability — for every external SDK class referenced by migration targets, grep the KMM SDK source sets (`commonMain`, `androidMain`, `iosMain`) to confirm the class exists. Record availability in findings.md as a table (`Class | commonMain | androidMain | iosMain`). If unavailable, add to the scaffold list in PLAN.md. (parallelizable — Haiku sub-agent, Batch 1)
- **Task 1.10:** Dependency decision framework — Read `references/dependency-decision-framework.md`. For each Android-only dependency in the module:
  1. Look up the recommended decision (Replace/Port/Abstract) in the framework
  2. Present the recommendation WITH rationale to the user — do not ask open-ended "what should we do?" questions
  3. Only ask if the framework has no recommendation or the user's situation differs from the default
  4. Record all decisions in findings.md with the rationale
- **Task 1.10b:** Cross-check migration levels against dependency decisions — scan every DAG entry and verify it matches the decision in findings.md / dependency-decision-framework. Files involving a library with a recorded decision MUST use the decided approach (Replace/Port/Abstract). Fix mismatches before running the plan-analyzer.
- **Task 1.10c:** Scope-change propagation — Any decision that adds files to scope MUST immediately trigger a re-check of: (1) scaffolding list, (2) DAG levels, (3) phase task counts — propagate changes before continuing Q&A.
- **Task 1.10d:** Import-vs-DAG verification — for every file annotated `Migrate after: none` (no dependencies), read its actual import list and verify no import resolves to a file scheduled for later migration levels. Missed dependencies cause compilation failures when the file migrates early. Update DAG annotations for any mismatches found.
- **Task 1.11:** Android API audit — Before writing migration-guide.md per-file specs, grep all files planned for commonMain migration for Android-only APIs (`android.util.Log`, `System.currentTimeMillis`, `java.util.Date`, `org.joda.time`, `org.json`, `com.google.gson`, `@Synchronized`, `java.util.concurrent`, `Dispatchers.IO`, `GlobalScope`, `@VisibleForTesting`, `android.content.Context`, `android.content.SharedPreferences`), singleton instance references (`instance`, `getInstance`, `companion object` singletons), cross-package imports to non-migration-target packages, enum references where the enum is defined outside the migration batch, and **domain/data class methods that construct infrastructure classes inline** (e.g., infrastructure classes (e.g., store instances, service singletons) called inside model method bodies — flag these as "requires DI refactor before or during migration" in migration-guide.md, as they create silent reattach debt when the model migrates to commonMain but retains an androidMain extension). Record EVERY occurrence per file. For any batch count > 20 files of the same type, read each file individually to confirm classification before recording the count — never trust directory grep counts alone. The per-file spec in migration-guide.md MUST list the specific replacement for each occurrence — never write "should port cleanly" or "minimal changes". (parallelizable — Haiku sub-agent, Batch 2)
  - Never write "Platform APIs: none" for more than 3 consecutive files without re-reading each file individually — this field must be derived from grep, not from inference.
- **Task 1.12:** Library KMP audit — For every Android-only library being replaced (Paging3, Room, DataStore, Navigation, etc.), web search for official KMP support before planning a manual alternative. AndroidX libraries are rapidly adding KMP support — training data is outdated, always research first. Record findings in findings.md. Phase 1 planning pre-verifies ALL library versions and pins them in migration-guide.md Swaps field with exact versions. Migrator agents use these pinned versions — no re-research during Phase 3. This is the single source of truth for dependency versions. (parallelizable — Haiku sub-agent, Batch 2; needs web search capability)
- **Task 1.13:** Verify build task names — run `./gradlew :<module>:tasks --all | grep -i <platform>` to discover exact Gradle task names for Android compilation, iOS arm64 compilation, and app assembly. Record verified task names in PLAN.md build verification section. Never write build commands based on assumptions.
- **Task 1.14:** Generate `build-verify.sh` in the gameplan directory using the verified build commands from Task 1.13. This project-specific script is the single source of truth for build checks throughout all phases — zero LLM tokens on mechanical builds. See [Build Verification Script](#build-verification-script) for the template and usage.
- **Task 1.15:** Dispatch **Sonnet agent** (`plan-analyzer.md`) to find remaining ambiguity → resolve → user approves.
- **Task 1.15b:** Gap analysis is mandatory before presenting plan for approval. The orchestrator MUST run the plan-analyzer agent and fix all BLOCKER/HIGH issues BEFORE asking the user to approve. Do NOT present a plan with known gaps and wait for the user to ask for a review. If BLOCKER + HIGH count > 5, do not resolve issues one-by-one — identify the root cause category (batch assertions? missing grepping? scope propagation?) and fix the planning process gap first, then rerun the analyzer.
- **Task 1.15c:** Interface completeness check — When creating abstraction interfaces (e.g., ScripStore wrapping ObjectBox), read the FULL implementation class AND all consumers (grep for usages across all repos). Include:
  - All public methods from the implementation class
  - All direct field access by consumers (e.g., `store.boxStore.query()` bypassing the API)
  - Convert these direct accesses into proper interface methods
  Never estimate the method count — read the code and list every method.
- **Task 1.16:** Verify the current repo builds clean (in the worktree) by running `<gameplan-dir>/build-verify.sh <worktree-dir>`. If already broken → STOP and escalate.
- **Task 1.17:** Generate `parity-check.sh` in the gameplan directory alongside `build-verify.sh`. This script runs static analysis checks at Phase 4/5 boundaries BEFORE Appium testing — zero tokens, zero devices, catches 80% of parity bugs in seconds. Template checks:
  1. Route mapping completeness — every sealed class/enum variant has explicit mapping (no else→null fallback)
  2. Listener/callback registration parity — every Android callback registration has iOS equivalent
  3. SDK initialization parameter match — parameter lists identical between platforms
  4. Session field coverage — every field read by isLoggedIn/isTokenExpired is written by all credential-save paths
  5. Asset/resource parity — every Image("x") / LottieAnimation.named("x") resolves to actual file
  6. Info.plist key verification — every Bundle.main.infoDictionary read has matching key in target Info.plist
  7. String literal diff — all user-visible strings character-for-character identical between original and migrated
  8. Empty lambda detection — callback params with default `= {}` traced to real actions
  9. Stub audit — error("…"), TODO(), // TODO, // FIXME in non-test files
  10. Koin binding completeness — every VM constructor param type has binding in both platform modules
  
  The script is project-specific (paths, module names derived from PLAN.md). Run it at every Phase 4/5 checkpoint BEFORE Appium. If any check fails → fix → rerun. Only proceed to Appium after parity-check.sh passes clean.

  Additionally, generate these verification scripts from the project structure:
  - `flow-collector-check.sh` — customize SHARED_SRC and IOS_SRC paths from the template
  - `koin-binding-check.py` — customize koin module glob and shared source path from the template
- **Task 1.18:** Generate `manual-test-checklist.md` in the gameplan directory from migration-guide.md. For each platform-stay screen:
  1. Navigate to: <screen name> (navigation path from parent)
  2. Verify visually: <key visual elements from UI Branches field>
  3. Test interactions: <each callback from Callbacks field — tap X, verify Y happens>
  4. Verify data: <expected data elements from Public API field>
  This turns the manual test gate from a vague "test the app" into a specific, reproducible checklist.
- **Checkpoint 1** committed in the worktree. Commit message: `chore: begin KMM migration for [module-name]`

---

## Phase Template: Shared Migration

Each shared-code phase migrates one architectural layer. Tasks have file-level specificity:

- **Read:** exact file paths to understand first
- **Create:** full paths of new files, with description of contents
- **Modify:** full paths of files to change + what changes (add/remove/rename what)
- **Delete:** full paths of files to remove (with grep-before-delete if needed)
- **Verify:** build/test command

Tasks within a phase execute **sequentially by default**. Mark tasks as `(parallelizable)` when they touch no shared files — files at the same dependency level run as parallel subagents.

If a phase depends on unknowns that can't be resolved upfront, add a `Task N.0: PRE-CHECK` that researches the unknowns and updates PLAN.md with concrete file paths before executing the remaining tasks. This runs autonomously — no user approval pause needed.

Every shared-code phase ends with:
```
MIGRATE → VERIFY (Haiku diff) → Gradle tests → DEBUG if needed → CHECKPOINT
```

Checkpoint committed after this phase completes. Commit message: `[type]: [description]` (use conventional commits; include structured trailers like `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:` when the commit involves non-obvious decisions).

---

## Per-File Migration Loop

For each file, execute this loop in order:

```
1. Stage      — copy original to staging area (do not modify original yet)
2. Compile    — verify the original compiles clean before touching it
3. Write tests — write unit tests against the original (TDD: red first)
4. Run on original — confirm tests pass on original (establishes baseline)
5. Migrate    — Sonnet agent performs the 1:1 port to KMM target
6. Run on migrated — run the same tests against the migrated output
7. Verify     — Haiku diff: API surface, method signatures, return types all match exactly
8. Delete staged — remove the staging copy; original is replaced by migrated
```

The migrator agent owns the full TDD pipeline (stage → tests → migrate → verify). A separate test-writer agent is dispatched ONLY for: (a) retroactive characterization testing in Verify mode, (b) pre-characterization when a file's tests must be written by a different agent due to dependency chain constraints.

Verifier (step 7) is a fast pre-filter — diffs migrated output vs original source:
- API surface: every method, param, return type matches exactly
- No use cases combined, split, or altered
- Allowed changes: library swaps, package changes, imports, LiveData→StateFlow

If VERIFY_FAIL → re-dispatch migrator (max 2 retries) → escalate after 3 failures.

Gradle tests are the real catch-all for subtle bugs that pass the diff check.

Batch any REQUIRES_APPROVAL items → present to user at phase boundary (not one-by-one).

---

## Wire Android Phase

Runs after all shared migration phases are complete.

**Step 1: Wire Android** — read `android-wiring.md`

**Step 2: Stub audit**

Scan all migrated files for `error("…")`, `TODO()`, `TODO("…")`, and `stub` markers. Any unresolved stubs BLOCK the checkpoint or must be explicitly deferred with rationale in PROGRESS.md.

**Step 3: Koin binding completeness check**

For each VM registered in the shared Koin module, verify ALL constructor parameter types AND all types used by child composables/screens (e.g., `FeatureUseCase` used by a top bar composable) have Koin bindings. Check transitively — not just direct constructor params. Verify bindings exist in BOTH `androidBridgeModule` AND `iosBridgeModule`. Missing bindings crash Koin startup at runtime and block ALL VM resolution, not just the missing one.

**Step 4: Android build + test**

Run the project-specific build script (zero LLM tokens):
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
  → BUILD_VERIFY_PASS → proceed
  → BUILD_VERIFY_FAIL → check findings.md → DEBUG LOOP → FIX → rerun script
```

**Step 5: Runtime Verify (appium-mcp, fallback: adb)**

appium-mcp E2E per `appium-mcp-testing.md` — create session, navigate screens, verify elements, screenshot for 3-build comparison.

If crash → DEBUG LOOP (Android): instrument with Napier `[DebugScreenName]` → `adb -s $ANDROID_SERIAL logcat -s DebugScreenName`

**Step 6: Summary Table** (promised vs achieved per file — see Summary Table Step)

**Step 7: appium-mcp E2E (real app, real device)**

Run 3-build comparison per `appium-mcp-testing.md`. On blocker: pause and ask user.

**Step 8: Manual Test**
```
User tests remaining edge cases that automation couldn't cover
Bug → DEBUG LOOP → Appium smoke after each fix
All flows pass → COMMIT (Wire Android + flows complete)
```

PROGRESS.md committed at end of this phase.

---

## Wire iOS Phase

Runs after Wire Android is committed.

**Step 1: UI Migration** — per screen per migration-guide.md (CMP / SwiftUI / Hybrid per spec)

**Step 2: Wire iOS** — read `ios-wiring.md`

**Step 3: Stub audit + Koin completeness check** (same as Wire Android Steps 2-3, for iOS bindings)

**Step 4: iOS build**

Run the project-specific build script (zero LLM tokens):
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
  → BUILD_VERIFY_PASS → proceed
  → BUILD_VERIFY_FAIL → DEBUG LOOP (iOS) → fix → rerun script
```

**Step 5: Runtime Verify (appium-mcp on simulator, fallback: xcrun)**

appium-mcp E2E per `appium-mcp-testing.md` — create session, navigate screens, verify elements, screenshot for 3-build comparison.

If crash → DEBUG LOOP (iOS): `xcrun simctl launch --console-pty $IOS_UDID <bundle-id> 2>&1 | grep DebugScreenName`

**Step 6: Summary Table** (promised vs achieved — compare Android vs iOS columns)

**Step 7: appium-mcp E2E (iOS simulator)**

Run 3-build comparison per `appium-mcp-testing.md`. On blocker: pause and ask user.

**Step 8: Manual Test**
```
User tests remaining edge cases on iOS
Bug → DEBUG LOOP (iOS) → fix → retest
All flows pass → COMMIT (Wire iOS + flows complete)
```

PROGRESS.md committed at end of this phase.

---

## Parallel Execution

Files at the same dependency level (no ordering constraint between them) run as parallel subagents — do not serialize unnecessarily.

- Mark tasks `(parallelizable)` in PLAN.md when they touch no shared files.
- The orchestrator launches these concurrently via separate Sonnet agents.
- Tasks that share files or have dependency order execute sequentially.
- **Within each level, sort by complexity (LOC ascending).** `wc -l` each file before Phase 3. Flag >300 LOC with a complexity note; flag >500 LOC as "dedicated agent, longest runtime" for time budgeting.

### Overlapping Verification in Phase 3

Within a DAG level, Haiku verifiers start immediately as each migrator sub-agent completes — they do NOT wait for the entire level to finish:

```
Level N:
  [Sonnet Migrator A] ──done──→ [Haiku Verifier A starts]
  [Sonnet Migrator B] ──(running)──
  [Sonnet Migrator C] ──done──→ [Haiku Verifier C starts]
  [Sonnet Migrator B] ──done──→ [Haiku Verifier B starts]
  [ALL migrators + verifiers complete]
  Orchestrator: ./gradlew build (Gradle lock)
```

The migration-coordinator team member manages this internally — it fires verifier sub-agents as callbacks when migrator sub-agents return results.

### Early-Start Across DAG Levels

If File F (Level 1) depends only on File A and File B (Level 0), then F can start migrating as soon as A and B are verified — even if C, D, E (also Level 0) are still in progress.

The execution blueprint's Deps column encodes per-file dependencies. The migration-coordinator checks actual file deps (from "Migrate after" field), not level boundaries.

### Sub-Agent Rule

**N independent files → N sub-agents.** Team members never process independent files sequentially. The execution blueprint's Parallel? column pre-computes this — team members read it and fire sub-agents accordingly.

---

## Agent Execution Strategy

All work flows through a 3-tier hierarchy. The orchestrator creates teams, team members fire sub-agents.

| Phase | Team | Member (Tier 2) | Model | Tmux | Sub-Agents (Tier 3) | Parallelism |
|-------|------|-----------------|-------|------|---------------------|-------------|
| 1: PLAN — research | planning-team | researcher | Sonnet | Yes | N Haiku (grep, read, web search) | Parallel batches (1.7-1.9, then 1.11-1.12, then per-file guide) |
| 1: PLAN — analysis | planning-team | plan-analyzer | Sonnet | No | Haiku (grep verification) | Sequential |
| 1: PLAN — decisions | (orchestrator) | — | Opus | — | — | Sequential (REQUIRES_APPROVAL) |
| 2: SCAFFOLD | scaffold-team | scaffolder | Sonnet | Yes | N Haiku (one per interface file) | Parallel per interface |
| 3: MIGRATE | migration-team | migration-coordinator | Sonnet | Yes | N Sonnet (one per file, TDD pipeline) | Parallel per DAG level, early-start per file deps |
| 3: VERIFY | migration-team | migration-coordinator | — | — | N Haiku (one per file, structural diff) | Overlapping with migrators |
| 3: AUDIT | migration-team | (coordinator fires) | — | — | 1 Sonnet auditor + 1 Haiku checklist | Parallel |
| 4: ANDROID | wiring-team | android-wirer | Sonnet | Yes | N Haiku (consumers) + 1 Sonnet (DI) | Parallel consumers + DI |
| 5A: iOS UI | wiring-team | ios-coordinator | Sonnet | Yes | N Sonnet (one per screen) + 1 Sonnet (Koin) | Parallel per screen (overlaps Phase 4) |
| 5B: iOS PLUMB | wiring-team | ios-coordinator | — | — | 1 Sonnet (nav) + N Haiku (scripts) | Sequential nav, parallel scripts |
| Verify L1 | verify-team | verifier | Sonnet | Yes | 2 Haiku + 1 Sonnet | 3-way parallel |
| Verify L2 | verify-team | verifier | — | — | 1 Haiku + 1 Sonnet | 2-way parallel |
| Verify L3 | verify-team | verifier | — | — | 2 Sonnet (Android + iOS devices) | 2-way parallel |
| Retro — apply | retro-team | consolidator | Sonnet | Yes | N Sonnet (one per target file) | Parallel per file |

---

## PROGRESS.md Template

Created during Phase 1 with empty checkboxes. Filled during execution. PROGRESS.md is committed after each phase completes — not all at once at the end.

Task names describe WHAT was accomplished, not HOW (no agent names, tool names, or method references). This ensures the checklist remains valid across skill version updates.

```markdown
# Progress: <module-name>

## Phase 1: PLAN
- [ ] Gameplan directory + worktree created
- [ ] Plan files written (PLAN.md, PROGRESS.md, migration-guide.md, findings.md)
- [ ] Source files analyzed, APIs recorded
- [ ] Devices booted, serials recorded
- [ ] Navigation architecture verified
- [ ] SDK availability verified
- [ ] Dependency decisions made (all REQUIRES_APPROVAL resolved)
- [ ] Cross-check: migration levels vs dependency decisions
- [ ] Android API audit complete (per-file Platform APIs populated)
- [ ] Library KMP compatibility verified
- [ ] Import-vs-DAG verification complete
- [ ] Build task names verified
- [ ] Verification scripts generated (build-verify, parity-check, flow-collector, koin-binding)
- [ ] Interface completeness check passed
- [ ] Plan quality review passed (zero BLOCKERs, zero HIGH)
- [ ] Baseline build passes
- [ ] Manual test checklist generated
- [ ] Checkpoint committed

## Phase 2: SCAFFOLD
- [ ] KMM module skeleton created (build.gradle.kts, source sets)
- [ ] expect/actual stubs written for platform APIs
- [ ] commonTest source set configured
- [ ] kotlinx-atomicfu added (if @Synchronized replacement needed)
- [ ] Fakes writable from commonTest
- [ ] Build passes
- [ ] Checkpoint committed

## Phase 3: SHARED CODE MIGRATION
<!-- One line per file — "migrated + tested + verified" is the outcome -->
- [ ] <FileName>.kt — migrated + tested + verified
- [ ] <FileName>.kt — migrated + tested + verified
- [ ] ...
- [ ] Full unit test suite passes
- [ ] Post-migration audit passed (zero CRITICAL)
- [ ] String literal diff verified
- [ ] Cross-platform Koin bindings verified
- [ ] Checkpoint committed
- [ ] Retrospective complete

## Phase 4: WIRE ANDROID
- [ ] Imports + DI rewired
- [ ] Consumer files updated
- [ ] Original Android files deleted
- [ ] Stub audit passed (zero error()/TODO() in non-test)
- [ ] Empty lambda audit passed
- [ ] Koin binding check passed (both platforms)
- [ ] Build + all unit tests pass
- [ ] Parity check passed
- [ ] DI binding audit passed
- [ ] E2E comparison passed (3-build)
- [ ] Manual test passed
- [ ] Checkpoint committed

## Phase 5: WIRE iOS
- [ ] SwiftUI screens wired for all platform-stay files
- [ ] Koin iOS module: all bindings registered
- [ ] Navigation + pbxproj updated
- [ ] Stub audit passed
- [ ] Empty lambda audit passed
- [ ] Info.plist keys verified
- [ ] Asset parity verified
- [ ] Route mapping complete (every variant has explicit case)
- [ ] Session fields verified (all persist paths)
- [ ] Flow inventory audit passed
- [ ] Callback completeness verified
- [ ] UI branch audit passed
- [ ] DI binding audit passed
- [ ] Build + all unit tests pass
- [ ] Parity check passed
- [ ] E2E comparison passed (3-build)
- [ ] Cross-platform parity classified
- [ ] Manual test passed
- [ ] Checkpoint committed
- [ ] Retrospective complete (final)

## Final Verify
- [ ] All checkboxes marked [x]
- [ ] findings.md saved for next migration
```

Checkbox states: `[x]` = done, `[ ]` = pending, `[~]` = deferred (add inline reason).

---

## Session Gameplans

Session-scoped gameplans live at:

```
~/dev/gameplans/.sessions/<session_id>.active
```

Not a global `.active` file. Each session has its own scoped active file so concurrent sessions do not collide.

---

## migration-guide.md Structure

One entry per file. Agents consume this during execution — they do not re-read source code or make decisions.

See `references/agent-prompts/migration-guide-template.md` for the full template with all fields and examples.

> **Source path rule:** The Source field MUST be the actual file path verified by reading the file — never assumed from context, naming convention, or co-location.

---

## findings.md Structure

```markdown
# Findings: <module-name>

### Decisions Made During Planning
| Decision | Options Considered | Chosen | Rationale |
|----------|-------------------|--------|-----------|

### Known Fixes
| Symptom | Fix | Category |
|---------|-----|----------|

### Gotchas
- (non-obvious project-specific issues)

### Library Versions (verified via docs)
| Library | Version | Verified |
|---------|---------|---------|

### Issues Encountered
| # | Task | Attempt | What Failed | Resolution |
|---|------|---------|-------------|------------|

### Research
(Library docs, API references, version compatibility. ONLY place for external content — never in PLAN.md.)
```

---

## Summary Table Step

Include a Summary Table before every manual test step (Wire Android and Wire iOS phases):

```markdown
## Summary Table: <phase-name>

| File | Promised (migration-guide.md) | Achieved | VERIFY result | Notes |
|------|------------------------------|----------|--------------|-------|
| LoginRepository.kt | login(email), login(phone) separate | login(email), login(phone) separate | VERIFY_PASS | — |
| LoginApi.kt | Retrofit→Ktor 3.1.0, same endpoints | Retrofit→Ktor 3.1.0, same endpoints | VERIFY_PASS | — |
```

Every row must have a VERIFY result. If any row is VERIFY_FAIL, fix it before manual test. The Wire iOS Summary Table adds an Android column for side-by-side parity comparison.

---

## Compact Format

Use compact table format when plan exceeds 50 tasks to reduce PLAN.md size. Replace verbose task prose with a table inside each phase section:

```
| # | Task | File(s) | Classification | Notes |
|---|------|---------|----------------|-------|
| 2.1 | Add UserRepository interface | shared/src/commonMain/kotlin/data/UserRepository.kt | Create | — |
| 2.2 | Implement AndroidUserRepository | shared/src/androidMain/kotlin/data/AndroidUserRepository.kt | Create | depends on 2.1 |
| 2.3 | Delete LegacyUserDao | android/src/main/java/data/LegacyUserDao.kt | Delete | grep-before-delete |
```

Classification values: `Create`, `Modify`, `Delete`, `Read`, `Verify`, `PRE-CHECK`.

---

## Plan Quality Rules

- **Tasks must be atomic** — a single file or single logical change, retryable independently
- **Every task specifies exact file paths** — Create/Modify/Delete with full paths, no vague references
- **Every phase ends with a checkpoint commit** — the codebase is always in a buildable state
- **Checkpoint commits are MANDATORY** — but ONLY after build verification AND all tests pass. Never commit with failing builds or failing tests. Unit tests (`./gradlew :shared:testDebugUnitTest`) must be green before a checkpoint is valid.
- **PROGRESS.md committed after each phase** — not all at once at the end
- **A task is only marked `[x]` in PROGRESS.md after its verification step passes** — not before
- **Pre-check gates** — phases depending on unknowns get a Task X.0 PRE-CHECK that researches and updates PLAN.md with concrete paths before continuing (no approval pause)
- **Phase boundaries are by LAYER** — each phase corresponds to a distinct architectural layer (domain, data, platform API, expect/actual, tests). No task cap per phase; split by layer, not count. Large layers → sub-phases (3A, 3B).
- **FINDINGS.md is always the destination for research** — never inline external content or untrusted data into PLAN.md

---

## Safeguards and Key Risks

**Safeguards (always active):**
- grep-before-delete on any file removal
- verify-before-swap on any library substitution
- Escalate after 3 failures on any loop — never suppress errors
- Any project-specific constraints discovered during research go here

**Key Risks (include when non-obvious):**
- List risks with brief explanation of impact and mitigation

---

## API 500 Debug Protocol (curl bisection)

When a Ktor API call returns 500 but the same endpoint works from master/original code:

1. **Add debug logging** — log the full URL, headers, and body being sent by Ktor
2. **Reproduce via curl** — copy the exact request as a curl command
3. **Bisect headers** — remove headers one at a time until the 500 becomes a valid response (e.g., 422, 200)
4. **Identify the offending header/param** — the header whose removal fixes the 500 is the root cause

This technique found the `platform` header root cause in 5 minutes after 2+ hours of code-level analysis. Always try curl bisection before diving into server-side debugging.

---

## Session Completion

- All phases in PROGRESS.md marked `[x]`
- `findings.md` saved for next migration (Known Fixes, Gotchas, Library Versions)
- `migration-guide.md` and `PLAN.md` kept for reference or deleted per user preference
- **Device cleanup:** ask user before deleting gameplan AVD (`avdmanager delete avd -n <gameplan-name>`) and simulator (`xcrun simctl delete <UDID>`). Do not auto-delete. Never touch `master-build` (emulator-5556).

---

## Version Compatibility Protocol

PLAN.md records `skill: <version>` in its header. When the skill loads a plan created by an older version:

1. **Read skill version from header** — e.g., `skill: 6.4.3`
2. **Compare with current skill version** — e.g., current is `6.5.0`
3. **If same version** → proceed normally
4. **If older version** → run lightweight data upgrade:
   - Check if migration-guide.md has all expected fields (add missing fields with defaults or by re-analyzing code)
   - Check if execution blueprint exists in PLAN.md (generate from migration-guide.md DAG if missing)
   - Check if PROGRESS.md uses outcome-based tasks (if old format with tool/agent references, don't rewrite — map old tasks to current workflow internally)
   - Report to user: "Plan was created with skill v6.4.3, now running v6.5.0. Data upgraded. Workflow uses current skill version."
5. **Never rewrite existing plan data** — only add missing fields. Decisions, progress, and findings are preserved.

This generalizes the existing verify-protocol.md Step 2a (upgrade pre-v6 gameplan) to handle any version gap.

---

## Build Verification Script

During Phase 1 (Task 1.14), generate a project-specific `build-verify.sh` in the gameplan directory. This script is tailored to the actual project — using the exact Gradle task names and xcodebuild commands verified in Task 1.13. The skill stays project-agnostic; the script is project-specific.

**Template** (adapt to the project's verified build commands):

```bash
#!/usr/bin/env bash
# build-verify.sh — Project-specific build verification
# Generated during Phase 1 planning. Uses verified task names.
# Usage: ./build-verify.sh [worktree-dir]
set -euo pipefail

WORKTREE="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$WORKTREE"

PASS=0; FAIL=0; FAILURES=""

run_check() {
  local cmd="$1"
  echo "--- Running: $cmd"
  local start=$(date +%s)
  local out=$(mktemp)
  if eval "$cmd" > "$out" 2>&1; then
    echo "    PASS ($(($(date +%s) - start))s)"
    PASS=$((PASS + 1))
  else
    local rc=$?
    echo "    FAIL (exit $rc, $(($(date +%s) - start))s)"
    tail -20 "$out" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAILURES="$FAILURES\n  - $cmd (exit $rc)"
  fi
  rm -f "$out"
}

# ── Verified build commands (from Task 1.13) ──
# NEVER use assumed task names. These must come from:
#   ./gradlew :<module>:tasks --all | grep -i <platform>
# Replace these with the actual verified commands for this project:
#
# CRITICAL: Always include a FULL APP build (e.g., :app:assembleDebug or
# :app:compileProductionDebugKotlin), not just the shared module build.
# Module-only builds (:shared:assemble) miss consumer compilation errors
# that only surface when the app module compiles against the migrated SDK.
run_check "./gradlew :shared:compileDebugKotlin"
run_check "./gradlew :shared:compileKotlinIosArm64"
run_check "./gradlew :app:assembleDebug"
# run_check "xcodebuild -workspace iosApp/iosApp.xcworkspace -scheme iosApp -destination '...' build"

# DI verification (if project uses Koin)
./gradlew :shared:checkKoinModules 2>/dev/null || echo "WARN: Koin module check not available — grep-based audit will be used in verify mode"

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && { echo -e "Failed:$FAILURES"; echo "BUILD_VERIFY_FAIL"; exit 1; }
echo "BUILD_VERIFY_PASS"
```

**Usage throughout all phases:**
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
```

The orchestrator calls this at every checkpoint. Only on `BUILD_VERIFY_FAIL` does it engage an LLM agent (debugger) to diagnose. This saves significant tokens on the happy path — builds are purely mechanical.
