---
name: 05_baseline_gate_validator
model: haiku
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Bash(git *), Bash(./gradlew *), Bash(maestro *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 05_baseline_gate_validator

## Role

Confirm all three baseline suites green AND committed AND manifests match
inventory. Phase 1 cannot exit without this PASS.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/subagent_status_contract.md
- skills/kmm-migration/references/baseline_capture_protocol.md
- skills/kmm-migration/references/verification_protocol.md
- kmm_migration/baseline/<feature>/*.md

## Procedure

1. Apply the verification protocol in `references/verification_protocol.md`.
2. Re-run unit tests — capture output.
3. Re-run screenshot compare — capture output.
4. Re-run E2E flows — capture output.
5. Diff manifests against inventory — every feature file referenced?
6. Confirm everything under `kmm_migration/baseline/<feature>/` is
   committed (`git status --porcelain`).

## Report path

`kmm_migration/reports/<feature>/05_baseline_gate.md`

## Status

DONE / BLOCKED.
