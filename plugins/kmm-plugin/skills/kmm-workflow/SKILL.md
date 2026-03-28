---
name: kmm-workflow
description: >
  KMM module migration orchestrator. ALWAYS invoke for KMM migrations, migration plans, or any KMM work. Do not attempt KMM migrations directly — use this skill first.
argument-hint: "[create|continue] <module>"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "PLAN_DIR=\"$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)\"; if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PLAN.md\" ]; then echo '[kmm-workflow] ACTIVE MIGRATION:'; head -15 \"$PLAN_DIR/PLAN.md\"; echo ''; echo '=== recent progress ==='; tail -15 \"$PLAN_DIR/PROGRESS.md\" 2>/dev/null; fi"
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "PLAN_DIR=\"$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)\"; if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PLAN.md\" ]; then head -15 \"$PLAN_DIR/PLAN.md\"; fi"
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "PLAN_DIR=\"$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)\"; if [ -n \"$PLAN_DIR\" ] && [ -f \"$PLAN_DIR/PROGRESS.md\" ]; then echo '[kmm-workflow] Update PROGRESS.md with what you just did.'; fi"
  SubagentStop:
    - hooks:
        - type: command
          command: |
            PLAN_DIR="$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)"
            if [ -z "$PLAN_DIR" ]; then exit 0; fi
            LAST_OUTPUT=$(tail -5 "$PLAN_DIR/PROGRESS.md" 2>/dev/null)
            if echo "$LAST_OUTPUT" | grep -qE "TDD_COMPLETE|TDD_BLOCKED|MIGRATION_COMPLETE|MIGRATION_BLOCKED|VERIFY_PASS|VERIFY_FAIL|DEBUG_COMPLETE|DEBUG_BLOCKED|UI_COMPLETE|UI_BLOCKED|AUDIT_COMPLETE|AUDIT_BLOCKED|REQUIRES_APPROVAL|PLAN_ANALYSIS"; then
              exit 0
            fi
            echo "[kmm-workflow] WARNING: Agent stopped without a completion promise. Expected one of: TDD_COMPLETE, TDD_BLOCKED, MIGRATION_COMPLETE, MIGRATION_BLOCKED, VERIFY_PASS, VERIFY_FAIL, DEBUG_COMPLETE, DEBUG_BLOCKED, UI_COMPLETE, UI_BLOCKED, AUDIT_COMPLETE, AUDIT_BLOCKED, REQUIRES_APPROVAL, PLAN_ANALYSIS. Check agent output."
            exit 0
  Stop:
    - hooks:
        - type: command
          command: |
            PLAN_DIR="$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)"
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
          command: "PLAN_DIR=\"$HOME/dev/gameplans/$(cat $HOME/dev/gameplans/.active 2>/dev/null)\"; if [ -n \"$PLAN_DIR\" ]; then mkdir -p \"$PLAN_DIR/backups\"; TS=$(date +%s); for f in PLAN.md PROGRESS.md FINDINGS.md; do [ -f \"$PLAN_DIR/$f\" ] && cp \"$PLAN_DIR/$f\" \"$PLAN_DIR/backups/${f%.md}_$TS.md\"; done; echo \"[kmm-workflow] Plan files backed up before compaction. Re-read PLAN.md + PROGRESS.md now.\"; fi"
---

# KMM Migration Orchestrator

## THE RULE
1:1 MECHANICAL PORT. Only Android→KMM specifics change.
Zero improvisation. Zero combining. Zero signature changes.
Any behavioral change → REQUIRES_APPROVAL.

## On Invocation — Always Ask
On ANY invocation, always ask: Create / Continue. Never auto-resume. Never assume.
- **Create** → ask module name, base branch (default: current, confirm), what user wants to achieve
  - Ask questions one at a time until enough context to plan
  - Research codebase to verify current state
  - Build plan files covering ONLY what's needed (skip done phases)
  - Write to ~/dev/gameplans/<name>/ (mkdir -p if needed)
  - Write .active marker: `echo "<name>" > ~/dev/gameplans/.active`
  - Do NOT use plan mode — write PLAN.md, PROGRESS.md, migration-guide.md, findings.md directly
  - After approval: tell user /clear then /kmm-workflow → pick Continue
- **Continue** → scan ~/dev/gameplans/, list ALL with status, user picks
  - Write .active marker → read PLAN.md + PROGRESS.md → report state → continue
- On completion (all phases done + committed): delete .active so hooks go silent

## Workflow
CREATE (research + write plan files) → user /clear → CONTINUE (fresh context)
## Agent Dispatch (read prompt file, inject into Agent tool)
| Task | Prompt | Model | Returns |
|------|--------|-------|---------|
| Migrate file | agent-prompts/migrator.md | sonnet | MIGRATION_COMPLETE / BLOCKED |
| Verify migration | agent-prompts/verifier.md | haiku | VERIFY_PASS / VERIFY_FAIL |
| Write tests | agent-prompts/test-writer.md | sonnet | TDD_COMPLETE / BLOCKED |
| Debug failure | agent-prompts/debugger.md | sonnet | DEBUG_COMPLETE / BLOCKED |
| UI migration | agent-prompts/ui-migrator.md | sonnet | UI_COMPLETE / BLOCKED |
| Audit code | agent-prompts/auditor.md | sonnet | AUDIT_COMPLETE / BLOCKED |
| Analyze plan | agent-prompts/plan-analyzer.md | sonnet | PLAN_ANALYSIS |
## References (read before relevant phase)
- iterative-execution.md — per-file loop + end-to-end flow
- plan-structure.md — PLAN/PROGRESS/migration-guide/findings templates
- wire-android.md / wire-ios.md — platform wiring phases
- automated-testing.md — Appium + fake server + mobile-mcp
- escalation-rules.md — 3-strike + REQUIRES_APPROVAL
- runtime-verification.md — app launch verification
- guardrail-cheatsheet.md — compact rules for all agents
- dependency-map.md, android-to-swiftui.md, skie-interop.md, audit-checklist.md, battle-tested-gotchas.md, kmm-patterns.md — domain knowledge
## Rules
- Orchestrator NEVER writes migration code — only agents do
- After EVERY migration agent: dispatch verifier (haiku) to diff output vs source
- Always use latest docs (Context7/find-docs/web search), never training data
- REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
- Every decision in files — /clear erases chat, only files survive
