# Resume — crash / session recovery

**Principle:** durable state (`.harness/` files + git branch/commits + PR) survives any crash; transient state (the tmux panes, the running Claude sessions, the watchdog, the Orchestrator's memory) does not. Resume = rebuild the transient from the durable.

## Save points (written every transition)
- `state.json` — run_id, slug, branch, stage, phase, `in_flight`, counters, heartbeat.
- `log.md` — append-only history.
- per-role `worklog.md` — fine-grained "where I stopped".

## `continue` / `/harness --resume` → `bash .harness/resume`
`harness-resume.sh` (the `.harness/resume` wrapper):
```
1. read state.json → the in-flight stage
2. if the run's Orchestrator pane is ALIVE (pane_alive) → restart it: respawn the watchdog
   + re-nudge the Orchestrator to "continue from state.json". That's the common case.
3. if the window/pane is GONE → tell the user to re-run /harness from inside tmux to rebuild
   the panes; .harness/ + git state are intact, so the rebuilt run picks up where it stopped.
```
On a rebuild, each agent re-records its `session` id and re-reads its inbox/worklog/the code on disk + the remaining plan/design, and continues from there.

## Stale runs (days old) → rebase from master first
Before re-dispatching Dev on an old run (or before a major refactor), have Dev `git pull --rebase origin master`. During the rebase, a conflict in a file NOT part of our feature is master's call (take theirs); resolve only inside our own feature's files; ask the user if unsure. After a sanctioned rebase, `--force-with-lease` on the run's OWN branch is the one allowed force-push (`guard.sh` still blocks plain `--force` and any push to master).

## Why re-sending is safe (idempotency)
- "do the next **unticked** chunk" — plan ticks live in the same commit as the code, so the git tree is authoritative.
- artifacts are written temp-then-rename (never read half-written); re-running a step never double-applies.

## Failure mid-run
A network/emulator/API failure ends a pane's turn; the watchdog detects the role going silent → check-in → ESCALATE to the user (or, for a rate limit, the recovery path). The run pauses with the reason in `log.md`; `continue` picks up later.

## Multiple runs (v2)
See `multirun.md`: each run is a git worktree + a registry entry (`~/.dev-harness/registry.json`) with heartbeat + per-run lock. (The reattach/picker flow is smoke-tested.)
