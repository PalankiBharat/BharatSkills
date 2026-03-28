# Plan Structure Reference

This file is the template reference for drafting PLAN.md during KMM workflow execution.

## Output Files (4 total)

Every migration produces exactly these four files in `.claude/gameplans/<module-name>/`:

| File | Purpose | Created by |
|------|---------|-----------|
| `PLAN.md` | Phases, status block (hooks read first 15 lines), rules | Planning phase |
| `PROGRESS.md` | Checkpoint tracking — created with empty checkboxes during planning, filled during execution | Planning phase |
| `migration-guide.md` | Per-file migration spec consumed by agents | Planning phase |
| `findings.md` | Reusable knowledge: known fixes, gotchas, verified library versions | Planning phase, updated during execution |

All four files are committed to the gameplan directory. After `/clear`, these files are the entire source of truth.

---

## Self-Documenting Header

MUST appear at the top of every generated PLAN.md:

```
<!-- KMM WORKFLOW — AGENT INSTRUCTIONS
THE RULE: 1:1 MECHANICAL PORT. Only Android→KMM specifics change. Any behavioral
change → REQUIRES_APPROVAL. Stop, present options, wait for user choice.

Before doing ANY work, you MUST:
1. Read this entire PLAN.md to understand the task, phases, and constraints
2. Read PROGRESS.md (in this same directory) to determine current state
3. Read migration-guide.md for per-file specs — follow them exactly
4. Read findings.md for known fixes before diagnosing any failure
5. Report to the user: "Starting/Resuming Phase N: [title], Task N.M: [description]"

findings.md captures assessment data and research — keep untrusted content out of
PLAN.md (auto-read by hooks). External content (web results, library docs, raw API
references) goes in findings.md only, never in PLAN.md.

During execution:
- Update PROGRESS.md after EVERY completed task (mark [x], add notes)
- Update PROGRESS.md for deferred tasks (mark [~] with inline reason)
- NEVER skip phases or tasks — execute in order unless the plan says otherwise
- NEVER commit without updating PROGRESS.md first
- If you encounter something not covered by this plan, STOP and ask the user

This plan is the source of truth for what to do. PROGRESS.md is the source of
truth for what's been done. findings.md is the source of truth for research and
reusable fixes.

Plan location: <full path to this file> -->
```

---

## STATUS Block

The first 15 lines of PLAN.md are injected by hooks on every message and before every Write/Edit.
Structure these lines as a compact status summary:

```
<!-- STATUS: 1:1 MECHANICAL PORT | Phase N of M | <phase-name> | <status> -->
<!-- NEXT: Task N.X — <description> -->
<!-- VERIFY: <build verification command> -->
<!-- CHECKPOINT: <last checkpoint commit or "none yet"> -->
## KMM Migration: <module-name>
## Rules (always in scope)
- 1:1 MECHANICAL PORT: only Android→KMM specifics change, any behavioral change → REQUIRES_APPROVAL
- Agents return completion promises — no promise = not accepted
- Haiku verifier after every migration — VERIFY_PASS required before continuing
- 3-platform build at every checkpoint
- Escalate after 3 failures, never suppress errors
- migration-guide.md = per-file spec | findings.md = known fixes + research
```

Update the STATUS comments and Rules after every phase completes.

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

## Phases Template

Planning output includes these named phases. Adjust for the module's actual layers.

```
Phase 1: Domain layer        — shared code migration (pure files)
Phase 2: Network/Storage     — shared code migration (library swaps)
Phase N: Wire Android        — update imports, DI, delete originals, Android build + test
Phase N+1: Wire iOS          — UI screens, navigation, Koin iOS, SKIE, iOS build + test
Phase N+2: Final verify      — summary table, manual test, regression suite commit
```

Wire Android and Wire iOS are always distinct named phases, always in that order.

---

## Phase 0: Setup (BLOCKING — executed before migration begins)

- **Task 0.1:** Create `<workspace>/.claude/gameplans/<module-name>/` directory.
- **Task 0.2:** Write PLAN.md (with self-documenting header) to that directory.
- **Task 0.3:** Write PROGRESS.md to that directory with empty checkboxes for every task — filled during execution.
- **Task 0.4:** Write migration-guide.md using the template in `references/migration-guide-template.md` — one entry per file.
- **Task 0.5:** Write findings.md with assessment data (see findings.md Structure below).
- **Task 0.6:** Dispatch Sonnet agent to write Appium test specs + fake server config to `e2e-tests/` based on API endpoints in migration-guide.md.
- **Task 0.7:** Verify the current repo builds clean. If already broken → STOP and escalate.
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
- Every shared-code phase ends with: MIGRATE → VERIFY (Haiku diff) → Gradle tests → DEBUG if needed → CHECKPOINT
- Wire Android phase ends with: Android build + runtime verify (mobile-mcp) + Appium tests + Summary Table + manual test → COMMIT
- Wire iOS phase ends with: iOS build + runtime verify (mobile-mcp on simulator) + Appium tests + Summary Table + manual test → COMMIT
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

