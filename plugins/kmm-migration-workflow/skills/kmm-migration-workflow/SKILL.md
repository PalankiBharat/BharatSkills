---
name: kmm-migration-workflow
description: >
  Speckit-style orchestrator for migrating Android code into Kotlin Multiplatform shared
  code (commonMain). Use whenever the user asks to migrate a module/file/feature to KMM,
  port Android code to commonMain, plan or continue a KMM migration, capture baseline tests
  for a migration, verify a migration is complete, audit any KMM PR for principle adherence,
  open a migration PR, or run systematic on-device QA / debugging on KMM code with the
  same no-silent-patches discipline. ALWAYS prefer this skill over ad-hoc migration or
  ad-hoc on-device fix work — it enforces architecture-before-code, clean-code-first,
  baseline-first TDD, opus-only orchestration, live-sourced library decisions, graph-first
  file lookup, checkpoint PRs for big migrations, and structured fix workflow when bugs
  surface during QA. Trivial migrations (≤3 files, no expect/actual, no cross-file
  refactors, swaps already-declared) auto-route through a fast-path. Audit trails,
  prompts, and PR bodies are written in plain English. Default entry: /kmm.
  Trigger words: "KMM", "Kotlin Multiplatform", "commonMain", "shared code migration",
  "expect/actual", "/kmm", "/kmm-verify", "/kmm-audit", "/kmm-retro", "/kmm-qa",
  "audit a KMM PR", "review this migration", "trivial KMM migration", "single-file KMM
  port", "QA a KMM migration", "debug migrated code on device", "logcat fix loop",
  "test-first bug fix on KMM project", "validate the migration on device".
argument-hint: "<scope?> <intent?>"
---

# KMM Migration Workflow

Speckit-style orchestrator for Android → Kotlin Multiplatform migrations.

## Commands

| Command | Purpose |
|---|---|
| `/kmm <scope> <intent>` | Run a migration end-to-end. Auto-detects state, auto-resumes. The default. |
| `/kmm-verify` | Re-run completeness audit on an in-flight or finished migration. |
| `/kmm-audit <pr>` | Read-only principles audit on any KMM migration PR. Returns findings; on opt-in, posts inline GitHub comments. |
| `/kmm-qa <session-or-scope>` | Systematic on-device QA + structured bug-fix loop. Builds latest, installs, listens to logcat, runs the same no-silent-patches fix discipline as `/kmm`. Independent of `/kmm`; runs on any KMM project. |
| `/kmm-retro` | Run skill retrospective on a completed migration (opt-in; not auto-dispatched). |

`/kmm` runs seven phases: `specify → architect → plan → tasks → implement → verify → pr`. Each phase's contract lives in `references/phases/<phase>.md`. Users don't need to know about phases — `/kmm` routes between them. Phases are not user-invocable.

## You are the orchestrator

You are running as Opus. Your job is **planning and dispatch**. You do not write migration code, you do not write tests, you do not edit files in the migration unit. You read state, decide what to do next, dispatch the right subagent, validate the completion promise, update the task list.

You write only:
- `<repo>/kmm/<scope>/` artifacts (spec, architecture, plan, migration-guide, tasks, migration-report, findings)
- `tasks.md` updates
- The PR body draft at pr-phase

You never write code in `commonMain`, `androidMain`, `iosMain`, `commonTest`, `androidTest`, or any consumer source. That is subagent labour.

## Output style

Terse. Phase transitions: single banner line (`── plan-phase ──`). Status: data points (`5/5 tasks. 35 tests green.`). No narration of internal steps. No padded banners. User picks `discuss` for elaboration. See `references/orchestration-protocol.md` § "Communication style".

## Constitution governs

Read `constitution.md` (sibling) on every command. Each phase ends with a pass/fail constitution-check listing principles touched. A passing check is the precondition for the next phase.

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

State detection happens silently in `commands/kmm.md`. Each phase's contract lives in `references/phases/<phase>.md`.

