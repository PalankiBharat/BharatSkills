# KMM Migration Autopilot — tmux-orchestrated headless phase pipeline

**Date:** 2026-06-07
**Status:** Design — approved, pending spec review
**Skill:** `plugins/kmm-migration-workflow/skills/kmm-migration`

---

## 1. Problem

The KMM migration skill is already orchestrator-and-subagent: the main thread never writes
code, it dispatches Haiku/Sonnet/Opus subagents in parallel within a phase, and all state is
serialized to `.kmm/` with a `resume_session.py` SessionStart hook that deterministically
rebuilds phase state into a fresh context.

But the **phase-to-phase boundary is manual**. Today the skill, at a phase boundary, *suggests
the user open a new session* and waits. A 5–9h migration therefore stalls on human latency
between every phase, and the "clean context per phase" benefit depends on the user remembering
to `/clear` + re-invoke. The decision gates are also blocking in-session prompts — the workflow
cannot run unattended even where the decisions are mechanical.

## 2. Goals

- **Headless phase pipeline.** An orchestrator auto-advances phase→phase, each phase running in
  a *fresh* headless `claude` session, with no human wait between phases.
- **Max intra-phase parallelism.** Each phase worker keeps dispatching its own parallel `Task`
  subagents (unchanged from today).
- **Minimum-human autonomy.** Post Phase 0 + A, the orchestrator decides everything mechanical
  using KMM best practices + the locked plan, escalating only an irreversible decision class.
- **Reduce wall-clock.** Eliminate inter-phase human latency; pre-flight environment checks so
  workers don't fail late on a missing device.

### Non-goals

- **Inter-phase parallelism.** The phases are a strict safety pipeline
  (`0 → A → B → C → D → E → F → G → H → I`) with hard data dependencies; freeze is what *makes*
  migration safe, etc. Phases stay sequential. (Intra-phase parallelism is the only parallelism.)
- **Multi-feature concurrency.** Running several independent migrations at once is out of scope.
- **Replacing the worker logic.** The per-phase skill behaviour is unchanged except where this
  spec calls it out (Phase F smoke removal, Phase I build flavor, qa-autopilot/Maestro cleanup).

## 3. Architecture

Two roles, **both running the same skill**, distinguished by an autopilot-worker flag:

```
┌─ tmux session: kmm-<feature>-<depth> ────────────────────────────┐
│                                                                   │
│  pane 0: ORCHESTRATOR  (interactive — the human attaches here)    │
│    • runs Phase 0 + A WITH the human (planning, unchanged)        │
│    • then drives the pipeline (see §6 drive-loop)                 │
│    • holds ONLY orchestration state → light context all session   │
│                                                                   │
│  window N: PHASE WORKER  (headless claude, ONE phase, then exits) │
│    • resume_session hook bootstraps state from .kmm/              │
│    • runs the active phase, dispatching parallel Task subagents    │
│    • escalates a gated decision → writes decision-request + exits │
│    • completes → writes phase-<X>.status=COMPLETE + exits         │
│                                                                   │
│  window: PR-REVIEW   (review-pr --auto, after Phase G)            │
│  window: PHASE I     (parity loop, own long-lived pane)           │
└───────────────────────────────────────────────────────────────────┘
```

- **Mechanism: tmux CLI `claude` processes per phase + in-session `Task` subagents for
  intra-phase parallelism.** A fresh `claude` process per phase self-bootstraps via the resume
  hook, gets a truly isolated OS process + context window, and is watchable via `tmux attach`.
  Chosen over native background agents because those do not fire the SessionStart resume hook
  (losing the deterministic bootstrap) and are not watchable as panes.
- **The orchestrator is the single human touchpoint.** Phases 0 + A are interactive there.
  Phases **B → I run headless**. The orchestrator never does phase work itself — it only drives,
  relays escalations, and pre-flights (the skill's "no code from the orchestrator" rule, raised
  to phase level).
- **One phase per worker session** — max context freshness; spawn cost is trivial next to gradle
  time.

### 3.1 Control plane — files, not pane-scraping

Worker ↔ orchestrator communicate through `.kmm/migrations/kmm/<feature>-<depth>/orchestration/`:

| File | Writer | Purpose |
|---|---|---|
| `phase-<X>.status` | worker | `COMPLETE` \| `BLOCKED` \| `FAILED` + payload (atomic write before exit) |
| `decision-request.md` | worker | plain-language problem + options + impacts + worker's recommendation (batched if several) |
| `decision-response.md` | orchestrator | the human's answer(s), consumed by the relaunched worker |

The orchestrator waits on the **OS process exit** (reliable signal), then reads the status file —
no keystroke timing, no `capture-pane` scraping. A worker that dies mid-phase leaves its state on
disk; the orchestrator relaunches and the resume hook picks it up.

## 4. Worker lifecycle & status protocol

A worker launched for phase `X`:

1. SessionStart resume hook rebuilds state; skill detects autopilot-worker mode + active phase.
2. Runs **exactly phase `X`** to completion, **including the per-phase retro** (the retro gate is
   non-negotiable and must not be skipped in autopilot).
