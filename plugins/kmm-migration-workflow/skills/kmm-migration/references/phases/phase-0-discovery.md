# Phase 0 — Discovery & Scoping

**Purpose.** Convert natural-language intent into a confirmed, persisted migration session ready for Phase A.

**Inputs:** `.kmm/project.md`, sibling `.kmm/migrations/*/coverage.md` (cross-session ripple lookups), user's natural-language intent.

---

## Sub-phases

### 1. Capture intent
User invokes with natural language (e.g., *"migrate the funds screen to KMM"*).

### 2. Profile read + drift check
Scan repo against profile claims (modules in `settings.gradle`, plugins applied, source-set folders); surface mismatches; ask user to confirm updates via diff-confirm.

### 3. Determine which profile facts this migration needs
Driven by seed type and depth. Gap-fill missing facts: **auto-detect → confirm with user** where possible, ask user otherwise. Lazy growth — profile expands per session, not via one-shot interview.

### 4. Branch + worktree setup (if needed)
If user is on `main` or any non-`kmm/` branch:
- Capture feature + depth from user.
- Propose branch: `kmm/<feature>-<depth>` (e.g., `kmm/funds-business-logic`).
- Propose worktree path: `../<repo>-<branch-suffix>/` (default; configurable in `project.md`).
- User confirms → run `git worktree add <path> -b <branch>`.
- Tell user: *"Worktree ready at `<path>`. Open it in your editor and re-invoke the skill there to begin Phase 0."*
- **This invocation ends.** User re-invokes in the worktree; Phase 0 continues from step 5 there.

### 5. Seed resolution
**Primary path — navigation flow:** ask *"How do you navigate to that screen in the app?"* User describes (e.g., *"JumpTo menu → Funds → Fund screen"*). Sonnet subagent walks the navigation graph: app entry / main nav → JumpTo menu code → Funds menu item → its click/nav action → target screen. Confirm resolved file with user.

Why this beats grep: filenames lie, navigation paths don't. User flow is ground truth.

**Fallback path — functional:** if target isn't a screen, or user can't describe a navigation flow, ask for a file / class / package the user knows is part of the feature. Same confirmation gate. Equally valid path, not a downgrade.

### 6. Dep-graph walk per seed
Parallel Sonnet subagents from each seed. Bounds:
- Stop at stdlib (`kotlin.*`, `java.*`, `kotlinx.*`), Android (`android.*`, `androidx.*`), known KMM-native libs (Ktor, SQLDelight, Koin/Hilt runtime), generated code (KSP, Hilt-generated).
- Cycle detection.
- **Full DI traversal:** follow Hilt `@Provides`/`@Binds` and Koin module DSL to resolve interfaces to concrete impls. Static-types-only walk would miss the bottom half of the iceberg in this codebase.

**Walk reports confidence and unresolved bindings.** Example output: *"30 files via static + Hilt graph; 3 Koin DSL modules with dynamic logic — 2 unresolved bindings flagged for sanity check."* Skill admits limits; user sanity-checks before confirming. Koin DSL with dynamic logic / Hilt+Koin coexistence can hide bindings.

### 7. Classification
Haiku subagent. Each discovered file → one type per `test-discipline` taxonomy:
ViewModel / UseCase / Repository / RemoteStore / LocalStore / Mapper / Model / Interactor / Presenter / Composable / Worker / Receiver / Service / Other.

Signals: filename suffix, class hierarchy, path heuristics, content markers. Unclassifiable files flagged for user resolution.

### 8. Test + registry pass
Per file:
- Mirrored test file exists (y/n) — by `test-discipline` package-mirror convention.
- Already frozen elsewhere — scan sibling `.kmm/migrations/*/coverage.md` for matches. If found → flag *"already frozen by `<other-session>`; reuse the baseline rather than re-writing."*

**Target test source-set health check** (one-time, per session):
- **Test-compile state of `<dest>/androidUnitTest`.** All baselines land here in Phase B (uniform routing). Quick compile check; report clean / N broken (file list). Broken pre-existing tests are **quarantined via `@Ignore` in Phase B** (per `test-discipline §12 — Quarantine`), not fixed as part of this migration. `<dest>/commonTest` is not checked at Phase 0 — Phase E does its own pre-promotion check if any baseline migrates there.

### 9. Cross-feature ripple detection
For each in-scope file, count back-references from out-of-scope project files. Shared models / utilities used widely → flag prominently.

Each shared dep gets a **per-occurrence decision** (include in this session / hold back). The lens: *"which carries less behavioral-drift risk for untouched features?"* Tightly-coupled utilities used by many features default to hold-back; isolated ones default to include. **No default-include.**

### 10. Destination module discovery
- If profile has destination set → use it, confirm.
- Else: scan `settings.gradle*` for KMM-enabled modules (`kotlin("multiplatform")` plugin, conventional names like `:shared`, `:*-shared`, `:sniper`).
- Present found modules to user with brief descriptions; user picks. No hardcoded defaults — user always confirms.
- **Sanity-check chosen module's source sets.** Must have at minimum: `commonMain`, `commonTest`, `androidMain`, `androidUnitTest`. Phase B targets `androidMain` + `androidUnitTest` uniformly; Phase D / E target `commonMain` + `commonTest` for files migrating this session (per Phase A's plan). If any of the four is missing, flag as out-of-skill setup and ask user to configure the module first before this session continues.
- *"Create new"* → flagged as out-of-skill setup task; skill stops and points user at it.
- Record choice in scope.md and (if first time) in project.md.

### 11. Present manifest + depth question
**Depth options:**
- Business logic only — UseCase, Repository, RemoteStore, LocalStore, Mapper, Model
- + ViewModel — above + ViewModel, Presenter, Interactor
- + UI — above + Composables/Pages
- Custom — manual pick

Filter manifest by depth.

**Manifest review = deselect, not approve.** All classified files in selected layers are in-scope **by default**. User scans the manifest and **removes** files that shouldn't be in this session. Faster than per-file approval. Per-file adjustments here, before confirming. *Depth is a starting filter, not a fence* — "Custom" is the same UI without the pre-filter.

### 12. Confirm scope
Hard gate: scope + depth + destination + per-ripple decisions all user-confirmed before Phase A.

---

## Output: `scope.md`

Living document, written progressively. Contains:

- Intent (user's original request)
- Navigation flow used for seed resolution (or fallback rationale)
- Seed files (resolved)
- Full manifest (categorized by layer: UI / Presentation / Domain / Data / Platform)
- Dep-walk confidence report (resolved + unresolved bindings)
- Depth selected
- Destination module
- Per-ripple decisions (include / hold back, with reasoning)
- Per-file deselections made during manifest review
- Platform deps encountered
- **Pre-existing test-compile state in `<dest>/androidUnitTest`** (clean / N broken; action: @Ignore in Phase B per `test-discipline §12 — Quarantine`)
- Tasks (checklist)
- Decisions log (chronological)
- Status

---

## Phase-specific gates

Beyond universals:

- **Scope is locked once user confirms.** Adding a file later isn't a Phase 0 reopen — it's either a new session or an explicit `update scope` action that re-walks deps from the new file. Prevents silent scope drift. The scope-creep traceability gate (SKILL.md cross-cutting rules) enforces this at every action in later phases.
