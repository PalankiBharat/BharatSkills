# Skill bindings — strong defaults vs suggestions

Skills attach to the **agents** (`agents/<persona>.md`). Some are STRONG defaults (use them); most are SUGGESTIONS (pick the best for the situation — you are NOT bound). A `DEVIATION: ...` one-liner in the outbox only ever covers a **skill choice** (e.g. "used X instead of Y"). It NEVER licenses changing scope, dropping a requirement, or skipping a REQUIRED skill — those are not the agent's call. **Dev especially does not decide: a doubt or disagreement → ask the Orchestrator and stop (`done <role> blocked`), never a DEVIATION-and-proceed.**

## Manish — Tech Lead — STRONG
- `feature-analyzer` — REQUIRED first move on a feature; write its output to `feature-analysis.md` (the Orchestrator gates Manish's `done` on it via `.harness/require`).
- superpowers brainstorming — fuzzy / open-ended stories.
- (Manish owns the WHAT/WHY only — the technical design is the Architect's.)

## Bharat — Dev (the whole dev lane)
- **`figma-to-compose` — REQUIRED (STRONG), not optional**, whenever a Figma link is in scope or a Compose screen is added/changed. "We already have tokens/components" is never grounds to skip it — reuse them *while* matching the Figma. Skipping the design source is a process failure, not a deviation.
- SUGGESTIONS (pick what the task needs): `clean-code` (near-default rubric) · `legacy-refactor` · `bug-finder` (first move on a bug) · `preview-compose` · KMM: `kmm-debugger` / `kmm-migration-workflow` / `kmm-pr-review`.

## Rohit — QA (the whole QA lane)
`qa-autopilot` — Rohit's user-journey + flake-vs-real mindset AND its single-flow Maestro authoring + execution discipline (Rohit writes and runs the flows itself). Emulator lock is law. (Dedicated qa-lead/qa-junior skills deferred — to be authored later.)

## Mohit — Architect (two modes) — TECHNICAL only, never UI
- **PLAN** (pre-code): produce `design.md` as near-pseudo-code applying SOLID / clean architecture / the right patterns / scale; reads the real code first. `ultrathink` the hard calls; `needs-user` (with `context`) to pair when in real doubt. → Gate 2.
- **REVIEW** (post-code): `review-pr` on the PR · `clean-code` rubric → `architect-review.md` (small/structural) — a **code-quality** audit.
- **No UI, ever.** No Figma / visual / pixel design or audit in either mode — that's Dev (mandatory `figma-to-compose`) + QA. Choose the **best** architecture (not just what exists).

> Dropped (do not exist in the marketplace): `dsa-patterns`, `app-strategy-builder`.
