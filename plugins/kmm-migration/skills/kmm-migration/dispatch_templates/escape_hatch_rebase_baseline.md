---
name: escape_hatch_rebase_baseline
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Edit, Write, Bash(./gradlew *), Bash(maestro *), Bash(git *), WebSearch, mcp__context7__*]
tool_denylist: []
requires_success_criterion: true
---

# escape_hatch_rebase_baseline

## Role

Named exception to Law 2. Re-record baseline artifacts with a new tolerance
envelope. ONLY when the existing envelope is demonstrably wrong.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/baseline_capture_protocol.md
- skills/kmm-migration/references/knowledge_lookup_protocol.md
- skills/kmm-migration/references/subagent_status_contract.md
- The rebase request passed in the dispatch prompt (must include user
  approval artifact)

## Preconditions

1. User has approved the rebase via REQUIRES_APPROVAL.
2. Evidence attached that the existing tolerance envelope is wrong.
3. NO production-code changes may happen in this dispatch.

## Procedure

1. Re-record baseline artifacts (the specific suite affected) on OG code.
2. Record the new tolerance envelope with a live source (Rule 13).
3. Log rebase decision in findings.md with ISO date + reason + source.

## Report path

`kmm_migration/reports/<feature>/rebase_baseline_<ts>.md`

## After DONE

Orchestrator dispatches `spec_compliance_reviewer` and `code_quality_reviewer`
with EXTRA strict checks:
- Only baseline artifacts changed.
- Envelope change is justified and sourced.

## Status

DONE / BLOCKED.
