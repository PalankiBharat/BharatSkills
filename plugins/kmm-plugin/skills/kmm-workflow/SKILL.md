---
name: kmm-workflow
description: >
  KMM module migration orchestrator. ALWAYS invoke for KMM migrations, migration plans,
  or any KMM work. Use when the user asks to "migrate a module to KMM", "create a migration plan",
  "continue a migration", "port Android to shared code", "move to commonMain", or any work involving
  KMM, Kotlin Multiplatform, shared module migration, or iOS porting.
  Do not attempt KMM migrations directly — use this skill first.
argument-hint: "[create|continue] <module>"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/inject-plan-context.sh"
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/resolve-gameplan.sh plan-header"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/check-progress.sh"
  SubagentStop:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/validate-completion.sh"
  Stop:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/check-phase-status.sh"
  PreCompact:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/backup-before-compact.sh"
---

# KMM Migration Orchestrator

## THE RULE

1:1 MECHANICAL PORT. Only Android→KMM specifics change.
Zero improvisation. Zero combining. Zero signature changes.
Any behavioral change → REQUIRES_APPROVAL.

## On Invocation — Always Ask

On ANY invocation, always ask: Create / Continue. Never auto-resume. Never assume.

- **Create** → ask module name, base branch, what user wants to achieve
  - Ask questions one at a time until enough context to plan
  - Research codebase to verify current state
  - Build plan files covering ONLY what's needed (skip done phases)
  - Write to ~/dev/gameplans/<name>/ (mkdir -p if needed)
  - Session binding: write `echo "<name>" > ~/dev/gameplans/.sessions/<session_id>.active` (mkdir -p .sessions)
  - Do NOT use plan mode — write PLAN.md, PROGRESS.md, migration-guide.md, findings.md directly
  - After approval: tell user /clear then /kmm-workflow → Continue
- **Continue** → scan ~/dev/gameplans/, list ALL with status, user picks
  - Write session marker (`~/dev/gameplans/.sessions/<session_id>.active`) → read PLAN.md + PROGRESS.md → report state
  - If PLAN.md specifies a worktree path, verify it exists or create it (`git worktree add <path> <base-branch> -b feature/<name>`). Copy `local.properties` to the worktree. All subsequent file edits happen in the worktree path.
  - Continue execution from last checkpoint
- On completion (all phases done + committed): delete session marker

## Workflow

```
Phase 1 (PLAN) → /clear → Phases 2-3 (scaffold + migrate) → /clear → Phases 4-5 (wiring + testing) → Retrospective → DONE
```

### Mandatory /clear Points

The skill is file-based (PLAN.md, PROGRESS.md, migration-guide.md, findings.md) — nothing is lost on `/clear`.

| When | Why | What to do |
|------|-----|------------|
| After Phase 1 (PLAN) | Planning fills context with research, file reads, Q&A | Run retrospective → `/clear` → `/kmm-workflow` → Continue |
| After Phase 3 (SHARED CODE MIGRATION) | Heaviest phase — per-file TDD loops, agent outputs, debug traces bloat context 300K+ tokens. Fresh start prevents stale-reference errors in wiring phases. | Run retrospective → `/clear` → `/kmm-workflow` → Continue |

The orchestrator MUST stop after these phases and instruct the user to `/clear`. Do not continue into the next phase group without clearing.

## Phases

### Phase 1: PLAN

