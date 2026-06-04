# Restart — context relief

Two layers keep workers fresh:
1. **By design** — the per-chunk `IMPLEMENT-NEXT` loop keeps every `claude -p` small; each worker is a fresh one-shot, so context never accumulates across dispatches.
2. **Manual `restart <name|role>`** — a safety valve for a single long dispatch.

## `restart <role>` procedure (Orchestrator-driven)
```
1. checkpoint  → the role appends a handoff to its outbox/handoff:
                 done · in-progress · remaining · key decisions
2. stop        → end the current run; `tmux respawn-pane` to clear the view,
                 relaunch role-runner.sh <role>
3. RESUME      → send the role its RESUME instruction; the fresh worker reads
                 the handoff + worklog + code on disk + remaining plan.md, and continues
```
The handoff + `worklog.md` are the resume token — nothing is lost because workers are stateless and all state is on disk. The Orchestrator itself is resumable too (see `resume.md`).
