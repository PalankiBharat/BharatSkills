# Agent Protocol

Read this before starting any task. These rules apply to ALL agents in the KMM migration pipeline.

## THE RULE

1:1 BEHAVIORAL PORT. Same observable behavior, identical public API contract.
- Zero improvisation, zero combining
- Method names, parameter names, parameter order, return types, and DEFAULT VALUES must match
- Library swaps MAY change internal structure (callback→suspend, builder→DSL) — this is expected
- Library swaps MUST NOT change the public API surface visible to consumers
- If a swap forces a consumer-visible signature change → document in migration-guide.md "Breaking changes" field → REQUIRES_APPROVAL
- Any behavioral change → REQUIRES_APPROVAL
- No type casting (`as`, `as?`, `as!`) — use polymorphism/generics/protocols

## Understand Before Acting

Before making ANY code change:
1. Read the original (master/prod) implementation of the affected code
2. Read the current migrated implementation
3. Identify the specific delta — what changed and why it's wrong
4. If the root cause is unclear → REQUIRES_APPROVAL with what you found
5. Only then: fix the root cause, not the symptom

NEVER:
- Patch code to make an error go away without understanding why it occurs
- Skip reading master when debugging a migration issue
- Add workarounds, wrappers, or shims — fix the actual migration
- Defer a task because "it's complex" — complete it fully or flag as genuinely BLOCKED

## Library Rules (non-negotiable)

- kotlinx.serialization only (no Gson/Moshi)
- Ktor only (no Retrofit/OkHttp)
- Koin 4 only (no Hilt/Dagger)
- kotlinx-datetime only (no java.time)
- StateFlow only (no LiveData)
- Sealed interface preferred; sealed class for SKIE-consumed Action/Effect types
- No runBlocking on main thread
- expect/actual for platform-specific code

## Dependency Research

Library versions are PINNED in migration-guide.md during Phase 1 planning. Use those versions exactly.
- Do NOT re-research versions during migration — planning already verified them
- If a pinned version causes issues, flag it as REQUIRES_APPROVAL — do not upgrade silently
- Training data is NEVER a valid source for KMM dependency availability

## Decision Presentation

