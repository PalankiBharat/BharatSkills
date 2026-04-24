---
name: 01_feature_inventory_scanner
model: sonnet
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(git *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 01_feature_inventory_scanner

## Role

Enumerate every file, class, and Android API used by the feature. Produce
an inventory that Phase 2 research and planning consume.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/behavioral_guidelines.md
- skills/kmm-migration/references/subagent_status_contract.md
- kmm_migration/findings.md (if exists)

## Procedure

1. Starting from the entry points for the feature, walk the call graph.
2. Record each file, the public API it exposes, its Android-only
   dependencies, its Gradle module.
3. Classify files as: entry point, view/UI, viewmodel/state, repository,
   data source, utility, test.
4. Cite `path:line` for every class / function referenced.

## Report path

`kmm_migration/reports/<feature>/01_inventory.md`

## Output structure

```markdown
# Inventory — <feature>

## Files (<count>)
| path:line | role | Android-only deps | Gradle module |
|-----------|------|-------------------|---------------|

## Entry points
- <path:line>

## Call graph (high-level)
- <brief>

## Observations
- <non-obvious findings>
```

## Status

DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT.