3. Decision routing during the phase:
   - **Trivial / ceremony / mechanical** → auto-decide, log a one-liner + reasoning into the phase
     file's decisions log (visible on `tmux attach`), proceed. No stop.
   - **Gated class (see §5)** → write/append `decision-request.md`, set status `BLOCKED`, exit.
   - **Batch before exiting** — multiple *independent* gated decisions bundle into one
     `decision-request` so the human answers them together with one relaunch. Never exit/relaunch
     per decision.
4. On clean finish → `phase-<X>.status = COMPLETE`, exit.
5. On unrecoverable error → `phase-<X>.status = FAILED` + diagnostic (gradle log path + error
   summary), exit.

The status file is written **atomically** (write temp + `mv`) so the orchestrator never reads a
half-written status.

## 5. Autonomy & escalation model

### 5.1 The 4 always-gated decision classes

These always escalate to the human (via `decision-request`), even when they look straightforward.
They are the irreversible class; this is the skill's existing "never auto-decide" list, unchanged:

1. **Dependency / library swaps + versions** — adding/replacing/version-bumping a dependency or
   choosing a library substitution.
2. **Behavior-changing fixes (migration-exceptions)** — anything that shifts observable output
   (JSON ordering, timezone, error strings). Requires a signed exception file.
3. **Scope / plan flips** — adding a file not in scope, or flipping a file `migrate → hold`.
4. **Real-money / mutating device journeys** — Phase I runs that would transact, mutate server
   state, or trigger re-login / eviction on a real account.

### 5.2 Three inherent escalations (beyond the 4 classes)

Physical or one-time, kept as escalations:

1. **Device / login pre-flight** — before any device/iOS phase (B.6b golden capture, D/E iOS
   compile, I parity), the orchestrator checks `adb`/Xcode/simulator availability and Phase I's
   one-time manual prod login. Missing → escalate *"connect a device / log into prod"* rather than
   let the worker fail late.
2. **PII gate** (Phase B.6b) — discovered PII classes surface to the human. Privacy, not covered
   by the 4 classes. Cheap, important.
3. **First-time detekt bootstrap accept** (Phase C, one-time only) — structural enforcement setup;
   if wrong, freeze protection breaks. After first time, fully auto.

### 5.3 Everything else is auto-decided

The orchestrator/worker auto-decides ceremony + mechanical gates with logged reasoning the human
can interrupt but that does not block: phase transitions, B-strategy choice, promote-scope
(defaults to **promote-only-clean**: move clean files, defer the rest), re-validation scope,
detekt after first time, PR-body content, PR open mode.

## 6. Orchestrator drive-loop

After Phase 0 + A complete interactively, the orchestrator loops over phases B → I:

```
for phase in [B, C, D, E, F, G, H, I]:
    pre_flight(phase)          # device/iOS/login checks → escalate if missing
    if phase == H: spawn review-pr --auto against the PR (own pane); feed findings to worker
    launch worker(phase) in a fresh tmux window     # headless claude, one phase
    wait for worker process exit
    status = read phase-<phase>.status
    case COMPLETE: continue
    case BLOCKED:
        surface decision-request.md to the human (already in plain-language format)
        collect answer → write decision-response.md
        relaunch worker(phase)                      # resumes via hook, consumes the answer
        (repeat until COMPLETE/FAILED)
    case FAILED:
        ./gradlew --stop ; retry worker(phase) ONCE fresh
        if still FAILED: escalate to the human with the diagnostic
```

The orchestrator's context stays light because it holds only: current phase, escalation queue,
and pre-flight results — never phase detail.

## 7. Failure & retry policy

- Transient gradle failures (KSP incremental-cache `Number of loaded files in snapshots differs`,
  daemon contention) are common and already documented by the skill. The orchestrator runs
  `./gradlew --stop` and retries the failed phase **once** with a fresh worker.
- A second failure escalates to the human with the captured diagnostic (gradle log path + error
  summary). The orchestrator never picks up the phase work itself.

## 8. Phase-by-phase automation map

| Phase | Where it runs | Auto-decided | Escalates |
|---|---|---|---|
| **0** Discovery | Orchestrator (interactive) | — | all (unchanged) |
| **A** Diagnostic | Orchestrator (interactive) | — | all (unchanged) |
| **B** Baseline | Headless worker | B-strategy, baselines, red-on-breakage, deferrals | PII gate; device pre-flight |
| **C** Freeze | Headless worker | verify/detekt-smoke/freeze; detekt after 1st time | first-time detekt accept; baseline-vs-scope conflict |
| **D** Migrate | Headless worker | topo order, `git mv`, planned swaps, compile-fix, iOS checks | exceptions, plan-flips, new deps; iOS pre-flight |
| **E** Promote | Headless worker | skip-check, K/N compiles, `git mv`, tests, promote-only-clean default | portability fix needing behavior/dep change; iOS pre-flight |
| **F** Validate | Headless worker | build, tests (JVM+iOS), pre-merge integration, code-quality/iOS-surface, heatmap-skeleton draft | semantic merge conflicts; blocker fix in a gated class |
| **G** PR | Headless worker | provenance, self-review, body draft, **open as DRAFT PR** | never auto-merge; never auto-mark-ready |
| **H** Review | Headless worker ← `review-pr --auto` | triage, resolve non-gated blockers, proceed-when-clean | any fix in a gated class |
| **I** Parity | Headless worker (own pane) | replay/A-B, verdicts, parity-bug diagnosis+fix, iterate | 4 gated classes, max-iter cap; device+login pre-flight |

