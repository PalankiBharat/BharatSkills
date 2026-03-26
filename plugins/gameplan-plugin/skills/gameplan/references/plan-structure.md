# Plan Structure Reference

This file is the template reference for drafting PLAN.md during `/gameplan create` Step 2.

## Table of Contents

- [Self-Documenting Header](#self-documenting-header)
- [Title and Context](#title-and-context)
- [Build Verification Template](#build-verification-template)
- [Worktrees](#worktrees)
- [Plan Presentation](#plan-presentation)
- [Phase 0: Setup](#phase-0-setup-blocking--executed-as-part-of-gameplan-create)
- [Phase N: Template](#phase-n-title)
- [Safeguards](#safeguards)
- [Key Risks](#key-risks-optional--include-when-there-are-non-obvious-gotchas)
- [Agent Execution Strategy](#agent-execution-strategy)
- [Plan Quality Rules](#plan-quality-rules)

---

## Self-Documenting Header

MUST appear at the top of every generated PLAN.md:

```
<!-- GAMEPLAN — AGENT INSTRUCTIONS
Before doing ANY work, you MUST:
1. Read this entire PLAN.md to understand the task, phases, and constraints
2. Read PROGRESS.md (in this same directory) to determine current state
3. Report to the user: "Starting/Resuming Phase N: [title], Task N.M: [description]"

During execution:
- Update PROGRESS.md after EVERY completed task (mark [x], add notes)
- Update PROGRESS.md for deferred tasks (mark [~] with inline reason)
- NEVER skip phases or tasks — execute in order unless the plan says otherwise
- NEVER commit without updating PROGRESS.md first
- If you encounter something not covered by this plan, STOP and ask the user

This plan is the source of truth for what to do. PROGRESS.md is the source of
truth for what's been done.

Plan location: <full path to this file>
Worktrees: <listed in the Worktrees section below> -->
```

---

## Title and Context

- `# [Title]` — what the plan is for
- `## Context` — what we're doing, why, current state, definition of done
- `## Decisions Made` — starts empty, filled during Q&A and execution

---

## Build Verification Template

- The verification step(s) the user specified
- Runs at EVERY checkpoint before committing
- ALL must pass before a checkpoint commit is allowed — no exceptions

---

## Worktrees

- List every repo involved with its worktree path and branch
- Format: `- **[Repo name]:** repo-path/.claude/worktrees/<name> (branch: <branch-name>)`
- If only one repo, still list it — consistency matters

---

## Plan Presentation

After writing PLAN.md, present a **concise summary** in chat — not the full file:
- Title and one-line context
- Each phase as a one-liner with task count (e.g., "Phase 2: Auth migration (5 tasks)")
- Total phases and tasks
- Key risks or open items (if any)

Tell the user where the full PLAN.md is if they want to review details. Wait for approval before proceeding to Phase 0.

---

## Phase 0: Setup (BLOCKING — executed as part of `/gameplan create`)

The `/gameplan create` flow is: research → questions → write PLAN.md → present summary → user approves → execute Phase 0 → continue autonomously through Phase 1...N (the full execution loop kicks in immediately).

- **Task 0.1:** Create `<workspace>/.claude/gameplans/<name>/` directory. Write PLAN.md (with self-documenting header) and PROGRESS.md there. These are NOT committed — workspace metadata only.
- **Task 0.2:** Create worktree(s) — one per repo involved
  - **Check for uncommitted changes first.** Run `git status` on each repo's base branch. If uncommitted changes exist, ask the user:
    - Commit them first (so the worktree includes them)
    - Stash them (worktree starts clean, changes preserved on base branch)
    - Work directly on the branch instead of creating a worktree

    Do NOT create a worktree from a dirty branch without the user's explicit choice.
  - **Ask the user to pick a worktree/branch name.** Always suggest feature-branch style names (`feature/...`). Suggest 3 options based on the task, e.g.:
    - `feature/session-auth`
    - `feature/grpc-migration`
    - `feature/ios-pattern-cleanup`
  - User picks one — that name is used for both the worktree directory and the branch.
  - Command: `cd <repo> && git worktree add .claude/worktrees/<chosen-name> -b <chosen-name>`
  - If creation fails (branch exists, dirty state, etc.), retry:
    - Try appending `-v2`, `-v3`, etc. to the chosen name
    - Or create a new branch from current HEAD and base the worktree off it
  - **Keep trying until every worktree is created.** This is non-negotiable.
- **Task 0.3:** Verify all worktrees build clean using the Build Verification Template
- **Checkpoint 0** with commit message: `chore: setup worktrees for [title]`
  (commits only worktree scaffold and test infrastructure, NOT plan files)

---

## Phase N: [Title]

- One-line description of what this phase accomplishes
- Tasks with file-level specificity:
  - **Read:** exact file paths to understand first
  - **Create:** full paths of new files, with description of contents
  - **Modify:** full paths of files to change + what changes (add/remove/rename what)
  - **Delete:** full paths of files to remove (with grep-before-delete if needed)
  - **Verify:** build/test command
- Tasks within a phase execute **sequentially by default**. Mark tasks as `(parallelizable)` when they touch no shared files — the orchestrator can run these concurrently via parallel agents.
- If a phase depends on unknowns that can't be resolved upfront, add a `Task N.0: PRE-CHECK` that researches the unknowns and updates PLAN.md with concrete file paths before executing the remaining tasks. This runs autonomously — no user approval pause needed.
- Checkpoint N with commit message: `[type]: [description]` (use conventional commits; include structured trailers like `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:` when the commit involves non-obvious decisions)

---

## Safeguards

- Project-specific rules (grep-before-delete, verify-before-swap, etc.)
- Any other project-specific constraints discovered during research

---

## Key Risks (optional — include when there are non-obvious gotchas)

- List risks with brief explanation of impact and mitigation

---

## Agent Execution Strategy

The plan MUST include a concrete agent strategy table mapping phases to agent models and parallelism. Use these rules (from the project's agent configuration):

- **Opus:** Orchestrator only — coordinates agents, reviews results, escalates decisions. Never does code changes directly.
- **Sonnet agents:** Code reading, editing, build verification, complex logic.
- **Haiku agents:** Quick searches, greps, mechanical deletions, simple file operations.
- **All subagents:** `mode: "bypassPermissions"` so they don't get blocked by permission prompts.
- **Maximize parallelism.** Launch multiple agents concurrently when tasks are independent.

Write these rules explicitly into the plan so the document is self-contained for any future conversation reading it.

---

## Plan Quality Rules

- **Tasks must be atomic** — a single file or single logical change, retryable independently
- **Every task specifies exact file paths** — Create/Modify/Delete with full paths, no vague references
- **Every phase ends with a checkpoint commit** — the codebase is always in a buildable state
- **Checkpoint commits are MANDATORY** — but ONLY after build verification passes. Never commit with failing builds.
- **A task is only marked `[x]` in PROGRESS.md after its verification step passes** — not before
- **Pre-check gates** — phases depending on unknowns get a Task X.0 PRE-CHECK that researches and updates PLAN.md with concrete paths before continuing (no approval pause)
- **Max 7 tasks per phase** — split into sub-phases (3A, 3B) if larger. When a parent skill (e.g., kmm-workflow) specifies its own phase boundary rules, defer to those rules instead of the 7-task cap.

### Compact Format

Use compact table format when plan exceeds 50 tasks to reduce PLAN.md size. Replace verbose task prose with a table inside each phase section:

```
| # | Task | File(s) | Classification | Notes |
|---|------|---------|----------------|-------|
| 2.1 | Add UserRepository interface | src/data/UserRepository.kt | Create | — |
| 2.2 | Implement RoomUserRepository | src/data/RoomUserRepository.kt | Create | depends on 2.1 |
| 2.3 | Delete LegacyUserDao | src/data/LegacyUserDao.kt | Delete | grep-before-delete |
```

Classification values: `Create`, `Modify`, `Delete`, `Read`, `Verify`, `PRE-CHECK`.
