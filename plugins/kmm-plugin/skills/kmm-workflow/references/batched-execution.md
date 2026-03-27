# Batched Parallel Execution Model

Single `:shared` module means Gradle serializes builds. The workflow uses batched parallel
to maximize speed.

## Per-Batch Execution (4 Steps)

1. **PARALLEL AGENTS** (code work, no Gradle):
   Launch N agents, one per file. Each agent does:
   - Read file + dependencies
   - Assess existing KMM version
   - Stage to androidMain with minimal compile fixes
   - Write characterization tests in commonTest
   - Agent reports: "staged + N tests written, ready for baseline"

2. **SINGLE BASELINE** (one Gradle run):
   Orchestrator runs: `./gradlew :shared:testDebugUnitTest`
   All test classes from all agents run at once. Must ALL pass.
   If any fail → test bug, fix and re-run. This is the ONLY time tests may be modified.

3. **PARALLEL AGENTS** (code work, no Gradle):
   Same N agents resume. Each agent does:
   - Migrate from androidMain → commonMain
   - Apply dependency swaps if needed (reference dependency-map.md patterns)
   - Delete staged androidMain copy
   - Agent reports: "migrated, ready for re-test"

4. **SINGLE RE-TEST** (one Gradle run):
   Orchestrator runs: `./gradlew :shared:testDebugUnitTest`
   Same tests, must pass WITHOUT modification.
   If any fail → migration bug. Fix migration, NOT tests.

## Phase-Level Steps (After All Batches in Phase)

- Step 8 (Wire+Cleanup) → Final phase tasks
- Step 9 (Audit) → Final phase auditor agent prompt
- Step 10 (Build Verify) → Every gameplan checkpoint (full 3-platform build)

## Batching Within a Phase

When files have dependencies on each other:

```
Phase 3: Network + Storage
  Batch A (parallel): LoginApi, SessionStore, SecureTokenStorage — no intra-batch deps
  → Baseline → Migrate (parallel) → Re-test
  Batch B (sequential, depends on A): LoginRepositoryImpl
  → Baseline → Migrate → Re-test
  Checkpoint 3
```

## Key Mapping Rules

| Classification | Migration Task | Per-File Verification | Parallelizable? |
|---------------|--------------|----------------------|----------------|
| migrate-pure | Migrate file | Tests only (fast) | Yes (if no shared deps) |
| migrate-swap | Migrate + swap | Tests only (fast) | No (sequential) |
| migrate-expect-actual | Migrate + e/a | Tests only (fast) | No (sequential) |
| platform-stay (screen) | iOS equivalent | xcodebuild only | Yes |
| wire-only | Rewire + audit | None (checkpoint) | No |
| — (phase end) | Checkpoint | Full 3-platform build | — |
