# Plan Structure Reference

This file is the template reference for drafting PLAN.md during KMM workflow execution.

## Table of Contents

- [Self-Documenting Header](#self-documenting-header)
- [Title and Context](#title-and-context)
- [Build Verification Template](#build-verification-template)
- [Plan Presentation](#plan-presentation)
- [Phase 0: Setup](#phase-0-setup-blocking--executed-before-migration-begins)
- [Phase N: Template](#phase-n-title)
- [Compact Format](#compact-format)
- [FINDINGS.md Structure](#findingsmd-structure)
- [Safeguards](#safeguards)
- [Key Risks](#key-risks-optional--include-when-there-are-non-obvious-gotchas)
- [Agent Execution Strategy](#agent-execution-strategy)
- [Plan Quality Rules](#plan-quality-rules)

---

## Self-Documenting Header

MUST appear at the top of every generated PLAN.md:

```
<!-- KMM WORKFLOW — AGENT INSTRUCTIONS
Before doing ANY work, you MUST:
1. Read this entire PLAN.md to understand the task, phases, and constraints
2. Read PROGRESS.md (in this same directory) to determine current state
3. Read FINDINGS.md for assessment data and research context
4. Report to the user: "Starting/Resuming Phase N: [title], Task N.M: [description]"

FINDINGS.md captures assessment data and research — keep untrusted content out of
PLAN.md (auto-read by hooks). External content (web results, library docs, raw API
references) goes in FINDINGS.md only, never in PLAN.md.

During execution:
- Update PROGRESS.md after EVERY completed task (mark [x], add notes)
- Update PROGRESS.md for deferred tasks (mark [~] with inline reason)
- NEVER skip phases or tasks — execute in order unless the plan says otherwise
- NEVER commit without updating PROGRESS.md first
- If you encounter something not covered by this plan, STOP and ask the user

This plan is the source of truth for what to do. PROGRESS.md is the source of
truth for what's been done. FINDINGS.md is the source of truth for research and
assessment data.

Plan location: <full path to this file> -->
```

---

## Title and Context

- `# [Title]` — what the plan is for (e.g., "Migrate :networking module to KMM")
- `## Context` — what we're doing, why, current state, definition of done
- `## Decisions Made` — starts empty, filled during Q&A and execution

---

## Build Verification Template

- The verification step(s) the user specified
- Runs at EVERY checkpoint before committing
- ALL must pass before a checkpoint commit is allowed — no exceptions

---

## Plan Presentation

After writing PLAN.md, present a **concise summary** in chat — not the full file:
- Title and one-line context
- Each phase as a one-liner with task count (e.g., "Phase 2: Data layer migration (8 tasks)")
- Total phases and tasks
- Key risks or open items (if any)

Tell the user where the full PLAN.md is if they want to review details. Wait for approval before proceeding to Phase 0.

---

## Phase 0: Setup (BLOCKING — executed before migration begins)

The KMM workflow flow is: research → questions → write PLAN.md + FINDINGS.md → present summary → user approves → execute Phase 0 → continue autonomously through Phase 1...N (the full execution loop kicks in immediately).

- **Task 0.1:** Create `<workspace>/.claude/gameplans/<module-name>/` directory.
- **Task 0.2:** Write PLAN.md (with self-documenting header) and PROGRESS.md to that directory. These are NOT committed — workspace metadata only.
- **Task 0.3:** Write FINDINGS.md to that directory with the assessment data gathered during research (see FINDINGS.md Structure below).
- **Task 0.4:** Verify the current repo builds clean using the Build Verification Template. This is a baseline — if the build is already broken before migration begins, STOP and escalate.
- **Checkpoint 0** with commit message: `chore: begin KMM migration for [module-name]`

---

## Phase N: [Title]

- One-line description of what this phase accomplishes
- Phase boundaries are drawn **by architectural layer** (e.g., data layer, domain layer, platform API layer, expect/actual declarations, test layer) — not by arbitrary task count
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

## Compact Format

Use compact table format when plan exceeds 50 tasks to reduce PLAN.md size. Replace verbose task prose with a table inside each phase section:

```
| # | Task | File(s) | Classification | Notes |
|---|------|---------|----------------|-------|
| 2.1 | Add UserRepository interface | shared/src/commonMain/kotlin/data/UserRepository.kt | Create | — |
| 2.2 | Implement AndroidUserRepository | shared/src/androidMain/kotlin/data/AndroidUserRepository.kt | Create | depends on 2.1 |
| 2.3 | Delete LegacyUserDao | android/src/main/java/data/LegacyUserDao.kt | Delete | grep-before-delete |
```

Classification values: `Create`, `Modify`, `Delete`, `Read`, `Verify`, `PRE-CHECK`.

---

## FINDINGS.md Structure

FINDINGS.md is written during Phase 0 and updated throughout execution. It is the designated container for assessment data and external research — content that must NOT appear in PLAN.md.

```markdown
# Findings: <module-name>

## Assessment

### Files to Migrate

| File | Current Location | Target Location | Notes |
|------|-----------------|-----------------|-------|
| UserRepository.kt | android/src/.../data/ | shared/commonMain/.../data/ | — |

### Dependency Map

List every dependency the module uses, with KMM compatibility status:

| Dependency | Current | KMM Compatible | Replacement |
|------------|---------|----------------|-------------|
| Room | room:2.6 | Android-only | SQLDelight |

### Migration Order

Ordered list of files/components to migrate, with reasoning (e.g., interfaces before
implementations, domain before data, no circular dependencies).

### Risks

Non-obvious risks discovered during assessment, with impact and mitigation.

## Research

Library documentation, API references, version compatibility notes.
Free-form section — paste docs, link references, record findings here.
This is the ONLY place external content (web results, raw docs) should live.

## Technical Decisions

| Decision | Options Considered | Chosen | Rationale |
|----------|--------------------|--------|-----------|

## Issues Encountered

| # | Task | Attempt | What Failed | Resolution |
|---|------|---------|-------------|------------|

## External Content

Web search results, copied documentation, raw API references.
NEVER put this content in PLAN.md — it is untrusted and auto-read by hooks.
```

---

## Safeguards

- Project-specific rules (grep-before-delete, verify-before-swap, etc.)
- Any other project-specific constraints discovered during research

---

## Key Risks (optional — include when there are non-obvious gotchas)

- List risks with brief explanation of impact and mitigation

---

## Agent Execution Strategy

The plan MUST include a concrete agent strategy table mapping phases to agent models and parallelism. Use these rules:

- **Opus:** Orchestrator only — coordinates agents, reviews results, escalates decisions. Never writes code or edits files directly.
- **Sonnet agents:** Code reading, editing, build verification, complex logic (expect/actual wiring, dependency resolution, test migration).
- **Haiku agents:** Quick searches, greps, mechanical deletions, simple file operations, dependency lookups.
- **All subagents:** `mode: "bypassPermissions"` so they don't get blocked by permission prompts.
- **Maximize parallelism.** Launch multiple agents concurrently when tasks are independent (e.g., migrating unrelated files in the same layer).
- **Agents return completion promise strings** — the orchestrator collects these and checks results before marking tasks complete in PROGRESS.md.

Write these rules explicitly into the plan so the document is self-contained for any future conversation reading it.

Example strategy table:

| Phase | Work Type | Agent | Parallelism |
|-------|-----------|-------|-------------|
| 0 | Setup, baseline build | Sonnet | Sequential |
| 1 | Assessment PRE-CHECK | Haiku (search) + Sonnet (analysis) | Parallel where possible |
| 2 | Domain layer migration | Sonnet | Parallel per file |
| 3 | Data layer migration | Sonnet | Sequential (dependencies) |
| 4 | expect/actual wiring | Sonnet | Sequential |
| 5 | Test migration | Sonnet | Parallel per test file |

---

## Plan Quality Rules

- **Tasks must be atomic** — a single file or single logical change, retryable independently
- **Every task specifies exact file paths** — Create/Modify/Delete with full paths, no vague references
- **Every phase ends with a checkpoint commit** — the codebase is always in a buildable state
- **Checkpoint commits are MANDATORY** — but ONLY after build verification passes. Never commit with failing builds.
- **A task is only marked `[x]` in PROGRESS.md after its verification step passes** — not before
- **Pre-check gates** — phases depending on unknowns get a Task X.0 PRE-CHECK that researches and updates PLAN.md with concrete paths before continuing (no approval pause)
- **Phase boundaries are by LAYER** — each phase corresponds to a distinct architectural layer (domain, data, platform API, expect/actual, tests). There is no task cap per phase; split by layer boundaries, not by count. If a single layer is very large, split into sub-phases (3A, 3B) by sub-component.
- **FINDINGS.md is always the destination for research** — never inline external content or untrusted data into PLAN.md
