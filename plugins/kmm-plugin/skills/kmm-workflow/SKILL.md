---
name: kmm-workflow
description: >
  KMM module migration orchestrator. ALWAYS invoke for module-level KMM migrations or migration plans.
  Do not run /kmm or /gameplan directly for module scope — use this skill first.
argument-hint: "<module-path-or-description>"
---

## Quick Start

For module-level KMM migrations only. Single-file migrations → use `/kmm migrate` directly.

1. `/kmm-workflow <module-path-or-description>` — runs full Phase A → B → C
2. Handles: file discovery → classification → gameplan creation → autonomous execution
3. Phases: Assess → Plan (via /gameplan) → Execute (batched parallel)

## When to Use Reference Files

- `references/batched-execution.md` — read during Phase C before launching parallel agents
- `references/feedback-capture.md` — read when creating feedback files in Phase 0
- `../kmm/references/dependency-map.md` — read during Phase A classification

---

## Workflow

### Phase A: Assess

Inline assessment — does NOT invoke /kmm assess as a sub-skill. Uses the
**Anchor → Crawl → Verify** discovery algorithm from `/kmm assess`.

**Workflow — copy and track:**
- [ ] Step 1: Discover files (Anchor → Crawl → Verify)
  - [ ] Determine if input is directory path or feature name
  - [ ] Find anchors — grep for directories/files matching feature name
  - [ ] Ask user: "Are these the right starting points? Any other names for this feature?"
  - [ ] Crawl imports recursively (stop rule: fanout ≥ 3 = shared infra, stop)
  - [ ] Reverse grep — find who imports each discovered file from outside the set
  - [ ] Cross-module check — check :shared/{commonMain,iosMain,androidMain} for existing versions
- [ ] Step 2: Classify each file
  - `migrate-pure` — pure Kotlin, no Android deps
  - `migrate-swap` — needs library replacement (ref: dependency-map.md)
  - `migrate-expect-actual` — needs expect/actual
  - `platform-stay` — stays on Android (note as /kmm swift-screen reference)
  - `wire-only` — DI/navigation rewiring only
- [ ] Step 3: Build assessment
  - [ ] Map internal dependencies between discovered files
  - [ ] Map external dependencies — flag blockers not in KMM
  - [ ] Determine bottom-up migration order
  - [ ] Identify library replacements and risks
  - [ ] Completeness check: classified count = discovered count
- [ ] Step 4: Present and confirm
  - TO MIGRATE: files grouped by layer with classification
  - ALREADY IN KMM: files in shared module with parity status
  - CONSUMERS TO UPDATE: files that import from this feature
  - EXTERNAL DEPS: shared infra excluded by fanout rule
  - User reviews and confirms (or adjusts scope)

### Phase B: Plan

**Workflow — copy and track:**
- [ ] Task 0.1: Write ASSESSMENT.md
  - [ ] Create `<gameplans-dir>/ASSESSMENT.md` as a file — do NOT pass this data inline
  - [ ] Content template:
    ```
    # Assessment: <module-name>

    ## Files to Migrate
    | File | Layer | Classification | Notes |
    |------|-------|---------------|-------|
    | ...  | ...   | ...           | ...   |

    ## Dependency Map
    (internal dependencies between files in this migration set)

    ## Migration Order
    (bottom-up order derived from dependency map)

    ## External Dependencies
    (shared infra excluded by fanout rule — flag any blockers not in KMM)

    ## Risks
    (library replacements, expect/actual complexity, consumer impact)
    ```
- [ ] Task 0.2: Create feedback files
  - [ ] Create `<gameplans-dir>/KMM_FEEDBACK.md` with header:
    ```
    # KMM Feedback
    <!-- KMM skill gaps: missing patterns, dep map holes, test gotchas -->
    ```
  - [ ] Create `<gameplans-dir>/KMM_WORKFLOW_FEEDBACK.md` with header:
    ```
    # KMM Workflow Feedback
    <!-- Assessment accuracy: misclassifications, missed files, parallelism issues -->
    ```
  - [ ] Create `<gameplans-dir>/GAMEPLAN_FEEDBACK.md` with header:
    ```
    # Gameplan Feedback
    <!-- Planning/execution: build issues, checkpoint problems, escalations -->
    ```
