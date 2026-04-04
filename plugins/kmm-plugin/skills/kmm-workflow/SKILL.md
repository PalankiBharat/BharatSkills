---
name: kmm-workflow
description: >
  KMM module migration orchestrator. ALWAYS invoke for KMM migrations, migration plans,
  or any KMM work. Use when the user asks to "migrate a module to KMM", "create a migration plan",
  "continue a migration", "port Android to shared code", "move to commonMain", or any work involving
  KMM, Kotlin Multiplatform, shared module migration, or iOS porting.
  Do not attempt KMM migrations directly — use this skill first.
argument-hint: "[create|continue|improve|verify] <module>"
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

1:1 BEHAVIORAL PORT. Same observable behavior, identical public API contract.
Zero improvisation. Zero combining. Zero signature changes.
Any behavioral change → REQUIRES_APPROVAL.

## On Invocation — Always Ask

On ANY invocation, always ask: Create / Continue / Improve / Audit. Never auto-resume. Never assume.

- **Create** → ask module name, base branch, goal (one question at a time). Research codebase. Write PLAN.md, PROGRESS.md, migration-guide.md, findings.md to `~/dev/gameplans/<name>/`. Write session marker. After approval: tell user `/clear` → `/kmm-workflow` → Continue.
- **Continue** → if exactly one non-stale gameplan exists, auto-resume it (report: "Resuming <name> — Phase N: <description>. Say STOP to switch."). If multiple gameplans exist, list all with status, user picks. Write session marker → read PLAN.md + PROGRESS.md → verify/create worktree (`git worktree add <path> <base-branch> -b feature/<name>`, copy `local.properties`) → continue from last checkpoint.
- **Improve** → **FIRST: `cd ~/dev/claude-code-skills`** — ALL file edits use paths under that directory (NEVER `~/.claude/plugins/`). Then: read open GitHub issues with `skill:kmm-workflow` label, classify learnings, create branch, consolidate into skill files (NEVER append — rewrite to absorb), measure file growth, bump patch version in `plugin.json`, raise PR, self-review (Consolidation Mandate rule 6). See `references/self-improvement.md`.
- **Verify** → unified verification of a migrated module. Runs 3 layers in order:
  - Layer 1 (Static): anti-pattern scan, parity-check.sh, cross-platform parity, phase checklists — no devices needed, fast
  - Layer 2 (Completeness): ViewModel flow inventory audit, callback completeness trace, UI branch audit, DI binding verification — code analysis, no devices. Runs deterministic scripts (flow-collector-check.sh, koin-binding-check.py) plus AI-powered callback and branch analysis.
  - Layer 3 (Device): appium-mcp E2E, 3-build screenshot comparison (master Android vs migrated Android vs iOS), runtime DI check — needs devices, slow
  If devices unavailable: Layers 1-2 run fully, Layer 3 reports warning. Always gets useful results.
  Detects existing gameplan state (v6 / pre-v6 / none), upgrades or reverse-engineers migration-guide.md.
  See `references/verify-protocol.md`.
- On completion (all phases done + committed): delete session marker.

## Workflow

```
Phase 1 (PLAN) → /clear → Phases 2-3 (scaffold + migrate) → /clear → Phases 4-5 (wiring + testing) → Retrospective → DONE
```

The skill is file-based — nothing is lost on `/clear`. The orchestrator MUST stop after Phase 1 and Phase 3. Before instructing `/clear`, the orchestrator MUST run the migration retrospective — this is a BLOCKING prerequisite, not optional. If the retrospective has not run, do NOT tell the user to `/clear`. Do not continue into the next phase group without clearing.

| Stop after | Why |
|------------|-----|
| Phase 1 (PLAN) | Research + Q&A fills context |
| Phase 3 (SHARED CODE MIGRATION) | Per-file TDD loops bloat context 300K+ tokens |

## Phases

### Phase 1: PLAN

- Create worktree, research codebase, write migration-guide.md (enriched template with 15 fields), findings.md (with Decisions section), PLAN.md, PROGRESS.md
- Generate build-verify.sh, parity-check.sh; boot emulator/simulator; record device serials in PLAN.md header
- Dispatch plan-analyzer → fix all BLOCKERs → user approval
- Run Phase 1 checklist (`references/phase-checklists.md`) before approval
- Read `references/planning-and-execution.md` for full protocol

