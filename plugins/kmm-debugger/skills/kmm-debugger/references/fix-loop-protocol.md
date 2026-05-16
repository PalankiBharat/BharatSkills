# Fix-loop protocol — recovering when a shipped fix doesn't fully resolve

A shipped fix that doesn't fully resolve the symptom is the most dangerous moment in a debugging session. The natural instinct is to refine — Fix N → Fix N.1 → Fix N.2 — patching the patch. That's the patches-after-patches loop the user explicitly named as the failure mode this skill is built to prevent.

This file is the recovery procedure. Read it the moment you notice the loop starting.

## Recognizing the loop

Signals that you're entering the loop:

- The same symptom (or a near-symptom) recurs after Fix N shipped
- Fix N "almost works but" — partial resolution, edge cases still firing
- The user reports "the fix didn't work" or "it's still happening"
- You catch yourself drafting "Fix N+1" before re-investigating
- You're tempted to say "I think I see what I missed" without running fresh subagents
- Your proposed Fix N+1 references Fix N's diagnosis as a foundation rather than treating it as invalidated
- The diff between Fix N and Fix N+1 is small — a conditional adjustment, a null check addition, an extra branch

If any of these are present, you're in the loop. The protocol below is the only legitimate response.

## The protocol

### Step 1: Stop

Do not propose Fix N+1. Do not extend Fix N. Do not say "I'll just adjust the conditional." Stop drafting code.

### Step 2: Declare Fix N's diagnosis invalidated — explicitly, to the user

The act of stating it explicitly breaks the bias. Use language like:

> "Fix N (commit SHA) didn't fully resolve the symptom. I'm declaring the diagnosis behind it invalidated. Going to re-fire Phase 1 with a fresh-lens addendum — do not want to patch Fix N because that's the loop this skill is built to prevent."

This is a hard pivot, not a soft adjustment. The user needs to see you switch modes.

### Step 3: Re-fire Phase 1 with the fresh-lens addendum

Use `scripts/dispatch.sh` to regenerate the subagent prompts. Then add this addendum to every prompt before spawning:

```
## Addendum: fresh-lens override

The parent agent previously diagnosed this bug as: <Fix N's diagnosis, verbatim>
The parent agent previously shipped: <Fix N's commit SHA + one-line description>
That diagnosis did NOT fully resolve the symptom.

Your job: investigate as if Fix N never happened. Do NOT propose refinements to Fix N's diagnosis. Do NOT take Fix N as evidence the root cause is in that area. Treat Fix N as one more data point about what is NOT the root cause.

If your fresh investigation lands on Fix N's general area but with a different mechanism, that's a valid finding. If your investigation lands in a completely different area, that's also a valid finding — possibly the more important one.
```

Dispatch the full A/B consensus (8 subagents for ambiguous bugs, 2 for unambiguous). The full dispatch is mandatory — the loop is the failure mode of cutting corners on investigation.

### Step 4: Synthesize the new consensus

Apply the standard consensus synthesis (`subagent-prompts.md` "Consensus dispatch" section). Two outcomes to watch for:

- **The new consensus confirms a fix is needed AND identifies a different root cause than Fix N's diagnosis.** Write Fix N+1 against the new root cause, not as a refinement of Fix N. Make the per-fix summary explicit: "Fix N's diagnosis was wrong because <X>; Fix N+1's diagnosis is <Y>."
- **The new consensus says Fix N's general area was right but the mechanism was different.** Write Fix N+1 as a from-scratch implementation in that area, not as a diff against Fix N's code. (You may end up reverting Fix N and applying Fix N+1 cleanly — that's often the right shape.)
- **The new consensus says the bug was never in the SDK** (e.g., upstream contract violation, Pitfall #7). Escalate to upstream; ship a client shield as a parallel fix, NOT as the primary fix.

### Step 5: Update the skill

After the session, in the closing retro (Q6 in `retro-questions.md`), capture what you learned:

- Which anti-pattern phrase (from `doctrines.md` Doctrine 3) did you almost say before catching yourself? Add it to the catalog if it's not there.
- What recognition criterion in this file ("Recognizing the loop" above) was the one that fired? Did it fire fast enough? If not, sharpen the criterion.
- Did the bias-guard preamble for the fresh-lens dispatch produce subagents that actually pushed back, or did they still inherit Fix N's framing? If the latter, strengthen the preamble.

## What NOT to do

Each of these is an instance of the loop. If you catch yourself about to do any of these, return to Step 1 above.

- **"Let me just tweak the previous fix."** Tweaks are patches. The previous fix's diagnosis is invalidated — there's nothing to tweak.
- **"I think I see what was wrong — let me adjust the conditional."** Even if you're right, the discipline of re-firing Phase 1 is what catches the cases where you're wrong. The discipline is the value.
- **"The fix was close — small refinement should do it."** "Close" is the bias. A/B Template 1 will tell you whether close is close or close is wrong.
- **"I'll add a fallback for the edge case Fix N missed."** Fallbacks added on top of an invalidated diagnosis are scar tissue. The right shape is the from-scratch fix against the new diagnosis.
- **"Let me read the failing code more carefully this time."** More careful reading of the same code with the same frame produces the same biased diagnosis. You need *different* readings (A/B pairs) and *different* angles (Templates 5, 6).
- **"I won't ship until I'm sure, but let me draft Fix N+1 first."** Drafting before re-investigating biases the re-investigation toward confirming the draft. Re-investigate first; draft second.

## Worked example — the real-session case this protocol was built from

In a prod-down ObjectBox UniqueViolationException session, the first investigation diagnosed the bug as "Android storage's dedup logic is broken — need to add a uniqueness check on insert." Fix N shipped (added the uniqueness check). Symptom persisted: still throwing UniqueViolationException, just at a slightly different code path.

What Claude almost did: propose Fix N+1 as "extend the uniqueness check to cover the new code path."

What the user forced (and what this protocol now codifies): stop, declare Fix N invalidated, fresh-lens 4-subagent dispatch.

The fresh investigation surfaced three findings Fix N's diagnosis missed entirely:
1. **iOS already implemented the right business-key upsert pattern** (`ObjectBoxScripStore.swift:565-567`). Android was the deviant — not the SDK as a whole.
2. **`Scrip.id` had zero live BE-bound consumers.** The "must preserve BE id" invariant Fix N had been protecting was vestigial.
3. **The BE had violated a contract today** (Pitfall #7). The SDK was correctly trusting a load-bearing invariant; the BE deploy broke it.

The right fix sequence was:
- Escalate to the BE team to restore the contract (real fix)
- Ship a client-side shield: converge Android's storage to iOS's business-key upsert pattern (parallel fix, removes the deviation)
- Delete the `Scrip.id` preservation machinery as vestigial (Doctrine 3 deletion)

None of those three findings were reachable from Fix N's diagnosis. They required fresh-lens investigation with all biases (toward the existing Android code, toward "SDK is broken", toward "small adjustment to Fix N") explicitly overridden.

Cost of the loop, had it continued: Fix N+1 (extend uniqueness check), Fix N+2 (add fallback for races), Fix N+3 (handle the BE-side variation), Fix N+4 (...). None would have resolved the symptom because none would have identified the actual root cause. Each would have added machinery that the eventual real fix would then have to navigate around.

This is what the patches-after-patches loop costs. The protocol above is the cheapest way out.
