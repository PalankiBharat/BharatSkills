# Skill bindings — strong defaults vs suggestions

Skills attach to the **agents** (`agents/<persona>.md`). Some are STRONG defaults (use them); most are SUGGESTIONS (pick the best for the situation — you are NOT bound). To skip a strong default, write a one-line `DEVIATION: ...` in the outbox first.

## Manish — Tech Lead — STRONG
- `feature-analyzer` — REQUIRED first move on a feature; write its output to `feature-analysis.md` (the Orchestrator gates Manish's `done` on it via `.harness/require`).
- superpowers brainstorming — fuzzy / open-ended stories.
- (Manish owns the WHAT/WHY only — the technical design is the Architect's.)

## Mohit-Dev + Bharat-Dev — Dev — SUGGESTIONS (not every time)
`clean-code` (the near-default rubric) · `figma-to-compose` (Figma→Compose) · `legacy-refactor` · `bug-finder` (first move on a bug) · `preview-compose` · KMM: `kmm-debugger` / `kmm-migration-workflow` / `kmm-pr-review`. Use what the task needs.

## Rohit + Bharat-QA — QA
`qa-autopilot` — Rohit uses its QA mindset + flake-vs-real judgement; Bharat-QA uses its single-flow Maestro authoring + execution discipline. Emulator lock is law. (Dedicated qa-lead/qa-junior skills deferred — to be authored later.)

## Mohit-Arch — Architect (two modes)
- **PLAN** (pre-code): produce `design.md` as near-pseudo-code applying SOLID / clean architecture / the right patterns / scale; reads the real code first. `ultrathink` the hard calls; `needs-user` (with `context`) to pair when in real doubt. → Gate 2.
- **REVIEW** (post-code): `review-pr` on the PR · `clean-code` rubric → `architect-review.md` (small/structural).
Choose the **best** architecture (not just what exists).

> Dropped (do not exist in the marketplace): `dsa-patterns`, `app-strategy-builder`.
