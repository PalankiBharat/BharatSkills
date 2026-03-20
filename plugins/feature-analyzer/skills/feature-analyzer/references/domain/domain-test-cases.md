# Domain Test Cases

Generate test scenarios that validate business rules and domain logic. These are NOT technical tests — they verify the feature behaves correctly from a business perspective.

## Test case generation approach

Think like a business analyst validating the feature against domain rules. Each test case should have:
- **Scenario**: What business situation is being tested
- **Given**: The precondition / business state
- **When**: The action or event
- **Then**: The expected business outcome

## Trading/fintech test scenario categories

### Market state scenarios
- [ ] Feature behavior during market open (normal trading hours)
- [ ] Feature behavior during pre-market session
- [ ] Feature behavior during post-market session
- [ ] Feature behavior on market holidays
- [ ] Feature behavior during extended trading hours
- [ ] Feature behavior during market close transition

### Order and trade scenarios
- [ ] Valid order placement with all required fields
- [ ] Order with minimum lot size / tick size validation
- [ ] Order exceeding available margin
- [ ] Order for suspended/halted instrument
- [ ] Order during circuit breaker (upper/lower circuit hit)
- [ ] Modification of pending order
- [ ] Cancellation of pending order
- [ ] Partial fill scenarios
- [ ] Order rejection by exchange — user notification

### Instrument-specific scenarios
- [ ] Equity cash segment behavior
- [ ] F&O segment behavior (lot sizes, expiry)
- [ ] Commodity segment behavior (MCX trading hours differ)
- [ ] Currency segment behavior
- [ ] Multi-exchange instrument (listed on both NSE and BSE)

### Price and data scenarios
- [ ] Real-time price feed available
- [ ] Price feed delayed or stale
- [ ] Price feed disconnected
- [ ] Price at circuit limit
- [ ] Zero volume / no trades scenario
- [ ] Corporate action adjusted prices

### User state scenarios
- [ ] New user (first time using this feature)
- [ ] User with no holdings/positions
- [ ] User with existing positions in the affected instrument
- [ ] User with pending orders
- [ ] User with insufficient margin/funds
- [ ] User in different risk categories

## For non-trading apps

### General domain test categories
- [ ] Happy path — standard user journey
- [ ] User with different permission levels
- [ ] Data boundary conditions (min/max values)
- [ ] Time-sensitive scenarios (expiry, deadlines)
- [ ] Multi-step workflow — completion and abandonment
- [ ] Concurrent user actions on shared data
- [ ] Feature interaction with existing features

## Output format

```
### Domain test cases
- [ ] **[Scenario name]**: Given [precondition], when [action], then [expected outcome]
- [ ] **[Scenario name]**: Given [precondition], when [action], then [expected outcome]
```

Focus on scenarios that a developer would NOT think of naturally — the non-obvious business rules and domain-specific gotchas.
