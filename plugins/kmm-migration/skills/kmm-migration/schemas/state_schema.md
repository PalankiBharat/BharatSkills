# state.json schema

> Single source of truth for migration progress. Written ONLY by the
> orchestrator. Readable by every subagent (read-only bundle).

## Location

`kmm_migration/state.json` at the target-repo root.

## Schema

```json
{
  "schema_version": "1",
  "feature": "login",
  "base_branch": "main",
  "worktree_path": ".worktrees/kmm-migrate-login",
  "worktree_branch": "kmm-migrate/login",
  "phase": 3,
  "phase_substep": "migrate.batch_2_of_3",
  "status": "in_progress",
  "gates": {
    "gate_1_baseline_freeze": "approved_at_2026-04-24T10:15:00Z",
    "gate_2_plan_approved": "approved_at_2026-04-24T11:30:00Z",
    "gate_3_android_parity": null,
    "gate_4_ios_parity": null,
    "gate_5_pr_merge": null
  },
  "last_dispatch": {
    "subagent": "10_migrator",
    "started_at": "2026-04-24T12:42:00Z",
    "expected_report_path": "kmm_migration/reports/login/10_migrate_batch2.md",
    "completion_status": "pending"
  },
  "ios_decision": "pending",
  "accepted_deltas_count": 2
}
```

## Status values

- `in_progress` — work in flight, no gate pending.
- `awaiting_gate` — a `REQUIRES_APPROVAL` is active.
- `blocked` — three-strike or reviewer hit max cycles without PASS.
- `complete` — Phase 6 gate 5 approved, migration merged.

## Update discipline

Orchestrator writes state.json only after:
- A gate is approved.
- A subagent dispatch completes (writes `last_dispatch.completion_status`).
- A user decision changes `ios_decision` or similar field.
