---
name: gameplan
description: >
  Execution planning expert. ALWAYS invoke when starting any multi-step task, refactor, or feature.
  Do not begin multi-phase work directly — create a gameplan first.
argument-hint: "[create|update|resume]"
---

## Quick Start

- **New task:** `/gameplan` or `/gameplan create` — research → questions → PLAN.md + PROGRESS.md → Phase 0 → autonomous execution
- **Resume:** `/gameplan resume` — scans gameplans dir, reports state, continues
- **Adjust:** `/gameplan update` — modify active plan
- **Plans live at:** `<workspace>/.claude/gameplans/<name>/`

## When to Use Reference Files

- `references/plan-structure.md` — read during `/gameplan create` Step 2 when drafting PLAN.md
- `references/escalation-rules.md` — read when hitting a blocker during execution

## Overview

Gameplan creates structured, phased execution plans for complex tasks with automatic checkpoint commits. It produces two documents:

- **PLAN.md** — What to do: phases, tasks, verification steps, constraints
- **PROGRESS.md** — What's done: task status, commit hashes, notes

**Key principles:**
- Every phase ends with a verified checkpoint commit (build must pass first)
- Tasks are atomic and small (retryable independently, max 7 per phase)
- All decisions go through the user — never assume
- Execution is autonomous after plan approval (no pausing between phases)
- Multiple gameplans can run in parallel (each in its own directory)

**Plan files** live at `<workspace>/.claude/gameplans/<name>/` (containing PLAN.md and PROGRESS.md) — not committed to git, enabling parallel gameplans without conflicts.

---

## Subcommands — `/gameplan create`

**Workflow — copy and track:**
- [ ] Step 1: Research codebase + ask questions **one at a time** (never batch; skip if obvious from research — state assumption and move on)
  - [ ] Build verification command(s)?
  - [ ] Multiple repos?
  - [ ] Project-specific open decisions
  - [ ] Look up library/framework docs via Context7 or `/find-docs` (don't rely on training data for API signatures)
- [ ] Step 2: Draft PLAN.md — see `references/plan-structure.md` for template
  - [ ] If the plan exceeds ~60 tasks, warn the orchestrator: "This plan has N tasks — consider using compact table format (see plan-structure.md § Compact Format) to reduce PLAN.md size and context consumption."
- [ ] Step 3: Draft PROGRESS.md — mirror plan structure with `[ ]`/`[x]`/`[~]` checkboxes
- [ ] Present concise summary in chat → wait for user approval
- [ ] Phase 0: Create gameplans dir + write PLAN.md + PROGRESS.md + create worktree(s) + verify build
- [ ] **Checkpoint 0** — commit scaffold, then proceed autonomously through Phase 1...N

**Key constraints:**
- Max 7 tasks per phase (split into sub-phases if larger)
- Every task specifies exact file paths
- Every phase ends with a checkpoint commit
- Tasks are atomic — retryable independently

---

### Step 3: Draft PROGRESS.md

Draft the progress tracker (written to disk alongside PLAN.md in Phase 0 Task 0.1). It mirrors the plan structure:

**Header metadata:**
- Worktree path(s) and branch(es) for every repo
- Verification commands (quick reference)

**Phase sections:**
- Each phase from PLAN.md gets a section
- Tasks listed with checkbox markers:
  - `[ ]` — not started
  - `[x]` — completed (verification passed)
  - `[~]` — partially done or deferred — **MUST include reason inline**, e.g.: `[~] Task 3.5: Delete LegacyConfig — DEFERRED to Phase 6 (AppModule.kt + routing still reference it)`
- Checkpoint lines include commit hashes after completion: `[x] Checkpoint 1 — Build verify + commit (abc1234)`
- For multi-repo: include all commit hashes: `[x] Checkpoint 1 — Build verify + commit (repo-a: abc1234, repo-b: def5678)`

**Notes sections:**
- Added after each completed phase
- Capture: build quirks, surprises, version bumps, decisions made during execution, file counts, anything useful for future phases

---

## Subcommands — `/gameplan resume`

**Workflow:**
1. Scan `<workspace>/.claude/gameplans/` → list all plans with name, current phase, last completed task
2. Ask user which plan to resume (even if only one)
3. Read PLAN.md + PROGRESS.md → report: Plan title, Completed phases/tasks, Current/next phase, Deferred `[~]` tasks, Worktree paths (verify they exist)

**Plan incomplete?** → Ask: Continue (execute next phase) or Adjust (`/gameplan update`)

**Plan complete?** → Offer: Verify (re-run builds), Extend (add phases via `/gameplan update`), or Close (cleanup)

---

## Subcommands — `/gameplan update`

**Workflow — copy and track:**
- [ ] Scan gameplans dir → select plan (if multiple, ask user)
- [ ] Read current PLAN.md + PROGRESS.md
- [ ] Ask user what changed
- [ ] Update PLAN.md with revised phases/tasks
- [ ] Update PROGRESS.md to match (new tasks `[ ]`, deferred `[~]` with reason)
- [ ] Present change summary → confirm with user
- [ ] Do NOT commit — plan files are workspace metadata

---

## Automatic Checkpoints (Feedback Loop)

The execution loop: **tasks → verification → fix if failing → commit → next phase**

1. All tasks in phase complete → Run Build Verification Template
2. If **PASS** → update PROGRESS.md (mark `[x]`, record commit hash, add Notes) → commit → report → next phase
3. If **FAIL** → fix → re-run → **max 3 attempts**
4. If still failing after 3 → **STOP** → escalate to user (what failed, what tried, root cause theory)

**Autonomous execution:** After user approves plan, do not pause between phases. Only stop for:
- Uncovered decisions
- Unexpected pre-check findings
- Unfixable verification failures
- Plan contradictions

---

## Escalation Rules

See `references/escalation-rules.md`. Summary: never stub, never substitute technology, never omit features, never silently downgrade. When blocked: present blocker + 2-4 options with pros/cons/confidence + your recommendation. Wait for user choice.

---

## Execution Defaults

- `<workspace>` = directory from which `/gameplan` was invoked
- Plan files at `<workspace>/.claude/gameplans/<name>/` — NOT committed to git
- Each gameplan has its own named subdirectory (parallel gameplans supported)
- All work happens in worktrees — retry with different branch names if creation fails
- PROGRESS.md is source of truth — task done only when `[x]` after verification
- Deferred tasks `[~]` always have inline reasons
- Checkpoint lines record commit SHAs
- Opus orchestrates, Sonnet/Haiku agents handle code. All subagents: `mode: "bypassPermissions"`, `run_in_background: true` unless result needed immediately. Maximize parallelism.

---

## Completion & Cleanup

When a gameplan is fully complete:
1. Report final status: all phases done, all commits recorded in PROGRESS.md
2. The worktree branch is ready for merge/PR — leave this to the user
3. The user can delete the gameplan directory when no longer needed

When abandoning a gameplan mid-flight:
1. Ask the user whether to keep or discard the worktree branch
2. If discarding: `git worktree remove <path>` then `git branch -D <branch>`
3. If keeping: leave as-is for future `/gameplan resume`
4. Delete the gameplan directory only if the user confirms

---

## Post-flight Check

A gameplan is complete when:
- [ ] All phases marked `[x]` in PROGRESS.md (no unexplained `[~]`)
- [ ] All checkpoint commits recorded with SHAs in PROGRESS.md
- [ ] Build Verification Template passes on final commit
- [ ] Worktree branch is clean and ready for PR (leave merge to user)
- [ ] Plan files NOT committed to git (workspace metadata only)
