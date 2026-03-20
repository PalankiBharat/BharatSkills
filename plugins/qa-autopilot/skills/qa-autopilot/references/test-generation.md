# Test Case Generation Framework

## Generation Strategy

For every affected screen/feature identified in the change analysis, systematically generate test cases across ALL applicable dimensions. Do not cherry-pick — exhaustiveness catches bugs.

## Dimension 1: Happy Path

The primary success scenario. What the developer intended to work.

**Template:**
```
Precondition: {valid state, valid data, network available}
Steps: {the golden flow from start to finish}
Expected: {success state — data saved, screen navigated, confirmation shown}
```

**Think about:**
- What is the primary user story this change serves?
- What does the PM expect to demo?
- What would the developer show in a code review?

## Dimension 2: Boundary Values

Test the limits. Where numbers, strings, and collections have edges.

**For numeric inputs:**
- Zero (0)
- One (1) — the off-by-one killer
- Maximum allowed value
- Maximum + 1 (should reject)
- Negative values
- Decimal precision limits (e.g., ₹0.01 for prices)
- Very large numbers (overflow risk)

**For text inputs:**
- Empty string
- Single character
- Maximum length
- Maximum length + 1
- Special characters: `<>&"'/\`
- Unicode: emojis 🔥, RTL text, CJK characters
- Only whitespace
- Leading/trailing spaces
- SQL injection patterns (shouldn't matter but verify)

**For collections/lists:**
- Empty list (0 items)
- Single item (1 item)
- Full page (boundary of pagination)
- Very large list (performance, scrolling)

## Dimension 3: Error States

What happens when things go wrong?

**Network errors:**
- No internet connection
- Slow network (timeout)
- API returns 400 (bad request)
- API returns 401 (unauthorized — token expired)
- API returns 500 (server error)
- API returns unexpected response shape

**Input validation errors:**
- Required field left empty
- Invalid format (email, phone, PAN, etc.)
- Duplicate entry
- Conflicting values

**App state errors:**
- Session expired mid-flow
- Stale data (opened screen, data changed server-side)
- Feature flag disabled after screen loaded

## Dimension 4: State Transitions

Test every possible state the UI can be in and transitions between them.

```
States: Initial → Loading → Success | Error | Empty
```

**Test each transition:**
- Initial → Loading: Shows loading indicator?
- Loading → Success: Data renders correctly? Loading dismissed?
- Loading → Error: Error message shown? Retry button works?
- Loading → Empty: Empty state shown with proper message?
- Error → Loading (retry): Loading shown again? Previous error cleared?
- Success → Loading (refresh): Pull-to-refresh works? Data updates?

## Dimension 5: Interruptions

Real users don't follow the happy path linearly.

- **Back press**: At each step, what happens on back press?
- **App backgrounded**: Leave mid-flow, come back — state preserved?
- **Process death**: App killed by system, restored — state preserved?
- **Rotation**: Screen rotates mid-flow — state preserved? Layout correct?
- **Incoming call**: Phone call interrupts — app resumes correctly?
- **Notification tap**: User taps a notification mid-flow — navigation correct?
- **Multi-window**: App in split screen — layout adapts?

## Dimension 6: Regression

The most critical dimension. What EXISTING functionality could break?

**For every screen in the impact graph that was NOT directly changed:**
1. Can the user still reach the screen via normal navigation?
2. Does the screen still load data correctly?
3. Do all interactive elements still work (buttons, inputs, toggles)?
4. Is the data displayed correctly (no missing fields, no wrong formatting)?
5. Do error states still show correctly?

**Pay extra attention to:**
- Screens sharing the same ViewModel or Repository that changed
- Screens using the same data model that changed
- Screens in the same navigation graph where nav args changed
- Any screen that calls the same API endpoint that changed

## Dimension 7: Data Edge Cases

What weird data can the backend send?

- Null/missing optional fields
- Empty strings where text expected
- Very long strings that could overflow UI
- Dates in unexpected formats
- Negative amounts/quantities
- Currency with many decimal places
- Mixed encodings
- Missing images (broken URLs)

## Dimension 8: Concurrency & Timing

Race conditions and rapid interactions.

- **Rapid taps**: Tap a button 5 times fast — does it fire once or five times?
- **Double submit**: Submit a form, tap submit again before response — duplicate created?
- **Back during loading**: Hit back while API call in progress — crash? Memory leak?
- **Multiple data sources**: If screen shows data from 2 APIs, what if one fails?
- **Stale cache**: Cached data differs from server — which wins?

## Dimension 9: Navigation

The back stack is where bugs go to hide.

- **Deep link**: Can the screen be reached via deep link? Does it have the right data?
- **Back stack**: After complex navigation, does Back go to the right screen?
- **Pop to root**: Does "go home" from deep in the stack work?
- **Tab switching**: Switch tabs, switch back — state preserved?
- **Same screen re-entry**: Navigate to ScreenA → ScreenB → ScreenA — fresh or cached?

## Dimension 10: Performance & Responsiveness

The silent killer. An app that works correctly but feels sluggish loses users faster than one with minor bugs.

### What to check in the diff

Before generating performance test cases, scan the diff for these red flags:

**Compose/UI performance:**
- New `LazyColumn`/`LazyRow` without `key` parameter — causes full recomposition on data change
- `remember` removed or key changed — recomputation on every recomposition
- Heavy computation inside `@Composable` (not wrapped in `remember` or `derivedStateOf`)
- New `collectAsState()` on a high-frequency Flow (tick data, sensor data)
- Nested `LazyColumn` inside `Column` with `verticalScroll` — infinite measurement
- Large images loaded without sizing constraints or caching
- `animateContentSize` or `AnimatedVisibility` on lists — triggers relayout per item

**Data layer performance:**
- New Room query without index on WHERE/ORDER BY columns
- N+1 query pattern — looping DB calls instead of a single JOIN
- Missing `distinctUntilChanged()` on Flow/StateFlow — redundant UI updates
- Large object serialization/deserialization on main thread
- New network call without caching strategy
- Unbounded list fetch (no pagination)

**Memory & lifecycle:**
- New `collect` in `init{}` or `onStart` without cancellation — potential leak
- Bitmap/image loading without recycling or size limits
- Growing in-memory cache without eviction policy
- `GlobalScope.launch` — survives ViewModel, leaks Activity reference
- `MutableStateFlow` holding large objects (entire list vs diff)

### Test cases to generate

**Screen load time:**
```
Precondition: Cold start (app force-stopped)
Steps: Launch app, navigate to {affected screen}
Expected: Screen fully rendered (all data visible, no shimmer/skeleton) within 2 seconds
Measurement: Time from tap to last element visible
```

**List scrolling (if LazyColumn/LazyRow changed):**
```
Precondition: Screen loaded with 50+ items
Steps: Rapid scroll through the entire list, then scroll back to top
Expected: No visible jank, no dropped frames, smooth 60fps scrolling
Measurement: Visual smoothness — any stutter or blank frames?
```

**Rapid interaction:**
```
Precondition: Screen loaded
Steps: Tap between tabs/screens 10 times rapidly
Expected: No ANR dialog, no increasing delay between taps and response, no memory growth
```

**Data-heavy screen:**
```
Precondition: Large dataset (100+ items, or 1MB+ response)
Steps: Load the screen, scroll through data, pull-to-refresh
Expected: Initial load < 3s, refresh < 2s, no OOM crash
```

**Background to foreground:**
```
Precondition: App in background for 5+ minutes
Steps: Switch back to the app
Expected: Screen resumes within 1s, no re-fetch of already loaded data, no flash of loading state
```

**Memory under stress:**
```
Precondition: Open 5+ other apps to pressure memory
Steps: Navigate to {affected screen}
Expected: No crash, no blank screen, graceful degradation (lower-res images OK, but data must show)
```

### Phone Driver performance commands

Phone driver can't measure FPS directly, but it CAN detect:
- **ANR dialogs**: "Verify no 'App isn't responding' dialog appears"
- **Visible jank**: "Scroll the list rapidly and check if content appears smoothly"
- **Load completion**: "Wait for {element} to appear — if it takes more than 5 seconds, report as slow"
- **Crash/blank screen**: "Verify the screen shows data, not a blank or error state"

For precise metrics, generate a separate section in the report recommending:
```
Manual performance verification needed:
- Run with Android Studio Profiler attached
- Check: GPU rendering bars (Settings > Developer > Profile GPU rendering)
- Check: StrictMode violations in logcat
- Check: Memory allocation in heap dump
```

### Diff-based performance checklist

Generate this checklist automatically by scanning the diff:

| Pattern found in diff | Performance test to generate |
|----------------------|------------------------------|
| New `LazyColumn`/`LazyRow` | List scrolling test with 50+ items |
| New network call (`suspend fun`, `retrofit`, `ktor`) | Load time test + timeout test |
| New Room `@Query` | Query performance with large dataset |
| `collectAsState` / `StateFlow` | Recomposition count check |
| Image loading (`Coil`, `Glide`, `painterResource`) | Memory test + large image test |
| New `remember` / removed `remember` | Before/after recomposition test |
| Pagination added/changed | Scroll-to-load-more smoothness |
| New animation (`animate*`, `Transition`) | Animation smoothness + reduced-motion |
| `withContext(Dispatchers.IO)` added/removed | Main thread blocking check |
| `GlobalScope` / missing cancellation | Memory leak test (navigate away and back) |

## Generating Phone Driver Instructions

For each test case, translate steps into phone-driver-compatible natural language:

**Good (actionable, specific):**
```
"Open the app, go to Order Entry, type '0' in the quantity field, tap 'Place Order' button, verify an error toast or message appears saying quantity must be positive"
```

**Bad (vague, unverifiable):**
```
"Test that order entry works with zero"
```

**Rules for phone-driver instructions:**
1. Always start with how to reach the screen (launch app, navigate)
2. Use exact element text visible on screen (not code identifiers)
3. End with a VERIFIABLE expected result (text visible, screen changed, element present)
4. Include necessary wait/delays for animations or API calls
5. Specify cleanup if needed (back out, clear data)

## Priority Assignment Matrix

| Change Type | Happy Path | Boundary | Error | Regression | Performance |
|------------|-----------|----------|-------|------------|-------------|
| Core business logic | P0 | P0 | P1 | P0 | P1 |
| Data model | P0 | P1 | P1 | P0 | P1 |
| ViewModel | P1 | P1 | P1 | P1 | P1 |
| UI layout / Compose | P1 | P2 | P2 | P1 | P0 |
| List/RecyclerView/Lazy | P1 | P2 | P2 | P1 | P0 |
| Network/API | P1 | P1 | P0 | P1 | P1 |
| Database/Room | P1 | P1 | P1 | P1 | P0 |
| Navigation | P1 | P2 | P1 | P0 | P2 |
| Image loading | P2 | P2 | P2 | P2 | P0 |
| Styling/theme | P2 | P3 | P3 | P2 | P3 |
| Build/config | P1 | P2 | P1 | P1 | P2 |
| Test only | — | — | — | — | — |
