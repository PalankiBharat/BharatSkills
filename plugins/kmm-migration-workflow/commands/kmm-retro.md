---
description: Run the skill retrospective on a migration. Opt-in (not auto-dispatched at end of pr-phase). Useful after manual edits, or for a final pass before opening a follow-up issue on the skill repo.
argument-hint: "<scope-name?>"
---

# /kmm-retro

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

`/kmm-retro` runs the skill retrospective. **Opt-in** — pr-phase no longer auto-dispatches the retrospector at end of every migration (that was a cure-shaped capture pattern; the skill now improves only when the user asks).

## Inputs

- `<scope-name>` — optional. If omitted and `<repo>/kmm/` has exactly one scope, use that. If multiple, ask which.

## Steps

1. Confirm artifacts exist: `<repo>/kmm/<scope>/spec.md` and `migration-report.md` are required.
2. Dispatch `skill-retrospector` (read-only, sonnet) with the artifact paths.
3. Write the result to `<repo>/kmm/<scope>/skill-retro.md` (overwriting any prior).
4. Print the markdown block to chat for copy-paste.
5. Tell the user: "Retrospective written. Copy into an issue on the skill repo or apply directly to skill files."

## Constitution check

Touched: §12 (retrospective is itself a document recording skill-level signals).

Checklist:
- `[ ]` Artifacts present
- `[ ]` Subagent returned `RETRO_COMPLETE`
- `[ ]` `skill-retro.md` written

## What you MUST NOT do

- Do not modify skill files. Retrospective is advisory.
- Do not auto-create GitHub issues.
- Do not enrich findings beyond what the retrospector emits.