- [ ] Invoke `/gameplan create` via the Skill tool with context:
  - [ ] Task description: "Migrate [module] to KMM — [summary]"
  - [ ] Build verification: the 3 KMM platform builds:
    ```
    ./gradlew :app:compileProductionDebugKotlin --no-configuration-cache
    ./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
    xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp -destination 'platform=iOS Simulator,name=iPhone 16e' build
    ```
  - [ ] Assessment data: reference `<gameplans-dir>/ASSESSMENT.md` by file path — do NOT inline the full content
  - [ ] Phase mapping rules (layer-based, not task-count based)
- [ ] Inject KMM-specific PLAN.md header (see PLAN.md Header Template section below)
- [ ] Gameplan asks clarifying questions → produces PLAN.md + PROGRESS.md

**Phase mapping rules:**
- Each assessment layer → one gameplan phase
- `migrate-pure` files within a phase → parallelizable batch
- `migrate-swap` / `migrate-expect-actual` → check dependencies for batch grouping
- `platform-stay` screens → separate phase after all migration (for `/kmm swift-screen`)
- `wire-only` files → final phase (with `/kmm audit`)
- Phase boundaries are by LAYER, not task count. No 7-task cap.

**Per-task instructions:**
- `migrate-*` files → `/kmm migrate` (steps 1-7 only within batched execution)
- iOS screens → `/kmm swift-screen`
- Library swaps → reference `/kmm deps` for patterns
- Final phase → `/kmm audit` on entire migrated module + wiring + cleanup
- Mandatory final phase: Completeness Verification (Phase N+1)

### Phase C: Execute (Feedback Loop)

Gameplan's autonomous execution loop takes over.
See `references/batched-execution.md` for the full execution model.

**Simplified Mode vs Full Batched Mode:**

| Condition | Mode | What it means |
|-----------|------|---------------|
| All files in the phase are independent (no intra-phase dependencies) | **Simplified** | Parallel agents → one compile check at the end |
| Files have behavioral dependencies on each other within the phase | **Full Batched** | baseline → migrate → re-test per batch |

Use **Simplified Mode** when every file in a phase can be migrated without depending on another
file in the same phase. The baseline→migrate→re-test cycle exists to catch regressions caused
by inter-file dependencies; it adds no value when files are truly independent.

Use **Full Batched Mode** when files in a phase share behavior — e.g., a repository depends on
a store being migrated in the same phase.

**Simplified Mode execution:**
1. **PARALLEL AGENTS** — each agent migrates its file fully (Steps 1-7, no Gradle)
   - Inject the Guardrail Cheat Sheet from `/kmm` SKILL.md into each agent's prompt as a lightweight
     alternative to full `/kmm` skill invocation
   - Agent reports: "migrated, ready for compile check"
2. **COMPILE CHECK** — single `./gradlew :shared:testDebugUnitTest` across all migrated files
   - If red → identify which migration caused it → fix → re-run
3. Phase complete → **CHECKPOINT** (3-platform build → commit → next phase)

**Full Batched Mode execution:**
1. **PARALLEL AGENTS** — Steps 1-4 (read, assess, stage, write tests) → no Gradle
   - Inject the Guardrail Cheat Sheet from `/kmm` SKILL.md into each agent's prompt as a lightweight
     alternative to full `/kmm` skill invocation
2. **BASELINE** — single `./gradlew :shared:testDebugUnitTest` → must ALL pass
   - If red → fix tests (only time allowed) → re-run
3. **PARALLEL AGENTS** — Step 6 (migrate to commonMain) → no Gradle
4. **RE-TEST** — single test run → must pass WITHOUT test changes
   - If red → fix migration → re-run
5. Phase complete → **CHECKPOINT** (3-platform build → commit → next phase)

---

## Mid-Flight Discovery (Conditional)

**Unmapped file found?** → Agent STOPS → orchestrator classifies → updates ASSESSMENT.md + PLAN.md + PROGRESS.md → resumes
**Wrong classification?** → Agent reclassifies → updates plan → notes in PROGRESS.md → no user escalation
**External dependency blocker?** → **STOP** → escalate to user with options: (a) migrate dep first, (b) create interface/expect-actual, (c) skip for now