- Create worktree: `git worktree add .claire/worktrees/<name> <base-branch> -b feature/<name>`, copy `local.properties`. All subsequent file creation happens in the worktree path. Record the worktree path in PLAN.md header.
- Research codebase, identify files, dependencies, API endpoints
- Write migration-guide.md (per-file specs with "Migrate after" for DAG)
- PARALLEL after migration-guide done: [PLAN.md + PROGRESS.md] ‖ [findings.md] ‖ [fake-server-config + screen-map.json]
- Generate fake server infrastructure: `e2e-tests/fake-server.js` and `e2e-tests/fake-server-config.json`. See `references/automated-testing.md`.
- **All e2e-tests files** (`fake-server-config.json`, `screen-map.json`, `fake-server.js`) MUST be created inside the worktree path, not the main repo working directory. The worktree is created in Task 1 of Phase 1 — all file creation happens there.
- **Allocate dedicated device + ports** for this gameplan (prevents collisions when multiple gameplans test concurrently). Auto-allocate by scanning for free ports and existing devices. Record in PLAN.md header. See `references/automated-testing.md` § Device & Port Isolation.
- Verify platform navigation architecture: read the actual Android Router/Navigator and iOS AppRouter/Coordinator code before writing Wire phases. Record the verified architecture in findings.md.
- Verify build task names: run `./gradlew :<module>:tasks --all | grep -i <platform>` to discover exact Gradle task names. Record verified names in PLAN.md build verification section.
- Generate `build-verify.sh` in the gameplan directory using the verified build commands. This project-specific script runs all build checks with zero LLM tokens. Commit it with the gameplan files.
- Verify SDK availability: for every external SDK class referenced by migration targets, grep the KMM SDK source sets to confirm the class exists in commonMain. Record availability in findings.md. If unavailable, add to scaffold list.
- Dispatch plan-analyzer → present gaps → user approval
- **Dependency decision framework:** Read `references/dependency-decision-framework.md`. For each Android-only dependency in the module: (1) look up the recommended decision (Replace/Port/Abstract), (2) present recommendation WITH rationale — do not ask open-ended questions, (3) only ask if framework has no recommendation. Record all decisions in findings.md.
- **Android API audit:** Before writing migration-guide.md per-file specs, grep all files planned for commonMain migration for Android-only APIs (android.util.Log, System.currentTimeMillis, java.util.Date, org.joda.time, org.json, com.google.gson, @Synchronized, java.util.concurrent, Dispatchers.IO, GlobalScope, @VisibleForTesting, android.content.Context, android.content.SharedPreferences). Record EVERY occurrence per file. The per-file spec MUST list the specific replacement for each occurrence.
- **Library KMP audit:** For every Android-only library being replaced, web search for official KMP support before planning a manual alternative. AndroidX libraries are rapidly adding KMP support — training data is outdated, always research first. Record findings in findings.md.
- **Gap analysis is mandatory** before presenting plan for approval. The orchestrator MUST run the plan-analyzer agent and fix all BLOCKER/HIGH issues BEFORE asking the user to approve. Do NOT present a plan with known gaps.
- **Interface completeness check:** When creating abstraction interfaces, read the FULL implementation class AND all consumers. Include all public methods and all direct field access by consumers. Never estimate the method count — read the code and list every method.
- **Impl completeness check:** For every interface listed in migration-guide.md, grep for implementation classes in the source. If an impl exists, it MUST have its own migration item in migration-guide.md — do not assume "interface-only" without verifying. Missing impls surface as compile errors in wiring phases when consumers try to instantiate the class. Check: `grep -r "class.*Impl.*:.*<InterfaceName>" src/` for each interface.
- Read `references/planning-and-execution.md` before this phase

### Phase 2: SCAFFOLD

- From migration-guide.md, identify ALL external dependencies (classes not being migrated)
- For each: create interface in commonMain + androidMain actual delegating to original
- **Scaffold dependencies:** Ensure `build.gradle.kts` for the shared module includes:
  - `kotlinx-atomicfu` in commonMain if ANY migrated file uses `@Synchronized` or `java.util.concurrent` (check migration-guide.md)
  - `commonTest` source set with `kotlin("test")` and `kotlinx-coroutines-test` — without this, `@Test` annotations fail with `NonExistentClass` errors and ALL characterization tests are blocked
- Build check: run `<gameplan-dir>/build-verify.sh` (project-specific, zero LLM tokens)
- CHECKPOINT COMMIT "scaffold: interfaces for <module>"
- Read `references/kmm-architecture.md` before this phase

### Phase 3: SHARED CODE MIGRATION (dependency-level parallelism)

