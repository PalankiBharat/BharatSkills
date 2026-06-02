# Phase I — Parity-QA + Bug-fixing

**Purpose.** Hand the open PR to the `kmm-qa-autopilot` skill for behavioral parity QA, **and fix any bug it surfaces through the workflow** — then close the migration session. **This is the final phase.** The migration skill does **not** run parity QA itself — autopilot is a separate, heavy, user-triggered skill that builds master and the PR head as two ProductionRelease APKs, boots two emulators, waits for a manual prod login on each, derives a no-exclusions heatmap from the master-vs-PR diff, runs the same flows on both, and diffs into a per-journey parity verdict. Phase I sets that up cleanly, gets out of the way, and **stays open to fix QA findings the right way** — never live-patched.

**Why QA moved here (post-PR).** `kmm-qa-autopilot` works *off a GitHub PR link* — it needs the PR to exist before it can do anything. So the migration skill opens the PR at Phase G, resolves code review at Phase H, then hands off to autopilot here. Parity QA is no longer a gate before the PR; it runs after, on the shipped artifact.

**Why bug-fixing is in-phase (not "just hand off").** Changes made after the migration looked "complete" once shipped untested and undocumented — exactly the failure §Late-change discipline exists to prevent. So a QA bug (or any late change that arrives while this skill is active) is fixed with the migration's own discipline: **failing test first**, fix, green, migration-exception if behavior shifts, proper commit, retro entry. Phase I does not close on an open, unresolved QA bug.

**Inputs:** `pr.md` (PR URL, recorded at G.4), `review.md` (Phase H), `heatmap.md`, `validation.md`, `plan.md`, `coverage.md`, `project.md`.

---

## Sub-phases

### I.1 — Confirm hand-off readiness

- **Reuse the PR URL recorded in `pr.md`** (from G.4) directly — do **not** re-query `gh pr view --json` (a jq-quoting flake cost a needless detour in a prior session). If G.4 only emitted `pr-body.md` for a manual open, prompt the user for the PR URL once it's up.
- `heatmap.md` exists with `TBD` cells (it's the QA checklist; autopilot derives its own heatmap from the PR diff, but the embedded checklist in the PR body is the human-facing gate).
- Working tree clean; nothing left uncommitted that should be in the PR (including any Phase H review fixes).

### I.2 — Present the autopilot invocation (suggestion, NOT auto-launch)

The skill **suggests** running `kmm-qa-autopilot` with the PR link and shows the exact invocation. It does **not** launch it and does **not** block — autopilot is user-triggered (it needs two visible emulators and a manual prod login on each; it's a long run best driven deliberately, often in its own session).

Present, concisely (per SKILL.md Output economy — no multi-paragraph explainer):
- The PR URL.
- The one-line suggestion: *"Parity QA runs via `kmm-qa-autopilot` on this PR — it compares master vs the PR head head-to-head. Run it with the PR link when you're ready."*
- A one-line note that the PR body already carries the heatmap as the pre-merge QA checklist.

### I.3 — Bug-fixing loop (per QA bug or late change — through the workflow)

When parity QA reports a bug — or any late change arrives while the skill is active — resolve it with the migration's discipline, **never a live patch** (per SKILL.md §Late-change discipline):

1. **Reproduce + write the failing test first.** A QA-found behavioral divergence gets a baseline-style test (KMM-portable stack) that goes **red** on the current code, proving the bug. No fix before the red test.
2. **Fix via the workflow.** Surgical edits only, each via a **dispatched subagent** (never the orchestrator). Make the red test green.
3. **Migration-exception if observable behavior shifts**, or if the fix edits a frozen / `migrated` / `promoted` baseline: the orchestrator **creates/confirms the `.kmm/exceptions/` file BEFORE dispatching the edit** (the `frozen_baseline_guard` hook doesn't fire on subagent calls — per SKILL.md Migration-exception process). Commit carries `[migration-exception <id>]`.
4. **Re-validate** at the Phase F.6 mechanical scope (surgical → F.3 + F.5 smoke; non-surgical → full F.1 re-run). Announce the scope + one-line justification.
5. **Commit** (two-commit cadence), **push**, and **update** `coverage.md` / the PR body's heatmap row + out-of-scope follow-ups as needed.
6. **Log** the bug + its resolution in `qa.md` (repro, failing test, fix, exception ref, commit SHA).

If the bug means a file should not have been shared, the Phase D plan-flip path (`migrate` → `hold`, D.3) is still available with user approval. If the right process isn't obvious, surface to the user — don't improvise around a gate.

**Phase I stays open until QA is resolved** — either all surfaced bugs are fixed-through-the-workflow, or the user explicitly accepts/defers a finding (recorded as a follow-up). It does not close on an open bug.

### I.4 — Write `qa.md` (hand-off + bug-fixing record)

Living document, finalized here with status `complete`. Contains:
- PR URL + base branch.
- The autopilot invocation suggested (verbatim, with the PR link).
- Pointer to the embedded heatmap in the PR body (the pre-merge QA gate).
- **Bug-fixing log** — per QA bug: repro, failing-test-first evidence, fix, migration-exception ref (if any), re-validation scope, commit SHA. (Empty if QA found nothing.)
- Hand-off timestamp + a one-line statement that parity QA is tracked on the PR.

`.kmm/migrations/` is gitignored, so `qa.md` is working-tree-only — no audit commit (per SKILL.md gitignore-collapse). Bug-fix code commits normally.

### I.5 — Phase I retro

Amend `retro.md` with `## Phase I — Parity-QA + Bug-fixing (captured YYYY-MM-DD)` — five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate). This is the final phase retro. Because review (Phase H) and QA bugs now flow through the workflow, their friction lands in the retro too — the skill keeps learning from what review and QA caught.

### I.6 — Session close-out

Run the session-end consolidation step (SKILL.md → Special actions → Session close-out). This is a **safety-net sweep** — pure per-repo facts were written to `project.md` **inline at discovery** throughout the session, so most `[project.md]` values are already in place. The sweep diffs `retro.md`'s `[project.md]`/`[both]` bullets against current `project.md` and diff-confirms only what wasn't already captured (usually nothing). Not skippable; writes remain diff-confirmed. After consolidation, the session is complete — offer worktree cleanup per Phase E post-session notes once the PR merges.

---

## Output: `qa.md`

- Header (status, tasks)
- PR URL + base branch
- Suggested `kmm-qa-autopilot` invocation (with PR link)
- Heatmap location (embedded in PR body)
- Bug-fixing log (per QA bug: repro, failing test, fix, exception ref, re-validation, commit SHA)
- Hand-off timestamp + delegation statement
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase H complete (code review received + blockers resolved through the workflow; user approved).
- PR open with URL recorded; working tree clean at hand-off.
- Autopilot is **suggested, never auto-launched** from this skill — and the skill does not block waiting on QA results (they live on the PR).
- **Every QA bug fixed through the workflow** — failing-test-first, exception if behavior shifts, all edits via subagents, committed and re-validated. No live patches. Phase I does not close on an open, unresolved bug (unless the user explicitly defers it as a recorded follow-up).
- Phase I retro captured (blocking) and session-end consolidation run before the session is declared complete.