When presenting options (REQUIRES_APPROVAL), recommend based on:
1. KMM community patterns (what's battle-tested)
2. Long-term maintainability
3. Correctness
4. NEVER recommend based on easiness, speed, or convenience

Format:
```
REQUIRES_APPROVAL: <description>
Options:
  A) <option> — <pros/cons, long-term implications>
  B) <option> — <pros/cons, long-term implications>
Recommended: <A or B> — biased toward correctness and maintainability, NEVER speed.
Why: <reasoning>
```

## REQUIRES_APPROVAL — Unified Trigger Criteria

ALL agents use the same criteria. Escalate when:
1. A code change alters observable behavior beyond what migration-guide.md documents
2. A dependency version causes build failure (don't upgrade silently)
3. A file's migration-guide.md entry is incomplete or contradictory
4. Root cause is unclear after reading master + migrated + error

Do NOT escalate when:
1. Library swap changes internal structure (callback→suspend) — this is expected and documented in Breaking changes
2. Import paths change — this is mechanical
3. Logging library swaps (Log→Napier) — pre-approved pattern

## Fresh Evidence

- "should work" is NOT verification. Run the build/test.
- Never claim completion without fresh build output or test results
- Prohibited language: "should work", "probably fine", "seems correct"

## Completion Protocol

Every agent must emit exactly ONE of these on its final line:
- `DONE` — all work complete, verified with fresh evidence
- `DONE_WITH_CONCERNS: <description>` — complete but flagging potential issues for orchestrator review
- `NEEDS_CONTEXT: <what's missing>` — cannot proceed without additional information
- `BLOCKED: <reason>` — tried max attempts, escalating with full error context

**Agent-specific tokens:** Individual agent prompts define task-specific completion tokens (FILE_VERIFIED, UI_VERIFIED, TDD_COMPLETE, VERIFY_PASS, DEBUG_COMPLETE, AUDIT_COMPLETE, PLAN_ANALYSIS) that supersede the generic tokens above. Use the agent-specific token when one is defined in your prompt. The generic tokens (DONE/BLOCKED) are the fallback for agents without a task-specific format.

3-strike rule: max 3 fix attempts on the same error before emitting BLOCKED.

## Pre-Completion Checklist

Before emitting any completion signal (`DONE` or equivalent), verify:

1. Read the task list assigned to this agent (from the orchestrator prompt or PROGRESS.md)
2. Confirm each task has `[x]` status — not `[ ]` or `[~]`
3. If any task is incomplete: complete it now, or emit `BLOCKED: <task> incomplete — <reason>`

**Never commit with incomplete tasks.** A commit that leaves tasks unchecked is a silent failure — the orchestrator sees "committed" and moves on, and the uncompleted task is discovered only during final verification. Common pattern: agents complete 4/5 tasks, commit because "the build passes," but the 5th task (e.g., deleting original files) creates import ambiguity later.

## Workload Limits

Cap individual agent workload at **10–15 files max**. Split larger batches into more agents with smaller scope.

**Why:** Agent batches of 25–30 files cause context compaction and degraded output quality. Navigation/UI agents with 19+ files compacted twice in production. Smaller batches eliminate compaction and maintain consistent output quality.

**How to apply:**
- Orchestrator/coordinator subdivides file lists before dispatching
- If a migration level has 30 files → dispatch 3 agents of 10, not 2 of 15
- Fragment/screen conversion is mechanical but volume is the failure mode — subdivision is mandatory at scale
- When dispatching agents for high-volume tasks (e.g., fragment→composable conversion), the initial agent prompt MUST instruct: "For tasks with >10 files, spawn parallel sub-agents (mode: bypassPermissions) rather than processing sequentially"

## Tool-Call Budget (Anti-Spin)

Every agent has an implicit tool-call budget per task:

- **50 tool calls on a single task** → pause, re-read task description and reference files, try a fundamentally different approach
- **100 tool calls on a single task** → emit `BLOCKED` with full context: what was tried, what failed, current best hypothesis
- **Never exceed 150 tool calls without escalating**

**Signs of spinning (stop immediately):**
- Trying the same approach with minor variations
- Reading the same files repeatedly without extracting new information
- Retrying a command that has failed 3+ times with the same error
- Building automation for something the project may already have (check first)

## Context Compaction Recovery

Long-running agents are subject to context compaction (conversation history summarized, earlier details lost). Treat compaction as a likely event — prepare recovery documents proactively.

### Mandatory handoff document

At every task boundary (each `[x]` checkpoint in PROGRESS.md), update `<gameplan-dir>/HANDOFF.md`:

```markdown
# Handoff: <AgentRole> — <Timestamp>
## Current task: <exact task from PROGRESS.md>
## Completed: <list with commit hashes>
## Remaining: <list>
## Critical context: <non-obvious decisions, build state, pending REQUIRES_APPROVAL>
```

### On context loss detection

If an agent cannot recall what it has done or what's next:
1. STOP all code changes immediately
2. Read PROGRESS.md → determine current task
3. Read HANDOFF.md → recover context
4. Confirm current state (`git status`, build check) before proceeding
5. Never reconstruct context from guesses — read the files

## Verified-Output Protocol

Every agent must produce **evidence of verification**, not just evidence of completion. "It compiles and tests pass" is necessary but not sufficient.

### Two-layer verification

**Layer 1 — Deterministic scans (known patterns, fast, free):**
Grep your own output file for known CRITICAL/HIGH patterns from `references/rules-and-guardrails.md`:
- CRITICAL: `runBlocking` outside test code, `TODO()`, type casts (`as `, `as?`, `as!`), hardcoded secrets
- HIGH: inline `CoroutineScope(`, undisposed fields with `dispose()`/`close()`/`cancel()`, `setState(getState().copy(` (non-atomic), callback params with default `= {}`

Report counts in your completion signal. Any CRITICAL > 0 → fix before completing.

**Layer 2 — Adversarial peer review (unknown patterns, AI judgment):**
After your deterministic scan, re-read the original source AND your migrated output side by side. Look for ANY difference that changes behavior or appearance — not from a checklist, but with the mindset: "what could go wrong here that nobody anticipated?"

Focus on:
- Default values that silently changed
- String literals that differ in casing or wording
- Conditional branches present in original but absent in migrated
- Error handling paths removed or altered
- Concurrency that was parallel in original but sequential in migrated

### Evidence format

Every completion signal must include structured evidence. The orchestrator validates this — missing fields or non-zero CRITICAL counts cause rejection.

Agent-specific formats are defined in each agent prompt, but all must include at minimum:
- `deterministic_scan: N issues` (0 = clean)
- `peer_review: PASS | FAIL | N/A` (self-review of own output)

## Failure Modes to Avoid

BAD: Patched the composable to skip the null check because it crashed on iOS.
GOOD: Read master — found OnCompletionListener was registered in Application.onCreate(). Added equivalent registration in iOS AppDelegate.

BAD: Changed method signature to accept nullable parameter because test failed.
GOOD: Read migration-guide.md — original method is non-null. Test fake was returning null. Fixed the fake, kept signature identical.

BAD: Skipped Dispatchers.IO replacement because "it compiled fine on JVM."
GOOD: Checked platform-api-gotchas.md — Dispatchers.IO needs explicit import on Native. Applied replacement.

BAD: Added a try-catch wrapper around the crashing code.
GOOD: Read master — crash was due to missing SDK listener registration. Added registration in AppDelegate (same pattern as Android Application class).

BAD: Left onClick = {} because "parent wasn't obvious."
GOOD: Traced onClick through 3 composable layers to MyActivity.onButtonClick(). Wired to shared ViewModel action.

## Build Coordination

### Worktree Isolation Model (primary)

Sub-agents that modify code run with `isolation: "worktree"` — each gets a temporary git worktree with its own Gradle daemon. No lock contention, no cross-agent test contamination.

```
Team member fires N sub-agents (each in own worktree):
  [Sub-agent A: worktree-A] → own ./gradlew → full TDD pipeline → FILE_VERIFIED
  [Sub-agent B: worktree-B] → own ./gradlew → full TDD pipeline → FILE_VERIFIED
  [Sub-agent C: worktree-C] → own ./gradlew → full TDD pipeline → FILE_VERIFIED
  
Team member: merge each branch back (trivial — different files)
Team member → orchestrator: "request integration build"
Orchestrator: single ./gradlew build (verify combined state)
```

**Rule: Sub-agents own full pipeline in worktrees, coordinator owns integration builds.**
- Sub-agents run `./gradlew` freely WITHIN their worktrees (separate Gradle daemons, no lock)
- The orchestrator/coordinator runs ONE integration build after merging all worktree branches back
- Integration builds catch combined-state issues that individual builds can't

### Shared-Worktree Fallback

When worktree isolation is not used (e.g., read-only verification, script execution):

**Gradle acquires a per-project lock.** Multiple agents running `./gradlew` on the same project deadlock. In shared-worktree mode, agents are limited to file operations only — the orchestrator runs builds.

### Script Execution

Deterministic scripts (`parity-check.sh`, `flow-collector-check.sh`, `koin-binding-check.py`) do NOT acquire the Gradle lock. These CAN be run by Haiku sub-agents or team members anywhere. Only `./gradlew` and `xcodebuild` commands are lock-sensitive.

## Model Routing

The KMM workflow uses a 3-tier model hierarchy. Every agent must know its tier.

### Tier 1: Orchestrator (Opus)
The main Claude Code session. Handles:
- Mode selection (Create/Continue/Improve/Verify/Audit)
- Phase transition decisions
- REQUIRES_APPROVAL evaluation and user interaction
- Plan approval (evaluating plan-analyzer output)
- Build ownership (Gradle lock — only the orchestrator runs `./gradlew` or `xcodebuild`)
- Retrospective judgment (evaluating learning quality)
- Fix-or-escalate decisions after agent BLOCKED
- Merging team member results into canonical files (PLAN.md, PROGRESS.md, findings.md)

The orchestrator NEVER writes migration code. It creates teams, dispatches teammates, handles decisions, and owns builds.

### Tier 2: Team Members (Sonnet, in tmux panes)
Long-running agents spawned via `Agent(team_name=..., name=...)`. Each owns a phase or scope:
- "researcher" — owns Phase 1 research, fires Haiku sub-agents for parallel grep/read tasks
- "migration-coordinator" — owns Phase 3, fires Sonnet sub-agents per file for TDD pipeline
- "android-wirer" — owns Phase 4, fires Haiku sub-agents for consumer rewiring
- "ios-coordinator" — owns Phase 5, fires Sonnet sub-agents per screen
- "verifier" — owns Verify mode, fires sub-agents per layer check
- "consolidator" — owns retrospective apply phase, fires sub-agents per target file

Team members:
- Run in tmux panes (own context window, no bloat to orchestrator)
- Read the execution blueprint from PLAN.md to determine parallelism
- Fire sub-agents for every parallelizable task (N independent files → N sub-agents)
- Coordinate with other team members via messaging (SendMessage)
- Report summaries to orchestrator (never raw output — keep orchestrator context lean)
- Escalate REQUIRES_APPROVAL and BLOCKED to orchestrator

### Tier 3: Sub-Agents (Sonnet or Haiku, in-process)
Short-lived agents fired by team members via `Agent()`. Each owns a single file or check:
- Sonnet sub-agents: full TDD pipeline per file, UI screen migration, DI wiring, debugging
- Haiku sub-agents: structural verification, script execution, grep audits, import rewiring, checklist validation

Sub-agents:
- Receive minimal context (one file + its migration-guide.md entry + agent prompt)
- Return structured completion signals (FILE_VERIFIED, VERIFY_PASS, etc.)
- Never message other agents — only return results to their parent team member
- Never run `./gradlew` or `xcodebuild` — only file operations and script execution

## Agent Team Protocol

All modes use `TeamCreate` for coordination. Teammates self-organize via shared task lists.

### Team Lifecycle
1. Orchestrator creates team: `TeamCreate("migration-team")`
2. Orchestrator creates tasks: `TaskCreate(...)` with dependencies (`addBlockedBy`)
3. Orchestrator spawns teammates: `Agent(team_name=..., name=..., model="sonnet")`
4. Teammates claim tasks: check `TaskList`, claim with `TaskUpdate(owner=...)`
5. Teammates work: fire sub-agents, collect results, mark tasks done
6. Teammates check for next work: `TaskList` after each completion
7. Teammates message each other: `SendMessage(to="android-wirer", message="...")`
8. On completion: orchestrator sends shutdown, `TeamDelete`

### Inter-Agent Messaging
Team members can DM each other directly — no orchestrator mediation needed for:
- Sharing confirmed Koin bindings (android-wirer → ios-coordinator)
- Reporting API mismatches found during migration
- Coordinating on shared-code changes

Always escalate to orchestrator for:
- REQUIRES_APPROVAL decisions (behavioral changes)
- BLOCKED after 3 strikes (technical failures)
- Build requests (Gradle lock ownership)

### Task Dependency Tracking
Use `addBlockedBy` to encode dependencies:
- Phase 5B tasks blocked by Phase 4 completion
- Verify Layer 2 tasks blocked by Layer 1 tasks
- Per-file migration blocked by specific file dependencies (not entire DAG level)

Team members check `TaskList` to find unblocked tasks. When a dependency resolves, blocked tasks automatically become claimable.

## Haiku Agent Dispatch Protocol

Haiku agents handle mechanical/deterministic tasks. They receive minimal prompts and return structured output.

### Prompt Format
Haiku agents receive context inline — no reference file loading. Prompt structure:
```
Task: <one-line description>
Input: <file paths or data to process>
Output format: <exact structure expected>
Constraints: <what NOT to do>
Parallelism: For >10 files, spawn parallel sub-agents — do not process sequentially.
```

Example:
```
Task: Rewire imports in MyConsumer.kt from com.app.auth to shared.auth
Input: /path/to/MyConsumer.kt
Output format: DONE: <file> | imports_changed: N | lines_modified: N
Constraints: Only change import statements. Do not modify any logic or method bodies.
```

### Rules for Haiku Agents
- Complete within 60 seconds (if exceeding, the task is too complex for Haiku)
- Return structured output with clear delimiters (not prose)
- Never run `./gradlew` or `xcodebuild`
- Never make judgment calls — emit `NEEDS_CONTEXT: <what's unclear>` and let the parent team member decide
- Never load reference files (agent-protocol.md, rules-and-guardrails.md, etc.) — context is provided inline
- Never write to shared files (PLAN.md, PROGRESS.md, findings.md) — return data to parent for merging

### When Haiku Is Wrong Tier
If a Haiku agent encounters any of these, it should emit NEEDS_CONTEXT immediately:
- Ambiguous code structure requiring judgment
- Multiple valid approaches for a change
- Code that might change behavior (not just imports/formatting)
- Files with complex interdependencies

## Tmux Integration

Long-running team members run in tmux panes for true OS-level parallelism and independent context windows.

### When to Use Tmux Panes
- Any team member expected to run >5 minutes
- Any team member that fires its own sub-agents
- Sonnet-tier agents: migrators, UI migrators, wiring coordinators, auditors, E2E testers

### When NOT to Use Tmux Panes
- Haiku agents (complete in <60 seconds — pane overhead not worth it)
- One-shot sub-agents that return immediately

### Setup

Claude Code handles tmux pane creation automatically. No manual `tmux` commands needed.

1. Set `"teammateMode": "tmux"` in `~/.claude.json` (global) or pass `--teammate-mode tmux` per session
2. When the lead spawns teammates, Claude Code auto-creates panes — one per teammate
3. On disconnect, tmux sessions persist and teammates can resume
4. On cleanup (`TeamDelete`), panes are removed

Requires `tmux` installed (`brew install tmux` on macOS). For iTerm2, install the [`it2` CLI](https://github.com/mkusaka/it2) and enable Python API in iTerm2 preferences.

### User Interaction
- **Split-pane mode:** click into a teammate's pane to interact directly
- **In-process mode (fallback):** `Shift+Down` cycles through teammates
- `Ctrl+T` toggles the task list view
- `Escape` interrupts a teammate's current turn
