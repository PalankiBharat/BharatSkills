---
name: 17_pr_body_composer
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(git *), Write]
tool_denylist: [Edit, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 17_pr_body_composer

## Role

Compose the PR body + migration heatmap. Written for human AND AI reviewers.
Evidence-backed, zero ambiguity.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/schemas/pr_body_schema.md
- skills/kmm-migration/references/pr_body_heatmap_spec.md
- skills/kmm-migration/formats/pr_body_template.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/plans/<feature>_migration_guide.md
- kmm_migration/reports/<feature>/research_notes.md
- kmm_migration/reports/<feature>/15_final_baseline_reverification.md
- kmm_migration/reports/<feature>/16_kmm_focused_final_review.md
- kmm_migration/baseline/<feature>/*.md

## Procedure

1. `git diff --stat base..HEAD` for heatmap data.
2. Compose body per pr_body_schema (9 required sections).
3. Compose heatmap per pr_body_heatmap_spec (3 layers).
4. Write `kmm_migration/pr/<feature>/body.md` and
   `kmm_migration/pr/<feature>/heatmap.md`.
5. Inline the heatmap into the body at section 3.

## Status

DONE / DONE_WITH_CONCERNS.
