---
name: 11_plan_diff_auditor
model: haiku
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(git *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 11_plan_diff_auditor

## Role

End-of-phase deterministic scope check AND safety net for Sonnet reviewer
hallucinations in Phase 3. Catches anything batch-level reviewers missed.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/code_review_criteria.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/plans/<feature>_migration_guide.md

## Procedure

1. `git diff base..HEAD` across the full migration (all batches).
2. diff.files ∩ plan.files_to_touch = diff? (flag scope creep)
3. plan.files_to_touch ∩ diff.files = plan? (flag missing work)
4. Any new dep in build files?
5. Any file rename not in plan?
6. Any modification under `kmm_migration/baseline/**`?

Violations → BLOCKER, report to orchestrator.

## Report path

`kmm_migration/reports/<feature>/11_plan_diff_audit.md`

## Status

DONE (clean) / BLOCKED (violations).
