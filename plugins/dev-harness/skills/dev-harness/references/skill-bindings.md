# Skill bindings — strong defaults vs suggestions

Skills attach to the **agents** (`agents/<persona>.md`). Some are STRONG defaults (use them); most are SUGGESTIONS (pick the best for the situation — you are NOT bound). To skip a strong default, write a one-line `DEVIATION: ...` in the outbox first.

## Manish — Tech Lead — STRONG
- `feature-analyzer` — first move on any real story.
- superpowers brainstorming — fuzzy / open-ended stories.

## Mohit-Dev + Bharat-Dev — Dev — SUGGESTIONS (not every time)
`clean-code` (the near-default rubric) · `figma-to-compose` (Figma→Compose) · `legacy-refactor` · `bug-finder` (first move on a bug) · `preview-compose` · KMM: `kmm-debugger` / `kmm-migration-workflow` / `kmm-pr-review`. Use what the task needs.

## Rohit + Bharat-QA — QA
`qa-autopilot` — Rohit uses its QA mindset + flake-vs-real judgement; Bharat-QA uses its single-flow Maestro authoring + execution discipline. Emulator lock is law. (Dedicated qa-lead/qa-junior skills deferred — to be authored later.)

## Mohit-Arch — Architect
`review-pr` (on the PR) · `clean-code` (rubric) · `ultrathink` for hard calls. Choose the **best** architecture (not just what exists); set status `needs-user` to pair with the user when in real doubt.

> Dropped (do not exist in the marketplace): `dsa-patterns`, `app-strategy-builder`.
