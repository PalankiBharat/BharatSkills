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
CREATE → user /clear → Phases 2-3 (scaffold + migrate) → /clear → Phases 4-7 (wiring + Appium) → DONE
```

### Mandatory /clear Points

The skill is file-based (PLAN.md, PROGRESS.md, migration-guide.md, findings.md) — nothing is lost on `/clear`.

| When | Why | What to do |
|------|-----|------------|
| After Phase 1 (PLAN) | Planning fills context with research, file reads, Q&A | `/clear` → `/kmm-workflow` → Continue |
| After Phase 3 (SHARED CODE MIGRATION) | Heaviest phase — per-file TDD loops, agent outputs, debug traces bloat context 300K+ tokens. Fresh start prevents stale-reference errors in wiring phases. | `/clear` → `/kmm-workflow` → Continue |

The orchestrator MUST stop after these phases and instruct the user to `/clear`. Do not continue into the next phase group without clearing.

## Phases

### Phase 1: PLAN

- Create worktree: `git worktree add .claire/worktrees/<name> <base-branch> -b feature/<name>`, copy `local.properties`. All subsequent file creation happens in the worktree path. Record the worktree path in PLAN.md header.
- Research codebase, identify files, dependencies, API endpoints
- Write migration-guide.md (per-file specs with "Migrate after" for DAG)
- PARALLEL after migration-guide done: [PLAN.md + PROGRESS.md] ‖ [findings.md] ‖ [Appium scenarios + fake-server-config + screen-map.json + Appium infra]
- Generate Appium test infrastructure in `e2e-tests/`: `package.json` (appium, webdriverio, fake-server deps), `wdio.conf.js` (device capabilities, specs path), `run-tests.sh` (starts fake server, starts Appium, runs tests, collects results, cleans up). See `references/automated-testing.md` for templates.
- **Allocate dedicated device + ports** for this gameplan (prevents collisions when multiple gameplans test concurrently). Auto-allocate by scanning for free ports and existing devices. Record in PLAN.md header. See `references/automated-testing.md` § Device & Port Isolation for details.
- Verify platform navigation architecture: read the actual Android Router/Navigator and iOS AppRouter/Coordinator code before writing Wire phases. Record the verified architecture in findings.md.
- Verify build task names: run `./gradlew :<module>:tasks --all | grep -i <platform>` to discover exact Gradle task names. Record verified names in PLAN.md build verification section.
- Generate `build-verify.sh` in the gameplan directory using the verified build commands. This project-specific script runs all build checks with zero LLM tokens. Commit it with the gameplan files.
- Verify SDK availability: for every external SDK class referenced by migration targets, grep the KMM SDK source sets to confirm the class exists in commonMain. Record availability in findings.md. If unavailable, add to scaffold list.
- Dispatch plan-analyzer → present gaps → user approval
- Read `references/planning-and-execution.md` before this phase

### Phase 2: SCAFFOLD

- From migration-guide.md, identify ALL external dependencies (classes not being migrated)
- For each: create interface in commonMain + androidMain actual delegating to original
- Build check: run `<gameplan-dir>/build-verify.sh` (project-specific, zero LLM tokens)
- CHECKPOINT COMMIT "scaffold: interfaces for <module>"
- Read `references/kmm-architecture.md` before this phase

### Phase 3: SHARED CODE MIGRATION (dependency-level parallelism)

- Build dependency DAG from migration-guide.md "Migrate after" fields
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
- After all levels: `./gradlew :shared:testDebugUnitTest`
- **SharedFlow collector audit:** scan all composables/screens for `effect.collectLatest` or `effect.collect` calls. Flag any `SharedFlow` that has multiple concurrent collectors as a potential race condition — multiple collectors on `SharedFlow(replay=0)` silently swallow effects.
- Cross-platform Koin audit: for each VM registered in the shared Koin module, verify ALL constructor parameter types have bindings in BOTH `androidBridgeModule` AND `iosBridgeModule`. If a type is only bound on one platform, add the missing binding before proceeding.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/dependency-replacements.md`, `references/kmm-architecture.md`, and `references/rules-and-guardrails.md` before this phase
- After all levels complete: dispatch auditor (sonnet) for code quality sweep → AUDIT_COMPLETE required before wiring

