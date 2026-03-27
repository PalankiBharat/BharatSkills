---
name: kmm-workflow
description: >
  KMM module migration orchestrator. Use for module-level KMM migrations, migration plans,
  or any multi-file KMM work. Single-file migrations can use this or work directly.
argument-hint: "<module-path-or-description>"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1); if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PLAN.md\" ]; then echo '[kmm-workflow] ACTIVE MIGRATION:'; head -15 \"$PLAN_DIR/PLAN.md\"; echo ''; echo '=== recent progress ==='; tail -15 \"$PLAN_DIR/PROGRESS.md\" 2>/dev/null; fi"
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1); if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PLAN.md\" ]; then head -15 \"$PLAN_DIR/PLAN.md\"; fi"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1); if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PROGRESS.md\" ]; then echo '[kmm-workflow] Update PROGRESS.md with what you just did.'; fi"
  SubagentStop:
    - hooks:
        - type: command
          command: |
            PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1)
            if [ -z "$PLAN_DIR" ]; then exit 0; fi
            LAST_OUTPUT=$(tail -5 "$PLAN_DIR/PROGRESS.md" 2>/dev/null)
            # Check for completion promise strings in recent progress
            if echo "$LAST_OUTPUT" | grep -qE "TDD_BASELINE:|MIGRATION_COMPLETE:|AUDIT_COMPLETE:|SCREEN_COMPLETE:"; then
              exit 0
            fi
            echo "[kmm-workflow] WARNING: Agent stopped without a completion promise. Expected one of: TDD_BASELINE, MIGRATION_COMPLETE, AUDIT_COMPLETE, SCREEN_COMPLETE. Check agent output."
            exit 0
  Stop:
    - hooks:
        - type: command
          command: |
            PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1)
            if [ -z "$PLAN_DIR" ] || [ ! -f "$PLAN_DIR/PROGRESS.md" ]; then exit 0; fi
            TOTAL=$(grep -c '## Phase' "$PLAN_DIR/PROGRESS.md" 2>/dev/null || echo 0)
            DONE=$(grep -c '\[x\] Checkpoint' "$PLAN_DIR/PROGRESS.md" 2>/dev/null || echo 0)
            if [ "$DONE" != "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
              echo "[kmm-workflow] Migration in progress: $DONE/$TOTAL phases complete. Update PROGRESS.md before stopping."
            fi
            exit 0
  PreCompact:
    - hooks:
        - type: command
          command: "PLAN_DIR=$(find .claude/gameplans -maxdepth 1 -type d 2>/dev/null | tail -1); if [ -n \"$PLAN_DIR\" ]; then mkdir -p \"$PLAN_DIR/backups\"; TS=$(date +%s); for f in PLAN.md PROGRESS.md FINDINGS.md; do [ -f \"$PLAN_DIR/$f\" ] && cp \"$PLAN_DIR/$f\" \"$PLAN_DIR/backups/${f%.md}_$TS.md\"; done; echo \"[kmm-workflow] Plan files backed up before compaction. Re-read PLAN.md + PROGRESS.md now.\"; fi"
---

# KMM Migration Orchestrator

Self-contained orchestrator for module-level KMM migrations. All domain knowledge lives in
reference files — no external skill dependencies.

## State Machine

```
ASSESS → PLAN → EXECUTE → VERIFY → RUNTIME → MANUAL TEST → DONE
```

Each state transition is enforced by hooks. The orchestrator dispatches agents and runs builds.
**The orchestrator NEVER reads or writes migration code directly** — only agents do.

## Session Recovery

Hooks auto-reload plan on every message. After a disconnect:
1. Hooks inject PLAN.md + PROGRESS.md automatically
2. Read FINDINGS.md for assessment context
3. `git diff --stat` to see changes since last checkpoint
4. Continue from where PROGRESS.md left off

## Agent Dispatch Strategy

| Task | Agent | Mode | Returns |
|------|-------|------|---------|
| File discovery / grep | **Haiku** | background, parallel | File list (~100 tokens) |
| File classification | **Haiku** | background, parallel | Classification line (~50 tokens) |
| Test writing | **Sonnet** | background, parallel | `TDD_BASELINE: <file> \| tests: <test-file> \| count: N` |
| Migration | **Sonnet** | background, parallel | `MIGRATION_COMPLETE: <file> \| swaps: [libs]` |
| Swift screen | **Sonnet** | background | `SCREEN_COMPLETE: <screen> \| components: N` |
| Audit | **Sonnet** | foreground | `AUDIT_COMPLETE: <path> \| issues: N \| auto-fixed: N` |
| Builds / tests | **Orchestrator** | — | Direct Bash output |
| Completeness check | **Sonnet** | foreground | Structured report |

**Rules:**
- All agents: `mode: "bypassPermissions"`, `model: "sonnet"` or `model: "haiku"` as specified
- Background agents: `run_in_background: true` — don't block orchestrator
- Parallel agents: launch in a single message with multiple Agent tool calls
- **Agents return completion promise strings**, not verbose reports
- **Orchestrator validates promises** before advancing — no trust in prose

## Completion Promise Strings

Agents MUST emit exactly one of these at the end of their work:

```
TDD_BASELINE: <file> | tests: <test-file> | count: N
MIGRATION_COMPLETE: <file> | swaps: [list] | expect-actual: [list]
SCREEN_COMPLETE: <screen> | components: N | registered: yes/no
AUDIT_COMPLETE: <path> | issues: N | auto-fixed: N | escalated: N
```

If an agent's output does not contain a completion promise, its work is **not accepted**.
Re-dispatch the agent with more specific instructions.

## Agent Prompt Construction

When dispatching agents, construct prompts from reference files — do NOT invoke skills.

**For test-writing agents:** Read `references/agent-prompts/test-writer.md`, inject into prompt.
**For migration agents:** Read `references/agent-prompts/migrator.md`, inject into prompt.
**For swift-screen agents:** Read `references/agent-prompts/swift-screen.md`, inject into prompt.
**For audit agents:** Read `references/agent-prompts/auditor.md`, inject into prompt.

Each template includes the guardrail cheatsheet + task-specific rules + completion promise format.

## Reference Files

**Always read before the relevant phase:**
- `references/plan-structure.md` — PLAN.md / PROGRESS.md / FINDINGS.md templates (Phase B)
- `references/batched-execution.md` — parallel execution model (Phase C)
- `references/escalation-rules.md` — blocker handling (any phase)
- `references/feedback-capture.md` — feedback files (Phase 0)
- `references/runtime-verification.md` — app launch verification (Phase N+2)

**Read by agents (injected into prompts, not read by orchestrator during execution):**
- `references/migration-workflow.md` — 10-step TDD migration
- `references/dependency-map.md` — Android → KMM library replacements
- `references/android-to-swiftui.md` — Compose/XML → SwiftUI mapping
- `references/skie-interop.md` — Swift/SKIE patterns
- `references/audit-checklist.md` — anti-pattern checklist
- `references/battle-tested-gotchas.md` — production gotchas
- `references/kmm-patterns.md` — KMM patterns quick-reference
- `references/guardrail-cheatsheet.md` — compact rules for all agents

---

## Phase A: Assess

**Orchestrator dispatches Haiku agents for discovery, classifies results.**

- [ ] Step 1: Discover files
  - [ ] Launch **parallel Haiku agents** (background) to grep for feature anchors
  - [ ] Ask user: "Are these the right starting points? Any other names?"
  - [ ] Launch **parallel Haiku agents** (background) to crawl imports recursively
  - [ ] Stop rule: fanout ≥ 3 = shared infra, stop crawling
  - [ ] Reverse grep: find consumers outside the discovered set
  - [ ] Cross-module check: existing versions in :shared
- [ ] Step 2: Classify each file
  - [ ] Launch **parallel Haiku agents** (background) — one per file, returns classification:
    `migrate-pure` | `migrate-swap` | `migrate-expect-actual` | `platform-stay` | `wire-only`
  - [ ] Reference: `references/dependency-map.md` for library classification
- [ ] Step 3: Build assessment — orchestrator synthesizes agent results into:
  - [ ] Internal dependency map
  - [ ] External dependency map (flag blockers)
  - [ ] Bottom-up migration order
  - [ ] Library replacements and risks
  - [ ] Completeness check: classified count = discovered count
- [ ] Step 4: Present and confirm with user

---

## Phase B: Plan

**Orchestrator creates planning files. Read `references/plan-structure.md` for templates.**

- [ ] Task 0.1: Write FINDINGS.md with assessment data (file table, dep map, migration order, risks)
- [ ] Task 0.2: Create feedback files (KMM_FEEDBACK.md, KMM_WORKFLOW_FEEDBACK.md, PLANNING_FEEDBACK.md)
- [ ] Task 0.3: Write PLAN.md with KMM migration phases
  - [ ] Status block in first 15 lines (hooks read this):
    ```
    <!-- STATUS: Phase 0/N | Setup | **Status:** in_progress -->
    <!-- NEXT: Task 0.1 — Write FINDINGS.md -->
    <!-- VERIFY: ./gradlew :shared:testDebugUnitTest -->
    <!-- CHECKPOINT: none yet -->
    ## KMM Migration: <module-name>
    ## Rules (always in scope)
    - TDD: tests written FIRST, baseline must pass, then migrate, re-test WITHOUT test changes
    - Agents return completion promises — no promise = not accepted
    - Simplified Mode for independent files, Full Batched for dependent files
    - 3-platform build at every checkpoint
    - Escalate after 3 failures, never suppress errors
    - Assessment: FINDINGS.md | Feedback: append-only to feedback files
    ```
  - [ ] Phase mapping: each assessment layer → one phase
  - [ ] Phase boundaries by LAYER, no task cap
  - [ ] Compact table format if >50 tasks
- [ ] Task 0.4: Write PROGRESS.md mirroring phases with checkboxes
- [ ] Present summary → wait for user approval

**Phase mapping rules:**
- `migrate-pure` → parallelizable batch
- `migrate-swap` / `migrate-expect-actual` → check deps for batch grouping
- `platform-stay` → separate phase after all migration
- `wire-only` → final phase with audit

---

## Phase C: Execute

**Autonomous execution. Read `references/batched-execution.md` for full model.**

**Before EVERY phase:** Update STATUS block in PLAN.md (first 5 lines). This exploits recency
bias — the write action itself puts objectives into the attention window.

**Mode selection:**

| Condition | Mode |
|-----------|------|
| All files independent (no intra-phase deps) | **Simplified** |
| Files have behavioral dependencies | **Full Batched** |

### Simplified Mode

1. **Dispatch parallel Sonnet agents** (background) — each migrates one file fully
   - Inject `references/agent-prompts/migrator.md` into each prompt
   - Agent returns: `MIGRATION_COMPLETE: <file> | swaps: [...] | expect-actual: [...]`
2. **Orchestrator runs compile check:** `./gradlew :shared:testDebugUnitTest`
   - Red → identify cause → fix → re-run (max 3 attempts → escalate)
3. **CHECKPOINT:** 3-platform build → commit → update PLAN.md status → update PROGRESS.md

### Full Batched Mode (TDD Enforced Structurally)

1. **Dispatch parallel Sonnet agents** (background) — test writing only
   - Inject `references/agent-prompts/test-writer.md` into each prompt
   - Agent reads source file + deps, writes characterization tests in commonTest
   - Agent returns: `TDD_BASELINE: <file> | tests: <test-file> | count: N`
   - **Agent does NOT run Gradle. Agent does NOT write migration code.**
2. **Orchestrator runs BASELINE:** `./gradlew :shared:testDebugUnitTest`
   - ALL tests must pass. If red → fix tests (only time tests may be modified)
3. **Dispatch parallel Sonnet agents** (background) — migration only
   - Inject `references/agent-prompts/migrator.md` into each prompt
   - Agent migrates androidMain → commonMain, applies dep swaps
   - Agent returns: `MIGRATION_COMPLETE: <file> | swaps: [...] | expect-actual: [...]`
   - **Agent does NOT run Gradle. Agent does NOT modify test files.**
4. **Orchestrator runs RE-TEST:** `./gradlew :shared:testDebugUnitTest`
   - Same tests must pass WITHOUT modification
   - Red → fix migration, NEVER tests (max 3 attempts → escalate)
5. **CHECKPOINT:** 3-platform build → commit → update PLAN.md status → update PROGRESS.md

### 3-Strike Escalation

```
ATTEMPT 1: Diagnose & Fix — read error, identify root cause, apply targeted fix
ATTEMPT 2: Alternative Approach — different method, NEVER repeat same action
ATTEMPT 3: Broader Rethink — question assumptions, consider updating plan
AFTER 3: STOP → escalate to user with all attempts + error logs
```

---

## Mid-Flight Discovery

- **Unmapped file found?** → STOP → classify → update FINDINGS.md + PLAN.md + PROGRESS.md → resume
- **Wrong classification?** → reclassify → update plan → note in PROGRESS.md
- **External dep blocker?** → STOP → escalate: (a) migrate dep first, (b) expect/actual, (c) skip

Log all discoveries to FINDINGS.md immediately (2-Action Rule).

---

## Phase N+1: Completeness Verification

- [ ] Orphan scan: any .kt files still in original module?
- [ ] Import scan: grep for old import paths
- [ ] Consumer update check: all imports point to shared module
- [ ] Assessment vs Progress: file counts match
- [ ] Full test suite
- [ ] 3-platform build
- [ ] Report or add remediation tasks

---

## Phase N+2: Runtime Verification

Read `references/runtime-verification.md` for full protocol.

- [ ] Android: build → install → launch → capture logcat → parse crash patterns
- [ ] iOS: install on simulator → launch with console → capture output
- [ ] Fix loop: max 5 attempts per platform → escalate
- [ ] Both platforms clean → proceed to Manual Testing

---

## Phase N+3: Manual Testing Loop

1. User reports bug → dispatch Sonnet agent with `references/agent-prompts/migrator.md` for bugfix
2. Update PROGRESS.md per bug
3. Append to MANUAL_TESTING.md
4. Exit: user says "done testing"
5. Batch graduation: review findings, propose reference file updates, user approves

---

## Post-flight Check

- [ ] Every file from FINDINGS.md accounted for in PROGRESS.md
- [ ] All `migrate-*` files in commonMain with passing tests
- [ ] All `platform-stay` screens have SwiftUI equivalents
- [ ] All `wire-only` files rewired for both platforms
- [ ] 0 orphans, 0 stale imports
- [ ] 3-platform build passes
- [ ] App launches clean on both platforms
- [ ] Audit passes on migrated module
- [ ] Feedback files written and reviewed
- [ ] All PLAN.md phases marked complete
