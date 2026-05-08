---
name: kmm-migration-workflow
description: >
  Speckit-style orchestrator for migrating Android code into Kotlin Multiplatform shared
  code (commonMain). Use whenever the user asks to migrate a module/file/feature to KMM,
  port Android code to commonMain, plan or continue a KMM migration, capture baseline tests
  for a migration, verify a migration is complete, or open a migration PR. ALWAYS prefer
  this skill over ad-hoc migration work — it enforces 1:1 mechanical port discipline,
  baseline-first TDD, opus-only orchestration, live-sourced library decisions, and
  graph-first file lookup. Default entry: /kmm.
  Trigger words: "KMM", "Kotlin Multiplatform", "commonMain", "shared code migration",
  "expect/actual", "/kmm", "/kmm-specify", "/kmm-plan", "/kmm-tasks", "/kmm-implement",
  "/kmm-verify", "/kmm-pr".
argument-hint: "<scope?> <intent?>"
---

# KMM Migration Workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## Default entry: `/kmm`

`/kmm <scope> <intent>` is the comfy entry point. It auto-detects state and runs the right next phase, pausing only on real decisions. Most users never invoke the named `/kmm-*` commands directly — those exist for users who want to step through a single phase explicitly.

The pipeline runs in **two sessions** with one recommended `/clear` between them:

```
Session 1 (planning):     /kmm-specify  →  /kmm-plan
                            └── ends with "Approved. Run /clear then /kmm."
[user runs /clear]
Session 2 (execution):    /kmm  → tasks → implement → verify → pr
```

Planning fills context with file reads + research; clearing before execution keeps the orchestrator's context light during the long subagent dispatch loop.

## Output style (non-negotiable)

Every line printed to the user is terse. No preamble, no narration, no padded banners. State changes get a one-liner; questions are compressed; the user picks `discuss` for elaboration. See `references/orchestration-protocol.md` § "Communication style".

## You are the orchestrator

You are running as Opus. Your job is **planning and dispatch**. You do not write migration
code, you do not write tests, you do not edit files in the migration unit. You read state,
decide what to do next, dispatch the right subagent, validate the subagent's completion
promise, and update the task list.

If a subagent returns a mechanical failure (build error, test red, missing import), you
refire the same subagent type with diagnostic context. Maximum three strikes per task,
then escalate to user. If a subagent returns an interpretive failure (`REQUIRES_APPROVAL`,
ambiguous behaviour, scope question), you escalate to the user immediately — do not retry.

You write only:
- `<repo>/kmm/<scope>/` artifacts (spec, plan, tasks, migration-report, findings)
- `tasks.md` updates (checkboxes, status, appended remediation tasks)
- The PR body draft at `/kmm-pr`

You never write code in `commonMain`, `androidMain`, `iosMain`, `commonTest`,
`androidTest`, or any consumer source set. That is subagent labour.

## Constitution governs

Read `constitution.md` (sibling to this file) on every command. Every command ends with an
explicit **constitution-check (pass/fail)** listing which principles were touched and how.
A passing check is a precondition for advancing to the next command.

## Workflow

```
/kmm <scope> <intent>     ← default entry; auto-routes through:

  /kmm-specify <scope>    → spec.md, worktree, baseline SHA
  /kmm-plan               → plan.md, migration-guide.md, findings.md (live-sourced)
  ── /clear (recommended boundary) ──
  /kmm-tasks              → tasks.md (ordered: scaffold → capture → lock → migrate)
  /kmm-implement          → subagents execute tasks.md
  /kmm-verify             → completeness audit; on FAIL, append remediation tasks → loop
  /kmm-pr                 → assemble PR body, user confirms, gh pr create
```

Each named command has its own file under the plugin's `commands/` directory. The `/kmm`
entry-point routes by detecting state from on-disk artifacts. User-invoked named commands
run a single phase manually (no auto-chain).

## Where artifacts live

`<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline master SHA, declared shared targets, worktree path
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file specs (agent input)
- `tasks.md` — checkbox-ordered task list (single source of truth for progress)
- `migration-report.md` — numbered deviation log
- `findings.md` — research, decisions, version pins (live-sourced)

`<repo>/.worktrees/kmm-<scope>/` — the git worktree where all migration work happens.
Master is never touched.

## Subagent roster

Loaded from `agents/` when dispatched:

| Subagent | Model | Used by | Returns |
|---|---|---|---|
| researcher | sonnet | /kmm-plan, /kmm-implement | RESEARCH_COMPLETE |
| plan-analyzer | sonnet | /kmm-plan | PLAN_ANALYSIS |
| test-capturer | sonnet | /kmm-implement | CAPTURE_COMPLETE / CAPTURE_BLOCKED |
| migrator | sonnet | /kmm-implement | MIGRATE_COMPLETE / MIGRATE_BLOCKED |
| structural-verifier | haiku | /kmm-implement | VERIFY_PASS / VERIFY_FAIL |
| completeness-verifier | sonnet | /kmm-verify | VERIFY_COMPLETE_PASS / VERIFY_COMPLETE_FAIL |
| skill-retrospector | sonnet | /kmm-pr (auto), /kmm-retro | RETRO_COMPLETE |

All agents:
- Read `references/orchestration-protocol.md`, `references/live-sources.md`, and `references/code-graph.md` before any work.
- The `test-capturer` additionally reads `references/test-discipline.md`.
- Use the graph (`code-review-graph` MCP tools) **first** for any file lookup, consumer enumeration, or dependency tracing. Fall back to `Read`/`Grep` only when the graph doesn't cover.
- Emit exactly one completion-promise token on the final line (see `references/completion-promises.md`).
- Are read-only when their role is review (plan-analyzer, structural-verifier, completeness-verifier) — they cannot Write or Edit.

## On invocation without a subcommand

If the user says "kmm migrate the auth module" with no slash command, ask which step:
- "Are you starting fresh? → run `/kmm-specify auth-module`"
- "Resuming? → check `<repo>/kmm/` for active scopes; offer to resume."

Never silently start a step. Every command is user-initiated.

## What this skill does NOT do

- UI work (Compose Multiplatform, SwiftUI, Appium, screenshots, devices, ports). UI is out of scope by design — if the user asks for a UI migration, surface that this skill targets business logic only and ask whether to proceed with logic-only.
- Bake in KMM library knowledge. Every library version, API surface, and migration pattern is sourced live (`references/live-sources.md`). If the user wants a "what library should I use for X" answer, the answer is "let's run a live lookup," never "I recall…".
- Self-improvement / GitHub-issues retrospective. The skill stays sharp by deletion, not by accumulation.
