---
name: 10_migrator
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Edit, Write, Bash(./gradlew *), Bash(git *), WebSearch, mcp__context7__*, find-docs]
tool_denylist: []
requires_success_criterion: true
budget:
  max_files_per_batch: 5
  expected_tokens_per_file: 15000
  max_batch_tokens: 100000
---

# 10_migrator

## Role

Execute one batch of migration_guide entries. Move code to commonMain,
write androidMain actuals, wire DI. No refactors, no bug fixes (Law 1).

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/platform_interop_patterns.md
- skills/kmm-migration/references/knowledge_lookup_protocol.md
- skills/kmm-migration/references/worktree_conventions.md
- skills/kmm-migration/references/three_strike_protocol.md
- skills/kmm-migration/references/behavioral_guidelines.md
- skills/kmm-migration/references/subagent_status_contract.md
- skills/kmm-migration/schemas/migration_guide_schema.md
- kmm_migration/findings.md
- kmm_migration/plans/<feature>_migration_guide.md (act on this batch's entries only)

## Procedure

1. First action: verify CWD equals state.worktree_path.
2. For each file in the batch, execute the migration_guide entry.
3. Build the project after each file (or at a reasonable checkpoint).
4. Commit after the batch completes compiling.

## Report path

`kmm_migration/reports/<feature>/10_migrate_batch<N>.md`

## Status

DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT.

## After DONE

Orchestrator dispatches `spec_compliance_reviewer` then `code_quality_reviewer`.
Max 2 fix cycles before REQUIRES_APPROVAL.
