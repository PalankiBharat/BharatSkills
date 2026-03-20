# User Test Cases

Generate test cases from the user's perspective. Every scenario starts with what the user DOES and what the user SEES — not system internals.

## Test case structure

For each test case:
- **Precondition**: What state the user/app is in before the test
- **Steps**: What the user does (tap, swipe, type, wait)
- **Expected**: What the user should see/experience
- **Priority**: P0 (must test before release), P1 (should test), P2 (nice to test)

## Mandatory test categories

### Happy path (P0)
- [ ] Primary user journey — feature works exactly as described
- [ ] User completes the full flow end-to-end
- [ ] Success confirmation is visible and clear

### Error states (P0)
- [ ] Network error during the operation — error message shown, retry option
- [ ] Server-side validation failure — clear error message, form not cleared
- [ ] User input validation — inline errors, don't submit invalid data
- [ ] Timeout — user informed, not left hanging
- [ ] Permission denied — clear message, path to resolve

### Empty states (P1)
- [ ] First-time user sees the feature (no data yet)
- [ ] Data was deleted / cleared
- [ ] Search/filter returns no results
- [ ] Empty state has a clear CTA or explanation

### Loading states (P1)
- [ ] Initial load — skeleton/shimmer shown
- [ ] Pull-to-refresh — refresh indicator visible
- [ ] Pagination — loading indicator at bottom
- [ ] Action in progress — button disabled, loading indicator
- [ ] Partial load — some data visible, rest loading

### State persistence (P1)
- [ ] User navigates away and comes back — state preserved
- [ ] User minimizes app and returns — state preserved
- [ ] User rotates device — state preserved
- [ ] User switches tabs — state preserved
- [ ] App killed and relaunched — appropriate state restored

### User interruption scenarios (P1)
- [ ] User cancels mid-operation — clean state, no partial data
- [ ] User navigates back during async operation — operation cancelled cleanly
- [ ] Phone call during operation — app resumes correctly
- [ ] Notification tap during operation — state preserved on return

### Multi-step flows (if applicable) (P1)
- [ ] User completes step 1, goes back, then forward — data retained
- [ ] User abandons at step 2 — can resume or start fresh
- [ ] User completes all steps — confirmation shows summary
- [ ] User presses back on first step — exits flow cleanly

## Trading-specific user scenarios
- [ ] User places order → sees confirmation → order appears in order book
- [ ] User sees real-time price update while viewing the feature
- [ ] User gets notified when their action completes (order executed, alert triggered)
- [ ] User sees correct data after market close (static vs live)

## Output format

```
### User test cases

**P0 — Must test:**
- [ ] [Precondition] → [User action] → [Expected result]

**P1 — Should test:**
- [ ] [Precondition] → [User action] → [Expected result]

**P2 — Nice to test:**
- [ ] [Precondition] → [User action] → [Expected result]
```
