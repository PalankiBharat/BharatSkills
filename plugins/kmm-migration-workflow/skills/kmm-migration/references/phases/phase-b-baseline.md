# Phase B — Structural Relocation + Baseline Coverage Audit & Write

**Purpose.** Move every in-scope file uniformly from `:app` to `<dest>/androidMain` (structural — zero Kotlin-semantic change), then produce the frozen baseline test suite that proves current Android behavior, survives the migration (KMM-portable stack only), and catches divergence post-migration. **Longest phase by token count; strongest equivalence guarantee in the workflow.**

Relocation happens first because it preserves behavior trivially (`git mv` + consumer-import update, no Kotlin changes). Baselines are then written against the relocated code in the destination module's `androidUnitTest` source set — the same module where they'll live through Phase E.

**Inputs:** `scope.md`, `plan.md`, `audit.md` (if resuming), `project.md`, `coverage.md`, **`references/test-discipline.md` (mandatory — load at Phase B startup)**.

Phase B execution **must** load `references/test-discipline.md` before any audit or test-writing work. It contains the per-file-type checklists, the denylist (§12), the MockK templates, the broken-test quarantine pattern, and the KMM-portable stack rules that every sub-phase below relies on.

---

## Sub-phases

### B.1 — Structural relocation (uniform `git mv`)

For each in-scope prod file (parallel Haiku):

- `git mv :app/src/main/.../X.kt <dest>/src/androidMain/.../X.kt`
- Package declaration updated to the new path (Haiku).
- Consumer imports in `:app` updated for every reference to the moved file (Sonnet drafts the FQN search-replace plan, Haiku applies, diff-confirmed).

This step is **pure structural** — no Kotlin-semantic changes, no edits to function bodies. Behavior preserved trivially. Build must remain green throughout; if it doesn't, something other than a relocation happened — pause and investigate.

Existing tests for moved files stay in `:app/src/test/...` for now (with their imports updated to the new package). Their fate is decided in B.3 (audit).

`coverage.md` updated: in-scope files flip to `relocated` status.

Commit per file (or coherent per-layer batch); commit messages note "relocation only, no semantic change."

### B.2 — Quarantine pre-existing broken tests (Haiku)

Per Phase 0 step 8's broken-test discovery in `<dest>/androidUnitTest`:

- For each pre-existing broken test, apply `@Ignore("<one-line reason>; see PR out-of-scope follow-ups")`.
- Per `test-discipline §12 — Quarantine of unrelated broken tests`.
- Non-judgmental — does not assert the test is bad, only that fixing it is not this migration's job.

After this step, `<dest>/androidUnitTest` compiles clean — ready for baselines to be written.

If Phase 0 reported clean (no broken pre-existing tests), this sub-phase is skipped.

### B.3 — Audit existing tests (parallel Sonnet per file)

For each in-scope file with an existing test (currently in `:app/src/test/...` post-B.1):

- Read every test by name (Haiku does the parse).
- Score on three dimensions:
  - **Coverage %** — checklist items from `test-discipline §<file-type>` hit by existing tests, cited by test name (Sonnet scores).
  - **Migration-safety %** — pass against `test-discipline §12` denylist (Mockito, Truth, Robolectric, `@get:Rule`, `org.junit.runner.*`, `java.time.*`, `System.currentTimeMillis`, `MainCoroutineRule`, etc.). Haiku scans imports; Sonnet judges edge cases.
  - **Bug-catching power %** — proven by deliberate-breakage mutation (see B.5); for existing tests, run the menu mutation now.
- **Trust score = min(coverage%, migration-safety%, bug-catching%).** Forces explicit reasoning per dimension.
- **Verdict: Trust / Augment / Rewrite**, citing specific test names + checklist items + denylist hits as evidence.

**Verdict outcomes:**

- **Trust** — existing test is suitable as a baseline. `git mv :app/src/test/.../XTest.kt <dest>/src/androidUnitTest/.../XTest.kt`. Update package; update any imports. Per-test fixtures travel with the test (move from `:app/src/test/.../fixtures/` to `<dest>/src/androidUnitTest/.../fixtures/` if exclusively used by the moved tests; otherwise duplicate the needed factories).
- **Augment / Rewrite** — existing test stays in `:app/src/test/` as regression cover (not a baseline). New baseline written in `<dest>/androidUnitTest/` per B.4.