---

## Completeness Verification (Mandatory Final Phase)

**Phase N+1 — copy and track:**
- [ ] Orphan scan: glob original module path — any .kt files still there?
- [ ] Import scan: grep entire codebase for old import paths (any hits = incomplete)
- [ ] Consumer update check: verify every consumer's imports point to shared module
- [ ] Assessment vs Progress: file counts must match
- [ ] Full test suite: ALL tests (catches consumer regressions)
- [ ] 3-platform build: final full verification
- [ ] Report: "Migration complete: X/Y files migrated, Z consumers updated, 0 orphans" OR "INCOMPLETE: [gaps]" → add remediation tasks

---

## PLAN.md Header Template

When generating PLAN.md via `/gameplan create`, inject this KMM-specific header:

```
KMM-SPECIFIC INSTRUCTIONS:
- BATCHED PARALLEL execution: phases split into batches of independent files
- Per batch: parallel agents do Steps 1-4 (Read→Assess→Stage→Write Tests), then ONE baseline,
  then parallel agents do Step 6 (Migrate), then ONE re-test. Steps 8-10 at phase level.
- Tests go in commonTest. Hand-written fakes go in commonTest alongside tests.
- Gradle runs are BATCHED: 1 baseline + 1 re-test per batch (not per file).
  Single :shared module = Gradle serializes, so batching is faster than per-file.
- iOS screen tasks use /kmm swift-screen
- Library swaps reference /kmm deps for patterns
- Final audit uses /kmm audit on entire migrated module
- Phase boundaries are by LAYER, not task count. No 7-task cap.
- Assessment details: see ASSESSMENT.md in this directory
- FEEDBACK: Write to KMM_FEEDBACK.md, KMM_WORKFLOW_FEEDBACK.md, or GAMEPLAN_FEEDBACK.md
  when you encounter surprises, misclassifications, missing patterns, or gotchas.
  Format: ### [Phase N, Task] — YYYY-MM-DD | **Category:** [classification-miss |
  missing-pattern | dep-map-gap | test-gotcha | build-issue | escalation | new-gotcha] |
  **What happened:** [description] | **How resolved:** [fix] |
  **Suggestion for skill:** [what to add/change in which reference file].
  Append-only, write immediately.
```

---

## Feedback Capture

See `references/feedback-capture.md` for the three feedback files (KMM_FEEDBACK.md, KMM_WORKFLOW_FEEDBACK.md, GAMEPLAN_FEEDBACK.md), trigger table, entry format, and rules. Files created in Phase 0 alongside PLAN.md.

---

## Manual Testing Loop (Feedback Loop)

After completeness verification passes (Phase N+2):

1. Tell user: "Automated migration complete. Ready for manual testing."
2. **Loop until user says "done testing":**
   - [ ] User reports bug → run `/kmm bugfix` workflow
   - [ ] Update PROGRESS.md with bug entry
   - [ ] Write to MANUAL_TESTING.md in gameplans directory
   - [ ] Collect proposed graduations for batch review
3. **Exit signal:** User says "testing complete" or "done testing"
4. **Batch graduation:**
   - [ ] Review all MANUAL_TESTING.md entries
   - [ ] Group similar entries
   - [ ] Present all proposed reference file updates at once
   - [ ] User approves/rejects each
   - [ ] Apply approved updates
5. **Final checkpoint:** commit reference file updates + bug fixes
6. **Report:** "Manual testing complete: N bugs fixed, M learnings graduated"

**Rules:** Each bug fix = separate PROGRESS.md task. MANUAL_TESTING.md = append-only. Graduations batch at end. Reference updates included in same branch/PR.

---

## Post-flight Check

Migration is complete when ALL pass:
- [ ] Every file from ASSESSMENT.md accounted for in PROGRESS.md
- [ ] All `migrate-*` files in commonMain with passing tests (no stubs, no `@Ignore`)
- [ ] All `platform-stay` screens have SwiftUI equivalents
- [ ] All `wire-only` files rewired for both platforms
- [ ] Completeness verification: 0 orphans, 0 stale imports
- [ ] Full 3-platform build passes
- [ ] `/kmm audit` passes on migrated module
- [ ] Feedback files written and reviewed
