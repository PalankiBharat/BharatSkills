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
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/resolve-gameplan.sh plan-header"
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
  TeammateIdle:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/validate-completion.sh"
  TaskCompleted:
    - hooks:
        - type: command
          command: "cat | ${CLAUDE_PLUGIN_ROOT}/skills/kmm-workflow/scripts/validate-completion.sh"
---

# KMM Migration Orchestrator

## THE RULE

1:1 BEHAVIORAL PORT. Same observable behavior, identical public API contract.
Zero improvisation. Zero combining. Zero signature changes.
Any behavioral change → REQUIRES_APPROVAL.

## Docs lookup order — NEVER training data first

For ANY library version, API shape, or KMM compatibility question: (1) grep the project's `build.gradle.kts` and source first — live code beats external sources; (2) Context7 (`mcp__context7__query-docs`) or `find-docs` — authoritative current docs; (3) web search — for rapidly-moving KMP libraries; (4) skill references — battle-tested patterns and caveats; (5) training data — NEVER the first resort. Training data has caused real incidents (Paging3 KMP availability, Dispatchers.IO import, library versions). If live lookup fails, explicitly state "unable to verify via live docs" — never fall back to training data silently.

## On Invocation — Preflight

1. If this is a Continue/Verify invocation, read the current gameplan's `findings.md` (in `~/dev/gameplans/<name>/`) for project-specific learnings captured from prior migrations. Project-specific context lives in findings.md, not in the skill.
2. Check agent teams: `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. If unset, ask the user to enable (`export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and restart. Agent teams are REQUIRED for all phases — do not silently fall back to plain sub-agents.

Then ask: Create / Continue / Verify.

## On Invocation — Always Ask for Mode

On ANY invocation, always ask which mode: Create / Continue / Verify. Never auto-pick the mode. The auto-resume behavior described under Continue applies ONLY after the user has explicitly picked Continue — it is not a bypass of the mode prompt.

- **Create** → ask module name, base branch, goal (one question at a time). Research codebase. Write PLAN.md (pure data format — `<!-- KMM-PLAN v1 | skill: 6.6.0 | module: <name> -->` header, execution blueprint, NO workflow instructions), PROGRESS.md (outcome-based tasks), migration-guide.md, findings.md to `~/dev/gameplans/<name>/`. After approval: tell user `/clear` → `/kmm-workflow` → Continue.
- **Continue** (user picked Continue) → if exactly one gameplan exists, auto-resume it (report: "Resuming <name> — Phase N: <description>. Say STOP to switch."). If multiple gameplans exist, list all with status, user picks. Then:
  1. Read PLAN.md header → check `skill: <version>`. If older than current skill version → report mismatch and proceed with current workflow (the plan is DATA; workflow comes from this skill version).
  2. If PLAN.md has old-style workflow instructions (self-documenting header, inline Rules section) → ignore them. The plan is DATA only.
  3. Read PROGRESS.md → determine current phase/task.
  4. Verify/create worktree (`git worktree add <path> <base-branch> -b feature/<name>`, copy `local.properties`).
  5. Continue from last checkpoint.
