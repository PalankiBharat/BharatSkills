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
  - Write session marker → read PLAN.md + PROGRESS.md → report state → continue
- On completion (all phases done + committed): delete session marker

## Workflow

```
CREATE (research + write plan files) → user /clear → CONTINUE (fresh context)
```

## Phases

### Phase 1: PLAN

- Research codebase, identify files, dependencies, API endpoints
- Write migration-guide.md (per-file specs with "Migrate after" for DAG)
- PARALLEL after migration-guide done: [PLAN.md + PROGRESS.md] ‖ [findings.md] ‖ [Appium scenarios + fake-server-config]
- Dispatch plan-analyzer → present gaps → user approval
- Read `references/planning-and-execution.md` before this phase

### Phase 2a: SCAFFOLD

- From migration-guide.md, identify ALL external dependencies (classes not being migrated)
- For each: create interface in commonMain + androidMain actual delegating to original
- Build check: `./gradlew :shared:compileDebugKotlin`
- CHECKPOINT COMMIT "scaffold: interfaces for <module>"
- Read `references/migration-reference.md` before this phase

### Phase 2b: SHARED CODE MIGRATION (dependency-level parallelism)

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
    8. Dispatch Haiku verifier (background)
    9. Delete staged androidMain copy
    → FILE_COMPLETE or FILE_BLOCKED
  - Gate: ALL files at this level complete before next level
- After all levels: `./gradlew :shared:testDebugUnitTest`
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/migration-reference.md` and `references/rules-and-guardrails.md` before this phase

### Phase 3: WIRE ANDROID

- PARALLEL: [Haiku per consumer for import updates] ‖ [Sonnet for DI (Hilt→Koin)]
- Delete originals (grep-before-delete)
- Build + test + runtime verify (mobile-mcp/adb)
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/android-wiring.md` before this phase

### Phase 4: APPIUM ANDROID

- Write Appium tests from planned scenarios
- Run against Android app
- Debug failures if any
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/automated-testing.md` before this phase

### Phase 5: WIRE iOS

- PARALLEL: [Sonnet ui-migrator per screen] ‖ [Sonnet Koin iOS]
- Wire navigation + pbxproj
- Build + runtime verify (mobile-mcp/simulator)
- CHECKPOINT COMMIT, update PROGRESS.md
- Read `references/ios-wiring.md` before this phase

### Phase 6: APPIUM iOS

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
| Write characterization tests | agent-prompts/test-writer.md | sonnet | TDD_COMPLETE / TDD_BLOCKED |
| Debug failure | agent-prompts/debugger.md | sonnet | DEBUG_COMPLETE / DEBUG_BLOCKED |
| UI migration (per screen) | agent-prompts/ui-migrator.md | sonnet | UI_COMPLETE / UI_BLOCKED |
| Audit code | agent-prompts/auditor.md | sonnet | AUDIT_COMPLETE / AUDIT_BLOCKED |
| Analyze plan | agent-prompts/plan-analyzer.md | sonnet | PLAN_ANALYSIS |

## References (read ONLY when entering relevant phase)

- `references/planning-and-execution.md` — Phase 1 (PLAN)
- `references/migration-reference.md` — Phases 2a, 2b (SCAFFOLD, SHARED CODE MIGRATION)
- `references/rules-and-guardrails.md` — Phase 2b (SHARED CODE MIGRATION)
- `references/android-wiring.md` — Phase 3 (WIRE ANDROID)
- `references/ios-wiring.md` — Phase 5 (WIRE iOS)
- `references/automated-testing.md` — Phases 4, 6 (APPIUM ANDROID, APPIUM iOS)

## Rules

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