- Build dependency DAG from migration-guide.md "Migrate after" fields
- **Platform API pre-check:** Before dispatching migrator agents, ensure ALL agents receive `references/platform-api-gotchas.md` as context. APIs like `Dispatchers.IO`, `@Volatile`, `String.format()`, `removeFirst()` compile on JVM but fail on Native — agents must use the documented replacements.
- For each level (leaves first):
  - PARALLEL: dispatch Sonnet subagent per file (full TDD pipeline):
    1. Stage original → shared/src/androidMain/ (update imports to use interfaces/commonMain)
    2. Compile check
    3. Write characterization tests in commonTest (fakes for all deps)
    4. Run tests against staged androidMain → must PASS
    5. Migrate androidMain → commonMain (library swaps, expect/actual)
    6. Run same tests against commonMain → must PASS
    7. If FAIL → debug loop (3-strike)
    8. Dispatch Haiku verifier (background) — orchestrator records VERIFY_PASS/FAIL in PROGRESS.md after verifier returns
    9. Delete staged androidMain copy
    → FILE_COMPLETE or FILE_BLOCKED
  - **TDD enforcement:** The orchestrator MUST verify that each FILE_COMPLETE includes `tests: N` where N > 0. If an agent returns `tests: 0`, reject the completion and re-dispatch with explicit instruction to write characterization tests. Migration without test coverage is not accepted.
  - Gate: ALL files at this level complete before next level
  - **Original deletion (two-step):** (1) BEFORE dispatching agents for a level, the orchestrator deletes ALL `src/main/java` originals for files being migrated at that level — originals are committed in the previous checkpoint, safe to remove, prevents duplicate class errors when agents write to commonMain. (2) AFTER all agents complete, verify no originals remain — agents cannot reliably delete files, so the orchestrator handles cleanup.
- After all levels: `./gradlew :shared:testDebugUnitTest`
- **Removed API audit:** Diff the SDK's public API surface (pre vs post migration). Any extension functions, utility classes, or constants removed from src/main/java that consumers may reference → record in findings.md under "Breaking Changes for Consumers." Phase 4/5 consumer wiring agents use this list to create local replacements in the consumer app.
- **SharedFlow collector audit:** scan all composables/screens for `effect.collectLatest` or `effect.collect` calls. Flag any `SharedFlow` that has multiple concurrent collectors as a potential race condition — multiple collectors on `SharedFlow(replay=0)` silently swallow effects.
- **Cross-platform Koin binding verification (early):** For each VM registered in the shared Koin module, verify ALL constructor parameter types have bindings in BOTH `androidBridgeModule` AND `iosBridgeModule` during Phase 3 — do not wait until Phase 5 (iOS wiring). Missing iOS Koin bindings for ONE VM crash ALL VM resolution on that platform. Manifests as `trapOnUndeclaredException` in unrelated VMs (e.g., SplashViewModel). Android bindings are verified implicitly (it runs first); iOS bindings are only tested at end.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/dependency-replacements.md`, `references/kmm-architecture.md`, and `references/rules-and-guardrails.md` before this phase
- After all levels complete: dispatch auditor (sonnet) for code quality sweep → AUDIT_COMPLETE required before wiring

### Phase 4: WIRE ANDROID

- PARALLEL: [Haiku per consumer for import updates] ‖ [Sonnet for DI (Hilt→Koin)]
- Delete originals (grep-before-delete)
- **Stub audit:** scan all migrated files for `error("…")`, `TODO()`, `TODO("…")`, and `stub` markers. Any unresolved stubs BLOCK the checkpoint or must be explicitly deferred with rationale in PROGRESS.md.
- **Empty lambda audit:** Scan all migrated composables for callback parameters with default `= {}` (e.g., `onClick: () -> Unit = {}`). Trace each one to verify it reaches a real action from the parent composable. Empty lambdas on onClick/callback params are functional stubs that pass compilation but produce dead buttons.
- **Koin binding completeness check:** for each VM registered in the shared Koin module, verify ALL constructor parameter types AND all types used by child composables/screens have Koin bindings. Missing bindings crash at runtime — check transitively, not just direct constructor params.
- Build + test
- **Visual + functional parity testing (Appium):** Read `../kmm-test/references/appium-testing.md` for flow generation rules and `../kmm-test/references/device-slot-management.md` for device allocation. The full protocol:
  1. Generate Appium flows from `e2e-tests/screen-map.json` — per-platform, with blocker segmentation for OTP/payment steps
  2. Capture baseline screenshots: create temp worktree for master → build → install on allocated device → run Appium flows with `python3 e2e-tests/appium_driver.py` (takeScreenshot) → uninstall → clean up. Skip if baseline cache key matches `git rev-parse master`.
  3. Capture comparison screenshots: build current branch → install → run `python3 e2e-tests/appium_driver.py` (comparison mode)
  4. Diff: Claude reads both baseline and comparison screenshots to classify each screen as VISUAL_REGRESSION / EXPECTED_CHANGE / FALSE_POSITIVE (no pixel threshold)
  5. Functional check: any Appium flow with non-zero exit (tap/assertVisible failure) = functional failure
  6. On failure: debug loop → fix → rebuild → rerun only the failing screen's flow. Max 3 iterations.
- **Manual test** — user tests remaining edge cases that automation couldn't cover. Bug → DEBUG LOOP → fix → retest. All flows pass → COMMIT.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/android-wiring.md` before this phase

