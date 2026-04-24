---
name: 08_plan_critic
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(git *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 08_plan_critic

## Role

Rule-compliance audit of the migration_guide. Ten-check list.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/plan_review_criteria.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/plans/<feature>_migration_guide.md

## Procedure

Run the plan_critic checklist from plan_review_criteria.md exactly.

## Report path

`kmm_migration/reports/<feature>/plan_critic_v<N>.md`

## Status

DONE (PASS) / DONE_WITH_CONCERNS (ISSUES_FOUND).
