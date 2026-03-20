# Technical Edge Cases

Identify edge cases that are technical in nature — things that break due to timing, state, platform, or system behavior rather than business rules.

## Edge case categories

### Race conditions and timing
- [ ] User triggers action twice rapidly (double-tap, double-submit)
- [ ] API response arrives after user has navigated away
- [ ] Two features modify the same data simultaneously
- [ ] Background sync completes while user is editing the same data
- [ ] Real-time data update arrives while user is in the middle of an action
- [ ] System clock change (timezone change, daylight saving, manual time change)
- [ ] Feature triggered at exact boundary (midnight, market open/close second)

### Null and empty states
- [ ] API returns empty list vs null vs missing field
- [ ] Database query returns no results
- [ ] User has no data yet (first-time use of this feature)
- [ ] Required field is null due to partial data load
- [ ] Optional field absent — UI handles gracefully
- [ ] Empty string vs null string distinction
- [ ] Zero value vs null value vs absent value

### Network edge cases
- [ ] Network switches (WiFi → mobile data mid-request)
- [ ] Slow network (response takes 30+ seconds)
- [ ] Intermittent connectivity (connects/disconnects rapidly)
- [ ] VPN connected/disconnected
- [ ] Request completes but response is truncated
- [ ] WebSocket/MQTT reconnection — missed messages, stale state

### Process and lifecycle
- [ ] App killed by system (process death) mid-operation
- [ ] App backgrounded during API call
- [ ] App foregrounded after long time in background (stale data)
- [ ] Configuration change during async operation (rotation, theme, locale)
- [ ] Low memory warning — state preservation
- [ ] App update — migration from old data format

### Platform edge cases
- [ ] Different Android versions (min SDK to latest)
- [ ] Different screen sizes and densities
- [ ] Foldable devices — fold/unfold during operation
- [ ] Multi-window / split screen mode
- [ ] Picture-in-picture mode
- [ ] Device locale change
- [ ] Right-to-left (RTL) layout
- [ ] Large font / display size accessibility settings
- [ ] Dark mode / light mode switch during operation
- [ ] Battery saver mode (restricted background work)

### Data boundary edge cases
- [ ] Integer overflow for large numbers (portfolio values, quantities)
- [ ] Decimal precision (financial calculations — ₹0.01 rounding)
- [ ] Very long strings (instrument names, user input)
- [ ] Special characters in user input (emojis, unicode, SQL injection)
- [ ] Maximum list size (1000+ items in a list)
- [ ] Date/time boundary (end of day, end of month, end of year, leap year)

### Trading-specific edge cases
- [ ] Market data feed reconnection — gap in tick data
- [ ] Order modification during partial fill
- [ ] Position update during settlement
- [ ] Instrument delisting mid-session
- [ ] Exchange-level session change (normal → auction → close)
- [ ] Multiple exchange feeds with different timestamps

## Output format

```
### Technical edge cases
- [ ] **[Category]**: [Scenario] — Risk: [What breaks] — Mitigation: [How to handle]
```

Focus on edge cases specific to THIS feature — don't list generic Android edge cases that aren't relevant to the feature being analyzed.