### Phase 4: WIRE ANDROID

- PARALLEL: [Haiku per consumer for import updates] ‖ [Sonnet for DI (Hilt→Koin)]
- Delete originals (grep-before-delete)
- **Stub audit:** scan all migrated files for `error("…")`, `TODO()`, `TODO("…")`, and `stub` markers. Any unresolved stubs BLOCK the checkpoint or must be explicitly deferred with rationale in PROGRESS.md.
- **Koin binding completeness check:** for each VM registered in the shared Koin module, verify ALL constructor parameter types AND all types used by child composables/screens have Koin bindings. Missing bindings crash at runtime — check transitively, not just direct constructor params.
- Build + test
- **Mandatory runtime verification** (mobile-mcp/adb) — "app launches cleanly" is NOT sufficient. Uses `e2e-tests/screen-map.json` for cached element coordinates (see `references/automated-testing.md`). For each migrated screen listed in migration-guide.md:
  1. Navigate to the screen using cached coordinates from screen-map (first time: call `mobile_list_elements_on_screen` and populate cache)
  2. Verify data loads (not stuck on spinner)
  3. Verify primary CTA works
  4. Take screenshot as evidence
  Stubs that throw `error()` must be resolved or explicitly flagged as BLOCKED before checkpoint.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/android-wiring.md` before this phase

### Phase 5: APPIUM ANDROID ⚠️ MANDATORY — NEVER SKIP

- Run `cd e2e-tests && npm install` (first time only — installs Appium, WebDriverIO, fake-server deps)
- Execute: `e2e-tests/run-tests.sh android` — this script automatically:
  1. Starts the fake server with `fake-server-config.json`
  2. Starts Appium server (`npx appium`)
  3. Runs all `*.test.js` specs via WebDriverIO
  4. Collects results + screenshots
  5. Stops fake server and Appium
  6. Exits with 0 (all pass) or 1 (failures)
- If `run-tests.sh` exits non-zero → read output, identify failing tests, DEBUG LOOP (3-strike), fix migration code (NOT test code), re-run
- **ALL tests must pass.** No skipping, no commenting out, no `xit()`. Failing tests mean the migration has bugs.
- Commit `e2e-tests/` directory (test files + results + screenshots)
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/automated-testing.md` before this phase

**After Phase 5 — mobile-mcp automated flows (real app, real device):**
- Execute every flow defined in `e2e-tests/screen-map.json` against the real app using mobile-mcp
- Uses cached screen-map coordinates — does NOT re-discover elements on unchanged screens
- On `blocker` steps (OTP, payment, personal details): STOP, ask user to complete the action on device, wait for confirmation, then resume
- On failure: screenshot + re-discover elements + DEBUG LOOP
- All flows pass → Manual test (user verifies remaining edge cases only)

### Phase 6: WIRE iOS

- PARALLEL: [Sonnet ui-migrator per screen] ‖ [Sonnet Koin iOS]
- Wire navigation + pbxproj
- **Stub audit + Koin completeness check** (same as Phase 4, for iOS bindings)
- Build + runtime verify (mobile-mcp/simulator) — same mandatory per-screen checklist as Phase 4
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/ios-wiring.md` before this phase

### Phase 7: APPIUM iOS ⚠️ MANDATORY — NEVER SKIP

- Adapt Appium test selectors for iOS (accessibility IDs, XCUITest locators)
- Execute: `e2e-tests/run-tests.sh ios` — same script, iOS capabilities
- If failures → DEBUG LOOP (3-strike), fix migration code, re-run
- **ALL tests must pass.** Same rule as Phase 5 — no skipping, no commenting out.
- Screenshot parity with Android (`e2e-tests/screenshots/android/` vs `ios/`)
- Commit test file fixes and updated `e2e-tests/` screenshots
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/automated-testing.md` before this phase

