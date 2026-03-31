# Planning and Execution Reference

This file is the combined reference for both plan structure and iterative execution in KMM workflow migrations.

## Table of Contents

1. [Two-Phase Model](#two-phase-model)
2. [Output Files](#output-files)
3. [PLAN.md: Self-Documenting Header](#planmd-self-documenting-header)
4. [PLAN.md: STATUS Block](#planmd-status-block)
5. [PLAN.md: Title, Context, and Decisions](#planmd-title-context-and-decisions)
6. [PLAN.md: Build Verification Template](#planmd-build-verification-template)
7. [PLAN.md: Plan Presentation](#planmd-plan-presentation)
8. [Workflow Phases Overview](#workflow-phases-overview)
9. [Phase 1: PLAN (BLOCKING)](#phase-1-plan-blocking)
10. [Phase Template: Shared Migration](#phase-template-shared-migration)
11. [Per-File Migration Loop](#per-file-migration-loop)
12. [Wire Android Phase](#wire-android-phase)
13. [Wire iOS Phase](#wire-ios-phase)
14. [Parallel Execution](#parallel-execution)
15. [Agent Execution Strategy](#agent-execution-strategy)
16. [PROGRESS.md Template](#progressmd-template)
17. [migration-guide.md Structure](#migration-guidemd-structure)
18. [findings.md Structure](#findingsmd-structure)
19. [Summary Table Step](#summary-table-step)
20. [Compact Format](#compact-format)
21. [Plan Quality Rules](#plan-quality-rules)
22. [Safeguards and Key Risks](#safeguards-and-key-risks)
23. [Session Completion](#session-completion)

---

## Two-Phase Model

Two-phase separation: PLAN captures every decision in files. EXECUTE consumes those files with minimal context. `/clear` is the boundary — only files survive it.

After planning is complete, tell the user:

```
Planning complete. Run /clear then:

/kmm-workflow → pick Continue
```

Do NOT auto-clear. The user decides when to clear.

---

## Output Files

Every migration produces exactly these four files in `~/dev/gameplans/<module-name>/`:

| File | Purpose | Created by |
|------|---------|-----------|
| `PLAN.md` | Phases, status block (hooks read first 15 lines), rules | Planning phase |
| `PROGRESS.md` | Checkpoint tracking — created with empty checkboxes during planning, filled during execution | Planning phase |
| `migration-guide.md` | Per-file migration spec consumed by agents | Planning phase |
| `findings.md` | Reusable knowledge: known fixes, gotchas, verified library versions | Planning phase, updated during execution |

All four files are committed to the gameplan directory. After `/clear`, these files are the entire source of truth.

---

## PLAN.md: Self-Documenting Header

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

## PLAN.md: STATUS Block

The first 15 lines of PLAN.md are injected by hooks on every message and before every Write/Edit. Structure these lines as a compact status summary:

```
<!-- STATUS: 1:1 MECHANICAL PORT | Phase N of M | <phase-name> | <status> -->
<!-- NEXT: Task N.X — <description> -->
<!-- VERIFY: <build verification command> -->
<!-- CHECKPOINT: <last checkpoint commit or "none yet"> -->
<!-- DEVICE: android=<emulator-serial> | ios=<simulator-UDID> -->
<!-- PORTS: fake=<port> -->
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

## PLAN.md: Title, Context, and Decisions

- `# [Title]` — what the plan is for (e.g., "Migrate :networking module to KMM")
- `## Context` — what we're doing, why, current state, definition of done
- `## Decisions Made` — starts empty, filled during Q&A and execution

---

## PLAN.md: Build Verification Template

- The verification step(s) the user specified
- Runs at EVERY checkpoint before committing
- ALL must pass before a checkpoint commit is allowed — no exceptions

---

## PLAN.md: Plan Presentation

After writing PLAN.md, present a **concise summary** in chat — not the full file:
- Title and one-line context
- Each phase as a one-liner with task count (e.g., "Phase 2: Data layer migration (8 tasks)")
- Total phases and tasks
- Key risks or open items (if any)

Tell the user where the full PLAN.md is if they want to review details. Wait for approval before proceeding to Phase 1.

---

## Workflow Phases Overview

The canonical phase sequence for every migration:

```
Phase 1: PLAN (BLOCKING)
  ── /clear (mandatory) ──
Phase 2: SCAFFOLD                     — create KMM module skeleton, expect/actual stubs
Phase 3: SHARED CODE MIGRATION (TDD)  — per-file, bottom-up dependency order
  ── /clear (mandatory) ──
Phase 4: WIRE ANDROID                 — imports, DI, delete originals, build, runtime verify, mobile-mcp flows, manual test
Phase 5: WIRE iOS                     — UI screens, navigation, Koin iOS, build, runtime verify, mobile-mcp flows, manual test
```

Wire Android and Wire iOS are always distinct named phases, always in that order. mobile-mcp automated flows and manual testing are embedded in each Wire phase.

**Mandatory /clear points** are shown above. Phase 3 (shared code migration) is the heaviest phase — per-file TDD loops, agent outputs, and debug traces can bloat context by 300K+ tokens. Clearing before wiring prevents stale-reference errors. After each `/clear`, run `/kmm-workflow` → Continue to resume from the last checkpoint. The orchestrator MUST stop after these phases — do not continue without clearing.

Phase boundaries are drawn **by architectural layer** — not by arbitrary task count. If a single layer is very large, split into sub-phases (e.g., 3A, 3B) by sub-component.

---

## Phase 1: PLAN (BLOCKING — executed before migration begins)

- **Task 1.1:** Create `~/dev/gameplans/<module-name>/` directory.
- **Task 1.2:** Create worktree: `git worktree add .claire/worktrees/<module-name> <base-branch> -b feature/<module-name>`. Copy `local.properties` to the worktree. Record the worktree path in PLAN.md. All subsequent file creation and edits happen in the worktree.
- **Task 1.3:** Write PLAN.md (with self-documenting header) to the gameplan directory.
- **Task 1.4:** Write PROGRESS.md to the gameplan directory with empty checkboxes for every task — filled during execution.
- **Task 1.5:** Write migration-guide.md using the template in `references/agent-prompts/migration-guide-template.md` — one entry per file.
- **Task 1.5b:** Library KMP availability audit — for every Android-only library listed in migration-guide.md "Swaps" (Paging3, Room, DataStore, Navigation, etc.), web search or use Context7/`/find-docs` to verify whether an official KMP-compatible version exists. Record findings in findings.md under "Library Versions" with columns: `Library | KMP Available | Version | Source`. Never claim "no KMP alternative" without live research — training data is outdated. If an official KMP version exists, use it instead of building a manual alternative.
- **Task 1.6:** Write findings.md with assessment data (see findings.md Structure below).
- **Task 1.7:** Read every source file in scope. Identify every API endpoint the module calls. Record request/response shapes → write fake server config (`e2e-tests/fake-server-config.json`). Generate `e2e-tests/screen-map.json` — record every screen in scope with navigation steps, key elements to verify, CTA targets, and known blockers (OTP, login, personal details). Define user journey flows in the screen map for mobile-mcp automated testing.
- **Task 1.7b:** Generate fake server: `e2e-tests/fake-server.js`. See `references/automated-testing.md` for template. Commit `e2e-tests/` to the worktree.
- **Task 1.7c:** Allocate dedicated device and ports for this gameplan (prevents collisions with concurrent gameplans). See `references/automated-testing.md` § Device & Port Isolation. Auto-allocate by scanning for free ports and existing emulators/simulators. Record allocated device serials and FAKE_PORT in PLAN.md header (`<!-- DEVICE: ... -->`, `<!-- PORTS: ... -->`).
- **Task 1.8:** Verify platform navigation architecture — read the actual Android `Router.kt`/`NavHost` and iOS `AppRouter`/`Coordinator` to determine how each platform handles navigation. Record the verified architecture in findings.md. Do NOT assume navigation patterns — verify them before writing Wire phases.
- **Task 1.9:** Verify SDK availability — for every external SDK class referenced by migration targets, grep the KMM SDK source sets (`commonMain`, `androidMain`, `iosMain`) to confirm the class exists. Record availability in findings.md as a table (`Class | commonMain | androidMain | iosMain`). If unavailable, add to the scaffold list in PLAN.md.
- **Task 1.10:** Verify build task names — run `./gradlew :<module>:tasks --all | grep -i <platform>` to discover exact Gradle task names for Android compilation, iOS arm64 compilation, and app assembly. Record verified task names in PLAN.md build verification section. Never write build commands based on assumptions.
- **Task 1.11:** Generate `build-verify.sh` in the gameplan directory using the verified build commands from Task 1.10. This project-specific script is the single source of truth for build checks throughout all phases — zero LLM tokens on mechanical builds. See [Build Verification Script](#build-verification-script) for the template and usage.
- **Task 1.12:** Dispatch **Sonnet agent** (`plan-analyzer.md`) to find remaining ambiguity → resolve → user approves.
- **Task 1.13:** Verify the current repo builds clean (in the worktree) by running `<gameplan-dir>/build-verify.sh <worktree-dir>`. If already broken → STOP and escalate.
- **Checkpoint 1** committed in the worktree. Commit message: `chore: begin KMM migration for [module-name]`

---

## Phase Template: Shared Migration

Each shared-code phase migrates one architectural layer. Tasks have file-level specificity:

- **Read:** exact file paths to understand first
- **Create:** full paths of new files, with description of contents
- **Modify:** full paths of files to change + what changes (add/remove/rename what)
- **Delete:** full paths of files to remove (with grep-before-delete if needed)
- **Verify:** build/test command

Tasks within a phase execute **sequentially by default**. Mark tasks as `(parallelizable)` when they touch no shared files — files at the same dependency level run as parallel subagents.

If a phase depends on unknowns that can't be resolved upfront, add a `Task N.0: PRE-CHECK` that researches the unknowns and updates PLAN.md with concrete file paths before executing the remaining tasks. This runs autonomously — no user approval pause needed.

Every shared-code phase ends with:
```
MIGRATE → VERIFY (Haiku diff) → Gradle tests → DEBUG if needed → CHECKPOINT
```

Checkpoint committed after this phase completes. Commit message: `[type]: [description]` (use conventional commits; include structured trailers like `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:` when the commit involves non-obvious decisions).

---

## Per-File Migration Loop

For each file, execute this loop in order:

```
1. Stage      — copy original to staging area (do not modify original yet)
2. Compile    — verify the original compiles clean before touching it
3. Write tests — write unit tests against the original (TDD: red first)
4. Run on original — confirm tests pass on original (establishes baseline)
5. Migrate    — Sonnet agent performs the 1:1 port to KMM target
6. Run on migrated — run the same tests against the migrated output
7. Verify     — Haiku diff: API surface, method signatures, return types all match exactly
8. Delete staged — remove the staging copy; original is replaced by migrated
```

Verifier (step 7) is a fast pre-filter — diffs migrated output vs original source:
- API surface: every method, param, return type matches exactly
- No use cases combined, split, or altered
- Allowed changes: library swaps, package changes, imports, LiveData→StateFlow

If VERIFY_FAIL → re-dispatch migrator (max 2 retries) → escalate after 3 failures.

Gradle tests are the real catch-all for subtle bugs that pass the diff check.

Batch any REQUIRES_APPROVAL items → present to user at phase boundary (not one-by-one).

---

## Wire Android Phase

Runs after all shared migration phases are complete.

**Step 1: Wire Android** — read `android-wiring.md`

**Step 2: Stub audit**

Scan all migrated files for `error("…")`, `TODO()`, `TODO("…")`, `stub` markers, and `= {}` default lambdas on callback parameters. Empty lambdas are functional stubs — buttons compile but do nothing at runtime. Any unresolved stubs BLOCK the checkpoint or must be explicitly deferred with rationale in PROGRESS.md.

**Step 3: Koin binding completeness check**

For each VM registered in the shared Koin module, verify ALL constructor parameter types AND all types used by child composables/screens (e.g., `CustomerSupportUseCase` used by `WithdrawalsTopBar`) have Koin bindings. Check transitively — not just direct constructor params. Verify bindings exist in BOTH `androidBridgeModule` AND `iosBridgeModule`. Missing bindings crash Koin startup at runtime and block ALL VM resolution, not just the missing one.

**Step 4: Android build + test**

Run the project-specific build script (zero LLM tokens):
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
  → BUILD_VERIFY_PASS → proceed
  → BUILD_VERIFY_FAIL → check findings.md → DEBUG LOOP → FIX → rerun script
```

**Step 5: Runtime Verify (mobile-mcp, fallback: adb)**

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` |
| adb (fallback) | `adb install -r <apk>` → `adb shell am start` |

"App launches cleanly" is NOT sufficient. Uses `e2e-tests/screen-map.json` for cached element coordinates (see `references/automated-testing.md`). For each migrated screen in migration-guide.md:
1. Navigate to the screen using cached coordinates from screen-map (first time: call `mobile_list_elements_on_screen` and populate cache)
2. Verify data loads — not stuck on spinner (screenshot, NOT `mobile_list_elements_on_screen` on cached screens)
3. Verify primary CTA works (tap using cached coordinates, confirm expected result)
4. `mobile_take_screenshot` → save to `e2e-tests/screenshots/android/`

If cached tap fails (element moved) → re-discover with `mobile_list_elements_on_screen`, update screen-map, retry.

If crash → DEBUG LOOP (Android): instrument with Napier `[DebugScreenName]` → `adb logcat -s DebugScreenName`

**Step 6: Summary Table** (promised vs achieved per file — see Summary Table Step)

**Step 7: mobile-mcp Automated Flows (real app, real device)**

Drive full user journeys against the real app using `e2e-tests/screen-map.json`:

1. Install and launch app via mobile-mcp
2. Execute each flow from screen-map sequentially:
   - Use cached coordinates — do NOT call `mobile_list_elements_on_screen` on unchanged screens
   - On `blocker` steps (OTP, payment, personal details): STOP and ask user to complete the step on device, wait for confirmation, then resume
   - On tap failure (element moved): re-discover with `mobile_list_elements_on_screen`, update screen-map cache, retry
   - After each screen transition: `mobile_take_screenshot` → save to `e2e-tests/screenshots/android/`
3. On failure: screenshot + re-discover + DEBUG LOOP
4. All flows pass → proceed to manual test

**Step 8: Manual Test**
```
User tests remaining edge cases that automation couldn't cover
Bug → DEBUG LOOP → mobile-mcp smoke after each fix
All flows pass → COMMIT (Wire Android + flows complete)
```

PROGRESS.md committed at end of this phase.

---

## Wire iOS Phase

Runs after Wire Android is committed.

**Step 1: UI Migration** — per screen per migration-guide.md (CMP / SwiftUI / Hybrid per spec)

**Step 2: Wire iOS** — read `ios-wiring.md`

**Step 3: Stub audit + Koin completeness check** (same as Wire Android Steps 2-3, for iOS bindings)

**Step 4: iOS build**

Run the project-specific build script (zero LLM tokens):
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
  → BUILD_VERIFY_PASS → proceed
  → BUILD_VERIFY_FAIL → DEBUG LOOP (iOS) → fix → rerun script
```

**Step 5: Runtime Verify (mobile-mcp on simulator, fallback: xcrun)**

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` (iOS simulator) |
| xcrun (fallback) | `xcrun simctl install booted <app>` → `xcrun simctl launch booted <bundle-id>` |

"App launches cleanly" is NOT sufficient. Uses `e2e-tests/screen-map.json` for cached element coordinates. For each migrated screen in migration-guide.md:
1. Navigate to the screen using cached coordinates from screen-map (first time: call `mobile_list_elements_on_screen` and populate cache)
2. Verify data loads — not stuck on spinner (screenshot, NOT `mobile_list_elements_on_screen` on cached screens)
3. Verify primary CTA works (tap using cached coordinates, confirm expected result)
4. `mobile_take_screenshot` → save to `e2e-tests/screenshots/ios/`, compare with Android screenshot (visual parity check)

If cached tap fails OR screen source file was modified in this phase → re-discover with `mobile_list_elements_on_screen`, update screen-map, retry.

If crash → DEBUG LOOP (iOS): `xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | grep DebugScreenName`

**Step 6: Summary Table** (promised vs achieved — compare Android vs iOS columns)

**Step 7: mobile-mcp Automated Flows (iOS, real device)**

Same protocol as Wire Android Step 7, but on iOS simulator:

1. Install and launch via mobile-mcp on iOS simulator
2. Execute each flow from screen-map, handle blockers (ask user)
3. Compare screenshots with Android parity (`e2e-tests/screenshots/android/` vs `ios/`)
4. On failure: screenshot + re-discover + DEBUG LOOP (iOS)
5. All flows pass → proceed to manual test

**Step 8: Manual Test**
```
User tests remaining edge cases on iOS
Bug → DEBUG LOOP (iOS) → fix → retest
All flows pass → COMMIT (Wire iOS + flows complete)
```

PROGRESS.md committed at end of this phase.

---

## Parallel Execution

Files at the same dependency level (no ordering constraint between them) run as parallel subagents — do not serialize unnecessarily.

- Mark tasks `(parallelizable)` in PLAN.md when they touch no shared files.
- The orchestrator launches these concurrently via separate Sonnet agents.
- Tasks that share files or have dependency order execute sequentially.

---

## Agent Execution Strategy

Include this table in PLAN.md so agents know their roles.

| Phase | Work Type | Agent | Parallelism |
|-------|-----------|-------|-------------|
| 1: PLAN | Setup: PLAN.md, PROGRESS.md, migration-guide.md, findings.md, fake server config, screen-map | Sonnet | Sequential |
| 2: SCAFFOLD | Create KMM module skeleton, expect/actual stubs | Sonnet | Sequential |
| 3: SHARED CODE MIGRATION | Migrate → verify (Haiku) → Gradle test, per layer | Sonnet + Haiku verifier | Parallel per file at same dependency level, then sequential test |
| 4: WIRE ANDROID | Update imports, DI, delete originals, Android build, runtime verify, Summary Table, mobile-mcp flows, manual test | Sonnet | Sequential |
| 5: WIRE iOS | iOS screens, navigation, Koin iOS, iOS build, runtime verify, Summary Table, mobile-mcp flows, manual test | Sonnet | Sequential |

---

## PROGRESS.md Template

Created during Phase 1 with empty checkboxes. Filled during execution. PROGRESS.md is committed after each phase completes — not all at once at the end.

```markdown
# Progress: <module-name>

## Phase 1: PLAN
- [ ] 1.1 Create gameplan directory
- [ ] 1.2 Create worktree + copy local.properties
- [ ] 1.3 Write PLAN.md
- [ ] 1.4 Write PROGRESS.md
- [ ] 1.5 Write migration-guide.md
- [ ] 1.5b Library KMP availability audit (web search, record in findings.md)
- [ ] 1.6 Write findings.md
- [ ] 1.7 Write fake server config + screen-map.json
- [ ] 1.7b Generate fake server (fake-server.js), commit e2e-tests/
- [ ] 1.7c Allocate dedicated device + FAKE_PORT (auto), record in PLAN.md header
- [ ] 1.8 Verify platform navigation architecture
- [ ] 1.9 Verify SDK availability
- [ ] 1.10 Verify build task names
- [ ] 1.11 Generate build-verify.sh
- [ ] 1.12 Plan ambiguity analysis (plan-analyzer.md)
- [ ] 1.13 Verify clean build baseline
- [ ] Checkpoint 1 committed

## Phase 2: SCAFFOLD
- [ ] 2.1 Create KMM module skeleton (build.gradle.kts, source sets)
- [ ] 2.2 Write expect/actual stubs for platform APIs
- [ ] 2.N ...
- [ ] Checkpoint 2 committed

## Phase 3: SHARED CODE MIGRATION
<!-- One checkbox per file per loop step, grouped by phase -->
- [ ] 3.1 <FileName>.kt — stage
- [ ] 3.1 <FileName>.kt — compile original
- [ ] 3.1 <FileName>.kt — write tests
- [ ] 3.1 <FileName>.kt — run on original
- [ ] 3.1 <FileName>.kt — migrate
- [ ] 3.1 <FileName>.kt — run on migrated
- [ ] 3.1 <FileName>.kt — verify (Haiku)
- [ ] 3.1 <FileName>.kt — delete staged
- [ ] ...
- [ ] Checkpoint 3 committed

## Phase 4: WIRE ANDROID
- [ ] 4.1 Wire Android: update imports, DI, delete originals
- [ ] 4.2 Stub audit (scan for error(), TODO(), stub, = {} empty lambdas)
- [ ] 4.3 Koin binding completeness check (transitive, both platforms)
- [ ] 4.4 Android build + unit test — ALL tests pass
- [ ] 4.5 Runtime verify — per-screen: navigate, verify data loads, verify CTA, screenshot
- [ ] 4.6 Summary Table
- [ ] 4.7 mobile-mcp automated flows (real app, screen-map cached, blocker→ask user)
- [ ] 4.8 Manual test (remaining edge cases only)
- [ ] Checkpoint: Phase 4 Wire Android committed
- [ ] PROGRESS.md committed

## Phase 5: WIRE iOS
- [ ] 5.1 UI migration (per screen)
- [ ] 5.2 Wire iOS: imports, DI, SKIE, Koin iOS
- [ ] 5.3 Stub audit + Koin completeness check (iOS bindings)
- [ ] 5.4 iOS build + unit test — ALL tests pass
- [ ] 5.5 Runtime verify — per-screen: navigate, verify data loads, verify CTA, screenshot + Android parity
- [ ] 5.6 Summary Table
- [ ] 5.7 mobile-mcp automated flows (iOS, screen-map cached, blocker→ask user, Android parity)
- [ ] 5.8 Manual test (remaining edge cases only)
- [ ] Checkpoint: Phase 5 Wire iOS committed
- [ ] PROGRESS.md committed

## Final Verify
- [ ] All PROGRESS.md checkboxes marked [x]
- [ ] fake-server-config and screen-map in e2e-tests/ committed
- [ ] findings.md saved for next migration
```

Checkbox states: `[x]` = done, `[ ]` = pending, `[~]` = deferred (add inline reason).

---

## Session Gameplans

Session-scoped gameplans live at:

```
~/dev/gameplans/.sessions/<session_id>.active
```

Not a global `.active` file. Each session has its own scoped active file so concurrent sessions do not collide.

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
- **Base URL:** vault (uses buildVaultApiService)
- **API endpoints:** POST /api/auth/login, DELETE /api/auth/session
- **expect/actual:** none
- **Migrate after:** AuthCredentials.kt, TokenManager.kt
- **Consumers:** LoginUseCase.kt, LoginViewModel.kt (update imports after)
- **Rules:** keep `login(email)` and `login(phone)` as SEPARATE methods — DO NOT combine
```

See `references/agent-prompts/migration-guide-template.md` for the full template.

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

## Summary Table Step

Include a Summary Table before every manual test step (Wire Android and Wire iOS phases):

```markdown
## Summary Table: <phase-name>

| File | Promised (migration-guide.md) | Achieved | VERIFY result | Notes |
|------|------------------------------|----------|--------------|-------|
| LoginRepository.kt | login(email), login(phone) separate | login(email), login(phone) separate | VERIFY_PASS | — |
| LoginApi.kt | Retrofit→Ktor 3.1.0, same endpoints | Retrofit→Ktor 3.1.0, same endpoints | VERIFY_PASS | — |
```

Every row must have a VERIFY result. If any row is VERIFY_FAIL, fix it before manual test. The Wire iOS Summary Table adds an Android column for side-by-side parity comparison.

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

## Plan Quality Rules

- **Tasks must be atomic** — a single file or single logical change, retryable independently
- **Every task specifies exact file paths** — Create/Modify/Delete with full paths, no vague references
- **Every phase ends with a checkpoint commit** — the codebase is always in a buildable state
- **Checkpoint commits are MANDATORY** — but ONLY after build verification AND all tests pass. Never commit with failing builds or failing tests. Unit tests (`./gradlew :shared:testDebugUnitTest`) must be green before a checkpoint is valid.
- **PROGRESS.md committed after each phase** — not all at once at the end
- **A task is only marked `[x]` in PROGRESS.md after its verification step passes** — not before
- **Pre-check gates** — phases depending on unknowns get a Task X.0 PRE-CHECK that researches and updates PLAN.md with concrete paths before continuing (no approval pause)
- **Phase boundaries are by LAYER** — each phase corresponds to a distinct architectural layer (domain, data, platform API, expect/actual, tests). No task cap per phase; split by layer, not count. Large layers → sub-phases (3A, 3B).
- **FINDINGS.md is always the destination for research** — never inline external content or untrusted data into PLAN.md

---

## Safeguards and Key Risks

**Safeguards (always active):**
- grep-before-delete on any file removal
- verify-before-swap on any library substitution
- Escalate after 3 failures on any loop — never suppress errors
- Any project-specific constraints discovered during research go here

**Key Risks (include when non-obvious):**
- List risks with brief explanation of impact and mitigation

---

## Session Completion

- All phases in PROGRESS.md marked `[x]`
- fake-server-config and screen-map in `e2e-tests/` committed
- `findings.md` saved for next migration (Known Fixes, Gotchas, Library Versions)
- `migration-guide.md` and `PLAN.md` kept for reference or deleted per user preference
- **Device cleanup:** delete dedicated emulator AVD (`avdmanager delete avd -n <name>`) and iOS simulator (`xcrun simctl delete <UDID>`) that were allocated for this gameplan. Release ports.

---

## Build Verification Script

During Phase 1 (Task 1.11), generate a project-specific `build-verify.sh` in the gameplan directory. This script is tailored to the actual project — using the exact Gradle task names and xcodebuild commands verified in Task 1.10. The skill stays project-agnostic; the script is project-specific.

**Template** (adapt to the project's verified build commands):

```bash
#!/usr/bin/env bash
# build-verify.sh — Project-specific build verification
# Generated during Phase 1 planning. Uses verified task names.
# Usage: ./build-verify.sh [worktree-dir]
set -euo pipefail

WORKTREE="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$WORKTREE"

PASS=0; FAIL=0; FAILURES=""

run_check() {
  local cmd="$1"
  echo "--- Running: $cmd"
  local start=$(date +%s)
  local out=$(mktemp)
  if eval "$cmd" > "$out" 2>&1; then
    echo "    PASS ($(($(date +%s) - start))s)"
    PASS=$((PASS + 1))
  else
    local rc=$?
    echo "    FAIL (exit $rc, $(($(date +%s) - start))s)"
    tail -20 "$out" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAILURES="$FAILURES\n  - $cmd (exit $rc)"
  fi
  rm -f "$out"
}

# ── Verified build commands (from Task 1.10) ──
# Replace these with the actual verified commands for this project:
run_check "./gradlew :shared:compileDebugKotlin"
run_check "./gradlew :shared:compileKotlinIosArm64"
run_check "./gradlew :app:assembleDebug"
# run_check "xcodebuild -workspace iosApp/iosApp.xcworkspace -scheme iosApp -destination '...' build"

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && { echo -e "Failed:$FAILURES"; echo "BUILD_VERIFY_FAIL"; exit 1; }
echo "BUILD_VERIFY_PASS"
```

**Usage throughout all phases:**
```bash
<gameplan-dir>/build-verify.sh <worktree-dir>
```

The orchestrator calls this at every checkpoint. Only on `BUILD_VERIFY_FAIL` does it engage an LLM agent (debugger) to diagnose. This saves significant tokens on the happy path — builds are purely mechanical.
