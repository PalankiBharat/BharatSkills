# Orchestrator playbook

The authoritative driver instructions live in **`agents/orchestrator.md`** (the Orchestrator runs as a pane, `claude --agent orchestrator`). This file is the reference summary; if the two disagree, the agent file wins.

The Orchestrator is a **visible pane**, not the main session. `/harness` is launcher-only: `harness-init.sh` opens the `harness-<slug>-<date>` window in the current tmux session, spawns 6 panes (Orchestrator + tech-lead + dev + qa + architect + log), self-starts the Orchestrator, then steps back. The Orchestrator drives via files in `.harness/`; it never writes code or tests, and re-derives state from `state.json` on every re-entry.

## Dispatch + liveness
- Dispatch: `bash .harness/send <role> "<instruction>. EXPECT: .harness/artifacts/<file>"` (writes inbox, sets `working`, nudges the pane).
- Wait: `bash .harness/poll <role> --settle` — prints `done`/`blocked`/`still-working` (re-poll on `still-working`); returns under the tool cap so the turn never breaks.
- Before accepting `done`, confirm the artifact: `bash .harness/require <file>…` (a `done` with a missing artifact is really `blocked`).
- A file-based **watchdog** runs alongside (judges liveness by `worklog`+`activity.log`+transcript mtimes); it messages `SETTLE` (advance) or `ESCALATE` (a role is stuck — tell the user, pause). It re-sends a WAKE on a cadence while a dispatched role has never woken (a single wake can be dropped at pane boot).
- **Dropped nudge:** in_flight role `working` with activity-age rising across two consecutive SWEEPs (≥10 min) and no new worklog line → re-send the same dispatch; don't wait for the 30-min stuck path.

## Flow (two human gates; full path = feature)
1. **Tech Lead → requirement.** `send tech-lead "ANALYSE …"` → `require spec.md feature-analysis.md`.
2. **GATE 1 — requirement review (human).** `bash .harness/ask .harness/artifacts/questions.json` (or render `spec.md`); null `in_flight`; end turn. Resume: `bash .harness/answer tech-lead "<answers>"`.
3. **Design (feature only).** `send dev "PLAN — first-cut tech-plan.md"` → `send architect "PLAN — design.md (pseudo-code: SOLID / clean arch / scale)"` → `require design.md`.
4. **GATE 2 — design review (human).** render `design.md`; null `in_flight`; end turn. Resume: `answer architect`.
5. **Build per phase — separate lanes.** `send dev` (implement the design TDD; code/unit tests are Dev's, foreground; first build dispatch pre-flights Figma access when design.md mandates `figma-to-compose`; handoff carries `apk:` when device-verifiable) → classify the phase: **no user-visible surface → no device QA** (Dev's green tests close it); **UI phase** → `send qa "VERIFY phase N [SMOKE] …"` (max 6 journeys, only touched categories, reuse `.maestro/**`, install Dev's `apk:` — QA never builds). QA verifies **phases, never chunks**. A Figma-linked phase ends in the **PARITY GATE**: `require` the script-generated sheets (never trust the handoff claim), `bash .harness/parity-review .harness/artifacts/parity` → human approves/comments per screen → all-approve = QA dispatch, any needs-changes = verbatim block to Dev and gate again (see `figma-parity.md`); later phases keep the project's screenshot-tool **verify task** green. Phase done = `dev-handoff.md` **and** (UI phase) a QA-PASS `qa-report.md`. QA FAIL → re-dispatch Dev (fix cap **7**/phase). Depth belongs to the final `[FULL]` regression, never to per-phase passes.
6. **PR → Architect post-code REVIEW.** `[small]` → Dev fixes + final QA once; `[structural]` → Architect replans → Dev → QA re-test. Caps: Architect **3**, global QA↔Architect **3**, then escalate.
7. **DONE** — null `in_flight`, summarise `log.md`, `touch .harness/.stop-watchdog`.

**Small change / bug fix** → skip the two design gates (one Dev pass → QA → light Architect).

## Rules
- Never edit `app/**` / `.maestro/**`; never do a teammate's work — route gate answers via `.harness/answer`, never reconcile/analyse yourself.
- Keep Dev and QA lanes separate — Dev implements, QA verifies; never put render/ST/PASS-FAIL/screenshots in a Dev dispatch.
- `guard.sh` (PreToolUse) hard-blocks force-push / push-to-master / global-adb / `rm -rf /` for every pane.
- Gates render as HTML (`render-questions.sh` / `render-review.sh`). `--auto` skips a gate only when `questions.json` carries clarifications alone (recommended defaults apply); **a blocker always gates to the human**, `--auto` or not. Never the security rails — opt-in, small stories only.
- Push remote + PR base come from `state.json` (`remote`, `base`, pinned at init) — never from memory.
- Accepted-anytime user commands: see `orchestrator-prompts.md`.
