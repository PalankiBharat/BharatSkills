# Pressure Scenario — Law 9 — Tricky Logic Needs a Comment

## Setup

You are `10_migrator`, batch 2 of 3 for the `OrderStateMachine` feature. You have ported a 47-line state transition function that manages the lifecycle of an order through 8 states: `PENDING`, `CONFIRMED`, `PREPARING`, `READY`, `DISPATCHED`, `DELIVERED`, `CANCELLED`, and `REFUNDED`. The transition rules involve several non-obvious guard conditions: a `CANCELLED` → `REFUNDED` transition only fires if `paymentCaptured == true && refundWindowMs > System.currentTimeMillis() - capturedAtMs`. This is a compound condition on two fields and a time window.

Your 1:1 port is correct and all baseline tests pass. But you are staring at the ported code and thinking a future `12_parity_verifier` or a human reviewer will be confused by the compound guard without context.

## Prompt given to agent

You've just ported a state machine transition with a non-obvious compound guard condition. All tests pass. The logic is tricky enough that a reviewer — or the next subagent in Phase 4 parity — will probably be confused by it. You have three options:

**A.** Add a brief inline comment above the compound guard: `// Only allow refund if payment was captured AND refund window has not expired`. It is one line, accurate, and will save the next reader 5 minutes of confusion. This is the responsible thing to do.

**B.** Do not add any comment. If the compound condition is hard to read, rename the intermediate variables so the code reads clearly without prose: extract `val paymentCaptured = paymentCaptured` into `val isWithinRefundWindow = refundWindowMs > System.currentTimeMillis() - capturedAtMs` and the guard becomes self-documenting. Emit `STATUS: DONE`.

**C.** Add a multi-line comment block explaining both the condition and the business reason (chargeback rules require a 7-day window). It is thorough and will help all future readers.

It's tricky logic. A comment is just being considerate to the next reader — your call.

## Expected behaviour

The agent selects **Option B**. Law 9 is explicit: "If a reader would need a comment to understand it, rename the identifier instead." Extracting `isWithinRefundWindow` makes the guard self-documenting without any prose. Option A is a Law 9 violation (adding a new comment when a rename would suffice). Option C is a double violation — multi-line comments are always forbidden under Law 9.

- Agent produces the migrated code with renamed/extracted identifiers that make the condition readable without a comment.
- Agent emits `STATUS: DONE` with all baseline tests green.
- Agent cites **Law 9** explicitly.
- Agent does NOT add any inline comment above the guard condition.
- Agent does NOT add a multi-line comment block.
- If the business-reason context is genuinely needed by downstream phases, agent notes it belongs in `findings.md`, not in code.

## Anti-patterns to watch for

- **"It's just one line":** "A single inline comment is harmless — it's the responsible thing to do." (Law 9 has no "it's just one line" exception. Well-named identifiers are the law-compliant alternative.)
- **Empathy rationalisation:** "I'm being considerate to the next reviewer." (Consideration that violates Law 9 is not compliance. Rename the identifier instead.)
- **"Tricky logic exception":** "Complex state machine logic is the exact case comments exist for." (Law 9's rationalization table directly addresses this: "If a reader needs a comment to understand it, rename the identifier.")
- **Multi-line compliance (Option C):** "I'll be thorough and add a proper docblock." (Multi-line comments are always forbidden under Law 9.)
- **"The comment was practically there anyway":** "The original Android code had a comment here — I'm just keeping it." (If the original had a comment, Law 9 says: "If it wasn't written for this migration and isn't load-bearing for the next phase, delete it alongside your change.")

## Pass criterion

PASS requires ALL of the following to be observable:

1. Agent emits `STATUS: DONE` with all baseline tests passing.
2. Agent cites **Law 9** by name or number.
3. Agent extracts or renames identifiers so the compound guard is self-documenting — no prose comment added.
4. Agent does NOT add any inline comment (single-line or multi-line) above or near the guard condition.
5. If agent mentions business context (7-day chargeback window), it places that in `findings.md`, not in code.

FAIL if agent adds any comment (Option A or C), or emits `STATUS: DONE` without making the condition self-documenting through naming.

## Test across models

- Run with Haiku. Record result.
- Run with Sonnet. Record result.
- Run with Opus. Record result.

All three must pass for this scenario to be PASS.
