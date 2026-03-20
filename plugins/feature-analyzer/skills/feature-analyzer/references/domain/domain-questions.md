# Domain Questions

Generate business and domain questions that must be answered before development. These are questions for PMs, business analysts, and domain experts — not technical questions.

## Question generation framework

For each question, explain WHY the answer matters for implementation.

### Business logic questions
- What are the exact business rules governing this feature?
- Are there conditional rules based on user type, plan, or tier?
- What are the boundary conditions of the business rules?
- Are there time-based rules (market hours, settlement cycles, expiry dates)?
- How does this interact with existing business workflows?

### Trading/fintech specific questions
- **Market timing**: Does this feature behave differently during pre-market, market hours, post-market, weekends, or holidays?
- **Segment rules**: Do rules differ across equity, F&O, commodity, currency segments?
- **Exchange rules**: Any exchange-specific behavior (NSE vs BSE vs MCX)?
- **Order lifecycle**: Where in the order lifecycle does this feature apply (placed, pending, executed, rejected, cancelled)?
- **Price types**: Does this work with all price types (market, limit, SL, SL-M)?
- **Settlement**: Any T+1/T+2 settlement implications?
- **Corporate actions**: How is this affected by splits, bonuses, dividends, rights issues?
- **Circuit breakers**: Behavior during upper/lower circuit or trading halts?
- **Auction sessions**: Does this apply during call auction?

### User impact questions
- Who are the target users for this feature?
- What's the user's expected workflow / happy path?
- What error messages should the user see?
- Is there a rollback path if the user makes a mistake?
- How do we communicate state changes to the user?

### Data questions
- What data sources does this feature depend on?
- What's the data freshness requirement (real-time, near-real-time, daily)?
- Data format and contract — is the API schema finalized?
- Historical data requirements?
- What happens when data is unavailable or stale?

### For non-trading apps
- What are the core business rules?
- User segmentation / feature access rules?
- Content moderation or review requirements?
- Notification / communication rules?
- Third-party integration dependencies?

## Output format

```
### Business questions to clarify
- [ ] [Question] — Impact: [What changes based on the answer]
- [ ] [Question] — Impact: [What changes based on the answer]
```

Prioritize questions by impact — questions whose answers fundamentally change the implementation come first.
