# dev-harness — Design Spec (v3)

**Date:** 2026-06-02
**Branch target:** new `feat/dev-harness` from `origin/master`
**Status:** design — reviewed by 3 independent agents (architect/critic/security) + advisor. This amendment section GOVERNS where it conflicts with later sections.

## Pre-build review outcomes (multi-advisor) — v1 scope & required fixes

### Keystone risk — prove before building the rest (gates Task 1)
The Orchestrator is an LLM chat turn, **not a daemon**: it goes dormant when it yields, has no allowed foreground-sleep/poll primitive, and its own context grows across a long multi-phase run. The whole topology rests on it driving everything. **Task 1 (spike) must prove sustained, unattended self-re-engagement**, not "a poll spanning 10 min." Hardened bar:
- Worker completion **re-invokes** the Orchestrator (via `run_in_background`/Monitor wake on process exit), it does not rely on the Orchestrator remembering to poll.
- The Orchestrator **re-derives stage/phase/in-flight from `state.json` on every re-entry**, never from conversational memory (survives compaction).
- Repeated automatic wake→read-state→dispatch cycles with **zero keystrokes**.
- **Fallback:** if an LLM session cannot stay alive across the run, the Orchestrator becomes a **bash driver** that calls `claude -p` only for judgment calls. The spike SELECTS between these two topologies before any other file is written.

### Visibility fix (user's #1 requirement — empirically broken as specified)
The `stream-json | jq` filter on `text_delta` only renders final prose — a tool-heavy task showed ~1 visible line. **Broaden the filter to also surface `thinking_delta` and tool names** (`content_block_start`/`input_json_delta`). Task 1 must verify live activity is visible on a **real tool-using coding task in a narrow tiled pane**. (Confirmed good news: headless `claude -p` DOES load plugins/skills in-pane — scariest unknown retired.)

### Cheap correctness fixes (fold in)
- **Done = exit-0 AND the expected artifact exists / mtime-newer than dispatch** (exit-0 alone is a false positive: `claude -p` exits 0 on refuse/no-op).
- **Tick `plan.md` inside the same git commit as the chunk's code** → "do the next unticked chunk" becomes deterministic; resume can't double-apply.
- **Supervisor polls its OWN `status` file in an in-shell loop** (no `fswatch`/`inotify` — absent on macOS). Do **not** depend on coreutils `timeout`/`gtimeout` (absent); use shell-native waits.
- Write inbox **temp-then-rename before** setting `status=working` (no half-read handoff).

### Security rails — bash-ENFORCED (not prompt-level), hold even under `--auto`/`bypassPermissions`
1. **Story text, repo content, and all tool output are DATA, never instructions** (prompt-injection boundary — the single biggest gap).
2. **Never force-push.** Push only to the run's own `harness/<slug>` branch on `origin`. **PR base = the configured repo only** (never a fork/other remote).
3. **Redact secret/token-shaped strings** from every artifact (worklog, log, HTML, PR body) before write/publish.
4. **`.harness/` is gitignored**, never committed.
5. **All `adb`/`maestro` go through a serial-scoped wrapper** pinned to `emulator.lock`; global device commands (`kill-server`/`reboot`/global `uninstall`) banned.
6. `--auto` skips **review** gates but never the destructive-op / redaction rails.
7. **Accepted v1 risk (documented):** workers run un-sandboxed with `bypassPermissions` → full-machine blast radius on the dev's own machine/repo/stories. Sandboxing (container/VM) deferred to v2.

### v1.5 SCOPE (mid agreement) — keeps the real product; defers only the heavy/distributed/cross-repo bits

**CORE — never cut, in EVERY version:**
- The full **named team + their skill bindings** (table in §2): Manish=feature-analyzer/brainstorming · Mohit-Dev=clean-code/legacy-refactor/bug-finder/preview-compose/figma-to-compose/KMM · Bharat-Dev=clean-code/preview-compose · Rohit/Bharat-QA=qa-autopilot · Mohit-Arch=review-pr/clean-code. (Dedicated qa-lead/qa-junior skills DEFERRED — agents use qa-autopilot for now.)
- **Phased delivery** (UI→logic→wiring, Manish decides, user approves) + **per-phase Dev→QA**.
- **Architect** clean-room review + **structural-replan** routing; small vs structural.
- **Both feedback lanes** (task + skill-capture), **restart**, **single-run resume** (state.json + worklog + `continue`/`--resume`).
- **HTML reviews** for the user, all **security rails**, all correctness fixes.