- **Verify** → unified verification of a migrated module, optionally scoped to a PR diff (`verify --scope=pr <url>`). Runs 3 layers in order:
  - Layer 1 (Static): anti-pattern scan, parity-check.sh, cross-platform parity, phase checklists — no devices needed, fast
  - Layer 2 (Completeness): ViewModel flow inventory audit, callback completeness trace, UI branch audit, DI binding verification — code analysis, no devices. Runs deterministic scripts (flow-collector-check.sh, koin-binding-check.py) plus AI-powered callback and branch analysis.
  - Layer 3 (Device): appium-mcp E2E, 3-build screenshot comparison (master Android vs migrated Android vs iOS), runtime DI check — needs devices, slow.
  Layers 1-2 always run. Layer 3 skips with warning if devices unavailable.
  Classifies each finding: BUG (introduced by migration — must fix), PRE-EXISTING (broken before — document, don't block), INTENTIONAL (deliberate — document in findings.md). With `--scope=pr`, reverse-engineers context from the PR diff + affected files only. Verify REPORTS findings — fixing is a separate phase entered only on user approval (see `references/verify-protocol.md` §Fix Protocol). See `references/verify-protocol.md`.

## Workflow

```
Phase 1 (PLAN) → /clear → Phases 2-3 (scaffold + migrate) → /clear → Phases 4-5 (wiring + testing) → Retrospective → DONE
```

The skill is file-based — nothing is lost on `/clear`. The orchestrator MUST stop after Phase 1 and Phase 3. Before instructing `/clear`, the orchestrator MUST run the migration retrospective — this is a BLOCKING prerequisite, not optional. If the retrospective has not run, do NOT tell the user to `/clear`. Do not continue into the next phase group without clearing.

| Stop after | Why |
|------------|-----|
| Phase 1 (PLAN) | Research + Q&A fills context |
| Phase 3 (SHARED CODE MIGRATION) | Per-file TDD loops bloat context 300K+ tokens |

### Execution Model

3-tier hierarchy: Orchestrator (Opus) → Team Members (Sonnet, tmux panes) → Sub-Agents (Sonnet/Haiku, in worktrees). All execution through agent teams. N independent files → N sub-agents → Nx speed.

Read `references/agent-protocol.md` for: Model Routing, Agent Team Protocol, Haiku Dispatch Protocol, Tmux Integration.

## Phases

### Phase 1: PLAN
- Create `planning-team`. Spawn "researcher" and "plan-analyzer" teammates in ONE message
- Researcher fires parallel Haiku sub-agents: Batch 1 (4 agents), Batch 2 (2 agents), Batch 3 (1 per migration file)
- Plan-analyzer reviews plan after researcher completes → orchestrator fixes BLOCKERs → user approval
- Execution blueprint generated in PLAN.md: per-file deps, parallelism annotations, AND teammate assignments (group files into batches of 5-8, assign each batch a named teammate)
- Read `references/planning-and-execution.md`

### Phase 2: SCAFFOLD
- If >8 interfaces: spawn multiple "scaffolder" teammates (one per batch of 5-8), all in ONE message
- Each scaffolder fires N sub-agents (one per interface, each in worktree)
- After all scaffolders complete: orchestrator runs integration build → CHECKPOINT COMMIT
- Read `references/kmm-architecture.md`

### Phase 3: SHARED CODE MIGRATION
- Create `migration-team`. Read the execution blueprint's teammate assignments
- Spawn one "migration-coordinator" per file batch (5-8 files each) — all coordinators for the same DAG level in ONE message
- Each coordinator fires 1 sub-agent per file (worktree isolation, full TDD pipeline) + overlapping Haiku verifiers
- Orchestrator active loop: monitor TaskList → run integration build when a level completes → spawn next level's coordinators
- Early-start: if a file's specific deps are verified, its coordinator can start immediately — don't wait for the full level
- After all levels: fire auditor + checklist validation teammates in parallel
- Read `references/dependency-replacements.md`, `references/rules-and-guardrails.md`, `references/platform-api-gotchas.md`

### Phase 4+5: WIRE ANDROID + iOS
- Create `wiring-team`. Spawn ALL of the following teammates in ONE message:
  - Multiple "android-wirer" teammates if >8 consumer files (batches of 5-8 each), plus 1 for DI wiring
  - Multiple "ios-coordinator" teammates if >8 screens (batches of 5-8 each)
- Phase 4 android-wirers + Phase 5A ios-coordinators all launch simultaneously (no dependency between them)
- Phase 5B: navigation + pbxproj — blocks on Phase 4 completion (needs confirmed bindings)
- Each teammate fires sub-agents per file within its batch (Haiku for consumer rewiring, Sonnet for DI/screens)
- Inter-agent messaging: teammates DM each other about bindings, API mismatches
- Read `references/android-wiring.md`, `references/ios-wiring.md`, `references/appium-mcp-testing.md`
- **Ad-hoc fix agents:** include "Read `references/platform-api-gotchas.md` before changing any platform API usage" in prompt

## Verification Pipeline

Mandatory at Phase 4/5 boundaries — no skipping, no reordering. Deterministic checks run as Haiku sub-agents; device testing runs as Sonnet sub-agents.

1. build-verify.sh — orchestrator runs (Gradle lock)
2. parity-check.sh — Haiku sub-agent (zero tokens, zero devices)
3. flow-collector-check.sh — Haiku sub-agent (deterministic)
4. koin-binding-check.py — Haiku sub-agent (deterministic)
5. appium-mcp E2E — Sonnet sub-agents (one per platform, parallel on separate devices). See `references/appium-mcp-testing.md`
6. Manual test — structured checklist from migration-guide.md breaking changes

Steps 2-4 run as parallel Haiku sub-agents (all independent). Step 5 fires 2 Sonnet sub-agents (Android + iOS simultaneously).

If any layer fails → fix → rerun from that layer. If manual testing finds a new check → add it to parity-check.sh.

## Migration Retrospective

BLOCKING gate before every `/clear` instruction. Runs in-session with full conversation context.

**Phase 1 — OBSERVE (autonomous):** Scan conversation for 7 categories (A-G: Decision Gaps, Missing Guardrails, Process Improvements, Platform Gotchas, Library Knowledge, Steering Corrections, System & Performance). Score against skill-worthiness gate.

**Phase 2 — DISCUSS (interactive):** Present findings by risk tier. System/process observations → propose optimization with trade-offs → user approves/modifies/skips. Steering corrections → propose rule → user approves. Code/library → batch summary → user approves.

**Phase 3 — APPLY (after approval):** Create `retro-team`, fire parallel Sonnet sub-agents per target file. Bump version, raise PR, self-review.

See `references/self-improvement.md` for full protocol including scan patterns, scoring criteria, and consolidation mandate.

## Team Orchestration Protocol

### Context Budget

Sonnet teammates have ~200K context. Each file migration (TDD pipeline + verifier) consumes ~15-20K tokens of teammate context. Budget accordingly:
- **5-8 files per teammate** — safe ceiling, no compaction risk
- Scale teammates to the work: 20 files → 3-4 teammates, 40 files → 5-8 teammates
- Never cap teammate count — spawn as many as the work requires

### Mandatory Decomposition

The orchestrator MUST decompose every phase into batches of 5-8 files before spawning teammates. For each teammate, the prompt specifies:
1. **Exact file list** — which files this teammate owns (by name, not "the rest")
2. **Sub-agent instruction** — "Fire 1 sub-agent per file, ALL in ONE message"
3. **Dependencies** — which files/teammates must complete first
4. **Reference files** — which references to read for this phase
5. **Expected signals** — FILE_VERIFIED / UI_VERIFIED / etc.

### Parallel Launch

Fire ALL independent teammates in a SINGLE message (multiple `Agent()` calls in one response). Claude Code executes tool calls within one message in parallel — sequential messages create sequential teammates.

```
GOOD: One message → Agent("coord-L0-a", ...), Agent("coord-L0-b", ...), Agent("coord-L0-c", ...)
BAD:  Message 1 → Agent("coord-L0-a"), Message 2 → Agent("coord-L0-b"), Message 3 → Agent("coord-L0-c")
```

### Active Guidance Loop

After spawning a batch of teammates, the orchestrator does NOT wait passively:
1. **Monitor** — check TaskList for completed/blocked tasks
2. **Unblock** — when a DAG level completes, run integration build, then spawn next level's teammates
3. **Re-dispatch** — if a teammate reports BLOCKED, spawn a fresh teammate with debugger prompt
4. **Merge** — as teammates complete, merge worktree branches and update PROGRESS.md
5. **Next batch** — spawn the next set immediately when dependencies resolve

### Teammate Prompt Template

Every teammate receives a prompt structured as:
```
You are <role> for batch <N>. Your files: [exact list].
Fire 1 sub-agent per file, ALL in ONE message (true parallelism).
Each sub-agent gets: isolation: "worktree", mode: "bypassPermissions".
Read: <relevant reference files for this phase>.
Report: <expected completion signal> per file to orchestrator.
After all sub-agents complete: message orchestrator "Batch <N> done, request build."
```

### Model Routing

Opus = orchestrator (decisions, builds, merging) | Sonnet = teammates + code sub-agents | Haiku = mechanical sub-agents (scripts, grep, verification)

### Agent Definitions

See `agents/` — each role has a definition file. The orchestrator spawns MULTIPLE INSTANCES of the same definition when the workload exceeds one teammate's budget (5-8 files).

**Sub-agent prompts:** `references/agent-prompts/` — migrator.md, verifier.md, test-writer.md, debugger.md, ui-migrator.md, auditor.md, plan-analyzer.md

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

On any unexpected state — orphaned agent, failed checkpoint, wrong branch, or an in-progress gameplan whose status the orchestrator cannot interpret — STOP and emit REQUIRES_APPROVAL with the observed state and a minimal fix proposal. Never rollback, reset, or re-dispatch without user approval.

## Rules

1. **1:1 mechanical port** — zero improvisation, zero signature changes; behavioral changes are REQUIRES_APPROVAL
2. **All decisions through user** — REQUIRES_APPROVAL batched at phase boundaries, not one-by-one
3. **Always create worktree** — ALL work in worktrees, including E2E setup and SDK wiring; never on base branch
4. **Orchestrator never writes migration code** — only agents do
5. **TDD non-negotiable** — tests must pass on original AND migrated; FILE_VERIFIED with `tests: 0` is rejected
6. **No deferring tasks** — complete fully or flag as genuinely blocked; "it's complex" is not a valid reason
7. **No type casting** — no `as`, `as?`, `as!`; use polymorphism, generics, or protocol conformance
8. **User provides devices** — the user is responsible for creating/booting emulators and simulators. On Create, ask the user for the Android serial and iOS UDID and record them in PLAN.md header (`<!-- DEVICE: android=<serial> | ios=<UDID> -->`). Every adb/xcrun/appium-mcp call MUST include `$ANDROID_SERIAL` / `$IOS_UDID` explicitly — never `booted` or implicit device. When multiple devices exist, list and confirm with user. Build-install sequence: uninstall → build → install (no `install -r`, which leaves stale state).
9. **Verify every fix automatically** — rebuild + parity-check.sh + flow-collector-check.sh + koin-binding-check.py + appium-mcp E2E before reporting; never report without verification
10. **PROGRESS.md is checklist not journal** — one line per task; details belong in findings.md
11. **Retrospective before /clear** — mandatory and autonomous; skipping means learnings lost permanently
12. **parity-check.sh before appium-mcp E2E** — static analysis first, device testing second; never skip either layer
13. **Verified output, not just completed output** — every agent must produce evidence of verification (deterministic scan + adversarial self-review) before reporting completion; the orchestrator rejects completion signals without evidence fields; see `references/agent-protocol.md` Verified-Output Protocol; orchestrator reads evidence fields from agent output — if deterministic_scan or peer_review fields are absent or critical > 0, re-dispatch the agent with rejection reason
14. **Teams mandatory, no silent fallback** — ALL phases use TeamCreate (planning-team, migration-team, wiring-team, verify-team, retro-team). The orchestrator MUST NOT fall back to plain `Agent()` sub-agents when teams are available. If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is unset, STOP and ask user to enable — do not silently degrade to sequential sub-agent dispatch. Team members fire sub-agents for N independent files; orchestrator never fires sub-agents directly; see `references/agent-protocol.md` Agent Team Protocol
