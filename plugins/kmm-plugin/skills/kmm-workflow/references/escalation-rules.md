# Escalation Rules Reference

This file defines when and how to escalate blockers during KMM workflow execution.

---

## Never Work Around Blockers With Hacks

When the plan or requirements specify how something should work, implement it as specified. If you hit a blocker that makes the specified approach seem impossible, STOP and escalate — do not invent workarounds to keep the build green. Specifically:

- **No stubs or placeholder implementations** — don't create empty/mock implementations just to satisfy the compiler
- **No technology substitutions** — don't swap a specified dependency for a "simpler" alternative (e.g., using an in-memory store instead of SQLDelight because you think it won't work on the target platform)
- **No feature omissions** — don't skip or simplify specified behavior to avoid a hard problem
- **No silent downgrades** — don't weaken types, remove nullability constraints, or broaden error handling to make things compile

---

## When to Escalate

If implementing a task as specified would require something you're unsure about (platform support, library compatibility, API availability), stop and present the user with:

1. **The blocker** — what you're trying to do and why it's not straightforward
2. **Options** (2-4), each with:
   - What it involves
   - Pros
   - Cons
   - Your confidence it will work
3. **Your recommendation** — which option you'd pick and why

Wait for the user to choose before proceeding.

---

## 3-Strike Error Protocol

Before escalating a technical failure, make up to 3 attempts with distinct approaches. Track every attempt in FINDINGS.md under "Issues Encountered" and in PROGRESS.md.

- **Attempt 1 — Diagnose:** Try the obvious fix. If it fails, read the error carefully and diagnose the root cause before attempting again.
- **Attempt 2 — Different approach:** Change strategy based on what you learned. Do not retry the same thing. Consult docs, check related files, try an alternative implementation path.
- **Attempt 3 — Rethink:** Step back and question your assumptions about the problem. Re-read the relevant plan section and FINDINGS.md. Try a fundamentally different approach.
- **After 3 failures — Escalate:** Present the user with all three attempts, what failed in each, and your current best hypothesis. Never attempt a 4th variation silently.

The goal of 3 strikes is to avoid both giving up too early and spinning indefinitely. Each attempt must represent a materially different approach — not a minor variation.

---

## Never Repeat Failures

Once an approach has failed, it is off the table. Track all attempted approaches in PROGRESS.md alongside the task they belong to, so any agent resuming the plan can see what has already been tried. Mutate your approach with every attempt — do not retry the same command, the same dependency version, or the same wiring pattern that already failed.

Format in PROGRESS.md:

```
- [~] Task 3.2: Wire expect/actual for PlatformLogger
  - Attempt 1: Used typealias — failed, typealias not allowed for expect class with function bodies
  - Attempt 2: Used abstract expect class — failed, iOS actual requires open, not abstract
  - Attempt 3: Refactored to interface + platform impl — SUCCEEDED
```

---

## KMM-Specific Escalation Triggers

### Dependency Not in dependency-map.md

If a dependency needed for migration is not listed in `dependency-map.md` (or the equivalent FINDINGS.md Dependency Map), do not guess at a replacement. Either:

- **Search docs first** — check the library's official KMM/CMP compatibility page and record findings in FINDINGS.md under "Research"
- **Escalate to user** — if the compatibility status is unclear or no KMM alternative is documented, stop and present options

Never assume a library is KMM-compatible without verification.

### expect/actual Unclear

If the correct shape of an `expect`/`actual` declaration is ambiguous (e.g., should it be a class, interface, typealias, or object; what belongs in common vs. platform), do not guess. Present the user with:

- The specific declaration in question
- 2-3 concrete options for how to structure it
- Trade-offs for each (e.g., testability, iOS interop, API surface)
- Your recommendation

Wait for the user to decide before writing any expect/actual code.

### SKIE Interop Issue

If an interop issue arises related to Swift/Kotlin interface exposure (e.g., generics not visible in Swift, suspend functions not bridged, flows not exposed):

1. **Check `skie-interop.md` first** — the reference may already document the correct SKIE annotation or configuration for this pattern
2. If the answer is there, apply it and record in FINDINGS.md
3. If `skie-interop.md` does not cover the case, escalate to the user with the specific interop failure, what you've tried, and what SKIE docs say (record the docs excerpt in FINDINGS.md before escalating)

Never suppress an interop issue by changing the API shape without user approval.

### Tests Fail After Migration and Cause Is Unclear

If tests fail after a migration step and the cause is not immediately obvious:

- **STOP.** Do not continue to the next task.
- Do not suppress, skip, or comment out the failing tests.
- Do not mark the task `[x]` in PROGRESS.md.
- Record the failure in FINDINGS.md under "Issues Encountered."
- Apply the 3-Strike Error Protocol to diagnose the root cause.
- If all 3 attempts fail to resolve the failure, escalate with full context: which test, what error, what you tried, your current hypothesis.

Test failures are signal. Suppressing them destroys the value of the test suite and violates the non-negotiable rule: **the codebase is always in a verified, buildable, passing state at every checkpoint.**
