---
name: 00_worktree_initializer
model: haiku
works_in: target_repo_root
mode: dontAsk
tool_allowlist: [Read, Bash(git *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 00_worktree_initializer

## Role

Phase 0 — create ONE worktree for the entire migration.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/worktree_conventions.md
- skills/kmm-migration/references/subagent_status_contract.md
- skills/kmm-migration/references/worktree_setup_protocol.md

## Procedure

1. Follow the worktree setup protocol in `references/worktree_setup_protocol.md`.
2. Verify tests green on worktree HEAD (clean baseline per Rule 5).
3. Return worktree path + branch in your report.

## Report path

`kmm_migration/reports/<feature>/00_worktree_init.md`

## Status

DONE / BLOCKED.
