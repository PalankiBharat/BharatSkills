# findings.md schema

> Persistent decision journal. Lives at `kmm_migration/findings.md`.
> Updated across migrations in the same repo.

## Sections

```markdown
# KMM Migration Findings

## Architecture decisions (apply to all future features)
| Date | Decision | Reason | Source |
|------|----------|--------|--------|
| 2026-04-24 | <decision> | <reason, no hedging> | <context7 ID / URL> |

## Library versions verified live
| Date | Library | Version | Source |
|------|---------|---------|--------|

## Known gotchas
- <one-line fact with source>

## Intentional non-bugs (don't re-flag)
- <one line describing OG behaviour confirmed by user on <date>>

## Accepted deltas encountered
| Date | Feature | Delta | Source |
|------|---------|-------|--------|

## Skipped retrospective findings
| Date | Finding | Feature it arose in |
|------|---------|--------------------|
```

## Rules

- Every row cites a source (Rule 13).
- Dates in ISO format.
- One finding per row; no prose.