**BUILD in v1.5:** one run on one repo, the **full phased pipeline** above end-to-end → tested+reviewed PR. HTML gate generator is **lean** (clean but not the full feature-analyzer theming).

**v2 STATUS (built in this PR):** opt-in OS sandbox (`--sandbox`, Seatbelt/bubblewrap), themed review pages (Linear-inspired), and the multi-run core (`--worktree` + cross-run registry + heartbeat + per-run lock). Only **auto-raising skill-feedback PRs** remains deferred; the reattach/picker flow is smoke-only.

**DEFER to v2** (original list — kept for history):
- **Task 12.5** — running multiple harnesses at once (per-run git worktrees, `registry.json`, heartbeat, stale-lock takeover).
- **Auto-raising** skill-feedback as PRs to the skills repo (v1.5 still **captures** notes to the md store; only the automated PR-raising is deferred).
- **Fanciest HTML theming** (sticky sidebar / Original-Story tab / full feature-analyzer CSS) — v1.5 ships a clean, simpler page.

**Per-phase QA scoping (anti-deadlock):** each phase's QA tests **what that phase delivers** (a UI-only phase → screen-renders / elements-visible / navigation checks), not behavior not yet built. A phase's verdict is its own acceptance, not the whole feature.

---

(Original full design follows; treat the section above as the authoritative v1 cut.)

## Goal

A self-contained Claude Code plugin, `dev-harness`, exposing `/harness "<story>"`. It drives a story to a tested, reviewed feature through a **visible, named team** of agents across **5 tiled tmux panes**, coordinated by an **Orchestrator** running in the user's main session. The harness is **self-improving**: skill feedback the user gives during a run is captured continuously to an md store and raised as skill-improvement PRs later (a continuous workflow step, not a gating phase).

## The team

| Pane (role key) | Persona | Role | Model | Skills (strong default) |
|---|---|---|---|---|
| `tech-lead` | **Manish** | Tech Lead | opus | feature-analyzer, brainstorming |
| `dev` | **Mohit-Dev** (lead) + **Bharat-Dev** (worker) | Senior + Junior Dev | opus + sonnet | clean-code, legacy-refactor, bug-finder, preview-compose |
| `qa` | **Rohit** (lead) + **Bharat-QA** (worker) | QA Lead + Tester | opus + sonnet | qa-autopilot (qa-lead/qa-junior deferred) |
| `architect` | **Mohit-Arch** | Review Architect | opus | review-pr, clean-code |
| `log` | — | live `tail -f .harness/log.md` | — | — |

Names are a presentation layer; routing always uses the role key. Every pane introduces itself by persona name and is titled accordingly ("names on all").

## Architecture — Approach B (supervised one-shots)

Each role pane runs a small bash **supervisor loop** (`role-runner.sh <role>`), NOT an interactive Claude. The supervisor watches its inbox; on a new instruction it runs a **headless one-shot**:

```
claude -p --model <opus|sonnet> --permission-mode bypassPermissions \
  --output-format stream-json --verbose --include-partial-messages "<role prompt + instruction>" \
  | jq -rj 'select(.event.delta.type?=="text_delta") | .event.delta.text'
```

Claude does the task, writes artifacts, and **exits**; the supervisor sets `status=done` **from the exit code**. No screen-scraping; no agent-written sentinel. (Doc-backed: `claude -p` honors `--model`; `--permission-mode bypassPermissions` replaces the old `--dangerously-skip-permissions`; `stream-json --verbose --include-partial-messages` is what makes the live work visible. We do **NOT** pass `--bare` — the panes need the plugins/skills.)