### Phase 5: WIRE iOS

- PARALLEL: [Sonnet ui-migrator per screen] ‖ [Sonnet Koin iOS]
- Wire navigation + pbxproj
- **Stub audit + Koin completeness check** (same as Phase 4, for iOS bindings). Extended for iOS: in addition to Kotlin stubs (`error("…")`, `TODO()`, `TODO("…")`), scan all `.swift` files for `// TODO:`, `// FIXME:`, and `// HACK:` comments. Swift TODOs in non-test code indicate unwired functionality that will silently produce dead UI.
- **Empty lambda audit** (same as Phase 4 — for any CMP screens shared with iOS)
- **Visual + functional parity testing (Appium):** Read `../kmm-test/references/appium-testing.md` for flow generation rules and `../kmm-test/references/device-slot-management.md` for device allocation. The full protocol:
  1. Generate Appium flows from `e2e-tests/screen-map.json` — per-platform, with blocker segmentation for OTP/payment steps
  2. Capture baseline screenshots: create temp worktree for master → build → install on allocated device → run Appium flows with `python3 e2e-tests/appium_driver.py` (takeScreenshot) → uninstall → clean up. Skip if baseline cache key matches `git rev-parse master`.
  3. Capture comparison screenshots: build current branch → install → run `python3 e2e-tests/appium_driver.py` (comparison mode)
  4. Diff: Claude reads both baseline and comparison screenshots to classify each screen as VISUAL_REGRESSION / EXPECTED_CHANGE / FALSE_POSITIVE (no pixel threshold)
  5. Functional check: any Appium flow with non-zero exit (tap/assertVisible failure) = functional failure
  6. On failure: debug loop → fix → rebuild → rerun only the failing screen's flow. Max 3 iterations.
  - iOS flows use text-based selectors as primary, accessibility ID as secondary (see `../kmm-test/references/appium-testing.md` iOS Selector Fallback Strategy)
  - Cross-platform parity: after both Android and iOS Appium tests pass, compare Android vs iOS screenshots for structural equivalence using Claude vision
  - Additionally for iOS: verify no stale data sections ("loading", "NC", placeholder values) — add `assertVisible` checks for real data in the Appium flows
- **Manual test** — user tests remaining edge cases that automation couldn't cover. Bug → DEBUG LOOP → fix → retest. All flows pass → COMMIT.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/ios-wiring.md` before this phase

### Migration Retrospective (auto-triggers)