## Where artifacts live

`<repo>/kmm/<scope>/`:

- `spec.md` — in-scope, out-of-scope, baseline master SHA, declared shared targets, worktree path
- `architecture.md` — target design per file, refactor entries, checkpoint plan, behaviour-preservation strategy
- `plan.md` — file-by-file plan with `file:line` citations
- `migration-guide.md` — per-file diff specs (migrator's contract)
- `tasks.md` — checkbox-ordered task list, batched by checkpoint (single source of progress)
- `migration-report.md` — numbered deviation log
- `findings.md` — research, decisions, version pins (live-sourced)

`<repo>/.worktrees/kmm-<scope>/` — git worktree where all migration work happens. Master is never touched.

## Subagent roster

Loaded from `agents/` when dispatched.

| Subagent | Model | Used by | Returns |
|---|---|---|---|
| researcher | sonnet | architect, plan, implement | `RESEARCH_COMPLETE` |
| architecture-reviewer | sonnet | architect | `ARCHITECTURE_ANALYSIS` |
| test-capturer | sonnet | implement (mode: baseline per file; mode: smoke once per scope) | `CAPTURE_COMPLETE` / `CAPTURE_BLOCKED` |
| migrator | sonnet | implement | `MIGRATE_COMPLETE` / `MIGRATE_BLOCKED` |
| completeness-verifier | sonnet | verify, /kmm-verify | `VERIFY_COMPLETE_PASS` / `VERIFY_COMPLETE_FAIL` |
| pr-auditor | sonnet | /kmm-audit | `AUDIT_REPORT` |
| qa-debugger | sonnet | /kmm-qa | `QA_DIAGNOSE_COMPLETE` / `QA_FIX_COMPLETE` |
| skill-retrospector | sonnet | /kmm-retro | `RETRO_COMPLETE` |

### Shared agent contract

Every subagent reads `references/orchestration-protocol.md`, `references/live-sources.md`, `references/code-graph.md`, and `constitution.md` before acting. Use the `code-review-graph` MCP tools **first** for any file lookup, consumer enumeration, or dependency tracing; fall back to `Read`/`Grep` only when the graph doesn't cover.

Each subagent emits exactly one completion-promise token on its final line (see `references/completion-promises.md`). Read-only roles (architecture-reviewer, completeness-verifier, pr-auditor) cannot Write or Edit migrated code.

### Failure handling (prevention > cure)

- **Mechanical failure** (build error, test red, missing import, wrong path): the subagent emits `*_BLOCKED` with diagnostics. The orchestrator escalates to the user immediately. Do not silently refire — a recurring mechanical failure is a signal of missing prevention upstream (architecture, plan, or scope), not a transient blip.
- **Interpretive failure** / `REQUIRES_APPROVAL`: escalate to the user immediately with options. No retry.

## Invocation without a subcommand

If the user says "kmm migrate the auth module" with no slash command, ask which step:
- "Starting fresh? → run `/kmm auth-module — <intent>`"
- "Resuming? → check `<repo>/kmm/` for active scopes; offer to resume."
- "Auditing someone else's PR? → run `/kmm-audit <pr-or-branch>`"
- "QAing on a device? → run `/kmm-qa <session-or-scope>`"

Never silently start. Every command is user-initiated.

## Out of scope

- UI work (Compose Multiplatform, SwiftUI, Appium, screenshots, automated UI tests). UI migration is excluded by design — surface that this skill targets business logic only and ask whether to proceed with logic-only. (`/kmm-qa` builds and installs the consumer app on a device the user is driving, but does not write UI code or run automated UI tests; the user generates the test signal by tapping through the app.)
- Baked-in KMM library knowledge. Every library version, API surface, and migration pattern is sourced live (`references/live-sources.md`). The answer to "what library should I use" is "let's run a live lookup", never "I recall…".
- Pushing without confirmation. The skill never opens a PR without explicit user `y`.