### Phase 2: SCAFFOLD

- Create interfaces in commonMain + androidMain actuals; scaffold commonTest, kotlinx-atomicfu if needed
- build-verify.sh → CHECKPOINT COMMIT "scaffold: interfaces for <module>"
- Run Phase 2 checklist (`references/phase-checklists.md`) — Read `references/kmm-architecture.md`

### Phase 3: SHARED CODE MIGRATION (dependency-level parallelism)

- Build DAG from migration-guide.md "Migrate after" fields
- PARALLEL subagents per file (full TDD pipeline) — agents read `references/agent-protocol.md`
- TDD enforcement: FILE_VERIFIED with tests >= Expected tests from migration-guide.md; `tests: 0` is rejected
- Original deletion (two-step): orchestrator deletes before dispatch, verifies after all agents complete
- After all levels: full test suite, auditor sweep, Phase 3 checklist (`references/phase-checklists.md`)
- CHECKPOINT COMMIT — Read `references/dependency-replacements.md`, `references/rules-and-guardrails.md`, `references/platform-api-gotchas.md`

### Phase 4+5: WIRE ANDROID + iOS (parallel where possible)

- Spawn agent team if available (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1), else parallel subagents
  - Android-wirer: imports, DI (Hilt→Koin), delete originals, build+tests
  - iOS UI migration (Phase 5A): can start in parallel with Phase 4 — UI screens only depend on shared ViewModel API from Phase 3, not on Android wiring
  - iOS wiring (Phase 5B): Koin iOS, navigation+pbxproj, build+tests — must wait for Phase 4 to complete (needs confirmed bindings)
  - Team members communicate about shared-code issues (missing Koin bindings, API mismatches)
- After both complete: Verification Pipeline (see below) → CHECKPOINT COMMIT
- Run Phase 4 and Phase 5 checklists (`references/phase-checklists.md`)
- Read `references/android-wiring.md`, `references/ios-wiring.md`, `references/appium-mcp-testing.md`, `references/cross-platform-parity.md`

## Verification Pipeline

Mandatory at Phase 4/5 boundaries — no skipping, no reordering:
1. build-verify.sh — build + unit tests
2. parity-check.sh — static analysis, zero tokens
3. flow-collector-check.sh — ViewModel flow → iOS collector cross-reference (deterministic)
4. koin-binding-check.py — DI resolution verification (deterministic)
5. appium-mcp E2E — 3-build comparison (`references/appium-mcp-testing.md`), both platforms
6. Manual test — structured checklist from migration-guide.md breaking changes

If any layer fails → fix → rerun from that layer. If manual testing finds a new check → add it to parity-check.sh.

## Migration Retrospective

BLOCKING gate before every `/clear` instruction. The orchestrator MUST run this autonomously — if it has not run, the `/clear` instruction MUST NOT be given:
1. Read `references/self-improvement.md` for full protocol
2. Scan conversation + findings.md; cross-reference existing skill files; deduplicate
3. Create/update GitHub issues on skill repo with label `skill:kmm-workflow`

Output per learning: `{category, target_file, existing_rule_to_update, proposed_1_line_change, rationale}`
Generalization mandatory — strip project-specific names, extract reusable patterns. Runs before /clear.

## Agent Dispatch Table

All agents read `references/agent-protocol.md` before starting.

| Task | Prompt | Model | Returns |
|------|--------|-------|---------|
| Migrate file (full TDD pipeline: stage, test, migrate, verify) | agent-prompts/migrator.md | sonnet | FILE_VERIFIED / FILE_BLOCKED |
| Verify migration (structural diff) | agent-prompts/verifier.md | haiku | VERIFY_PASS / VERIFY_FAIL |
| Write characterization tests (standalone — Verify mode and pre-characterization only) | agent-prompts/test-writer.md | sonnet | TDD_COMPLETE / TDD_BLOCKED |
| Debug failure | agent-prompts/debugger.md | sonnet | DEBUG_COMPLETE / DEBUG_BLOCKED |
| UI migration (per screen) | agent-prompts/ui-migrator.md | sonnet | UI_VERIFIED / UI_BLOCKED |
| Audit code (Phase 3 inline) | agent-prompts/auditor.md | sonnet | AUDIT_COMPLETE / AUDIT_BLOCKED |
| Verify module (3-layer) | agent-prompts/verifier-full.md | sonnet | VERIFY_COMPLETE / VERIFY_BLOCKED |
| Analyze plan | agent-prompts/plan-analyzer.md | sonnet | PLAN_ANALYSIS |

