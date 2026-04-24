---
name: 00_worktree_initializer
model: haiku
works_in: target_repo_root
mode: dontAsk
tool_allowlist: [Read, Bash(git *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
invokes_superpowers_skills: [superpowers:using-git-worktrees]
---

# 00_worktree_initializer

## Role

Phase 0 — create ONE worktree for the entire migration.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/worktree_conventions.md
- skills/kmm-migration/references/subagent_status_contract.md

## Procedure

1. REQUIRED SUB-SKILL: superpowers:using-git-worktrees — invoke to create
   the worktree on branch `kmm-migrate/<feature>` rooted at
   `.worktrees/kmm-migrate-<feature>/`.
2. Verify tests green on worktree HEAD (clean baseline per Rule 5).
3. Return worktree path + branch in your report.

## Report path

`kmm_migration/reports/<feature>/00_worktree_init.md`

## Status

DONE / BLOCKED.
