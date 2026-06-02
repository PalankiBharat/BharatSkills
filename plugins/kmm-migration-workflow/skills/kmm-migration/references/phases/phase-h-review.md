# Phase H — Receive & Resolve Review

**Purpose.** Ingest the external code-review feedback on the open PR and resolve every blocker **through the workflow** — never live-patched. You (the user) get the PR reviewed by whoever/whatever you use (teammates on GitHub, another review tool); this phase brings that feedback back into the skill, triages it, fixes blockers with the same discipline as the migration itself (test + exception + commit + retro), and gates on your approval before handing off to parity QA (Phase I).

**The skill does NOT perform the review.** It receives review output. Phase H is the structured **intake** for review feedback — the mirror of Phase I's intake for QA bugs. Both exist so that changes arriving *after* the migration looks finished still get test coverage, documentation, and a retro entry instead of an undocumented live patch (per SKILL.md §Late-change discipline).

**Inputs:** `pr.md` (PR URL, recorded at G.4), `validation.md`, `plan.md` (risk register + decisions), `coverage.md`, `project.md`, plus the review feedback the user provides (pasted, or fetched from the PR).

---

## Sub-phases

### H.1 — Confirm readiness + ingest review feedback

- PR is open (URL present in `pr.md`; reuse it directly — don't re-query `gh`). If G.4 only emitted `pr-body.md` for a manual open, prompt once for the PR URL.
- **Ingest the review.** The user pastes the feedback, or points at the PR — then a **subagent fetches the review comments** (`gh pr view <url> --comments` / the review API) and returns a structured list, never the raw thread into main context (per SKILL.md Subagent-mediated exploration). If there's no review yet, Phase H waits — it does not invent findings.

### H.2 — Triage findings (Sonnet subagent → orchestrator synthesis)

Classify each review finding into exactly one bucket, in plain language (per SKILL.md Decision routing):

- **Blocker** — correctness/behavior/safety issue, or a change the reviewer requires before merge. Must be resolved this phase.
- **Non-blocker (nit)** — style/naming/readability preference with no behavioral impact. Resolve now only if cheap and the user wants it; otherwise log to the PR's out-of-scope follow-ups.
- **Out-of-scope** — a real point, but about code this migration didn't touch (pre-existing). Log to `pr.md` "Out-of-scope follow-ups"; not done here.

Present the triaged table to the user with the skill's recommended disposition per finding. **Batch the dispositions into one turn** (per SKILL.md Decision routing — don't serialize one finding per turn).

### H.3 — Resolve blockers through the workflow (NON-NEGOTIABLE — no live-patching)

For each blocker, route by what it actually is — never an ad-hoc edit:

- **A code change.** Follow the migration's own discipline: if it's behavioral, **write the failing test first** (proving the gap the reviewer caught), then fix, then green. Surgical edits only — never read-and-rewrite. Every edit lands via a **dispatched subagent**, never the orchestrator (per SKILL.md Smart subagent routing).
- **Touches a frozen / `migrated` / `promoted` baseline, or shifts observable behavior.** This is the migration-exception path: the orchestrator **creates/confirms the `.kmm/exceptions/` file authorizing the baseline edit BEFORE dispatching the subagent** (the `frozen_baseline_guard` hook does not fire on subagent tool calls — per SKILL.md Migration-exception process). Commit message carries `[migration-exception <id>]`.
- **Re-validate proportional to the fix** — reuse Phase F.6's mechanical re-validation scope: a surgical fix (≤5 LOC, single file, no new identifiers) re-runs F.3 + F.5 smoke; a non-surgical fix returns to F.1 and re-validates fully. Announce the scope chosen with a one-line justification.
- **Commit** per the two-commit cadence; **log** each finding's resolution (what changed, test added, exception if any, commit SHA) in `review.md`.

No fix-looping through variants until something sticks; no "while we're here" changes; nothing undocumented. If the right process for a finding isn't obvious, surface to the user (per §When in doubt) — don't improvise around a gate.

### H.4 — User-approval gate

- Present the resolution summary: blockers resolved (with test/exception evidence), nits done vs deferred, out-of-scope items logged.
- **The user approves proceeding to Phase I**, or sends another review round (loop back to H.1 with the new feedback). Non-blockers the user declines are recorded as follow-ups, not silently dropped.
- If H.3 changed code that ships in the PR, the PR body's "Out-of-scope follow-ups" / risk sections are updated (Sonnet subagent) and the new commits pushed.

### H.5 — Phase H retro

Amend `retro.md` with `## Phase H — Receive & Resolve Review (captured YYYY-MM-DD)` — five-bullet structure per SKILL.md. **Blocking, non-skippable** (per SKILL.md Retro gate). This is what lets the skill learn from review findings — capture which classes of issue the reviewer caught that the workflow didn't.

---

## Output: `review.md`

Living document, finalized here with status `complete`. Contains:

- Header (status, tasks)
- PR URL + the review source (who/what reviewed)
- Triaged findings table (finding → bucket → disposition)
- Per-blocker resolution log (change, failing-test-first evidence, migration-exception ref if any, re-validation scope, commit SHA)
- Nits done vs deferred; out-of-scope items logged to `pr.md`
- User approval to proceed to Phase I
- Decisions log

`.kmm/migrations/` is gitignored, so `review.md` is working-tree-only — no audit commit (per SKILL.md gitignore-collapse). Code fixes commit normally.

---

## Phase-specific gates

Beyond universals:

- Phase G complete; PR open with URL recorded.
- **Every blocker resolved through the workflow** — behavioral fixes have a failing-test-first proof, baseline/behavior edits have a migration-exception, all edits via subagents, all committed. No live patches.
- Re-validation run at the Phase F.6 scope appropriate to each fix's surface area.
- **User approval recorded** before proceeding to Phase I. Another review round loops back to H.1; the phase doesn't close on an unresolved blocker.
- Phase H retro captured (blocking).
