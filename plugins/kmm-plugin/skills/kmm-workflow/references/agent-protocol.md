# Agent Protocol

Read this before starting any task. These rules apply to ALL agents in the KMM migration pipeline.

## THE RULE

1:1 MECHANICAL PORT. Only Android→KMM specifics change.
- Zero improvisation, zero combining, zero signature changes
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
