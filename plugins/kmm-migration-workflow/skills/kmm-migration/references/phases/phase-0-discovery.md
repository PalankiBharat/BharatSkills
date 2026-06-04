# Phase 0 — Discovery & Scoping

**Purpose.** Convert natural-language intent into a confirmed, persisted migration session ready for Phase A.

**Inputs:** `.kmm/project.md`, sibling `.kmm/migrations/*/coverage.md` (cross-session ripple lookups), user's natural-language intent.

---

## Sub-phases

### 1. Capture intent
User invokes with natural language (e.g., *"migrate the funds screen to KMM"*).

### 2. Profile read + drift check
Scan repo against profile claims (modules in `settings.gradle`, plugins applied, source-set folders); surface mismatches; ask user to confirm updates via diff-confirm.

**iOS-project-state probe (one-time per repo; informs every seam decision downstream).** Before recommending any seam strategy, check whether the repo has a real iOS consumer: an Xcode project, CocoaPods/SPM setup, an existing `:shared` framework link. This materially changes the right answer — **a real iOS app means invest in genuine KMP (shared infrastructure), while no-iOS-yet makes thin commonMain interfaces with Android-only concretes acceptable.** A prior session only surfaced this when the user asked; it flipped the whole seam strategy. Record the finding in `project.md` (iOS consumption / distribution flow).

### 3. Determine which profile facts this migration needs
Driven by seed type and depth. Gap-fill missing facts: **auto-detect → confirm with user** where possible, ask user otherwise. Lazy growth — profile expands per session, not via one-shot interview.

### 3.5. Build-config access scope probe
Per `project.md` canonical field `networking.build_config_scope` (see SKILL.md). For each generated build-time config object (BuildKonfig, BuildConfig, or generated-constants equivalent) referenced by the seed graph:
- Determine access scope: `internal` / `module-private` / `public`. Inspect declaration site.
- If `internal` (or otherwise inaccessible from the app layer where DI providers are wired), enumerate the public constant aliases the app layer must use instead — typically grouped in a DNS-style constants file at the module's androidMain or commonMain boundary.
- Record under `networking.build_config_scope` per the canonical schema. Diff-confirm the addition.
- Skipped silently if `networking.build_config_scope` already covers all objects encountered.

This is a one-time per repo capture for objects the migration touches. Prevents the compile-error iteration of wiring DI providers against an inaccessible config object — Phase D consults the field when drafting providers.

### 4. Branch + worktree setup (if needed)
If user is on `main` or any non-`kmm/` branch:
- Capture feature + depth from user.
- Propose branch: `kmm/<feature>-<depth>` (e.g., `kmm/funds-business-logic`).
- Propose worktree path: `../<repo>-<branch-suffix>/` (default; configurable in `project.md`).
- User confirms (one line) → run `git worktree add <path> -b <branch>`.
- Skill runs `cd <path>` (Bash, sticks for the rest of the session) and announces *"Worktree at `<path>`. Continuing Phase 0 here."*
- **Verify `local.properties` exists (`sdk.dir`) before any gradle gate.** A fresh worktree doesn't inherit it; if absent, create it from `$ANDROID_HOME` or copy the primary worktree's — a missing `sdk.dir` blocks the entire Phase B entry gate (it cost a whole gate-failure cycle in a prior session).
- **Phase 0 continues in this same conversation** at step 4.5. No re-invocation needed.

### 4.5. `.gitignore` bootstrap
- Skill reads the repo's top-level `.gitignore`.
- If `.kmm/migrations/` is absent, propose appending it. One-time, diff-confirmed (this is a repo-level config touch, worth one prompt).
- Result: `.kmm/project.md`, `.kmm/searches/`, `.kmm/exceptions/` tracked; `.kmm/migrations/<feature>/*` local-only.
- Skipped silently if the entry already exists.

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

