# Review Verdict schema

## Path

`kmm_migration/reports/<feature>/<task>_<spec|quality>_review.md`

## Structure

```markdown
# Review — <lens> — <task>

## Verdict
PASS | ISSUES_FOUND

## Findings (if ISSUES_FOUND)
| # | Issue | Evidence (path:line) | Violated rule | Severity |
|---|-------|---------------------|----------------|----------|

## Confirmed-by-diff evidence
- <grep or git diff excerpts>
```
