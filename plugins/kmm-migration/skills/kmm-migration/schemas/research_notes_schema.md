# research_notes.md schema

> Phase 2a output. Structured Q&A with sources.

## Path

`kmm_migration/reports/<feature>/research_notes.md`

## Structure

```markdown
# Research Notes — <feature>

Date: <ISO>
Researcher: 06_researcher

## Concern: <concern-name>
- Question: <exact>
- Answer: <decision, no hedging>
- Source: <context7 libraryId / URL / find-docs>
- Version (if applicable): <x.y.z>
- Alternatives considered: <brief>

## Concern: <concern-name>
(repeat)

## Accepted deltas identified for this feature
- <delta> | <source>

## Open questions routed to NEEDS_CONTEXT
- <question> (sources exhausted)
```

## Rules

- Every answer cites a source.
- Zero training-data claims unless flagged.
- One entry per concern; no merging.
