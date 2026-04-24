# Root Cause Protocol

> Invoked by `debug_investigator` when a subagent hits three-strike. Replaces the external `superpowers:systematic-debugging`.

## Contents

- [The iron law](#the-iron-law)
- [Anti-patterns to reject](#anti-patterns-to-reject)
- [Procedure](#procedure)

## The iron law

**NO FIXES WITHOUT ROOT CAUSE FIRST.**

A patch that makes the symptom go away without identifying the root cause just moves the failure to the next manifestation. The point of this protocol is to find what actually went wrong and propose a fix aligned with the root cause — not to stop the immediate pain.

## Anti-patterns to reject

| Thought | Reality |
|---|---|
| "Just wrap it in a try/catch" | Suppresses the symptom, not the cause. Reject. |
| "Add a retry loop" | Masks a real concurrency/timing bug. Reject unless the OG has the same retry. |
| "Bypass the failing check" | Defeats the verification's purpose. Reject. |
| "Restart solves it" | State corruption fixed by restart indicates a cleanup bug; find it. |
| "Works on my machine" | Environment difference is the clue, not the excuse. |

## Procedure

1. READ the strike report in full — all 3 attempts, their outputs, their failure modes.
2. IDENTIFY the common denominator across the 3 attempts (often: a shared wrong assumption).
3. REPRODUCE the failure in minimal form (strip away everything not needed to trigger it).
4. FORM a hypothesis — what would have to be true at the boundary for the failure to occur?
5. VERIFY the hypothesis with a targeted test (log a specific value, attach an instrumented test, etc.).
6. ONLY AFTER verification, propose a remediation path — what a DIFFERENT subagent dispatch should do, with what different approach.

Do NOT write code fixes here — that's the remediation subagent's job. `debug_investigator` is read-only.
