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
CREATE (research + write plan files) → user /clear → CONTINUE (fresh context)
```

## Phases

### Phase 1: PLAN

- Create worktree: `git worktree add .claire/worktrees/<name> <base-branch> -b feature/<name>`, copy `local.properties`. All subsequent file creation happens in the worktree path. Record the worktree path in PLAN.md header.
- Research codebase, identify files, dependencies, API endpoints
- Write migration-guide.md (per-file specs with "Migrate after" for DAG)
- PARALLEL after migration-guide done: [PLAN.md + PROGRESS.md] ‖ [findings.md] ‖ [Appium scenarios + fake-server-config]
- Verify platform navigation architecture: read the actual Android Router/Navigator and iOS AppRouter/Coordinator code before writing Wire phases. Record the verified architecture in findings.md.
- Verify build task names: run `./gradlew :<module>:tasks --all | grep -i <platform>` to discover exact Gradle task names. Record verified names in PLAN.md build verification section.
- Verify SDK availability: for every external SDK class referenced by migration targets, grep the KMM SDK source sets to confirm the class exists in commonMain. Record availability in findings.md. If unavailable, add to scaffold list.
- Dispatch plan-analyzer → present gaps → user approval
- Read `references/planning-and-execution.md` before this phase

### Phase 2: SCAFFOLD

- From migration-guide.md, identify ALL external dependencies (classes not being migrated)
- For each: create interface in commonMain + androidMain actual delegating to original
- Build check: `./gradlew :shared:compileDebugKotlin`
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
  - Gate: ALL files at this level complete before next level
- After all levels: `./gradlew :shared:testDebugUnitTest`
- Cross-platform Koin audit: for each VM registered in the shared Koin module, verify ALL constructor parameter types have bindings in BOTH `androidBridgeModule` AND `iosBridgeModule`. If a type is only bound on one platform, add the missing binding before proceeding.
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/dependency-replacements.md`, `references/kmm-architecture.md`, and `references/rules-and-guardrails.md` before this phase
- After all levels complete: dispatch auditor (sonnet) for code quality sweep → AUDIT_COMPLETE required before wiring

### Phase 4: WIRE ANDROID

- PARALLEL: [Haiku per consumer for import updates] ‖ [Sonnet for DI (Hilt→Koin)]
- Delete originals (grep-before-delete)
- Build + test + runtime verify (mobile-mcp/adb)
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/android-wiring.md` before this phase

### Phase 5: APPIUM ANDROID

- Write Appium tests from planned scenarios
- Run against Android app
- Debug failures if any
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/automated-testing.md` before this phase

### Phase 6: WIRE iOS

- PARALLEL: [Sonnet ui-migrator per screen] ‖ [Sonnet Koin iOS]
- Wire navigation + pbxproj
- Build + runtime verify (mobile-mcp/simulator)
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/ios-wiring.md` before this phase

### Phase 7: APPIUM iOS

- Adapt Appium tests for iOS selectors
- Run against iOS simulator
- Screenshot parity with Android
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/automated-testing.md` before this phase

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

- When a worktree exists, ALL agent prompts must include the worktree path as the target directory for file creation and edits
- Orchestrator NEVER writes migration code — only agents do
- Tests MUST pass on original BEFORE migration proceeds
- Tests MUST pass on migrated code BEFORE file marked complete
- Always use latest docs (Context7/find-docs/web search), never training data
- REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
- Every decision in files — /clear erases chat, only files survive
- PROGRESS.md updated and committed after each phase
- Each phase gets its own checkpoint commit
- No type casting
- After EVERY migration agent: dispatch Haiku verifier