Recorded per file in `audit.md`.

### B.4 — Write missing baselines

**Parallelism:** Sonnet for routine files; Opus for complex files.

For files with audit verdict `Augment` / `Rewrite` or no existing test:

- **Routine (Sonnet):** UseCase, Mapper, Model, RemoteStore, simple Repository, simple Presenter.
- **Complex (Opus):** concurrency-heavy Interactor, multi-source cache Repository, state-machine Presenter, anything plan.md flagged high-stakes.

Per file:
- Identify file type → load `test-discipline §<type>` (checklist + template + KMM-portable stack).
- Write the baseline in `<dest>/src/androidUnitTest/.../XTest.kt` using **kotlin.test + MockK + Turbine + hand-rolled fakes** (per `test-discipline §12`).
- **Apply principle #2 (clean code):** no test-only `*Holder` / `*Manager`; fakes earn their existence (≥2 consumers or required for KMM portability).
- **Self-review before presenting.** Notes captured.
- User confirms per batch (per file or per file-type cluster).

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

### B.6 — Feature-surface baselines (Opus, sequential)

Beyond per-file unit tests, write higher-level tests exercising the **public feature surface** (per `test-discipline §12` "black-box at the feature surface").

Construct a `<Feature>.test(...)` factory that builds the production graph and exposes observables (`RecordingApiClient`, etc.). Baselines assert on observable feature behavior — strongest equivalence guarantee, because Phase D can rewrite the entire internal graph without breaking these.

Written in `<dest>/src/androidUnitTest/...`, KMM-portable stack only so they promote to `commonTest` in Phase E (for `migrate`-plan features).

**Mandatory by default**, proportional to scope:
- A 1-file migration's "feature surface" may simply be that file's public API.
- A multi-file migration gets one or more `<Feature>.test()` factories covering user-meaningful flows.

Opt-out requires explicit user rationale recorded in audit.md.

### B.7 — Verification

- Full baseline suite green: `./gradlew :<dest>:testDebugUnitTest` (or project-specific task per `project.md`) — runs everything in `<dest>/androidUnitTest`.
- Pre-existing tests in `:app/src/test/` for relocated files still compile and pass (imports updated correctly at B.1).
- `coverage.md` updated: in-scope files flip from `relocated` to `audited` with baseline paths filled in (one batch, diff-confirmed).
- `audit.md` status → `complete`.

---

## Output: `audit.md`

Living document, written progressively. Contains:

- Header (status, tasks, per-file checklist)
- B.1 relocation log (file → old path → new path → consumer-update summary)
- B.2 quarantine list (pre-existing broken tests `@Ignore`'d with reasons)
- Per-file audit verdicts (trust scores + evidence + citations + verdict, with Trust-verdict tests' new locations)
- New baselines written (file path, what they cover, test names)
- Red-on-breakage proofs (mutation applied + failure output + revert + success, per test)
- Feature-surface baselines (description, observables exercised)
- Self-review notes
- Final tallies (relocated count; existing reused / augmented / rewritten / new; aggregate trust)
- Decisions log

`coverage.md` gains `relocated` rows at B.1 and flips them to `audited` at B.7.

---

## Phase-specific gates

Beyond universals:

- B.1 structural relocation is **mechanically pure** — `git mv` + package + consumer-import updates only. No edits to function bodies. Build green throughout.
- B.2 quarantine applied to every broken pre-existing test surfaced at Phase 0. None deferred.
- Every existing in-scope test **audited** by reading every test by name — not spot-checked.
- Every new or rewritten test has **red-on-breakage proof** — no shortcuts.
- Every test in `<dest>/androidUnitTest` uses the KMM-portable stack — **no exceptions** (no Mockito, no Truth, no Robolectric, no `java.time.*`). JVM-stack tests stay in `:app/src/test/` as regression cover only.
- Feature-surface baselines exist, or explicit opt-out with rationale recorded.
- Full baseline suite green before Phase C.
- User confirmation on each batch; nothing freezes silently.
