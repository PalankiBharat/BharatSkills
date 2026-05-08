# kmm-migration-workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## Philosophy

- **Document-first.** Every decision lives on disk in `<repo>/kmm/<scope>/`. Conversations are not the source of truth; the artifacts are. `/clear` is survivable.
- **Baseline-first.** All in-scope files get exhaustive characterization tests in `commonTest` before any code moves. The baseline is locked at a master SHA and is immutable for the duration of the migration.
- **1:1 mechanical port.** Only Android → KMM specifics change. Zero refactors, zero "while I'm here", zero signature changes, zero scope expansion.
- **Opus orchestrates only.** Planning and dispatch happen in the orchestrator. All labour — capture, migrate, verify — is done by sonnet/haiku subagents. If a subagent fails, the orchestrator refires the same subagent type with diagnostic context — it does not pick up the labour itself.
- **Live sources only.** No KMM library knowledge baked in. Every framework version, library API, and configuration option is fetched live (Context7 → official vendor docs → web search) at the moment it is invoked.
- **No UI, no Appium, no devices.** This skill orchestrates business-logic migration. UI work is out of scope by design.

## Commands

| Command | Purpose |
|---|---|
| `/kmm-specify <scope>` | Declare in-scope and out-of-scope files. Create worktree from base branch. Record baseline master SHA. Detect and propose `@Ignore` patches for master tests already failing outside scope. |
| `/kmm-plan` | Opus deep-plans every in-scope file with `file:line` citations. Per-file migration-guide entries. Plan-analyzer subagent gates approval. |
| `/kmm-tasks` | Generate ordered task list: scaffold tasks (any required `commonMain` interfaces) → capture-test tasks (parallel across files) → baseline-lock task → migration tasks (DAG-ordered). |
| `/kmm-implement` | Run the task list. Opus dispatches subagents only — never writes labour code. Mechanical failures refire (max 3); interpretive failures escalate to user. |
| `/kmm-verify` | Completeness audit: plan-vs-reality diff, build clean across declared targets, all baseline tests still green, constitution-compliance scan, deviation log consistency. On `VERIFY_FAIL` the report is appended to `tasks.md` as new remediation tasks; user re-runs `/kmm-implement` then `/kmm-verify` until clean. |
| `/kmm-pr` | Assemble PR body from the artifacts. Show user. On confirm, run `gh pr create`. |

## Per-migration artifacts

Created in `<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline SHA, declared shared targets
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file specs the agents consume
- `tasks.md` — ordered checkbox list, single source of truth for progress
- `migration-report.md` — numbered deviations with status, root cause, closure path
- `findings.md` — research, decisions, version pins (live-sourced)

## Constitution

The skill ships a baked-in constitution at `skills/kmm-migration-workflow/constitution.md`. Every command ends with an explicit constitution-check (pass/fail). The constitution governs **only** work whose stated goal is migrating to KMM; on non-migration work, normal conventions resume.

## Install

Drop this directory into one of your plugin paths and enable the plugin, or copy `skills/kmm-migration-workflow/` into `~/.claude/skills/` for personal use.

## Status

v0.1 — initial release. Lean by design; principles and fields will grow only when usage demands it.