**You see every window working.** All 5 panes are tiled and each streams its live work (the `stream-json` text deltas), so you watch Manish/Mohit/Rohit/Mohit-Arch in real time and can intervene (feedback, Ctrl-C, restart). "Headless" means non-interactive, NOT invisible.

**Why B:** visible streaming panes (the user watches and intervenes), deterministic completion (process exit), stateless roles (all state lives in `.harness/` artifacts + code on disk + the PR), per-invocation model pinning, normal plugin/skill loading.

**Done-signal taxonomy considered:** screen-scrape (rejected — fragile), process-exit (chosen), subagent-return (Approach A — dropped: no visible panes), agent-written sentinel (Approach D — dropped: fragile).

### Start behavior (pane visibility)
- Inside tmux (`$TMUX` set): build the harness window in the current server and **switch the client to it** — all 5 panes visible immediately.
- Not in tmux: create the `harness` session **detached**, print `tmux attach -t harness`.

### Models (doc-confirmed)
- Lead panes launched `claude -p --model opus` (per-invocation pin; aliases `opus`/`sonnet` valid).
- Sonnet workers via two tiny plugin agent defs — `junior-dev`, `qa-tester` (`model: sonnet` frontmatter) — dispatched by leads through the Task tool, which honors the agent's `model` field. This is the documented best-practice "opus-lead / sonnet-workers" pattern.
- Plan mode dropped (blocks autonomy); leads write a plan to a file, then dispatch.

## Pipeline flow

```
/harness "<story>"   (this session = Orchestrator)

INIT · harness-init.sh
   PREFLIGHT: verify tmux, gh, adb + a booted emulator, maestro, and every required plugin/skill
              (feature-analyzer, clean-code, bug-finder, legacy-refactor, preview-compose,
               qa-autopilot, review-pr, skill-feedback) — fail fast with a clear message
   branch feat-style harness/<slug>-<date> from origin/master
   .harness/ layout (story.md, log.md, per-role inbox/outbox/status/feedback, artifacts/, qa/emulator.lock)
   capture booted emulator serial → qa/emulator.lock (refuse if none · --serial if >1)
   tmux session "harness": 5 tiled panes; role panes run role-runner.sh <role>
   (inside tmux → switch client into it; else detached + print attach cmd)

STAGE 1 · Tech Lead (Manish)
   ANALYSE → feature-analyzer + brainstorming → spec.md, findings.md, open-questions.md
             + PHASE PLAN: Manish decomposes the story into phases in NATURAL DEVELOPER ORDER
               (UI first → then logic → then wiring) — NOT by risk. You approve the phases in the HTML gate.
   open-questions? → HTML questionnaire → user answers → RESUME
   ► HTML PLAN-REVIEW GATE: render spec + phase plan to HTML (comments + Q&A), open it, wait for review

PER-PHASE LOOP  (for each phase P in the phase plan, in order):
  STAGE 2 · Dev (Mohit-Dev + Bharat-Dev) — Orchestrator-driven per-chunk loop, scoped to phase P
     PLAN(P) → Senior writes plan.md chunk checklist for P
     loop IMPLEMENT-NEXT: fresh claude -p (Senior) takes next unchecked chunk, dispatches Bharat-Dev
          (junior-dev, sonnet), reviews in-dispatch, checks off plan.md + appends dev-handoff.md
     until P's checklist done
     ░ GATE: phase P implemented — proceed to QA(P)? ░
  STAGE 3 · QA (Rohit + Bharat-QA) — SERIAL, QA never codes, only asks, scoped to phase P
     3a TAG-CHECK → testtag-requests.md → if any: Dev ADD-TAG → back
     3b PREP → qa-scenarios.md (prose, Rohit via qa-autopilot)
     3c TEST → qa-flows/*.yaml + run on locked serial → qa-report.md (PASS|FAIL+evidence, Bharat-QA via qa-autopilot)
     FAIL → Dev FIX-PER-QA → loop   (QA fix max 7)
     ░ GATE: phase P QA verdict ░
  → next phase

After all phases pass QA → Dev opens a draft PR for the branch

STAGE 4 · Architect (Mohit-Arch) — reviews the whole PR (clean-room: ignores dev-handoff)
   PASS (no changes)   → DONE
   only [small]        → Dev ADDRESS-SMALL → re-Architect          (NO re-QA per round)
   any [structural]    → Architect writes architect-replan.md (the fix design)
                         → Dev IMPLEMENT-REPLAN → QA re-test (affected phases) → re-Architect
   small fixes applied & Architect finally PASS → ONE FINAL QA → DONE
   Architect max 3 · GLOBAL ≤3 full QA→Architect cycles → escalate to user
   ░ GATE: architect verdict ░

DONE · append final block to log.md, post summary, leave PR ready.
```

