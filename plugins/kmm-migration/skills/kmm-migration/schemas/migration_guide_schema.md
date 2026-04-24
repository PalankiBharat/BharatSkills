# migration_guide.md schema

> Phase 2b output. Per-file structured spec the migrators consume.

## Path

`kmm_migration/plans/<feature>_migration_guide.md`

## Per-file entry template

```markdown
# File: <source path>

## Migration entry
- Source path          : <path>
- Target path          : <path>
- Target source set    : commonMain | androidMain | iosMain
- OG public API        : <signatures, verbatim>
- API changes          : NONE (Law 1). If any → STOP, escalate.
- Android-only APIs    : <api> → <replacement> | <source>
- Platform-specific    : <expect/actual or interface+DI>
- Dep kept 1:1         : <library>
- Dep swapped          : <from> → <to> (reason: Android-only)

## Expected tests
- Baseline unit tests  : <paths, counts>
- Post-migration       : same tests in commonTest, must pass unchanged.

## Accepted deltas for this file
- <delta> | <source>

## Decisions (frozen after plan approval)
- <decision> | <source>
```

## Header

Every migration_guide.md starts with:

```markdown
<!-- KMM-PLAN v1 | skill: kmm-migration | feature: <name> | date: <ISO> -->
# Migration Guide — <feature>
```

## Rules

- One entry per touched file.
- Every entry actionable by a migrator without clarification.
- No placeholders.
