# kmm-migration-workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## Philosophy

- **Architecture before code.** No code is written until `architecture.md` exists on disk and `architecture-reviewer` has gated it. Prevention beats cure.
- **Clean code first; refactor when the source isn't clean, surgical when it is. Behaviour preserved either way.** The migration is the cheapest moment to retire tech debt the source carries.
- **Document-first.** Every decision lives on disk in `<repo>/kmm/<scope>/`. Conversations are not the source of truth.
- **Baseline-first.** All in-scope files get exhaustive characterization tests in `commonTest` before any code moves. The baseline is locked at a master SHA and is immutable.
- **Checkpoint PRs.** Big migrations split into master-mergeable checkpoints (relocation → swaps → refactors). Each PR reviewable in minutes.
- **Opus orchestrates only.** Planning and dispatch in the orchestrator. All labour by sonnet/haiku subagents.
- **Live sources only.** No KMM library knowledge baked in. Every version and API is fetched live.
- **No UI, no Appium, no devices.** Business-logic migration only.

## Commands

| Command | Purpose |
|---|---|
| `/kmm <scope> <intent>` | Run a migration end-to-end. Auto-detects state, auto-resumes. |
| `/kmm-verify` | Re-run completeness audit on a migration directory. |
| `/kmm-audit <pr>` | Read-only principles audit of any KMM migration PR. |
| `/kmm-retro` | Run the skill retrospective on a migration (opt-in). |

The seven phases (`specify → architect → plan → tasks → implement → verify → pr`) are described in `skills/kmm-migration-workflow/references/phases/`. They're not user-invocable.

## Per-migration artifacts

Created in `<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline SHA, declared shared targets
- `architecture.md` — target design per file, refactor entries, checkpoint plan
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file specs the agents consume
- `tasks.md` — ordered checkbox list batched by checkpoint
- `migration-report.md` — numbered deviations with status, root cause, closure
- `findings.md` — research, decisions, version pins (live-sourced)

## Constitution

`skills/kmm-migration-workflow/constitution.md` (v3.1.0). Every phase ends with a constitution-check (pass/fail). The constitution governs **only** migration work; on non-migration work, normal conventions resume.

Highlights:
- §1 Architecture before code
- §6 Refactor stays inside scope
- §7 Clean-code-first decision tree
- §13 Checkpoint PRs
- §14 Proportionality (trivial-migration fast-path)
- §15 Plain language
- Verification §8 Mandatory smoke test (DI-boot + happy-path call) per checkpoint

## Install

Ships as a Claude Code marketplace plugin. Enable via the plugin marketplace; the four commands appear in your slash-command list.

## Changelog

See `CHANGELOG.md` in the plugin root.