## References (read ONLY when entering relevant phase)

- `references/agent-protocol.md` — ALL agents: understand-first protocol, failure modes, completion signals
- `references/phase-checklists.md` — ALL phases: boundary gates
- `references/planning-and-execution.md` — Phase 1
- `references/dependency-decision-framework.md` — Phase 1: dependency Replace/Port/Abstract decisions
- `references/kmm-architecture.md` — Phases 2, 3: expect/actual, source sets, ViewModel/DI/coroutines
- `references/dependency-replacements.md` — Phase 3: library swap tables
- `references/rules-and-guardrails.md` — Phase 3
- `references/platform-api-gotchas.md` — Phase 3: APIs unavailable in commonMain/Native
- `references/android-wiring.md` — Phase 4
- `references/ios-wiring.md` — Phase 5
- `references/cross-platform-parity.md` — Phases 4, 5: cross-platform verification
- `references/appium-mcp-testing.md` — Phases 4, 5, Verify: appium-mcp E2E, vision-based element finding, 3-build comparison
- `references/automated-testing.md` — Phases 4, 5: testing model overview, deterministic verification scripts, adb/xcrun fallback
- `references/verify-protocol.md` — Verify mode: 3-layer verification protocol
- `references/self-improvement.md` — Migration retrospective

## Recovery Protocols

**Orphaned Agent:** Check PROGRESS.md for partial state. If staged androidMain copy exists → re-dispatch migrator. If missing → test-writer first, then migrator. Mark re-queued in PROGRESS.md.

**Failed Checkpoint:** Do NOT proceed. Dispatch debugger per failing file (3-strike). On 3-strike exhausted → REQUIRES_APPROVAL. Rollback: `git reset --hard <last-checkpoint>` (user must approve).

**Wrong Branch:** On Continue, verify worktree is on `feature/<name>` and base branch matches PLAN.md header. Mismatch → STOP, report, do not proceed.

**Stale Sessions:** On Continue, check `.sessions/*.active` age. Older than 24 hours → mark "(stale)". User chooses to clean up or resume.

## Rules

1. **1:1 mechanical port** — zero improvisation, zero signature changes; behavioral changes are REQUIRES_APPROVAL
2. **All decisions through user** — REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
3. **Always create worktree** — ALL work in worktrees, including E2E setup and SDK wiring; never on base branch
4. **Orchestrator never writes migration code** — only agents do
5. **TDD non-negotiable** — tests must pass on original AND migrated; FILE_VERIFIED with `tests: 0` is rejected
6. **No deferring tasks** — complete fully or flag as genuinely blocked; "it's complex" is not a valid reason
7. **No type casting** — no `as`, `as?`, `as!`; use polymorphism, generics, or protocol conformance
8. **Device targeting explicit** — `$ANDROID_SERIAL` in every `adb` command, `$IOS_UDID` in every `xcrun simctl`; appium-mcp sessions target specific device serials; read from PLAN.md header
9. **Verify every fix automatically** — rebuild + parity-check.sh + flow-collector-check.sh + koin-binding-check.py + appium-mcp E2E before reporting; never report without verification
10. **PROGRESS.md is checklist not journal** — one line per task; details belong in findings.md
11. **Retrospective before /clear** — mandatory and autonomous; skipping means learnings lost permanently
12. **parity-check.sh before appium-mcp E2E** — static analysis first, device testing second; never skip either layer
13. **Verified output, not just completed output** — every agent must produce evidence of verification (deterministic scan + adversarial self-review) before reporting completion; the orchestrator rejects completion signals without evidence fields; see `references/agent-protocol.md` Verified-Output Protocol; orchestrator reads evidence fields from agent output — if deterministic_scan or peer_review fields are absent or critical > 0, re-dispatch the agent with rejection reason
