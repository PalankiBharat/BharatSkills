# Phase B — Structural Relocation + Baseline Coverage Audit & Write

**Purpose.** Move every in-scope file uniformly from `:app` to `<dest>/androidMain` (structural — zero Kotlin-semantic change), then produce the frozen baseline test suite that proves current Android behavior, survives the migration (KMM-portable stack only), and catches divergence post-migration. **Longest phase by token count; strongest equivalence guarantee in the workflow.**

Relocation happens first because it preserves behavior trivially (`git mv` + consumer-import update, no Kotlin changes). Baselines are then written against the relocated code in the destination module's `androidUnitTest` source set — the same module where they'll live through Phase E.

**Inputs:** `scope.md`, `plan.md`, `audit.md` (if resuming), `project.md`, `coverage.md`, **`references/test-discipline/index.md` and `references/test-discipline/migration-baselines.md` (mandatory — load at Phase B startup)**, plus **`references/test-discipline/<type>.md` per in-scope file type** (loaded on demand as each batch is processed — never bulk-load all per-type files).

Phase B execution **must** load `references/test-discipline/index.md` and `references/test-discipline/migration-baselines.md` before any audit or test-writing work. Together they contain: Toolbox + decision matrices + cross-cutting rules + file-level skeletons + KMM-portable stack rules (in `index.md`), and the denylist + feature-surface pattern + broken-test quarantine + migration-exception process (in `migration-baselines.md`). Per-type checklists and templates (`viewmodels.md`, etc.) are loaded per-batch as the audit/write loop reaches each file type — **subagent-mediated per cross-cutting rules** if multiple per-type files would otherwise enter main context simultaneously.

---

## Sub-phases

### B.0 — Source-set bootstrap (preempt classpath gaps)

Before any baseline writing, apply the SUT test-classpath gaps surfaced in Phase A (`plan.md` → SUT test-classpath gaps section):

- For each gap (e.g., `retrofit2.HttpException` referenced by an in-scope SUT, `androidx.paging.PagingData` in a Paging-using SUT), add the missing `testImplementation` dep to `<dest>/build.gradle.kts` under `androidUnitTest` (and `commonTest` if applicable).
- Run `:<dest>:compileDebugUnitTestKotlin` (or project-specific task) to confirm the test source set compiles before any baseline lands.
- If any gap was missed in Phase A and surfaces mid-B.4, this sub-phase reopens — but the goal is zero retroactive `testImplementation` adds during B.4.

Skipped silently if Phase A reported zero gaps.

### B.1 — Structural relocation (uniform `git mv`)

For each in-scope prod file (parallel Haiku):

- `git mv :app/src/main/.../X.kt <dest>/src/androidMain/.../X.kt`
- Package declaration updated to the new path (Haiku).
- Consumer imports in `:app` updated for every reference to the moved file (Sonnet drafts the FQN search-replace plan, Haiku applies).

This step is **pure structural** — no Kotlin-semantic changes, no edits to function bodies. Behavior preserved trivially. Build must remain green throughout; if it doesn't, something other than a relocation happened — pause and investigate.

Existing tests for moved files stay in `:app/src/test/...` for now (with their imports updated to the new package). Their fate is decided in B.3 (audit).

`coverage.md` updated: in-scope files flip to `relocated` status (per-batch).

Commits follow the two-commit cadence (SKILL.md): code commit ("relocation only, no semantic change") + audit commit (`chore(kmm): audit update — B.1 relocation`). Autopilot, one-line announcements.

### B.2 — Quarantine pre-existing broken tests (Haiku)

Per Phase 0 step 8's broken-test discovery in `<dest>/androidUnitTest`:

- For each pre-existing broken test, apply `@Ignore("<one-line reason>; see PR out-of-scope follow-ups")`.
- Per `test-discipline/migration-baselines.md` (Quarantine of unrelated broken tests).
- Non-judgmental — does not assert the test is bad, only that fixing it is not this migration's job.

After this step, `<dest>/androidUnitTest` compiles clean — ready for baselines to be written.

If Phase 0 reported clean (no broken pre-existing tests), this sub-phase is skipped.

### B.3 — Audit existing tests (parallel Sonnet per file)

For each in-scope file with an existing test (currently in `:app/src/test/...` post-B.1):

- Read every test by name (Haiku does the parse).
- Score on three dimensions:
  - **Coverage %** — checklist items from `test-discipline/<type>.md` hit by existing tests, cited by test name (Sonnet scores).
  - **Migration-safety %** — pass against `test-discipline/migration-baselines.md` denylist (MockK, Mockito, Truth, Robolectric, `@get:Rule`, `org.junit.runner.*`, `java.time.*`, `System.currentTimeMillis`, `MainCoroutineRule`, etc.). Haiku scans imports; Sonnet judges edge cases. **A test using MockK lands a hard 0 on this dimension** — MockK is now banned in baseline source sets (per the updated denylist), so a MockK-based test cannot be trusted as a baseline. Verdict for MockK-using existing tests is **Rewrite**.
  - **Bug-catching power %** — proven by deliberate-breakage mutation (see B.5); for existing tests, run the menu mutation now.