After Phase 1 approval and after final phase completion, the retrospective runs **autonomously** — do NOT wait for user prompting:
1. Read `references/self-improvement.md`
2. Scan conversation AND `findings.md` (if exists) for learnings (Categories A-E)
3. Cross-reference against existing skill files to avoid duplicates
4. Cross-reference findings against each other — merge duplicates within the same retrospective
5. Check existing open issues — comment on matching issues instead of creating duplicates
6. Create/update GitHub issues on the **skill's own repo** (NOT the app repo being migrated) — detect via `gh repo view --json nameWithOwner`
7. Label: `skill:kmm-workflow`, `type:self-improvement`, `session:<date>`
8. Present summary of what was created/updated — user reviews afterward

The retrospective is NOT optional and NOT interactive — it runs automatically and reports results. The user can modify issues after the fact.

**Generalization is mandatory.** All learnings must be project-agnostic — strip specific class names, branch names, API endpoints, and product names. Extract the reusable pattern. See `references/self-improvement.md` § "Generalization rule" for details.

## Agent Dispatch Table

| Task | Prompt | Model | Returns |
|------|--------|-------|---------|
| Migrate file (full TDD pipeline) | agent-prompts/migrator.md | sonnet | FILE_COMPLETE / FILE_BLOCKED |
| Verify migration (structural diff) | agent-prompts/verifier.md | haiku | VERIFY_PASS / VERIFY_FAIL |
| Write characterization tests (standalone only — migrator handles test-writing during normal TDD flow; test-writer is for standalone characterization test scenarios outside the migration pipeline) | agent-prompts/test-writer.md | sonnet | TDD_COMPLETE / TDD_BLOCKED |
| Debug failure | agent-prompts/debugger.md | sonnet | DEBUG_COMPLETE / DEBUG_BLOCKED |
| UI migration (per screen) | agent-prompts/ui-migrator.md | sonnet | UI_COMPLETE / UI_BLOCKED |
| Audit code | agent-prompts/auditor.md | sonnet | AUDIT_COMPLETE / AUDIT_BLOCKED |
| Analyze plan | agent-prompts/plan-analyzer.md | sonnet | PLAN_ANALYSIS |

## References (read ONLY when entering relevant phase)

- `references/planning-and-execution.md` — Phase 1 (PLAN)
- `references/automated-testing.md` — Phase 1 (PLAN): device/port isolation, fake server, screen-map setup
- `references/kmm-architecture.md` — Phase 2 (SCAFFOLD): expect/actual patterns, source set structure, ViewModel/DI/coroutine patterns, gotchas
- `references/dependency-replacements.md` — Phase 3 (SHARED CODE MIGRATION): library swap tables and before/after code examples
- `references/kmm-architecture.md` — Phase 3 (SHARED CODE MIGRATION): architecture patterns and battle-tested gotchas
- `references/rules-and-guardrails.md` — Phase 3 (SHARED CODE MIGRATION)
- `references/android-wiring.md` — Phase 4 (WIRE ANDROID)
- `references/ios-wiring.md` — Phase 5 (WIRE iOS)
- `references/automated-testing.md` — Phases 4, 5 (testing)
- `../kmm-test/references/appium-testing.md` — Phases 4, 5: Appium flow generation, iOS selectors, blocker segmentation
- `../kmm-test/references/device-slot-management.md` — Phase 1 (device allocation), Phases 4, 5 (device targeting)
- `references/dependency-decision-framework.md` — Phase 1 (PLAN): dependency Replace/Port/Abstract decisions
- `references/self-improvement.md` — Migration retrospective (post-Phase 1 and post-completion)
- `references/platform-api-gotchas.md` — Phase 3 (SHARED CODE MIGRATION): APIs not available in commonMain/Native

## Recovery Protocols

### Orphaned Agent
If a parallel subagent goes silent (no completion promise after reasonable time):
1. Check PROGRESS.md — was the file partially processed?
2. Check if staged androidMain copy still exists
3. If staged copy exists → re-dispatch fresh migrator for that file
4. If staged copy missing → dispatch test-writer first, then migrator
5. Mark the orphaned agent's file as re-queued in PROGRESS.md

### Failed Checkpoint
If a phase's build/test fails after migrations are complete:
1. Do NOT proceed to next phase
2. Read build/test output, identify failing files
3. Dispatch debugger agent per failing file (3-strike applies)
4. If 3-strike exhausted → REQUIRES_APPROVAL with full error context
5. Rollback option: `git reset --hard <last-checkpoint-commit>` (user must approve)