Notable auto-decisions: **Phase G opens a draft PR** (never auto-merges, never auto-marks-ready) —
respects "outward-facing → don't fully publish" while keeping the pipeline moving.

## 9. Changes to the existing skill

### 9.1 Phase F — remove the runtime-crash smoke

Phase I's find-and-fix parity loop now exercises the app at runtime, so the F.5 runtime-crash
smoke is **removed**. Phase F becomes pure static/automated checks: build + tests (JVM+iOS) +
pre-merge integration + code-quality/iOS-surface + **heatmap-skeleton draft** (the QA checklist
structure embedded in the PR body; Phase I fills the Result cells). **Phase F no longer requires a
device** (smoke was its only device dependency), so its pre-flight drops.

Files: `references/phases/phase-f-validation.md` (remove F.5 smoke; keep heatmap-skeleton draft;
drop device dependency note), `SKILL.md` (phase table row for F), `references/runtime-golden.md`
and any cross-refs that point at "F.5 smoke".

### 9.2 Phase I — ProductionDebug loop + ProductionRelease final sanity

The iterative A/B find-and-fix loop runs on **`ProductionDebug`** (logcat/logs available for
diagnosis). A **final confidence pass runs on `ProductionRelease`**.

⚠️ **Binding rule (encodes the hard-won R8 lesson):** Debug skips R8, which can strip
`@Serializable` keep rules that only break in Release → *false greens for serialization
migrations*. Therefore **parity is NOT declared green until the `ProductionRelease` A/B pass
confirms it.** The Debug loop is for iteration speed + observability; the Release pass is the
binding parity-truth gate. Both legs use the same flavor in any single comparison
(master-Debug vs migrated-Debug during the loop; master-Release vs migrated-Release for final).

Files: `references/phases/phase-i-qa.md` (build flavors + the binding Release gate),
`references/agent-device.md` / `references/runtime-golden.md` if they pin a flavor, `SKILL.md`
(Realistic expectations + phase table wording).

### 9.3 Remove kmm-qa-autopilot / Maestro references

Phase I is self-contained (in-skill agent-device A/B). Remove the migration skill's pointers to
the standalone tool:
- `hooks/resume_session.py:266` — drop the "handed off to kmm-qa-autopilot" wording.
- `references/phases/phase-i-qa.md:9` — drop the standalone-tool note.

Maestro is already absent from the skill (verified — no matches). The standalone
`kmm-qa-autopilot` *plugin* itself is left untouched; only the migration skill's references are
removed.

### 9.4 New autopilot layer

- `references/orchestration.md` — the orchestration doctrine (roles, control-plane file protocol,
  worker lifecycle, drive-loop, escalation model, pre-flight checks, failure/retry). Loaded only
  in autopilot mode, on demand (consistent with the skill's load-phase-refs-on-demand philosophy).
- `scripts/kmm-autopilot.sh` — the tmux driver: creates the session, spawns per-phase worker
  windows (headless `claude`), waits on process exit, reads status files, relays escalations,
  spawns the `review-pr --auto` and Phase I panes.
- `SKILL.md` — a thin autopilot trigger + a one-paragraph pointer to `references/orchestration.md`;
  worker-mode detection (the skill behaves as a single-phase worker when launched by the driver).

### 9.5 Version bump (lockstep — repo rule)

`plugin.json` version + `marketplace.json` entry version + `marketplace.json` top-level
`metadata.version` + `README.md` row, all bumped together. `claude plugin validate .` after edits.

## 10. Risks & open questions

- **Headless `claude` invocation contract** — exact flag(s) for one-shot autopilot-worker mode
  (e.g. `claude -p` with a sentinel prompt vs an env var the resume hook reads) is an
  implementation detail to settle in the plan; it must reliably (a) trigger the skill, (b) signal
  worker-mode + the target phase, (c) run permissionlessly in a pane.
- **Worker-mode skill behaviour** — the skill must run *exactly one* phase and exit in worker
  mode, instead of suggesting a session break and waiting. This is the main worker-side change.
- **Pre-flight coverage** — the device/iOS/login checks must be complete enough that workers never
  fail late on environment; gaps here reintroduce wall-clock loss.
- **review-pr ↔ Phase H wiring** — Phase H currently ingests *human-pasted* review feedback; the
  autopilot wires `review-pr --auto` output in as the feed. The intake format must match.

## 11. Out of scope

- Inter-phase parallelism; multi-feature concurrency.
- Changes to the standalone `kmm-qa-autopilot` plugin.
- Rewriting per-phase worker logic beyond §9.1–9.3.
