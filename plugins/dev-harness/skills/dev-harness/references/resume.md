# Resume — crash recovery

**Principle:** durable state (`.harness/` files + git branch/commits + PR) survives any crash; transient state (tmux, running `claude -p`, the manager's memory) does not. Resume = rebuild the transient from the durable.

## Save points (written every transition)
- `state.json` — run_id, slug, branch, stage, phase, in-flight instruction, counters, heartbeat.
- `log.md` — append-only history.
- per-role `worklog.md` — fine-grained "where I stopped".

## `/harness --resume` (also triggered by the plain word **"continue"**)
```
1. read state.json (+ worklog) → find the in-flight instruction
2. rebuild tmux session + 5 panes (supervisors just re-watch their inboxes — safe to restart)
3. re-pin the emulator (re-read or re-capture the serial)
4. RE-SEND the in-flight instruction → a fresh worker reads its worklog + handoff
   + code on disk + remaining plan.md, and continues from exactly there
5. carry on through the normal flow
```

## Stale runs (days old) → rebase from master first
If the run has been paused for a while (or is about to do a major refactor), before re-dispatching Dev, have Dev `git pull --rebase origin master` so the branch is current and history stays clean. During the rebase: a conflict in a file that is NOT part of our feature is **master's call** (take theirs); resolve carefully only inside our own feature's files, and ask the user if genuinely unsure. After a sanctioned rebase, `--force-with-lease` on the run's OWN branch is the one allowed force-push (the `guard.sh` hook still blocks plain `--force` and any push to master).

## Why re-sending is safe (idempotency)
- "do the next **unticked** chunk" — plan.md ticks live in the same commit as the code, so the git tree is authoritative.
- artifacts are written temp-then-rename (never read half-written).
- re-running a step never double-applies.

## Failure mid-run
Network/emulator failure → the worker `claude -p` errors → after a couple of quiet retries the supervisor sets `blocked` → the Orchestrator pauses the run (records the reason in `state.json`) and tells the user. `--resume`/`continue` picks up later.

## Multiple runs (v2 — built)
See `multirun.md`. Each run is a **git worktree** + a **registry** entry (`~/.dev-harness/registry.json`) with heartbeat + per-run lock. `--resume` / "continue" reads `registry_list`, renders an HTML picker, and reattaches the chosen run's tmux session + emulator before re-sending its in-flight instruction. (The reattach/picker flow is smoke-tested.)
