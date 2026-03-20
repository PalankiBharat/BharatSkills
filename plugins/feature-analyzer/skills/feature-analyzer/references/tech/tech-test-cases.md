# Tech Test Cases

Generate technical test cases that verify the implementation correctness at the code level. These complement domain test cases — focus on HOW things work, not WHAT the business expects.

## Test categories

### API / Network layer
- [ ] Successful API response — correct parsing and mapping
- [ ] API error response (4xx) — proper error handling and user message
- [ ] API server error (5xx) — retry logic, fallback, user notification
- [ ] Network timeout — timeout handling, cancellation
- [ ] No internet connection — offline handling, cached data fallback
- [ ] API response with unexpected/missing fields — graceful degradation
- [ ] API response with null values in non-nullable fields
- [ ] API pagination — first page, middle page, last page, empty page
- [ ] API rate limiting — 429 handling, backoff strategy
- [ ] Concurrent API calls — proper sequencing, no race conditions

### Data layer (Room / local storage)
- [ ] Database insert — new record, duplicate handling
- [ ] Database update — partial update, full update
- [ ] Database delete — cascade behavior, orphan data
- [ ] Database migration — schema change, data preservation
- [ ] Database query performance — large dataset behavior
- [ ] Cache invalidation — stale data detection, refresh strategy
- [ ] SharedPreferences — read/write correctness, default values

### Coroutine / Flow layer
- [ ] Flow collection — correct scope, lifecycle awareness
- [ ] Flow cancellation — ViewModel cleared, scope cancelled
- [ ] Flow error handling — catch in the right place
- [ ] StateFlow / SharedFlow — initial value, replay behavior
- [ ] Multiple collectors — shared vs independent collection
- [ ] Coroutine exception handling — structured concurrency
- [ ] Dispatcher usage — IO for network/db, Main for UI, Default for computation

### Hilt / DI
- [ ] Dependency provided correctly in the right scope
- [ ] Singleton vs scoped instance — correct lifecycle
- [ ] Test module overrides — can mock dependencies for testing
- [ ] Qualifier usage — correct binding when multiple implementations exist

### ViewModel / State management
- [ ] Initial state — correct defaults
- [ ] State transitions — valid state machine flow
- [ ] Event handling — one-time events consumed correctly
- [ ] SavedStateHandle — process death survival
- [ ] Multiple rapid events — debounce, throttle, conflation

## Output format

```
### Tech test cases
- [ ] **[Category]**: [Test scenario] — Expected: [behavior]
- [ ] **[Category]**: [Test scenario] — Expected: [behavior]
```

Prioritize tests that catch bugs a developer would miss during manual testing.
