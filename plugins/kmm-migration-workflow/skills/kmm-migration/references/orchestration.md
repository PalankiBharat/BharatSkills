# Autopilot orchestration (tmux headless phase pipeline)

Loaded **only in autopilot mode** (`KMM_AUTOPILOT_ROLE` set). Phases are a strict
safety pipeline (`0 → A → B → C → D → E → F → G → H → I`); there is no inter-phase
parallelism. Autopilot removes the *human-wait* between phases and the ceremony
gates — it does **not** loosen the four irreversible decision gates.

## Roles

- **Orchestrator** (`KMM_AUTOPILOT_ROLE=orchestrator`) — one interactive session,
  the single human touchpoint. Runs Phases 0 + A here as normal. From Phase B
  onward it does **not** run phases itself; it spawns a worker per phase and acts
  on the worker's status file. Holds only orchestration state (current phase,
  escalation queue, pre-flight results) → light context all session.
- **Worker** (`KMM_AUTOPILOT_ROLE=worker`, `KMM_AUTOPILOT_PHASE=<X>`) — a fresh
  headless `claude -p` session, one per phase, bootstrapped by the
  `resume_session` SessionStart hook. Runs exactly the active phase (incl. its
  blocking retro), then exits. Never advances, never waits for interactive input.
  Dispatches its own `Task` subagents for intra-phase parallelism (unchanged).

## Control plane (files, never pane-scraping)

Under `.kmm/migrations/kmm/<feature>-<depth>/orchestration/`:

| File | Writer | Meaning |
|---|---|---|
| `phase-<X>.status` | worker | `COMPLETE` \| `BLOCKED` \| `FAILED` (+ reason). Written atomically (temp + `mv`) just before exit. |
| `decision-request.md` | worker | plain-language problem + options + impacts + worker's recommendation; appended (batched) for each gated decision before a `BLOCKED` exit. |
| `decision-response.md` | orchestrator (writes the human's answer) | the human's answer(s). The worker consumes then deletes it on its next start. |

The orchestrator waits on the worker's **process exit** (reliable), then reads the
status file. A worker that dies leaves state on disk → relaunch resumes via hook.

## Drive-loop (orchestrator, Phases B→I)

```
for phase in B C D E F G H I:
    bash scripts/preflight.sh <phase>     # device/iOS/login gate; non-zero -> escalate reason, wait, re-check
    if phase == H: spawn review-pr --auto against the PR (own window)
                   # it posts findings as inline PR comments; the Phase H worker
                   # ingests them at H.1 via `gh pr view <url> --comments`
    retried = false
    loop:
        status = run-phase-worker.sh <phase>   # launch as a background Bash task; re-notified on exit
        if status == COMPLETE: break           # advance to the next phase
        if status == BLOCKED:
            present orchestration/decision-request.md to the human; collect the answer(s)
            write orchestration/decision-response.md; continue loop   # relaunch; resumes via hook
        if status == FAILED:
            if not retried: run `./gradlew --stop`; retried = true; continue loop   # one auto-retry
            escalate the diagnostic to the human; break
```

**Run the worker as a background task.** A phase can run for hours; do not block a
single foreground tool call on it. The orchestrator launches `run-phase-worker.sh
<phase>` as a **background** Bash task and is re-notified when it exits (the
script's stdout is the bare status line). This is also what lets the orchestrator
stay responsive to the human while a phase runs. A runaway/hung worker is the
orchestrator's call to kill (via `tmux kill-window`) and re-spawn.

The orchestrator never does phase work itself (the skill's "no code from the
orchestrator" rule, raised to phase level). Spawning workers and reading status
files is dispatch + read-only, which is allowed.

## Escalation classes

**Always escalate (the four irreversible classes):** dependency/library swap or
version, behavior-changing fix (migration-exception), scope/plan flip
(`migrate→hold` or new in-scope file), real-money/mutating device journey.

**Inherent escalations (physical / one-time):** missing device/simulator/login
(pre-flight), discovered PII (Phase B.6b), first-time detekt bootstrap accept
(Phase C).

**Everything else is auto-decided** with one-line logged reasoning in the phase
file's decisions log (visible on `tmux attach`): phase transitions, B-strategy,
promote-scope, re-validation scope, detekt after first time, PR-body content.

## Autopilot phase overrides (workers consult their row)

| Phase | Override |
|---|---|
| C | First time (`detekt_bootstrapped` absent/false) → **escalate** the detekt bootstrap for sign-off; subsequent runs → auto-accept (C.2 is skipped). |
| E | Default promote-scope to **promote-only-clean** (move clean files, defer the rest). |
| F | No runtime smoke (removed); draft the heatmap skeleton only. |
| G | Open the PR as a **DRAFT**; never auto-merge, never auto-mark-ready. |
| H | Reviewer is `review-pr --auto` against the PR; its findings arrive as inline PR comments, which the Phase H worker ingests at H.1 via `gh pr view <url> --comments`. Resolve non-gated blockers through the workflow; proceed when clean. |
| I | Loop on ProductionDebug; the binding parity gate is the ProductionRelease final-sanity pass (I.2.8). |

## Failure / retry

Transient gradle failures (KSP incremental-cache `Number of loaded files in
snapshots differs`, daemon contention) are common (see SKILL.md Tooling
discipline). On `FAILED`, run `./gradlew --stop` and retry the phase once with a
fresh worker. A second failure escalates with the captured diagnostic. The
orchestrator never picks up the phase work itself.
