# kmm-migration-workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## Philosophy

- **Architecture before code.** No code is written — not a `git mv`, not a swap — until a target architecture exists on disk and an architecture-reviewer subagent has gated it. Prevention beats cure: design-time decisions are an order of magnitude cheaper than fixing bad shape after the migrator has applied it.
- **Clean code first; refactor when the source isn't clean, surgical when it is. Behaviour preserved either way.** The migration is the cheapest moment to retire tech debt the source carries — the unit is being rewritten, baseline tests cover its behaviour, consumers will compile against the result regardless. Carrying badness forward "to keep the diff small" is the failure mode this skill exists to prevent.
- **Document-first.** Every decision lives on disk in `<repo>/kmm/<scope>/`. Conversations are not the source of truth; the artifacts are.
- **Baseline-first.** All in-scope files get exhaustive characterization tests in `commonTest` before any code moves. The baseline is locked at a master SHA and is immutable for the duration of the migration. Refactor invariants are pinned by tests in this baseline.
- **Checkpoint PRs for reviewability.** Big migrations split into a sequence of master-mergeable checkpoint PRs (e.g., relocation → library swaps → architecture-approved refactors). Each PR reviewable in minutes; rubber-stamping is where tech debt enters shared code.
- **Opus orchestrates only.** Planning and dispatch happen in the orchestrator. All labour — capture, migrate, verify — is done by sonnet/haiku subagents.
- **Live sources only.** No KMM library knowledge baked in. Every framework version, library API, and configuration option is fetched live (Context7 → official vendor docs → web search) at the moment it is invoked.
- **No UI, no Appium, no devices.** This skill orchestrates business-logic migration. UI work is out of scope by design.

## Commands

There are only **four** user-invocable commands. The migration pipeline is one command (`/kmm`), not seven.

| Command | Purpose |
|---|---|
| `/kmm <scope> <intent>` | Run a migration end-to-end. Auto-detects state, auto-resumes between phases (specify → architect → plan → tasks → implement → verify → pr), pauses only on real decisions. The default entry for everything migration-related. |
| `/kmm-verify` | Re-run the completeness audit on an in-flight or finished migration directory. Useful after manual mid-flight edits or post-merge re-checks. |
| `/kmm-audit <pr>` | Read-only principles audit of any KMM migration PR — whether or not it was made with this skill. Walks the diff line-by-line against the constitution + clean-code reference + KMM-specific principles. Returns a findings table; on user opt-in, posts inline GitHub comments. Distinct from verify (which is a completeness check on skill-made migrations). |
| `/kmm-retro` | Re-run the skill retrospective on a completed (or in-flight) migration. |

The seven phases the `/kmm` pipeline runs through are described in `skills/kmm-migration-workflow/references/phases/`. They're not user-invocable — `/kmm` routes between them. This is intentional: one comfy entry, not seven.

## Per-migration artifacts

Created in `<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline SHA, declared shared targets
- `architecture.md` — target design per file, refactor entries, checkpoint plan, behaviour-preservation strategy
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file specs the agents consume
- `tasks.md` — ordered checkbox list batched by checkpoint, single source of truth for progress
- `migration-report.md` — numbered deviations with status, root cause, closure path
- `findings.md` — research, decisions, version pins (live-sourced)

## Constitution

The skill ships a constitution at `skills/kmm-migration-workflow/constitution.md` (v2.0.0). Every phase ends with an explicit constitution-check (pass/fail). The constitution governs **only** work whose stated goal is migrating to KMM; on non-migration work, normal conventions resume.

Highlights of v2.0.0:
- §1 Architecture before code (architect phase is mandatory)
- §6 Refactor stays inside scope, never expands it
- §7 Clean-code-first decision tree (replaces the prior "1:1 mechanical port" rule)
- §13 Checkpoint PRs for reviewability

## Install

This skill ships as a Claude Code marketplace plugin. Enable it via the plugin marketplace and the four commands appear in your slash-command list.

## Status

v0.2 — adds architect phase, clean-code-first refactor support, checkpoint-PR splitting, and read-only PR audit mode. The user-facing command surface is intentionally small (four commands).