**Phased delivery:** the **Tech Lead (Manish) decides the phases** and orders them the way a normal developer works — **UI first, then the logic behind it, then wiring** — never "riskiest first." The user approves the phase list in the HTML plan-review gate. Each phase runs its own Dev→QA cycle and must pass QA before the next phase starts. The PR opens once all phases are code-complete; the Architect reviews the whole PR.

## Feedback Management Model (design pillar) — `references/feedback-model.md` + `feedback.sh`

**Flexible targets:** you address feedback by **persona name OR role key**, in natural phrasing — *"feedback for mohit"*, *"feedback for dev"*, *"feedback Rohit: …"* all resolve to a role. The Orchestrator maps names→roles (Manish→tech-lead, Mohit-Dev/Bharat-Dev→dev, Rohit/Bharat-QA→qa, Mohit-Arch→architect). Ambiguous first names (Mohit = Dev or Arch) → Orchestrator resolves by the currently-active role, else asks.

Two lanes, classified by the Orchestrator (asks the user when ambiguous):

- **Task feedback** (about *this story's* work): `feedback <name|role>: <text>` → append to `.harness/<role>/feedback.md`; supervisor folds it into the role's next dispatch (or interrupt + re-dispatch for "now"). Per-run.
- **Skill feedback** (about a role's *skill* being deficient): `skill-feedback <skill>: <text>` → the `skill-feedback` skill **appends it to an md store** (`~/.dev-harness/skill-feedback/<skill>.md`). It is **NOT a phase** — there is no feedback phase. Capture is a **continuous step** in the workflow; the accumulated md is **raised as PRs later** (user-triggered, or as an ongoing background step), never gating the pipeline.

## Context relief — chunked Dev + restart — `references/restart.md`

- **Structural prevention:** the per-chunk IMPLEMENT-NEXT loop keeps every `claude -p` small by construction; `dev-handoff.md` is updated each chunk.
- **Manual `restart <role>`:** checkpoint (append handoff: done · in-progress · remaining · decisions) → stop current run (respawn pane to clear view) → re-dispatch RESUME → fresh session reads handoff + disk + remaining plan → continues. The handoff file is the resume token.

## Crash recovery, resume & multiple runs — `references/resume.md`

**Principle:** durable state (`.harness/` files + git branch/commits + PR) survives any crash; transient state (tmux, running `claude -p`, the manager's memory) does not. **Resume = rebuild the transient from the durable.**

**Save file (updated at every transition):**
- `log.md` — append-only history.
- `state.json` — current snapshot: run-id, story, slug, repo, branch, current stage+phase, the in-flight instruction (e.g. `dev:IMPLEMENT-NEXT chunk 3`), loop counters, and a **heartbeat** timestamp.
- **Per-worker `worklog.md` (mandatory journal)** — EVERY role appends a line as it works ("started chunk 3 …", "done, tests green", "now reviewing"). It is the fine-grained "where I stopped" record; combined with the code on disk + the role's handoff, a fresh worker resumes from the exact spot. `dev-handoff.md` remains the per-chunk checkpoint.

**"continue" = resume.** The plain word **"continue"** is a first-class trigger: when the user says it, the Orchestrator runs the resume routine (identical to `--resume`).

**Run registry** `~/.dev-harness/registry.json` — every run on the machine: run-id, repo, branch, story, status (active|paused|crashed|done), tmux session, last heartbeat.

**Alive vs crashed:** manager touches the heartbeat every few seconds. Alive = tmux session exists AND heartbeat fresh (refuse to double-drive). Crashed = heartbeat stale AND session gone. A per-run **lock** (owning pid), taken only if stale, prevents two managers driving one run.

**`/harness --resume`:** read registry → HTML picker → choose run → take stale lock → rebuild tmux + 5 panes (supervisors are idempotent, just re-watch inboxes) → re-pin emulator → read `state.json` resume point → **re-send the in-flight instruction** (a fresh worker reads its handoff + code on disk + remaining checklist and continues) → carry on.

**Idempotency makes re-dispatch safe:** chunk checklist = "do the next unticked chunk"; git commits are authoritative; files written temp-then-rename (never read half-written). Re-running a step never double-applies.

**Network/emulator failure mid-run:** failed `claude -p` → a couple quiet retries → worker `blocked` → manager **pauses** the run (records reason in `state.json`) and tells the user; `--resume` continues later.

**Multiple concurrent runs:** each run = own run-id, own `.harness/runs/<id>/`, own tmux session `harness-<id>`, own branch; **same-repo runs each get their own git worktree** (no clobbering). Registry lists all; `status` shows all. **Constraints:** (1) each running harness needs its **own booted emulator** — QA can't share a phone; if none free, that run's QA is `blocked` rather than fighting for the device; (2) several Opus teams at once is cost/CPU heavy.

## Orchestrator prompt palette — `references/orchestrator-prompts.md`
The Orchestrator never improvises wording. It owns a **ready-made set of prompts** (a palette) for every action it takes — booting each role, dispatching each instruction (ANALYSE, PLAN, IMPLEMENT-NEXT, TAG-CHECK, PREP, TEST, REVIEW, ADDRESS-SMALL, IMPLEMENT-REPLAN, FIX-PER-QA), injecting feedback, **checkpoint + restart**, status, and resume. Each is a fixed, tested prompt template so behavior is consistent every run. User-facing commands that trigger them: `feedback <name|role>: …` · `skill-feedback <skill>: …` · `restart <name|role>` · `status` · `--auto` (skip gates) · `--resume` (also triggered by the plain word **"continue"**). **Restart is always driven by the Orchestrator using the palette's checkpoint+handoff+resume prompts** — the worker is told exactly how to hand over.

## The "log" pane vs the Orchestrator
The **Orchestrator (the manager) is your main session** — the window where you type the story and give commands. The 5th `log` pane in the harness window is just a **live mirror** of the Orchestrator's running ledger (`log.md`) so you can watch its decisions next to the four workers; it is a read-only view, not a separate agent.

## HTML Interaction Layer (design pillar) — `references/html-interaction.md` + `render-review.sh` + `assets/theme.css`

**Every human touchpoint in the harness renders as a themed HTML doc opened in the browser — never raw terminal markdown.** Touchpoints covered: story review · plan/spec review · the Tech-Lead clarification questionnaire (open-questions) · any feedback request · gate verdicts (spec/dev/QA/architect) · the final summary.

- **One shared themed template** wraps every payload (story · plan · questions · verdict) in a consistent shell: sticky sidebar nav, header block (feature · intent · date · session-id), and — where relevant — the **Original Story** tab (raw, unmodified) à la feature-analyzer.
- **Theme lineage:** the visual theme is inherited from `feature-analyzer`'s HTML workflow (`references/html-output.md`; canonical render `feature-analyzer-workspace/canonical/analysis-v2.html` = visual source of truth). We ship a themed `assets/theme.css` derived from it so the harness has its own consistent, branded format.
- **Always answerable + copyable:** comment boxes per section, Q&A inputs, radio/checkbox choices, and a **Copy** button assembling responses into one pasteable block (clipboard API + select-the-preview fallback for `file://`). The user reviews in the browser and pastes back; the Orchestrator parses the response and proceeds.
- **`render-review.sh <kind> <payload-file>`** emits `<.harness>/review/<kind>-<n>.html` from the themed template and `open`s it (or prints the path when not on a desktop session).

This is the standard interaction contract for the whole loop — gates and questionnaires are HTML, not terminal prompts.

## Hard rules
1. Only the Orchestrator writes role inboxes — panes never talk to each other.
2. The Orchestrator never writes code and never runs/authors tests.
3. QA never codes — it only asks (testtag-requests route to Dev).
4. Skill bindings are strong defaults with reason — deviation requires a one-line reason in outbox.
5. QA never reports overall PASS until pass criteria are met.
6. Architect tags every issue `[small]` or `[structural]`; structural ⇒ Architect replans, Dev implements, QA re-tests.
7. Everything is serialized — no pane runs concurrently with another.
8. The story is delivered in **ordered phases**; each phase passes its own Dev→QA cycle before the next begins.
9. Every pane is **visible and streams its live work**; all human touchpoints are **HTML docs**, never terminal prompts.
10. **Every worker journals what it does** to its `worklog.md` as it goes, so the run can always be resumed from the exact stopping point. "continue" resumes the run.

## Prerequisite — split qa-autopilot
**DEFERRED (changed):** the qa-autopilot → qa-lead/qa-junior split is NOT done in v1.5. The QA agents (Rohit, Bharat-QA) use the existing **`qa-autopilot`** skill directly (Rohit: QA mindset + flake-vs-real; Bharat-QA: single-flow Maestro authoring + execution). Dedicated `qa-lead`/`qa-junior` skills are to be authored later. The emulator lock is produced by `harness-init.sh` capturing a booted serial (NOT a provisioning script — `ensure-emulator.sh` does not exist and is not created). Fixing `qa-autopilot` itself is also deferred.

## Scope
The Sniper Android app, all-in-one (incl. KMM). feature-analyzer is app-specific by design — accepted.

## Resolved since v3-draft
- **Model pinning** — RESOLVED (doc-backed): `claude -p --model opus` for leads; `model: sonnet` agent defs for workers; `--permission-mode bypassPermissions`; live visibility via `stream-json --verbose --include-partial-messages`.
- **Skill-feedback cross-repo** — RESOLVED: not a phase; `skill-feedback` appends to an md store continuously; PRs raised later. No gating, no Phase 0.
- **Plugin/tool availability** — RESOLVED into a hard preflight in `harness-init.sh` (tmux, gh, adb+emulator, maestro, and every required plugin/skill) that fails fast.
- **qa-autopilot fix** — DEFERRED by user; out of scope.

## Named risks (still open)
1. **Streaming-pane UX** — `stream-json | jq` rendering must be readable in a narrow tiled pane; the spike (Task 1) validates it.
2. **Skill availability at pane runtime** — preflight covers presence, but `claude -p` must actually load them in the pane's cwd/env; spike confirms.

## Implementation ordering
**Task 1 is a 2-pane Approach-B spike** (one supervisor loop · one `claude -p` · exit-code→status · one Orchestrator poll across a >10-min run) to prove the load-bearing loop BEFORE writing the remaining files. The bash mailbox unit tests prove only file I/O; the spike + on-device smoke gate "usable".

## File structure (high level)
Plugin `plugins/dev-harness/`: `.claude-plugin/plugin.json`; `commands/harness.md`; `skills/dev-harness/SKILL.md`; `references/` (protocol, orchestrator, orchestrator-prompts, role-{tech-lead,dev,qa,architect}, skill-bindings, feedback-model, restart, resume, html-interaction); `assets/theme.css` (themed, derived from feature-analyzer); `scripts/` (lib.sh, harness-init.sh, role-runner.sh, send.sh, poll.sh, feedback.sh, render-review.sh); `agents/` (manish, mohit-dev, bharat-dev, rohit, bharat-qa, mohit-arch); `hooks/hooks.json` (guard); `test/`. marketplace.json + README updates. (qa-lead/qa-junior plugins deferred — QA uses qa-autopilot.)

## Authoring principle
Small, concise, precise SKILL files; hard imperative rules. Detail lives in references only when load-bearing.
