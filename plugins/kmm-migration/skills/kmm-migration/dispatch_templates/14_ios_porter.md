---
name: 14_ios_porter
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Edit, Write, Bash(./gradlew *), Bash(xcodebuild *), Bash(git *), Bash(maestro *), WebSearch, mcp__context7__*, find-docs]
tool_denylist: []
requires_success_criterion: true
budget:
  max_files_per_batch: 5
  max_batch_tokens: 100000
---

# 14_ios_porter

## Role

Add iosMain actuals + Swift-interop wrapper + iOS goldens + iOS E2E runs.
Uses the Swift interop library identified by the researcher.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/platform_interop_patterns.md
- skills/kmm-migration/references/knowledge_lookup_protocol.md
- skills/kmm-migration/references/worktree_conventions.md
- skills/kmm-migration/references/three_strike_protocol.md
- skills/kmm-migration/references/behavioral_guidelines.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/findings.md
- kmm_migration/plans/<feature>_migration_guide.md
- kmm_migration/reports/<feature>/research_notes.md

## Procedure

1. First action: verify CWD.
2. Write iosMain actuals matching androidMain interface contracts.
3. Set up Swift-interop wrapper per researcher's recommendation.
4. Record iOS goldens per baseline_capture_protocol.
5. Run iOS E2E flows.

## Report path

`kmm_migration/reports/<feature>/14_ios_port.md`

## After DONE

Orchestrator dispatches `spec_compliance_reviewer` then `code_quality_reviewer`.

## Status

DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT.
