# Story Clarifier

Parse the user story/feature spec and surface everything that's unclear, assumed, or missing BEFORE any analysis begins.

## What to extract from the input

Regardless of format (free text, ticket, structured AC), extract:

1. **Core intent** — What is the user trying to achieve? (one sentence)
2. **Actors** — Who interacts with this feature? (end user, system, admin, external API)
3. **Trigger** — What initiates this feature? (user action, system event, time-based, external)
4. **Input data** — What data does the feature need?
5. **Output/result** — What's the expected outcome?
6. **Scope boundary** — What's explicitly IN scope vs what might be assumed but isn't stated?

## Ambiguity detection

Flag these common ambiguity patterns:

### Vague language
- "should handle errors" → Which errors? How? What does the user see?
- "real-time" → WebSocket? Polling? What latency is acceptable?
- "similar to [existing feature]" → Which parts are similar? What differs?
- "fast" / "performant" → Define the threshold

### Missing states
- What happens on first use (empty state)?
- What happens on failure?
- What happens during loading?
- What happens on partial success?
- What happens on timeout?
- What happens when the user has no permission?

### Unstated business rules (trading/fintech defaults)
- Does this work during market hours only or 24/7?
- Does this apply to all segments (equity, F&O, commodity, currency)?
- Is this pre-market, market hours, post-market, or all?
- Does this need to handle circuit breaker / trading halt scenarios?
- Is this for all exchanges (NSE, BSE, MCX) or specific ones?
- Does the user need to be KYC-verified?
- Are there SEBI/exchange-specific regulations that apply?

### For non-trading apps, check
- Multi-user implications (shared state, permissions)
- Offline behavior
- Data persistence requirements
- Feature flag / rollout strategy

## Output format

```
### Story clarification

**Core intent:** [one sentence]
**Actors:** [list]
**Trigger:** [what starts it]
**Scope:** [in scope] | [ambiguous/out of scope]

**Assumptions made (verify with stakeholders):**
- [ ] [Assumption 1 — why it matters]
- [ ] [Assumption 2 — why it matters]

**Clarifying questions (ask before building):**
- [ ] [Question 1 — what decision depends on the answer]
- [ ] [Question 2 — what decision depends on the answer]

**Missing acceptance criteria:**
- [ ] [Missing AC 1]
- [ ] [Missing AC 2]
```