**After Phase 7 — mobile-mcp automated flows (iOS, real device):**
- Same as after Phase 5, but on iOS simulator
- Execute every flow from `screen-map.json`, handle blockers, compare screenshots with Android parity
- All flows pass → Manual test (user verifies remaining edge cases only)

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
- `references/kmm-architecture.md` — Phase 2 (SCAFFOLD): expect/actual patterns, source set structure, ViewModel/DI/coroutine patterns, gotchas
- `references/dependency-replacements.md` — Phase 3 (SHARED CODE MIGRATION): library swap tables and before/after code examples
- `references/kmm-architecture.md` — Phase 3 (SHARED CODE MIGRATION): architecture patterns and battle-tested gotchas
- `references/rules-and-guardrails.md` — Phase 3 (SHARED CODE MIGRATION)
- `references/android-wiring.md` — Phase 4 (WIRE ANDROID)
- `references/ios-wiring.md` — Phase 6 (WIRE iOS)
- `references/automated-testing.md` — Phases 5, 7 (APPIUM ANDROID, APPIUM iOS)

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
1. Current branch matches the base branch recorded in PLAN.md header
2. If mismatch → STOP, report to user, do not proceed

### Stale Sessions
On Continue, when listing gameplans:
1. For each `.sessions/*.active` file, check if the session is still alive
2. If session file is older than 24 hours → mark as "(stale)" in the listing
3. User can choose to clean up stale markers or resume them

## Rules

- Auto-continue between phases — do NOT pause to ask "should I continue?" or "Phase X complete, proceed?". Continue automatically to the next phase unless: (a) a mandatory `/clear` point is reached, (b) REQUIRES_APPROVAL items need user decision, or (c) a build/test failure blocks progress. Status updates are fine ("Starting Phase N"), confirmation prompts are not.
- Appium phases (5, 7) are MANDATORY. The orchestrator MUST NEVER suggest skipping them or offer "Skip to Phase 6/Done" as an option. Phase order is: Wire → Appium → Manual Test. No exceptions.
- When a worktree exists, ALL agent prompts must include the worktree path as the target directory for file creation and edits
- Orchestrator NEVER writes migration code — only agents do
- Tests MUST pass on original BEFORE migration proceeds
- Tests MUST pass on migrated code BEFORE file marked complete
- Always use latest docs (Context7/find-docs/web search), never training data
- REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
- Every decision in files — /clear erases chat, only files survive
- PROGRESS.md updated and committed after each phase
- Each phase gets its own checkpoint commit
- Build verification uses `<gameplan-dir>/build-verify.sh` (generated during Phase 1) — never waste LLM tokens on mechanical build checks
- Tests must PASS at every checkpoint — both unit tests (`./gradlew :shared:testDebugUnitTest`) and Appium tests (`e2e-tests/run-tests.sh <platform>`). A checkpoint with failing tests is invalid. If tests fail, fix the migration code (NOT the tests), then re-run. Tests are the safety net — never weaken them to get a green build.
- No type casting
- After EVERY migration agent: dispatch Haiku verifier
- TDD is non-negotiable: every migrated file MUST have characterization tests that pass against BOTH the staged original AND the migrated commonMain code. `FILE_COMPLETE` with `tests: 0` is rejected — re-dispatch the agent with explicit test-writing instructions. Migration without tests is the root cause of runtime bugs surfacing during manual testing.
- Stub audit at phase boundaries: before any checkpoint commit in Phases 4-7, scan for `error("…")`, `TODO()`, `TODO("…")`, and `stub` in migrated files. Unresolved stubs block the checkpoint.
