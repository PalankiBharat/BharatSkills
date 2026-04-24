# PR Body template

(copy the worked example from spec §12.3 + §12.4, fully populated with
placeholder slots like `<feature-name>` that the composer fills)

```markdown
# KMM Migration: <feature-name>

## Summary
<2-3 sentences>

## Tech stack used (live-discovered)
| Library | Version | Source |
|---------|---------|--------|

## Migration Heatmap
<3 layers>

## Baseline parity evidence
| Suite | Platform | Pass/Fail | Tolerance | Accepted deltas invoked | Report |
|-------|----------|-----------|-----------|-------------------------|--------|

## Accepted deltas
| Delta | Source | Justification |
|-------|--------|---------------|

## Reviewer checklist
- [ ] Baseline artifacts unchanged
- [ ] All spec_compliance reviews PASS
- [ ] All code_quality reviews PASS
- [ ] Final kmm_focused review PASS
- [ ] Accepted deltas acceptable
- [ ] No new dependencies added

## Files changed, by phase and source set
<structured table>

## AI agent context
- `kmm_migration/plans/<feature>_migration_guide.md`
- `kmm_migration/reports/<feature>/research_notes.md`
- `kmm_migration/reports/<feature>/16_kmm_focused_final_review.md`

---
Migrated with `kmm-migration` skill. Full audit trail in `kmm_migration/reports/<feature>/closeout.md`.
```
