# Multi-run (v2) — several harnesses at once

Each run is isolated by a **git worktree**; a cross-run **registry** tracks status + liveness.

## Per run
- `run-id` = `<slug>-<timestamp>`; branch = `<slug>` verbatim (plain and readable — no harness prefix, no date).
- `/harness --worktree` → `harness-init.sh` creates `git worktree add .harness-worktrees/<run-id>` (own checkout + own `.harness/`), tmux session `harness-<run-id>`, and runs inside it. Git's worktree lockfiles prevent two runs clobbering the same tree.
- Each run needs its **own booted emulator** (QA can't share a phone); if none is free that run's QA is `blocked`.

## Registry — `~/.dev-harness/registry.json`
Helpers in `lib.sh`: `registry_add` · `registry_set` · `registry_get` · `registry_list` · `registry_remove` · `heartbeat` · `is_stale` · `run_lock_acquire` / `run_lock_release`. Every run records repo, worktree, branch, tmux session, status (active/paused/crashed/done), heartbeat. `git worktree list` is the per-repo truth; the registry adds cross-repo + liveness.

## Liveness (no double-driving)
- The Orchestrator calls `heartbeat <run-id>` each step.
- **alive** = tmux session exists AND `is_stale` false → a second manager refuses it.
- **crashed** = `is_stale` true AND session gone → resumable.
- `run_lock_acquire <run-id> <pid>` is taken only after a stale check, so two managers never drive one run.

## Resume / pick
`/harness --resume` (or "continue"): read `registry_list` → render an HTML picker (`render-review.sh picker`) → choose a run → reattach its tmux session, re-pin its emulator, re-send the in-flight instruction (see `resume.md`).

## Status of this build
TDD-covered: registry CRUD, heartbeat, `is_stale`, per-run lock, run registration in `harness-init`. **Smoke (manual):** actual worktree creation, the per-run tmux session, and the reattach/picker flow — OS/tmux-level, see `test/SMOKE.md`.
