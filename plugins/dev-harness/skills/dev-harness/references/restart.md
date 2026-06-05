# Restart — context relief for a single pane

Each pane is a **persistent interactive `claude --agent <persona>`**. A long dispatch can fill a pane's context; `restart <name|role>` gives that one pane a fresh start without losing work.

## `restart <role>` procedure (Orchestrator-driven)
```
1. checkpoint → the role appends a handoff to its outbox/worklog:
                done · in-progress · remaining · key decisions
2. respawn   → tmux respawn-pane the role's pane: agent-pane.sh <role>
                (re-record its pane id; a fresh Claude session starts)
3. RESUME    → re-dispatch the role; the fresh agent reads its handoff + worklog +
                the code on disk + the remaining plan/design, and continues
```
The handoff + `worklog.md` are the resume token — nothing is lost, because all durable state is on disk (artifacts, git, plan ticks). On respawn the agent re-records its `session` id, so the watchdog keeps seeing it alive. The Orchestrator pane itself is resumable the same way (see `resume.md`).
