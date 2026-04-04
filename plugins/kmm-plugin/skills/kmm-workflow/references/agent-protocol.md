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

3-strike rule: max 3 fix attempts on the same error before emitting BLOCKED.

## Pre-Completion Checklist

Before emitting any completion signal (`DONE` or equivalent), verify:

1. Read the task list assigned to this agent (from the orchestrator prompt or PROGRESS.md)
2. Confirm each task has `[x]` status — not `[ ]` or `[~]`
3. If any task is incomplete: complete it now, or emit `BLOCKED: <task> incomplete — <reason>`

**Never commit with incomplete tasks.** A commit that leaves tasks unchecked is a silent failure — the orchestrator sees "committed" and moves on, and the uncompleted task is discovered only during final verification. Common pattern: agents complete 4/5 tasks, commit because "the build passes," but the 5th task (e.g., deleting original files) creates import ambiguity later.

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
GOOD: Traced onClick through 3 composable layers to FundsActivity.onAddFundsClick(). Wired to shared ViewModel action.
