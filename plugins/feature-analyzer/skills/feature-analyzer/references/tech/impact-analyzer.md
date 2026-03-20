# Impact Analyzer

Identify which existing features are affected by the new feature or change. This is the input for the cascading analysis phase.

## Impact detection approach

Think about impact in concentric circles — direct, indirect, and transitive.

### Direct impact (code-level)
- Features sharing the same data models / entities
- Features sharing the same repository or data source
- Features sharing the same ViewModel or state
- Features using the same Hilt-provided dependencies
- Features sharing the same navigation graph paths
- Features sharing the same Room database tables

### Indirect impact (behavior-level)
- Features that display data modified by this feature
- Features that depend on state changed by this feature
- Features that share the same real-time data stream (MQTT, WebSocket)
- Features that share cached data or in-memory state
- Features that use the same background workers / coroutine jobs

### Transitive impact (system-level)
- Features affected by API contract changes
- Features affected by database schema migration
- Features affected by shared preference / config changes
- Features affected by Hilt scope changes (singleton dependencies)
- Features affected by ProGuard / R8 rule changes

## Trading/fintech common impact patterns

- **Order entry changes** → Affects: watchlist (order status), portfolio (positions), order book, P&L calculations, margin display
- **Market data changes** → Affects: watchlist, charts, order entry (LTP reference), alerts, screeners
- **Authentication changes** → Affects: every feature that calls authenticated APIs
- **Account/profile changes** → Affects: order entry (margin), portfolio, fund management
- **Instrument model changes** → Affects: watchlist, search, order entry, charts, F&O chain

## Output format

```
### Impact on existing features

**Directly affected:**
- [ ] **[Feature name]** — [How it's affected] — Severity: [High/Medium/Low]
  - Shared dependency: [what's shared]
  - Risk: [what could break]

**Indirectly affected:**
- [ ] **[Feature name]** — [How it's affected] — Severity: [High/Medium/Low]

**Potentially affected (verify):**
- [ ] **[Feature name]** — [Why it might be affected]
```

For each feature marked High severity, flag it for cascading analysis (Phase 5).
