# Live Sources

This protocol implements Constitution §3 (Live sources only) and §4 (Drift detection). Read this before any decision that names a library, version, API surface, or configuration option.

## The ladder

For every framework / library / API / config decision, walk this ladder. **First match wins.** Stop at the first level that yields a verifiable answer with a citation.

### 1. Context7

Version-pinned library documentation. Preferred when available.

- Resolve the library: `mcp__context7__resolve-library-id` with the library name.
- Query: `mcp__context7__query-docs` with the resolved ID and the specific question.
- Citation format: `context7://<resolved-id>` with the doc snippet excerpted in `findings.md`.

If the library is not on Context7, drop to the next level.

### 2. Official vendor docs

For the canonical URL of the library's official documentation, e.g.:
- `https://kotlinlang.org/docs/...` for Kotlin / KMP fundamentals
- `https://ktor.io/docs/...` for Ktor
- `https://insert-koin.io/docs/...` for Koin
- `https://kotlinlang.org/api/kotlinx-datetime/` for kotlinx-datetime
- `https://github.com/<org>/<repo>` for the project's README and `CHANGELOG.md` on a tagged release
- `https://developer.android.com/...` for Android SDK behaviour

Use `WebFetch` against the canonical URL. The result must be from the live site, not training data summarising it.

Citation: the URL with the retrieval date.

### 3. Web search

For specific answers not on the official docs (release-note details, working-group resolutions, GitHub issue threads):

- Use `WebSearch` to find candidate sources.
- Use `WebFetch` against the most authoritative result.
- Prefer: the project's own GitHub issues, JetBrains/Google blog posts, Kotlin/KMP working-group threads on Slack/X archived publicly.
- Avoid: aggregator sites, Stack Overflow answers older than 12 months, blog posts not from the project's maintainers.

Citation: the URL with the retrieval date.

### 4. Training data — last resort

If steps 1–3 yield nothing, the skill has run out of live sources. The default response is to reject the recommendation and ask the user.

If a fallback is unavoidable (e.g., to make a temporary placeholder while the user decides), flag the value inline with `⚠ TRAINING DATA — VERIFY` and record it in `findings.md` under "Live-source audit" as an unresolved item. The migration cannot pass `/kmm-verify` while any unresolved training-data items remain.

## Drift phrases — automatic stop

Per Constitution §4, the following phrases are signals you are about to use training data. **Each one is a hard stop.** When you find yourself reaching for them, drop the sentence and run a live lookup instead.

- "I recall…"
- "Typically you…"
- "The API is usually…"
- "Should be…"
- "I think this works…"
- "In my experience…"
- "From what I remember…"
- "Generally…"

These are the most common path to silent breakage. The skill's job is to keep these out of `findings.md`, `plan.md`, and `migration-guide.md`.

## What needs a live source

Every claim about:

- a library version (e.g., "Ktor 3.0.3 supports KMP iOS arm64")
- an API surface (e.g., "`HttpClient(OkHttp) { ... }` is the right config")
- KMP support status (e.g., "DataStore now has KMP support as of …")
- configuration options (e.g., "Koin 4 uses `module {}` not `koinModule {}`")
- migration patterns (e.g., "Retrofit Call-based methods become suspend functions in Ktor")

If a claim does not cite a live source, the plan-analyzer rejects it as a `BLOCKER`. The orchestrator does not advance past `/kmm-plan` with un-sourced claims.

## What does NOT need a live source

The constitution itself does not need a citation — it is the skill's local source of truth.

The project's own codebase does not need a citation — it is what you are reading. (`file:line` is enough.)

Generic Kotlin language facts (e.g., "`val` is read-only") do not need a citation. The line is between language fundamentals and library / version specifics. When in doubt, lean toward citing.

## How findings.md is structured around this

`findings.md` has a "Library Versions" table where every row has a Source column and a Last-verified date. The completeness-verifier (at `/kmm-verify`) confirms every library mentioned in `migration-guide.md`'s `Library swaps` field has a row. Rows missing a source → fail.

`findings.md` has a "Live-source audit" footer that the plan-analyzer checks at `/kmm-plan` time and the completeness-verifier re-checks at `/kmm-verify`. Any `⚠ TRAINING DATA — VERIFY` flag still present at `/kmm-verify` → fail.

## When a live source contradicts your memory

The live source wins. Always. Constitution §3 — "Training data as last resort, flagged inline."

If your memory says "Library X supports KMP" and Context7 says "no KMP support yet, see issue #1234", believe Context7. Then surface the discrepancy to the user in the deviation log if a planned swap is no longer viable.