**Standard sweeps in the dep-walk output (all five mandatory — surfaced late in prior sessions, so they're now standard, not discovery-on-demand):**
- **Platform-specific logger sweep.** Catalogue `Timber` / `Log` / Logcat / `NSLog` usage across the reachable set, alongside ObjectBox/Firestore/DataStore, as a standard Android-only blocker. (Timber surfaced only on a third pass in *both* sessions.)
- **DI-qualifier enumeration.** List the Hilt/Koin qualifier annotations on the reachable graph (e.g., `@Live`, `@Practice`, `@*Sync`) — they shape Phase A's seam/DI design and the platform-ownership decision (SKILL.md / Phase A 1.6).
- **Final-class-without-interface flag.** Flag in-scope files whose dependencies are concrete `final` classes with no interface (grep `class X(` not `open`/`interface`/`abstract`) — these block clean baselining of their consumers and need a pre-baseline interface seam. (Caught two consumers at Phase B-time in a prior session.)
- **Static-singleton reachability sweep.** Grep in-scope SUTs for static / service-locator access (`BaseApplication.instance`, `*.getInstanceId`, `UserModel.<static>`) reachable from **public entry points or top-level functions** — not just constructor deps. A hidden `BaseApplication.instance` reached via a top-level `track()` call slipped past triage and surfaced only at runtime in a prior session. These statics block clean baselining and need an inject-the-collaborator seam.
- **Transitive display-model blocker scan.** When a business-logic file references a VM-co-located or view-data type, flag embedded domain models (Chart-style: mutable cached state, `@Stable` misuse, `java.util.Date` entanglement) that would block iOS-readiness — don't wait for the user to ask "what is X doing?".

### 6.5. Ground-truth live-vs-dead reachability (before locking scope)
A Phase-0 dead-code misclassification is expensive: a live OTP ViewModel chain wrongly excluded forced a mid-Phase-A re-scope that roughly doubled the analysis. Settle live-vs-dead **here**, not at Phase A.

- **Trace the nav graph to confirm each seed-reachable file is actually live** (a real navigation path reaches it), not orphaned/legacy code that merely still compiles.
- **Any "this is dead" claim must rest on a multiline-aware search, never a single-line grep.** Builder-style call sites span newlines (`WithdrawalModel\n  .create()`), so a per-line grep counts zero callers and reports a live symbol as dead. Use `rg -U` / a multiline pattern before classifying a static accessor or model method dead — a wrong "dead" nearly baked into the plan in a prior session.
- **When two dep-walks disagree on a path** (e.g. a live `:app` chain vs a dead `:library` store), run a dedicated verification subagent to resolve it **before** presenting the manifest — don't let a contested reachability claim corrupt scope.
- **For seeds with known legacy variants** (auth/login, checkout, onboarding — areas that commonly accrue multiple historical flows), explicitly ask the user *"which of these flows are dead?"* up front. Dead code routinely dominates the first walk; the user knows which paths were retired.

Resolved live/dead status feeds the manifest (sub-phase 11) and the per-ripple decisions (sub-phase 9).

### 7. Classification
Haiku subagent. Each discovered file → one type per `test-discipline` taxonomy (see `test-discipline/index.md`):
ViewModel / UseCase / Repository / RemoteStore / LocalStore / Mapper / Model / Interactor / Presenter / Composable / Worker / Receiver / Service / Other.

Signals: filename suffix, class hierarchy, path heuristics, content markers. Unclassifiable files flagged for user resolution.

### 8. Test + registry pass
Per file:
- Mirrored test file exists (y/n) — by `test-discipline/index.md` package-mirror convention.
- Already frozen elsewhere — scan sibling `.kmm/migrations/*/coverage.md` for matches. If found → flag *"already frozen by `<other-session>`; reuse the baseline rather than re-writing."*

**Target test source-set health check** (one-time, per session):
- **Compile BOTH candidate baseline source sets — `<dest>/androidUnitTest` AND `:app/src/test/`.** The B-strategy (relocate-first vs baseline-in-place) isn't chosen until Phase B, and baseline-in-place writes to `:app/src/test/` — so checking only `<dest>/androidUnitTest` misses pre-existing breakage in the other candidate. **Run the actual test-source-set compile** (e.g. `:app:compileProductionDebugUnitTestKotlin` for the flavored app set + the `<dest>` equivalent), not just an import scan; report clean / N broken (file list) per set. This surfaces pre-existing compile-broken tests **and** a missing `local.properties` at discovery — both blocked the Phase B entry gate in a prior session because the compile was deferred to it. Broken pre-existing tests are **quarantined via `@Ignore` (run-broken) or a build-level exclude (compile-broken) in Phase B** (per `test-discipline/migration-baselines.md` (Quarantine section)), not fixed as part of this migration. `<dest>/commonTest` is not checked at Phase 0 — Phase E does its own pre-promotion check if any baseline migrates there.

### 9. Cross-feature ripple detection
For each in-scope file, count back-references from out-of-scope project files. Shared models / utilities used widely → flag prominently. **Subagent-mediated** (Haiku, parallel) — raw `grep` output stays in the subagent; main thread receives only the per-file back-reference count + flagged shared deps (per SKILL.md Subagent-mediated exploration).

Each shared dep gets a **per-occurrence decision** (include in this session / hold back). The lens: *"which carries less behavioral-drift risk for untouched features?"* Tightly-coupled utilities used by many features default to hold-back; isolated ones default to include. **No default-include.**

### 10. Destination module discovery
- If profile has destination set → use it, confirm.
- Else: scan `settings.gradle*` for KMM-enabled modules (`kotlin("multiplatform")` plugin, conventional names like `:shared`, `:*-shared`, `:sniper`).
- Present found modules to user with brief descriptions; user picks. No hardcoded defaults — user always confirms.
- **Base the recommendation on the deep dep-walk (sub-phase 6), not a shallow interface-location scan.** Where the *interfaces* sit is not where the real data/domain layer lives — recommend the destination from where the dep-walk found the actual reachable code, else a shallow "the funds interfaces are in `:shared`" read mis-locates it and forces a corrective round-trip after the deeper walk.
- **Sanity-check chosen module's source sets.** Must have at minimum: `commonMain`, `commonTest`, `androidMain`, `androidUnitTest`. Phase B targets `androidMain` + `androidUnitTest` uniformly; Phase D / E target `commonMain` + `commonTest` for files migrating this session (per Phase A's plan). If any of the four is missing, flag as out-of-skill setup and ask user to configure the module first before this session continues.
- **Enumerate legacy / non-target test source sets.** List every test source set under `<dest>` (e.g., `src/test/`, `src/androidTest/`, `src/sharedTest/`, plus any double-nested patterns specific to this repo's layout). For each one NOT in the migration target set (`androidUnitTest`, `commonTest`), record in `scope.md` as `legacy test dir — exempt from Phase C detekt enforcement` with its path. Phase C.2 reads this list to pre-fill the detekt rule's exclude paths. No assumptions — enumeration is mechanical (`find <dest>/src -type d -name 'test' -o -name '*Test'`), and every entry not in the target set is treated as legacy by default unless the user marks it as in-scope.
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

**Frame the manifest by iOS outcome, not file counts.** Lead with *"what iOS gets vs doesn't get"* per file/layer — concrete user-visible outcomes drive better scope decisions than file-count abstractions (a prior session repeatedly pushed back on count-based framing). Include an explicit **"already in commonMain (no-op)"** section so the user can see what new value this session delivers vs what's already shared.

### 12. Confirm scope
Hard gate: scope + depth + destination + per-ripple decisions all user-confirmed before Phase A.

### 13. Phase 0 retro
Before marking Phase 0 complete, amend `.kmm/migrations/kmm/<feature>-<depth>/retro.md` with a `## Phase 0 — Discovery & Scoping (captured YYYY-MM-DD)` section: five-bullet structure per SKILL.md (recap / smooth / stuck / could-improve / user steering log). **Blocking, non-skippable** (per SKILL.md Retro gate). Purely reflective — no skill/drop verdicts.

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
- **Pre-existing test-compile state in `<dest>/androidUnitTest`** (clean / N broken; action: @Ignore in Phase B per `test-discipline/migration-baselines.md` (Quarantine section))
- **Legacy / non-target test source sets** (paths exempt from Phase C detekt enforcement; consumed by phase-c-freeze.md C.2 drafter)
- Tasks (checklist)
- Decisions log (chronological)
- Status

**No counts in section headers.** Write `### Repositories`, not `### Repositories (11)`. Hand-written counts drift from their lists as scope evolves mid-phase; the headers stay correct only by accident. A single total line at the top of scope.md (`Total: N files`) can be auto-computed by re-counting the manifest at write-time — never typed by hand.

---

## Phase-specific gates

Beyond universals:

- **Scope is locked once user confirms.** Adding a file later isn't a Phase 0 reopen — it's either a new session or an explicit `update scope` action that re-walks deps from the new file. Prevents silent scope drift. The scope-creep traceability gate (SKILL.md cross-cutting rules) enforces this at every action in later phases.
