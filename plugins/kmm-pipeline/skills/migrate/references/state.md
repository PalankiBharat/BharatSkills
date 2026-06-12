# Migration State — Schema & Resume

All pipeline state is plain files in the MAIN repo at `.kmm/migrations/` (excluded from git via `.git/info/exclude`; the exclude file lives in the common git dir, so it covers worktrees too). Durable knowledge does NOT live in state or in the target repo: it lives in the plugin's `knowledge/` files, updated per the protocol in `knowledge/learnings.md` — state is per-migration and disposable, knowledge is forever.

```
.kmm/migrations/ACTIVE            # contains: <slug>\nstate=<abs path to state dir>  — arms guard hooks; written LAST at preflight, removed at close/abandon
.kmm/migrations/<slug>/
  state.json                      # machine cursor (below)
  journal.ndjson                  # append-only events — the resume source of truth
  contract.md                     # human-approved parity contract
  plan.md                         # human-approved step plan
  research.md                     # sourced findings; every claim carries a citation
  qa-report.md  review-report.md  # phase-6 verdicts
  blockers/<n>.md                 # STOP-and-escalate records (Law Rule 11)
  retro.md                        # phase-7 friction log (orchestrator); never committed
```

A copy of `ACTIVE` is also written at the worktree root's `.kmm/migrations/ACTIVE` (same content, `state=` pointing at the main repo) so hooks arm and sessions opened inside the worktree can resume.

## state.json

```json
{
  "slug": "funds-withdrawal",
  "feature": "Funds withdrawal flow",
  "branch": "kmm/funds-withdrawal",
  "base": "master",
  "worktree": "/Users/ayush/dev/sniper-v2-android-funds-withdrawal",
  "phase": 4,
  "steps": [{"id": "S0-baselines", "status": "done", "commits": ["<sha>"]}],
  "gates": {"contract": "2026-06-13T10:01:00Z", "plan": null, "merge": null},
  "pr": null,
  "createdAt": "...", "updatedAt": "..."
}
```

Step status: `pending | in-progress | done | blocked`; the cursor is the first non-`done` step. Phases: 0 preflight · 1 scope · 2 research · 3 plan · 4 execute · 5 ios · 6 verify · 7 ship.

## journal.ndjson

One JSON object per line: `{"ts": "<UTC ISO>", "phase": 4, "step": "S2-move-stores", "type": "dispatch|commit|gate|blocker|phase-done|note", "sha": "...", "note": "..."}` — `step` carries the `steps[].id` it joins to. Workers append their own `commit` events; the orchestrator verifies on receipt and appends `phase-done`. Timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ`. A step without journal entries did not happen (Law Rule 10).

## Resume algorithm

On any invocation with `ACTIVE` present (or `resume` argument):

1. Read `ACTIVE` → state dir → `state.json` + the FULL `journal.ndjson` (step 2 reconciles every `commit` event; tail ~30 lines is only for the announce).
2. Reconcile against git: every `commit` event SHA must exist on `branch` (`git -C <worktree> log --format=%H`). Commits in git but not journaled → journal them now (`note: "reconciled"`). Journaled but missing from git → mark that step `pending` again and warn.
3. Verify environment: worktree exists, branch checked out there, `ACTIVE` copies present. Missing worktree → recreate from branch; missing branch → STOP (blocker).
4. Announce: slug, phase, step cursor, pending gates. Continue the state machine from the cursor — never restart a `done` phase.

## Concurrency rules

- One migration at a time: preflight refuses to start if `ACTIVE` exists for a different slug (offer resume or explicit abandon — abandon archives the state dir to `.kmm/migrations/_archive/<slug>-<date>/` and removes both `ACTIVE` markers).
- Single writer per file: the orchestrator owns `state.json`/`plan.md`/`contract.md`/`research.md`; the phase-6 qa/review skills own `qa-report.md`/`review-report.md`; a worker appends to `journal.ndjson` and writes its own `blockers/<n>.md`, nothing else. State writes are atomic (write temp, `mv` over).
- On resume, prose claims in old state files are hypotheses (Law Rule 7) — the journal+git reconciliation is authoritative; infra claims ("X blocks iOS link") get re-verified before acting.
