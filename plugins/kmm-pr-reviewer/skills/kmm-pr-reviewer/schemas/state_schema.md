# state.json schema

> Single source of truth for review progress. Written ONLY by the
> orchestrator. Readable by every subagent (read-only bundle).

## Location

`kmm_pr_review/<pr#>/state.json` at the target-repo root.

## Schema

```json
{
  "schema_version": "1",
  "pr_number": 154,
  "pr_url": "https://github.com/PunchHQ/punch-android/pull/154",
  "repo_owner": "PunchHQ",
  "repo_name": "punch-android",
  "base_branch": "master",
  "head_branch": "kmm-migrate/login",
  "base_sha": "def456abc...",
  "head_sha": "a1b2c3d4...",
  "phase": 2,
  "phase_substep": "per_file_review.12_of_18",
  "status": "in_progress",
  "files": [
    {
      "path": "shared/src/commonMain/kotlin/com/app/login/LoginViewModel.kt",
      "change_type": "ADDED",
      "classification": "migrated",
      "paired_master_path": "app/src/main/java/com/app/login/LoginViewModel.kt",
      "review_status": "done_with_concerns"
    },
    {
      "path": "shared/src/iosMain/kotlin/com/app/login/LoginViewModelActual.kt",
      "change_type": "ADDED",
      "classification": "ios_port",
      "paired_master_path": null,
      "review_status": "done"
    },
    {
      "path": "app/src/main/AndroidManifest.xml",
      "change_type": "MODIFIED",
      "classification": "nonmigrated",
      "paired_master_path": null,
      "review_status": "pending"
    }
  ],
  "unresolved": [],
  "gates": {
    "gate_1_approval": null
  },
  "last_dispatch": {
    "subagent": "20_file_reviewer_migrated",
    "started_at": "2026-04-29T12:42:00Z",
    "expected_report_path": "kmm_pr_review/154/per_file/shared_src_commonMain_kotlin_com_app_login_LoginViewModel_kt.md",
    "completion_status": "pending"
  },
  "ios_present": true,
  "approved_findings_count": null,
  "posted_review_url": null
}
```

## Field semantics

| Field | Purpose |
|---|---|
| `schema_version` | Always `"1"` for this iteration. Bump if schema changes. |
| `pr_number` | The integer PR number — the directory key for `kmm_pr_review/<pr#>/`. |
| `pr_url` | The full HTML URL from `gh pr view`. Used only in `posted_review.md` for human reference. |
| `repo_owner` / `repo_name` | Parsed from `gh pr view --json headRepository,baseRepository`. Used by `50_comment_poster` for the API endpoint. |
| `base_branch` | The PR's target branch (typically `master`). |
| `head_branch` | The PR's source branch. |
| `base_sha` / `head_sha` | SHAs from `gh pr view --json baseRefOid,headRefOid`. Every reviewer reads master via `git show <base_sha>:<path>` and head via `git show <head_sha>:<path>`. |
| `phase` | Current phase: 0 = bootstrap, 1 = review_guide, 2 = per_file, 3 = triage, 4 = approval, 5 = post. Advances only after every dispatch in the phase reports a status. |
| `phase_substep` | Free-form sub-step descriptor for resume (e.g. `"per_file_review.12_of_18"`). |
| `status` | `in_progress` / `awaiting_gate` / `blocked` / `complete`. |
| `files[]` | Per `references/classification_protocol.md` § "Output shape". `review_status` is `pending` until Phase 2 dispatch completes for this file. |
| `unresolved[]` | Paths where the per-file reviewer emitted `STATUS: BLOCKED` or `STATUS: NEEDS_CONTEXT`. The orchestrator raises a control-flow `REQUIRES_APPROVAL` if this list is non-empty after Phase 2. |
| `gates.gate_1_approval` | `null` until the user types `approved`; then `posted_at_<iso>` with the GitHub review URL. |
| `last_dispatch` | Set at dispatch start; `completion_status` flips to `done` / `done_with_concerns` / `blocked` / `needs_context` when the subagent's report is parsed. |
| `ios_present` | Boolean — true iff any file in `files[]` has `classification: "ios_port"`. Determines whether iOS reviewer dispatches happen. |
| `approved_findings_count` | Set by Phase 4 after the user's edit pass — the count of ticked items in `findings_pending_approval.md`. `0` is a valid value (graceful exit). |
| `posted_review_url` | Set by Phase 5 once the GitHub review POST succeeds. |

## Status values

- `in_progress` — work in flight, no gate pending.
- `awaiting_gate` — `findings_pending_approval.md` has been written; user hasn't typed `approved` / `revise` / `abandon` yet.
- `blocked` — a control-flow gate (Phase 2 unresolved list) is active, OR Phase 5 hit a gh-API failure.
- `complete` — Phase 5 successful, `posted_review.md` written.

## Update discipline

Orchestrator writes `state.json` only after:

- A subagent dispatch completes (writes `last_dispatch.completion_status` and the file's `review_status`).
- A user decision changes `gates.gate_1_approval`, `approved_findings_count`, or `status`.
- A control-flow change populates `unresolved[]`.

Subagents NEVER write `state.json`. Subagents read it (every dispatch lists `state.json` in `must_read_before_start`).
