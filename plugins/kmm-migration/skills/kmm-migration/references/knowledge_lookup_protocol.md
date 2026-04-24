# Knowledge Lookup Protocol

> The general protocol for Rule 13 ("LIVE KNOWLEDGE, NEVER TRAINING-DATA
> KNOWLEDGE"). Use this whenever a subagent needs any external knowledge —
> library behaviour, API shape, platform nuance, community best practice.

## Contents

- [Priority order](#priority-order)
- [Source citation format](#source-citation-format)
- [When lookup fails](#when-lookup-fails)

## Priority order

1. **Priority 1 — context7**
   - `mcp__context7__resolve-library-id(query=…)`
   - `mcp__context7__query-docs(libraryId=…, query=…)`
2. **Priority 2 — WebSearch / find-docs**
   - WebSearch with specific queries including current year
   - `find-docs` skill when a candidate library/version is known
3. **Priority 3 — training data**
   - ONLY if Priorities 1 and 2 both failed.
   - ONLY when the claim is flagged `⚠ TRAINING DATA — VERIFY BEFORE USE`.

If context7 disagrees with training data, context7 wins. Every claim goes
through this protocol; no exceptions.

## Source citation format

Every non-obvious claim cites its source at the point of assertion. Format:

- context7: `(source: context7 libraryId=/org/project, query="…")`
- WebSearch: `(source: <URL>)`
- find-docs: `(source: find-docs: <library name>)`
- Training data (flagged): `(⚠ TRAINING DATA — VERIFY: <claim>)`

## When lookup fails

If all three priorities fail to produce a confident answer, emit
`STATUS: NEEDS_CONTEXT` with the exact question. Do NOT guess.