- **Trust score = min(coverage%, migration-safety%, bug-catching%).** Forces explicit reasoning per dimension.
- **Verdict: Trust / Augment / Rewrite**, citing specific test names + checklist items + denylist hits as evidence.

**Verdict outcomes:**

- **Trust** — existing test is suitable as a baseline. `git mv :app/src/test/.../XTest.kt <dest>/src/androidUnitTest/.../XTest.kt`. Update package; update any imports. Per-test fixtures travel with the test (move from `:app/src/test/.../fixtures/` to `<dest>/src/androidUnitTest/.../fixtures/` if exclusively used by the moved tests; otherwise duplicate the needed factories).
- **Augment / Rewrite** — existing test stays in `:app/src/test/` as regression cover (not a baseline). New baseline written in `<dest>/androidUnitTest/` per B.4.

Recorded per file in `audit.md`.

### B.4 — Write missing baselines

**Parallelism (per SKILL.md Smart subagent routing — NON-NEGOTIABLE):** parallel **Sonnet subagents**, one per file in the current batch, dispatched in a single orchestrator turn. Complex files in the shortlist below go to **Opus subagents** (still parallel across independent files; never the orchestrator). The orchestrator never authors a baseline test itself — subagent failure triggers another subagent, not a main-thread fallback.

**Defer-to-Phase-D shortlist (no Phase B baseline):**
- Files classified `lib-swap: path-b` in `plan.md` (SUT public surface unavoidably exposes lib-specific types).
- Files with static-service-locator dependencies (e.g., `UserModel.getUcc()`) that can't be injected without an upstream refactor.
- Pure data classes with no logic (per `test-discipline/models.md`), pure interfaces (per repositories.md / usecases.md), pure-factory UseCase impls.

For each deferred file: write a `## Followup: <file>` entry to `phase-d-followups.md` with `**Source row:**` (audit row), `**Reason:**` (which deferral rule), `**Proposed action:**` (write baseline against migrated impl at Phase D / inject IUserQueryRepository / etc.), `**Status:**** open`. Skip baseline. coverage.md row flips to `audited` with `baseline-deferred-to-phase-d` in the baseline-path column.

For files with audit verdict `Augment` / `Rewrite` or no existing test (and not on the defer shortlist):

- **Routine (Sonnet subagent, parallel per batch):** UseCase, Mapper, Model, RemoteStore (Path A), simple Repository, simple Presenter.
- **Complex (Opus subagent, parallel where independent):** concurrency-heavy Interactor, multi-source cache Repository, state-machine Presenter, anything plan.md flagged high-stakes.

Per file:
- Identify file type → load `test-discipline/<type>.md` (checklist + template + KMM-portable stack).
- Write the baseline in `<dest>/src/androidUnitTest/.../XTest.kt` using **kotlin.test + hand-rolled fakes + Turbine** (per `test-discipline/migration-baselines.md` — MockK is banned; fakes only).
- For `lib-swap: path-a` files, write the baseline against SUT output **without referencing the old-lib types** (MockWebServer for HTTP, hand-rolled fakes for date/time, round-tripped objects for serializers — see `test-discipline/migration-baselines.md` §Library-substitution).
- **Apply principle #2 (clean code):** no test-only `*Holder` / `*Manager`; fakes earn their existence (≥2 consumers or required for KMM portability).
- **Self-review before presenting.** Notes captured.

**Do not print test bodies into the session.** Write the file, then point at the path in one line (`Wrote XTest.kt — 4 cases, all red`). Trust comes from the test running red (B.5), not from user inspection of the body in chat. If the user wants to inspect, they open the file. Same for mutations (B.5): summarize what mutated and the failure message, never paste diff or test code.

Per-batch close: coverage.md rows for the just-written batch flip from `relocated` to `audited` (not deferred to B.7). Two-commit cadence applies — code commit + audit commit.

### B.5 — Prove red-on-breakage (per new or rewritten test)

**Non-negotiable.** A test that doesn't go red on a deliberate breakage is tautologically green — useless as a baseline.

For each new or rewritten test:
1. Apply a deliberate breakage from the **per-file-type menu**:

| File type | Mutation |
|---|---|
| ViewModel | Flip a state-emission condition; null the error mapping |
| UseCase | Invert a `when` branch; corrupt an output field |
| Mapper | Drop a field; change a fallback value |
| Repository | Skip cache invalidation; return stale on warm read |
| RemoteStore | Change URL path; skip `invalidate(url)` |
| LocalStore | Skip the insert; return wrong row |
| Interactor | Skip listener notification; corrupt state transition |
| Presenter | Wrong color/label for a state; conflate distinct states |

2. Run the test → must go **RED**.
3. Revert breakage via `git restore` → must go **GREEN**.
4. Record proof in audit.md (mutation, failure output, revert, success).

Reviewer can reproduce by re-applying the standard mutation. No vibes.

