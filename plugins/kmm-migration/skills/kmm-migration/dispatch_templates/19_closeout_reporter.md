---
name: 19_closeout_reporter
model: haiku
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Write, Bash(git *)]
tool_denylist: [Edit, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 19_closeout_reporter

## Role

Write closeout.md. Update findings.md with new decisions.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/schemas/closeout_schema.md
- skills/kmm-migration/schemas/findings_schema.md
- skills/kmm-migration/references/subagent_status_contract.md
- All prior reports for this feature

## Procedure

1. Read all prior reports.
2. Write closeout per schema.
3. Append new architecture decisions, library versions verified,
   intentional non-bugs, accepted deltas to findings.md.

## Report path

`kmm_migration/reports/<feature>/closeout.md`

## Status

DONE.
