# Red-Team Rubric (Adversarial Pass)

Opt-in pass for high-stakes features — trading order paths, payment flows, regulatory/compliance work. The red-team specialist runs AFTER the critic and tries to **break** the output.

## When to enable

Activate via `--adversarial` flag. Always-on cases:

- Story mentions: *order, trade, payment, settle, KYC, AML, SEBI, RBI, PCI, refund, dispute, withdrawal*.
- Story touches money movement or regulated data.

The skill prompts the developer: "This story looks high-stakes (matched keyword `order`). Enable red-team? (y/n)". Default to yes; remember the answer per-session.

## What red-team attacks

The critic checks for structural correctness (schema, evidence, dup, conflict). Red-team attacks **semantic** correctness — questions that look fine but are wrong for this codebase.

### Attack 1 — fake auto-answers

For every question that flow-tracer claims auto-answered, red-team re-asks: "Is the cited fact actually answering this question, or is it superficially similar?"

Example: Flow-tracer cites `HistoryRemoteStore.kt:45` to auto-answer "what's the wire format?". Red-team checks whether line 45 actually answers the question, OR if line 45 is just where the request is built and the wire format is determined elsewhere.

Finding: `auto_answer_invalid` with the question and the cited line.

### Attack 2 — recommended-option wrongness

For every `recommended: true` option, red-team asks: "Is this Recommended right for THIS codebase, or is it generic best-practice that contradicts the existing pattern?"

Example: A design question recommends "Snackbar for error" — but the existing app uses inline error text in every other flow. Red-team flags the recommendation.

Finding: `recommended_off_pattern` with the question, the recommended option, and a counter-example from the codebase.

### Attack 3 — misleading cites

Flow-tracer cites are technically correct (line exists, content matches) but mislead about behaviour. Example: cite says "duration is stored in shared prefs" — true on disk, but at runtime it's read once at app start and never re-read.

Finding: `cite_misleads` with the fact, the cite, and the missing behavioural context.

### Attack 4 — regulatory blind spots

For trading/payment features, red-team runs a regulatory-specific checklist:

- **Order paths**: market-hours rule? circuit-breaker handling? freeze-period scenarios? partial-fill handling? pre-open vs continuous session difference?
- **Payment flows**: idempotency keys present? double-debit guard? settlement-vs-instant disclosure? PCI scope?
- **KYC/AML**: re-KYC trigger conditions? unverified-account caps? sanctions screening?

Each unanswered → `finding: regulatory_gap` with the missing concern.

### Attack 5 — accessibility leak

For UI-bearing features, red-team checks:

- TalkBack labels declared? Focus order tested?
- Dynamic font sizes handled at the recommended option?
- Color contrast on the chosen palette?

Each missed → `accessibility_gap`.

## Output schema

Same envelope as critic (`findings[]`) with `category: "adversarial"`:

```json
{
  "specialist": "red-team",
  "findings": [
    {"id": "rt-1",
     "category": "adversarial",
     "type": "auto_answer_invalid|recommended_off_pattern|cite_misleads|regulatory_gap|accessibility_gap",
     "target_id": "<question or fact id>",
     "detail": "...",
     "counter_evidence": [{"file": "...", "line": 123}],
     "suggested_action": "reopen_question|change_recommendation|add_question|escalate"}
  ]
}
```

## Lead behaviour

Same as critic findings — re-prompt source specialist or apply the suggested action. The difference: red-team findings have higher confidence by construction (they include counter-evidence), so the lead does NOT silently apply `drop` — it always surfaces the finding to the developer at Gate B with the option to accept the red-team's recommendation or override.

## When red-team would be wrong

- It's pattern-matching against a different codebase's conventions. Mitigation: counter-evidence must include a `file:line` from the current repo. No cite from current repo → finding downgraded to `confidence: medium` and surfaced as advisory.
- The "Recommended" was deliberately chosen against codebase pattern to introduce a new pattern. Mitigation: the questioner can flag `intentional_deviation: true` on the option's reason; red-team skips that attack for those questions.

## Output volume control

Red-team can over-fire on long sessions. Cap at:

- 5 `auto_answer_invalid` findings (drop lowest-confidence)
- 3 `recommended_off_pattern` per pillar
- 10 total `regulatory_gap` for the session

Overflow drops are logged at the bottom of the red-team output so the developer knows the cap was hit.

## Why opt-in

Red-team doubles token cost and adds 30-60s wall-clock. For non-high-stakes features the marginal value is low. Keeping it opt-in concentrates compute where the cost of a wrong answer is highest — money, regulation, accessibility.