### B.6 — Feature-surface baselines (Opus subagent; parallel across independent feature surfaces)

Dispatched as **Opus subagents**, never the orchestrator. When the scope has multiple feature surfaces that don't share fixture state (the common case in a multi-file migration), dispatch one Opus subagent per feature in a single orchestrator turn — parallel by default per SKILL.md Smart subagent routing. Only fall back to sequential dispatch when surfaces share a single fixture builder whose construction would race between subagents. Subagent failure → another Opus subagent, never the orchestrator picking up the pen.

Beyond per-file unit tests, write higher-level tests exercising the **public feature surface** (per `test-discipline/migration-baselines.md` "black-box at the feature surface").

Construct a `<Feature>.test(...)` factory that builds the production graph and exposes observables (`RecordingApiClient`, etc.). Baselines assert on observable feature behavior — strongest equivalence guarantee, because Phase D can rewrite the entire internal graph without breaking these.

Written in `<dest>/src/androidUnitTest/...`, KMM-portable stack only so they promote to `commonTest` in Phase E (for `migrate`-plan features).

**Mandatory by default**, proportional to scope:
- A 1-file migration's "feature surface" may simply be that file's public API.
- A multi-file migration gets one or more `<Feature>.test()` factories covering user-meaningful flows.

Opt-out requires explicit user rationale recorded in audit.md.

### B.7 — Verification

- Full baseline suite green: `./gradlew :<dest>:testDebugUnitTest` (or project-specific task per `project.md`) — runs everything in `<dest>/androidUnitTest`.
- Pre-existing tests in `:app/src/test/` for relocated files still compile and pass (imports updated correctly at B.1).
- **Stuck-`relocated` scan**: `grep` `coverage.md` for any row still at `relocated` status. Expected count: **zero** — per-batch flips at B.4 should have caught everything. Any stuck rows indicate a sub-batch that skipped the audit-commit half of the two-commit cadence. Fix by flipping each stuck row to the correct status (`audited` if baseline written, `audited` with `baseline-deferred-to-phase-d` if on the defer shortlist).
- `audit.md` status → `complete`. Final code + audit commits.

### B.8 — Phase B retro
Amend `retro.md` with `## Phase B — Baseline (captured YYYY-MM-DD)`. Five-bullet structure. User can skip with `skip retro`.

---

## Output: `audit.md` + `phase-d-followups.md`

`audit.md` is the per-file audit log; `phase-d-followups.md` is the accumulator for SUTs that skip Phase B baseline (Path B / static-service-locator / pure-interface deferrals) and Phase D post-migration cleanups surfaced during B.4.

`audit.md` — living document, written progressively. Contains:

- Header (status, tasks, per-file checklist)
- B.0 source-set bootstrap log (deps added, compile result)
- B.1 relocation log (file → old path → new path → consumer-update summary)
- B.2 quarantine list (pre-existing broken tests `@Ignore`'d with reasons)
- Per-file audit verdicts (trust scores + evidence + citations + verdict, with Trust-verdict tests' new locations)
- New baselines written (file path, what they cover, test names)
- Deferred-to-Phase-D shortlist (cross-referenced to `phase-d-followups.md` entries)
- Red-on-breakage proofs (mutation applied + failure output + revert + success, per test)
- Feature-surface baselines (description, observables exercised)
- Self-review notes
- Final tallies (relocated count; existing reused / augmented / rewritten / new; deferred; aggregate trust)
- Decisions log

`phase-d-followups.md` — sectioned by followup. Each entry: `## Followup: <title>` / `**Source row:**` (audit row #) / `**Reason:**` (deferral rule applied) / `**Proposed action:**` (Phase D step) / `**Status:**** open` (flips to `done` at Phase D close).

`coverage.md` gains `relocated` rows at B.1 and flips them to `audited` **per-batch at B.4** (not deferred to B.7). B.7 only verifies no row is stuck at `relocated`.

---

## Phase-specific gates

Beyond universals:

- B.1 structural relocation is **mechanically pure** — `git mv` + package + consumer-import updates only. No edits to function bodies. Build green throughout.
- B.2 quarantine applied to every broken pre-existing test surfaced at Phase 0. None deferred.
- Every existing in-scope test **audited** by reading every test by name — not spot-checked.
- Every new or rewritten test has **red-on-breakage proof** — no shortcuts.
- Every test in `<dest>/androidUnitTest` uses the KMM-portable stack with **hand-rolled fakes only** — **no exceptions** (no MockK, no Mockito, no Truth, no Robolectric, no `java.time.*`). JVM-stack tests (MockK or Mockito) stay in `:app/src/test/` as regression cover only.
- Feature-surface baselines exist, or explicit opt-out with rationale recorded.
- Full baseline suite green before Phase C.
- `coverage.md` shows zero rows at `relocated` status at B.7 close (per-batch flips during B.4).
- All Path B / static-service-locator / pure-iface skips have `phase-d-followups.md` entries.
- No test bodies, mutation diffs, or full file contents reproduced in chat (per SKILL.md Output economy).
