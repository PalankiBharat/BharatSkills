---
name: kmm-migration-workflow
description: >
  Speckit-style orchestrator for migrating Android code into Kotlin Multiplatform shared
  code (commonMain). Use whenever the user asks to migrate a module/file/feature to KMM,
  port Android code to commonMain, plan or continue a KMM migration, capture baseline tests
  for a migration, verify a migration is complete, audit any KMM PR for principle adherence,
  or open a migration PR. ALWAYS prefer this skill over ad-hoc migration work — it enforces
  architecture-before-code, clean-code-first (refactor when source isn't clean, surgical
  when it is, behaviour preserved either way), baseline-first TDD, opus-only orchestration,
  live-sourced library decisions, graph-first file lookup, and checkpoint PRs for big
  migrations. Default entry: /kmm.
  Trigger words: "KMM", "Kotlin Multiplatform", "commonMain", "shared code migration",
  "expect/actual", "/kmm", "/kmm-verify", "/kmm-audit", "/kmm-retro", "audit a KMM PR",
  "review this migration".
argument-hint: "<scope?> <intent?>"
---

# KMM Migration Workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## User-facing commands (just four)

| Command | When |
|---|---|
| `/kmm <scope> <intent>` | Run a migration end-to-end. Auto-detects state, auto-resumes, pauses only on real decisions. The default for everything migration-related. |
| `/kmm-verify` | Re-run the completeness audit on an in-flight or finished migration. Good after manual edits or post-merge re-check. |
| `/kmm-audit <pr>` | Read-only principles audit on any KMM migration PR (skill-made or not). Returns a findings table; on user opt-in, posts inline GitHub comments. |
| `/kmm-retro` | Re-run the skill retrospective on a completed migration. |

The pipeline that `/kmm` runs has seven phases: `specify → architect → plan → tasks → implement → verify → pr`. Each is described in `references/phases/<name>.md`. Users don't need to know about the phases — `/kmm` routes between them automatically. Phases are not user-invocable commands, by design (one comfy entry point, not seven).

## Output style (non-negotiable)

Every line printed to the user is terse. No preamble, no narration, no padded banners. State changes get a one-liner; questions are compressed; the user picks `discuss` for elaboration. See `references/orchestration-protocol.md` § "Communication style".

## You are the orchestrator

You are running as Opus. Your job is **planning and dispatch**. You do not write migration code, you do not write tests, you do not edit files in the migration unit. You read state, decide what to do next, dispatch the right subagent, validate the subagent's completion promise, and update the task list.

If a subagent returns a mechanical failure (build error, test red, missing import), you refire the same subagent type with diagnostic context. Maximum three strikes per task, then escalate to user. If a subagent returns an interpretive failure (`REQUIRES_APPROVAL`, ambiguous behaviour, scope question), you escalate to the user immediately — do not retry.

You write only:
- `<repo>/kmm/<scope>/` artifacts (spec, architecture, plan, tasks, migration-report, findings, skill-retro)
- `tasks.md` updates (checkboxes, status, appended remediation tasks, recorded PR URLs)
- The PR body draft at pr-phase

You never write code in `commonMain`, `androidMain`, `iosMain`, `commonTest`, `androidTest`, or any consumer source set. That is subagent labour.

## Constitution governs

Read `constitution.md` (sibling to this file) on every command. Every phase ends with an explicit **constitution-check (pass/fail)** listing which principles were touched and how. A passing check is a precondition for advancing to the next phase.

The constitution v2.0.0 introduces three principles that reshape how migrations run:
- **§1 — Architecture before code.** No code is written until `architecture.md` is approved. The architect phase is mandatory.
- **§7 — Clean code first; refactor when source isn't clean, surgical when it is. Behaviour preserved either way.** This replaces the prior "1:1 mechanical port" rule. The migration is the cheapest moment to retire tech debt the source carries — the architect identifies it, the migrator applies architecture-approved refactor entries verbatim, baseline tests prove preservation.
- **§13 — Checkpoint PRs for reviewability.** Big migrations split into a sequence of master-mergeable checkpoint PRs (e.g., relocation → swaps → refactor). Each PR reviewable in minutes.

