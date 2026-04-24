---
name: 04_baseline_e2e_author
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Edit, Write, Bash(maestro *), Bash(./gradlew *), Bash(git *), WebSearch, mcp__context7__*]
tool_denylist: []
requires_success_criterion: true
---

# 04_baseline_e2e_author

## Role

Write E2E flows that exercise the feature end-to-end against the OG APK.
All green. Same flow files will later run against the migrated APK.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/baseline_capture_protocol.md
- skills/kmm-migration/references/knowledge_lookup_protocol.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/reports/<feature>/01_inventory.md
- kmm_migration/baseline/<feature>/tech_stack_snapshot.md

## Procedure

1. For each end-to-end flow in the feature, author a YAML (or equivalent
   per the E2E tool chosen) flow.
2. Run each flow against the OG APK. All must be green.
3. Record retry policy in the manifest.
4. Record paths in `kmm_migration/baseline/<feature>/e2e_flows_manifest.md`.

## Report path

`kmm_migration/reports/<feature>/04_baseline_e2e.md`

## Status

DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT.
