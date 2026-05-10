# Live Sources

Implements Constitution §4 (Live sources only) and §5 (Drift detection). Read this before any decision that names a library, version, API surface, or configuration option.

## Ladder

For every framework / library / API / config decision, walk this ladder. **First match wins.**

### 1. Context7

- Resolve: `mcp__context7__resolve-library-id` with the library name.
- Query: `mcp__context7__query-docs` with the resolved ID and the question.
- Citation: `context7://<resolved-id>` with the doc snippet excerpted in `findings.md`.

If the library is not on Context7, drop to level 2.

### 2. Official vendor docs

Canonical URLs:
- `https://kotlinlang.org/docs/...` — Kotlin / KMP
- `https://ktor.io/docs/...` — Ktor
- `https://insert-koin.io/docs/...` — Koin
- `https://kotlinlang.org/api/kotlinx-datetime/` — kotlinx-datetime
- `https://github.com/<org>/<repo>` — project README and `CHANGELOG.md` on tagged release
- `https://developer.android.com/...` — Android SDK behaviour

`WebFetch` against the canonical URL. Citation: URL with retrieval date.

### 3. Web search

For details not on official docs (release notes, working-group resolutions, GitHub issues):

- `WebSearch` to find candidate sources.
- `WebFetch` against the most authoritative result.
- Prefer: project's own GitHub issues, JetBrains/Google blog posts, KMP working-group threads.
- Avoid: aggregator sites, Stack Overflow older than 12 months, blog posts not from project maintainers.

### 4. Training data — last resort

If steps 1–3 yield nothing, reject the recommendation and ask the user. If a placeholder is unavoidable, flag inline as `⚠ TRAINING DATA — VERIFY` and record in `findings.md § Live-source audit`. The migration cannot pass `/kmm-verify` while unresolved training-data items remain.

## Drift phrases — automatic stop

Per Constitution §5, these phrases signal training-data substitution. Each is a hard stop:

- "I recall…"
- "Typically you…"
- "The API is usually…"
- "Should be…"
- "I think this works…"
- "In my experience…"
- "From what I remember…"
- "Generally…"

Drop the sentence and run a live lookup.

## What needs a live source

Every claim about: library version, API surface, KMP support status, configuration options, migration patterns. Un-sourced claims are rejected.

## What does NOT need a live source

- The constitution itself.
- The project's own codebase (`file:line` is the citation).
- Generic Kotlin language facts (e.g., `val` is read-only).

## findings.md structure

`findings.md § Library Versions` has a Source column and Last-verified date per row. The completeness-verifier confirms every library mentioned in `migration-guide.md`'s `Library swaps` field has a row with a source.

`findings.md § Live-source audit` footer is checked at `/kmm-verify` time. Any `⚠ TRAINING DATA — VERIFY` flag still present → fail.

## When live source contradicts memory

The live source wins. Surface the discrepancy in the deviation log if a planned swap is no longer viable.