### Wrong Branch
On Continue, before reading PLAN.md, verify:
1. The worktree is on the `feature/<name>` branch recorded in PLAN.md header
2. The base branch in PLAN.md matches the branch the worktree was created from
3. If mismatch → STOP, report to user, do not proceed

### Stale Sessions
On Continue, when listing gameplans:
1. For each `.sessions/*.active` file, check if the session is still alive
2. If session file is older than 24 hours → mark as "(stale)" in the listing
3. User can choose to clean up stale markers or resume them

## Rules

- Auto-continue between phases — do NOT pause to ask "should I continue?" or "Phase X complete, proceed?". Continue automatically to the next phase unless: (a) a mandatory `/clear` point is reached, (b) REQUIRES_APPROVAL items need user decision, or (c) a build/test failure blocks progress. Status updates are fine ("Starting Phase N"), confirmation prompts are not.
- **Always create a worktree — even for non-migration work.** ALL work done via this skill must use git worktrees. This includes E2E test setup, Appium configuration, SDK wiring — not just migration phases. Working directly on the base branch risks polluting it with experimental changes.
- **Rate limit awareness in E2E testing.** Login OTP has rate limits (max 2-3 resends → 10-min block). Each test run counts. Plan E2E runs carefully and use a fake server for repeated iterations during development.
- Appium automated flows are MANDATORY after build verification in Phases 4 and 5. The orchestrator MUST NEVER skip them. Phase order is: Wire → build + unit tests → Appium flows (baseline capture + comparison + diff) → Manual Test. No exceptions.
- When a worktree exists, ALL agent prompts must include the worktree path as the target directory for file creation and edits
- Orchestrator NEVER writes migration code — only agents do
- Tests MUST pass on original BEFORE migration proceeds
- Tests MUST pass on migrated code BEFORE file marked complete
- **Dependency research (mandatory):** (1) Web search + Context7/find-docs for latest availability, versions, and API compatibility. (2) Skill references (`dependency-replacements.md`, `platform-api-gotchas.md`, `dependency-decision-framework.md`) for battle-tested migration patterns, swap examples, and known gotchas. **Combine both** — live data confirms what's current, skill references provide proven patterns and caveats. Neither alone is sufficient. (3) Training data NEVER — KMM moves fast and training data has caused incorrect guidance (Dispatchers.IO, Paging3 KMP).
- REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
- Every decision in files — /clear erases chat, only files survive
- PROGRESS.md updated and committed after each phase
- Each phase gets its own checkpoint commit
- Build verification uses `<gameplan-dir>/build-verify.sh` (generated during Phase 1) — never waste LLM tokens on mechanical build checks
- Tests must PASS at every checkpoint — unit tests (`./gradlew :shared:testDebugUnitTest`) must be green. A checkpoint with failing tests is invalid. Fix the migration code (NOT the tests). Tests are the safety net — never weaken them to get a green build.
- No type casting
- After EVERY migration agent: dispatch Haiku verifier
- TDD is non-negotiable: every migrated file MUST have characterization tests that pass against BOTH the staged original AND the migrated commonMain code. `FILE_COMPLETE` with `tests: 0` is rejected — re-dispatch the agent with explicit test-writing instructions. Migration without tests is the root cause of runtime bugs surfacing during manual testing.
- Stub audit at phase boundaries: before any checkpoint commit in Phases 4-5, scan for `error("…")`, `TODO()`, `TODO("…")`, and `stub` in migrated files. Unresolved stubs block the checkpoint.
- When migrating a library SDK consumed by a host app with its own DI framework: **keep the host app's DI untouched**. Add Koin alongside for the SDK's types only. Bridge via a small module that pulls host-provided deps into Koin. Do NOT propose removing the host app's DI framework unless the user explicitly asks.
- **No "Shared" prefix** on class/file names in commonMain. Keep names natural (e.g., `LoginViewModel` not `SharedLoginViewModel`).
- When using a reference branch for patterns, **copy specific files** — never merge or pull the branch.
- After Phase 1 approval, after Phase 3 completion, and after final phase completion, ALWAYS run the migration retrospective (`references/self-improvement.md`). This is the skill's learning mechanism — skipping it means the same mistakes repeat in the next migration.
- **Empty lambda audit at phase boundaries:** Before any checkpoint commit in Phases 4-5, scan all migrated composables for callback parameters with default `= {}`. Trace each to verify it reaches a real action. Dead buttons from empty lambdas are the most common form of silent unwiring.
- **Retrospective before /clear is mandatory and autonomous.** The orchestrator MUST run the migration retrospective (`references/self-improvement.md`) BEFORE instructing the user to `/clear`. Context is erased on clear — if the retrospective hasn't run, all session learnings are permanently lost. The retrospective runs end-to-end without user input: scan → deduplicate → create/comment issues → summarize. Sequence: finish phase → run retrospective → present summary → THEN instruct `/clear`.
- **PROGRESS.md is a checklist, not a journal.** Each checkbox should be ONE line describing *what* was done, not *how*. Implementation details (file names, version numbers, build flags, workarounds) belong in findings.md or commit messages. If a task needs sub-bullets, limit to 2-3 short items max.
- **No CoroutineScope lifecycle changes in 1:1 ports.** Migration agents MUST NOT add `CoroutineScope.cancel()` or scope recreation (`coroutineScope = CoroutineScope(...)`) to classes that manage their own scope lifecycle. If the original only cancels individual jobs in `disconnect()`, the migration must do the same. Scope lifecycle changes are behavioral changes that REQUIRES_APPROVAL. Specifically: changing `val coroutineScope` to `var coroutineScope` to enable cancel/recreate is a red flag — the original used `val` for a reason.
- **Verify every fix automatically.** After making any code fix, the orchestrator MUST rebuild, install, and run the specific Appium flow for the affected screen. Iterate until the fix is verified working. Never report a fix to the user without Appium verification passing first.
- **Scaffold backgroundColor on all CMP Scaffolds.** Every `Scaffold` in shared CMP screens MUST set `backgroundColor` explicitly (e.g., your app's background color token). The default is `MaterialTheme.colors.background` which is white when no dark MaterialTheme is configured. This applies to all sub-screens in nav hosts, not just the top-level screen.
- **No TODO placeholders in migrated code.** Migrated composables MUST NOT contain `// TODO` comments with placeholder content (emoji text, empty Box, commented-out Image). If a drawable resource is needed, copy it from Android `res/drawable/` to `shared/src/commonMain/composeResources/drawable/` during migration. The stub audit at phase boundaries MUST also scan for `// TODO` comments in view files.
- **Version resolution check (mandatory, Phase 4/5):** After updating the SDK version in a consumer project, run `./gradlew :app:dependencies --configuration <config>Classpath | grep <artifact>` to confirm the resolved version matches. Use `--refresh-dependencies` on the first build. Gradle caches can silently serve stale versions, making the build "pass" against the old SDK.
- **Emulator restart on network failure:** During runtime verification, if the emulator shows DNS resolution failures (`Unable to resolve host`), the orchestrator MUST restart the emulator (cold boot: `adb -s <device> emu kill`, then re-launch with `emulator -avd <name> -no-snapshot-load`), wait for boot + network, reinstall, and re-verify. Never commit a checkpoint when the app is stuck on splash due to network errors — it masks real DI/initialization crashes.
- **Device isolation is absolute.** Every `adb` command MUST include `-s $ANDROID_SERIAL` and every `xcrun simctl` command MUST use `$IOS_UDID` (never `booted`). Bare `adb install`, `adb shell`, `adb logcat`, `xcrun simctl install booted`, etc. will target whichever device the OS picks first — which may be another worktree's emulator/simulator. Read the device serial from the PLAN.md header (`<!-- DEVICE: android=... | ios=... -->`) and use it in EVERY command. No exceptions.
