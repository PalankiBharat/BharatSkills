# Orchestrator playbook

The authoritative driver instructions live in **`agents/orchestrator.md`** (the Orchestrator runs as a pane, `claude --agent orchestrator`). This file is the reference summary; if the two disagree, the agent file wins.

The Orchestrator is a **visible pane**, not the main session. `/harness` is launcher-only: `harness-init.sh` opens the `harness-<slug>-<date>` window in the current tmux session, spawns 6 panes (Orchestrator + tech-lead + dev + qa + architect + log), self-starts the Orchestrator, then steps back. The Orchestrator drives via files in `.harness/`; it never writes code or tests, and re-derives state from `state.json` on every re-entry.

## Dispatch + liveness
- Dispatch: `bash .harness/send <role> "<instruction>. EXPECT: .harness/artifacts/<file>"` (writes inbox, sets `working`, nudges the pane).
- Wait: `bash .harness/poll <role> --settle` — prints `done`/`blocked`/`still-working` (re-poll on `still-working`); returns under the tool cap so the turn never breaks.
- Before accepting `done`, confirm the artifact: `bash .harness/require <file>…` (a `done` with a missing artifact is really `blocked`).
- A file-based **watchdog** runs alongside (judges liveness by `worklog`+`activity.log`+transcript mtimes); it messages `SETTLE` (advance) or `ESCALATE` (a role is stuck — tell the user, pause).

## Flow (two human gates; full path = feature)
1. **Tech Lead → requirement.** `send tech-lead "ANALYSE …"` → `require spec.md feature-analysis.md`.
2. **GATE 1 — requirement review (human).** `bash .harness/ask .harness/artifacts/questions.json` (or render `spec.md`); null `in_flight`; end turn. Resume: `bash .harness/answer tech-lead "<answers>"`.
3. **Design (feature only).** `send dev "PLAN — first-cut tech-plan.md"` → `send architect "PLAN — design.md (pseudo-code: SOLID / clean arch / scale)"` → `require design.md`.
4. **GATE 2 — design review (human).** render `design.md`; null `in_flight`; end turn. Resume: `answer architect`.
5. **Build per phase — separate lanes.** `send dev` (implement the design TDD; code/unit tests are Dev's, foreground) → `send qa` (manual/user-journey via Maestro). Phase done = `dev-handoff.md` **and** a QA-PASS `qa-report.md`. QA FAIL → re-dispatch Dev (fix cap **7**/phase).
6. **PR → Architect post-code REVIEW.** `[small]` → Dev fixes + final QA once; `[structural]` → Architect replans → Dev → QA re-test. Caps: Architect **3**, global QA↔Architect **3**, then escalate.
7. **DONE** — null `in_flight`, summarise `log.md`, `touch .harness/.stop-watchdog`.

**Small change / bug fix** → skip the two design gates (one Dev pass → QA → light Architect).

## Rules
- Never edit `app/**` / `.maestro/**`; never do a teammate's work — route gate answers via `.harness/answer`, never reconcile/analyse yourself.
- Keep Dev and QA lanes separate — Dev implements, QA verifies; never put render/ST/PASS-FAIL/screenshots in a Dev dispatch.
- `guard.sh` (PreToolUse) hard-blocks force-push / push-to-master / global-adb / `rm -rf /` for every pane.
- Gates render as HTML (`render-questions.sh` / `render-review.sh`). `--auto` skips the human gates (never the security rails) — opt-in, small stories only.
- Accepted-anytime user commands: see `orchestrator-prompts.md`.
