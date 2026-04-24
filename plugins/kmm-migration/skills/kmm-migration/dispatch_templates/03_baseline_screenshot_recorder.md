---
name: 03_baseline_screenshot_recorder
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Edit, Write, Bash(./gradlew *), Bash(git *), WebSearch, mcp__context7__*]
tool_denylist: []
requires_success_criterion: true
---

# 03_baseline_screenshot_recorder

## Role

Record screenshot goldens of the OG UI with a per-platform tolerance
envelope. Goldens are immutable during migration.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/baseline_capture_protocol.md
- skills/kmm-migration/references/knowledge_lookup_protocol.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/reports/<feature>/01_inventory.md
- kmm_migration/baseline/<feature>/tech_stack_snapshot.md

## Procedure

1. Set up the screenshot framework recorded in tech_stack_snapshot.md.
2. Record goldens for every screen in the feature.
3. Set a tolerance envelope (change-threshold) per platform; record in
   the manifest.
4. Record paths in `kmm_migration/baseline/<feature>/screenshot_goldens_manifest.md`.

## Report path

`kmm_migration/reports/<feature>/03_baseline_screenshot.md`

## Status

DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT.
