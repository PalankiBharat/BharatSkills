# Phase H — Parity-QA Hand-off

**Purpose.** Hand the open PR to the `kmm-qa-autopilot` skill for behavioral parity QA, and close the migration session. **This is the final phase.** The migration skill does **not** run parity QA itself — autopilot is a separate, heavy, user-triggered skill that builds master and the PR head as two ProductionRelease APKs, boots two emulators, waits for a manual prod login on each, derives a no-exclusions heatmap from the master-vs-PR diff, runs the same flows on both, and diffs into a per-journey parity verdict. Phase H's job is to set that up cleanly and get out of the way.

**Why QA moved here (post-PR).** `kmm-qa-autopilot` works *off a GitHub PR link* — it needs the PR to exist before it can do anything (it compares master vs the PR head). So the migration skill opens the PR at Phase G, then suggests autopilot here. Parity QA is no longer a gate before the PR; it runs after, on the shipped artifact.

**Inputs:** `pr.md` (PR URL, recorded at G.4), `heatmap.md`, `validation.md` (all complete), `project.md`.

---

## Sub-phases

### H.1 — Confirm hand-off readiness

- PR is open (URL present in `pr.md`). If G.4 only emitted `pr-body.md` for a manual open, prompt the user for the PR URL once it's up.
- `heatmap.md` exists with `TBD` cells (it's the QA checklist; autopilot derives its own heatmap from the PR diff but the embedded checklist in the PR body is the human-facing gate).
- Working tree clean; nothing left uncommitted that should be in the PR.

### H.2 — Present the autopilot invocation (suggestion, NOT auto-launch)

The skill **suggests** running `kmm-qa-autopilot` with the PR link and shows the exact invocation. It does **not** launch it and does **not** wait for results — autopilot is user-triggered (it needs two visible emulators and a manual prod login on each; it's a long run best driven deliberately, often in its own session).

Present, concisely:
- The PR URL.
- The one-line suggestion: *"Parity QA runs via `kmm-qa-autopilot` on this PR — it compares master vs the PR head head-to-head. Run it with the PR link when you're ready."*
- A one-line note that the PR body already carries the heatmap as the pre-merge QA checklist.

No ceremony, no multi-paragraph explainer (per SKILL.md Output economy). The user invokes autopilot themselves.

### H.3 — Write `qa.md` (hand-off record)

Living document, finalized here with status `complete`. Contains:
- PR URL + base branch.
- The autopilot invocation suggested (verbatim, with the PR link).
- Pointer to the embedded heatmap in the PR body (the pre-merge QA gate).
- Hand-off timestamp.
- A one-line statement that parity QA is delegated to `kmm-qa-autopilot` and tracked on the PR, not in this session.

`.kmm/migrations/` is gitignored, so `qa.md` is working-tree-only — no commit (per SKILL.md gitignore-collapse).

### H.4 — Phase H retro

Amend `retro.md` with `## Phase H — Parity-QA Hand-off (captured YYYY-MM-DD)` — five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate). This is the final phase retro.

### H.5 — Session close-out

Run the session-end consolidation step (SKILL.md → Special actions → Session close-out): scan `retro.md` for `[project.md]` / `[both]` bullets, draft additions to the live repo's `project.md`, diff-confirm, write. Not skippable; its writes remain diff-confirmed. After consolidation, the session is complete — offer worktree cleanup per Phase E post-session notes once the PR merges.

---

## Output: `qa.md`

- Header (status, tasks)
- PR URL + base branch
- Suggested `kmm-qa-autopilot` invocation (with PR link)
- Heatmap location (embedded in PR body)
- Hand-off timestamp + delegation statement
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase G complete; PR open with URL recorded.
- Autopilot is **suggested, never auto-launched** from this skill — and the skill does not block waiting on QA results (they live on the PR).
- Phase H retro captured (blocking) and session-end consolidation run before the session is declared complete.