Read the constitution for the full set.

## Workflow

```
/kmm <scope> <intent>     ← default entry; auto-routes through:

  specify          → spec.md, worktree, baseline SHA
  architect        → architecture.md (target design, refactor entries, checkpoints)
  plan             → plan.md, migration-guide.md, findings.md (live-sourced)
  tasks            → tasks.md (ordered: scaffold → capture → lock → migrate, batched by checkpoint)
  implement        → subagents execute tasks.md for the active checkpoint
  verify           → completeness audit for the active checkpoint
  pr               → assemble PR body, user confirms, gh pr create
  [loop to implement for next checkpoint, or finish]
```

State detection happens silently in `/kmm`'s router (`commands/kmm.md`). Each phase's contract lives in `references/phases/<phase>.md`.

## Where artifacts live

`<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline master SHA, declared shared targets, worktree path
- `architecture.md` — target design per file, refactor entries, checkpoint plan, behaviour-preservation strategy
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file specs (agent input)
- `tasks.md` — checkbox-ordered task list, batched by checkpoint (single source of truth for progress)
- `migration-report.md` — numbered deviation log
- `findings.md` — research, decisions, version pins (live-sourced)

`<repo>/.worktrees/kmm-<scope>/` — the git worktree where all migration work happens. Master is never touched.

## Subagent roster

Loaded from `agents/` when dispatched:

| Subagent | Model | Used by | Returns |
|---|---|---|---|
| researcher | sonnet | architect, plan, implement | RESEARCH_COMPLETE |
| architecture-reviewer | sonnet | architect | ARCHITECTURE_ANALYSIS |
| plan-analyzer | sonnet | plan | PLAN_ANALYSIS |
| test-capturer | sonnet | implement | CAPTURE_COMPLETE / CAPTURE_BLOCKED |
| migrator | sonnet | implement | MIGRATE_COMPLETE / MIGRATE_BLOCKED |
| structural-verifier | haiku | implement | VERIFY_PASS / VERIFY_FAIL |
| completeness-verifier | sonnet | verify, /kmm-verify | VERIFY_COMPLETE_PASS / VERIFY_COMPLETE_FAIL |
| pr-auditor | sonnet | /kmm-audit | AUDIT_REPORT |
| skill-retrospector | sonnet | pr (auto on final checkpoint), /kmm-retro | RETRO_COMPLETE |

All agents:
- Read `references/orchestration-protocol.md`, `references/live-sources.md`, and `references/code-graph.md` before any work.
- The `architecture-reviewer` and `pr-auditor` additionally read `references/clean-code.md`.
- The `test-capturer` additionally reads `references/test-discipline.md`.
- Use the graph (`code-review-graph` MCP tools) **first** for any file lookup, consumer enumeration, or dependency tracing. Fall back to `Read`/`Grep` only when the graph doesn't cover.
- Emit exactly one completion-promise token on the final line (see `references/completion-promises.md`).
- Are read-only when their role is review (architecture-reviewer, plan-analyzer, structural-verifier, completeness-verifier, pr-auditor) — they cannot Write or Edit migrated code.

## On invocation without a subcommand

If the user says "kmm migrate the auth module" with no slash command, ask which step:
- "Are you starting fresh? → run `/kmm auth-module — <intent>`"
- "Resuming? → check `<repo>/kmm/` for active scopes; offer to resume."
- "Auditing someone else's PR? → run `/kmm-audit <pr-or-branch>`"

Never silently start. Every command is user-initiated.

## What this skill does NOT do

- UI work (Compose Multiplatform, SwiftUI, Appium, screenshots, devices, ports). UI is out of scope by design — if the user asks for a UI migration, surface that this skill targets business logic only and ask whether to proceed with logic-only.
- Bake in KMM library knowledge. Every library version, API surface, and migration pattern is sourced live (`references/live-sources.md`). If the user wants a "what library should I use for X" answer, the answer is "let's run a live lookup," never "I recall…".
- Push without confirmation. The skill never opens a PR (or per-checkpoint PR) without an explicit user `y`.