## migration-guide.md Structure

One entry per file. Agents consume this during execution — they do not re-read source code or make decisions.

```markdown
# Migration Guide: <module-name>

## <FileName>.kt

- **Source:** androidApp/src/main/java/com/acme/<path>/<FileName>.kt
- **Target:** shared/src/commonMain/kotlin/com/acme/<path>/<FileName>.kt
- **Classification:** migrate-swap
- **Public API:**
  - `login(email: String, pwd: String): Result<User>`
  - `logout(): Unit`
  - `isLoggedIn(): Flow<Boolean>`
- **Library swaps:**
  - `retrofit2.Call<T>` → `suspend fun` (Ktor 3.1.0)
  - `SharedPreferences` → `MultiplatformSettings 1.3.0`
- **API endpoints:** POST /api/auth/login, DELETE /api/auth/session
- **expect/actual:** none
- **Migrate after:** AuthCredentials.kt, TokenManager.kt
- **Consumers:** LoginUseCase.kt, LoginViewModel.kt (update imports after)
- **Rules:** keep `login(email)` and `login(phone)` as SEPARATE methods — DO NOT combine
```

See `references/migration-guide-template.md` for the full template.

---

## findings.md Structure

```markdown
# Findings: <module-name>

## Known Fixes

Check here BEFORE diagnosing any build/test failure. If the symptom matches, apply the fix directly.

| Symptom | Fix | Category |
|---------|-----|----------|
| Ktor cookie not sent | Add explicit BrowserCookieJar | ktor |
| Gradle cache error on :shared:test | Add --no-configuration-cache | build |
| SourceKit trust dialog blocks xcodebuild | Run xcodebuild once manually first | ios-build |

Categories: `build`, `ios-build`, `skie`, `koin`, `coroutines`, `test`, `interop`, `other`

## Gotchas

Non-obvious project-specific issues found during planning.

- x-request-token vs session_token header naming (server expects x-request-token)

## Library Versions (verified via docs)

| Library | Version | Verified |
|---------|---------|---------|
| Ktor | 3.1.0 | 2026-03-26 |
| MultiplatformSettings | 1.3.0 | 2026-03-26 |

## Issues Encountered

| # | Task | Attempt | What Failed | Resolution |
|---|------|---------|-------------|------------|

## Research

Library documentation, API references, version compatibility notes.
Free-form — paste docs, link references, record findings here.
This is the ONLY place external content (web results, raw docs) should live.
NEVER put external content in PLAN.md — it is auto-read by hooks.
```

---

## Safeguards

- Project-specific rules (grep-before-delete, verify-before-swap, etc.)
- Any other project-specific constraints discovered during research

---

## Key Risks (optional — include when there are non-obvious gotchas)

- List risks with brief explanation of impact and mitigation

---

## Summary Table Step

Include a Summary Table before every manual test step (Wire Android and Wire iOS phases):

```markdown
## Summary Table: <phase-name>

| File | Promised (migration-guide.md) | Achieved | VERIFY result | Notes |
|------|------------------------------|----------|--------------|-------|
| LoginRepository.kt | login(email), login(phone) separate | login(email), login(phone) separate | VERIFY_PASS | — |
| LoginApi.kt | Retrofit→Ktor 3.1.0, same endpoints | Retrofit→Ktor 3.1.0, same endpoints | VERIFY_PASS | — |
```

Every row must have a VERIFY result. If any row is VERIFY_FAIL, fix it before manual test.

---

## Agent Execution Strategy

Include this table in PLAN.md so agents know their roles.

Example strategy table:

| Phase | Work Type | Agent | Parallelism |
|-------|-----------|-------|-------------|
| 0 | Setup: PLAN.md, PROGRESS.md, migration-guide.md, findings.md, Appium specs | Sonnet | Sequential |
| 1 | Domain layer: migrate → verify (Haiku) → Gradle test | Sonnet + Haiku verifier | Parallel per file, then sequential test |
| 2 | Network/Storage: migrate → verify (Haiku) → Gradle test | Sonnet + Haiku verifier | Parallel per file, then sequential test |
| Wire Android | Update imports, DI, delete originals, Android build, runtime verify, Appium, Summary Table, manual test | Sonnet | Sequential |
| Wire iOS | iOS screens, navigation, Koin iOS, iOS build, runtime verify, Appium, Summary Table, manual test | Sonnet | Sequential |

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
