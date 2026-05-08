---
description: Re-run the skill retrospective on a completed (or in-flight) migration. Useful after manually updating skill files mid-flight, or for a final pass before opening a follow-up issue.
argument-hint: "<scope-name?>"
---

# /kmm-retro

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

`/kmm-retro` is the standalone version of the retrospective that `/kmm-pr` runs automatically. Use it when:

- The user updated skill files manually after `/kmm-pr` and wants a fresh retrospective.
- A migration was completed in step mode (no `/kmm-pr` auto-trigger fired).
- The user wants to re-read the retrospective after time has passed.

## Inputs

- `<scope-name>` — optional. If omitted and `<repo>/kmm/` has exactly one scope, use that scope. If multiple scopes, ask which (one question, options).

## What you do

1. Confirm the scope's artifacts exist: `<repo>/kmm/<scope>/spec.md` and `migration-report.md` are required.
2. Dispatch `skill-retrospector` (read-only, sonnet) with the artifact paths.
3. Write the result to `<repo>/kmm/<scope>/skill-retro.md` (overwriting any prior file).
4. Print the markdown block to chat for copy-paste.
5. Tell the user: "Retrospective written. Copy into an issue on the skill repo or apply directly to skill files."

## Constitution check

- Touched: §11 (documents are the contract — retrospective is itself a document recording skill-level deviations).
- Pass/fail:
  - `[ ]` Artifacts present
  - `[ ]` Subagent returned `RETRO_COMPLETE` with valid self-check
  - `[ ]` `skill-retro.md` written
- On fail: STOP, report which check failed.

## What you do NOT do

- Do not modify skill files. The retrospective is advisory; the user decides what to do with it.
- Do not auto-create GitHub issues. The user does that manually if they want.
- Do not enrich findings beyond what the retrospector subagent emits — its output is the canonical artifact.
