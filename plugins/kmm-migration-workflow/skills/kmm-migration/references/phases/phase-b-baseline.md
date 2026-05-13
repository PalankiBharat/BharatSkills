# Phase B — Baseline Coverage Audit & Write

**Purpose.** Produce the frozen baseline test suite that proves current Android behavior, survives the migration (KMM-portable stack only), and catches divergence post-migration. **Longest phase by token count; strongest equivalence guarantee in the workflow.**

**Inputs:** `scope.md`, `plan.md`, `audit.md` (if resuming), `project.md`, `coverage.md`, **`references/test-discipline.md` (mandatory — load at Phase B startup)**.

Phase B execution **must** load `references/test-discipline.md` before any audit or test-writing work. It contains the per-file-type checklists, the denylist (§12), the MockK templates, and the KMM-portable stack rules that every sub-phase below relies on.

---

## Sub-phases

### B.1 — Audit existing tests (parallel Sonnet per file)

For each in-scope file with existing tests:

- Read every test by name (Haiku does the parse).
- Score on three dimensions:
  - **Coverage %** — checklist items from `test-discipline §<file-type>` hit by existing tests, cited by test name (Sonnet scores).
  - **Migration-safety %** — pass against `test-discipline §12` denylist (Mockito, Truth, Robolectric, `@get:Rule`, `org.junit.runner.*`, `java.time.*`, `System.currentTimeMillis`, `MainCoroutineRule`, etc.). Haiku scans imports; Sonnet judges edge cases.
  - **Bug-catching power %** — proven by deliberate-breakage mutation (see B.3); for existing tests, run the menu mutation now.
- **Trust score = min(coverage%, migration-safety%, bug-catching%).** Forces explicit reasoning per dimension.
- **Verdict: Trust / Augment / Rewrite**, citing specific test names + checklist items + denylist hits as evidence.

Recorded per file in `audit.md`.

### B.2 — Write missing tests

**Parallelism:** Sonnet for routine files; Opus for complex files.

- **Routine (Sonnet):** UseCase, Mapper, Model, RemoteStore, simple Repository, simple Presenter.
- **Complex (Opus):** concurrency-heavy Interactor, multi-source cache Repository, state-machine Presenter, anything plan.md flagged high-stakes.

Per file:
- Identify file type → load `test-discipline §<type>` (checklist + template + KMM-portable stack).
- Write tests per the checklist, in **kotlin.test + MockK + Turbine + hand-rolled fakes** (per `test-discipline §12`).
- **Apply principle #2 (clean code):** no test-only `*Holder` / `*Manager`; fakes earn their existence (≥2 consumers or required for KMM portability).
- **Self-review before presenting.** Notes captured.
- User confirms per batch (per file or per file-type cluster).

### B.3 — Prove red-on-breakage (per new or rewritten test)

**Non-negotiable.** A test that doesn't go red on a deliberate breakage is tautologically green — useless as a baseline.

For each test:
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
3. Revert breakage → must go **GREEN**.
4. Record proof in audit.md (mutation, failure output, revert, success).

Reviewer can reproduce by re-applying the standard mutation. No vibes.

### B.4 — Feature-surface baselines (Opus, sequential)

Beyond per-file unit tests, write higher-level tests exercising the **public feature surface** (per `test-discipline §12` "black-box at the feature surface").

Construct a `<Feature>.test(...)` factory that builds the production graph and exposes observables (`RecordingApiClient`, etc.). Baselines assert on observable feature behavior — strongest equivalence guarantee, because Phase D can rewrite the entire internal graph without breaking these.

**Mandatory by default**, proportional to scope:
- A 1-file migration's "feature surface" may simply be that file's public API.
- A multi-file migration gets one or more `<Feature>.test()` factories covering user-meaningful flows.

Opt-out requires explicit user rationale recorded in audit.md.

### B.5 — Verification

- Full baseline suite green: `./gradlew :app:baselineTestDebug` (or project-specific task per `project.md`).
- `coverage.md` updated: in-scope files flip to `audited` status with baseline paths filled in (one batch, diff-confirmed).
- `audit.md` status → `complete`.

---

## Output: `audit.md`

Living document, written progressively. Contains:

- Header (status, tasks, per-file checklist)
- Per-file audit verdicts (trust scores + evidence + citations)
- New tests written (file path, what they cover, test names)
- Red-on-breakage proofs (mutation applied + failure output + revert + success, per test)
- Feature-surface baselines (description, observables exercised)
- Self-review notes
- Final tallies (existing reused / augmented / rewritten / new; aggregate trust)
- Decisions log

`coverage.md` gains `audited` rows as files clear B.5.

---

## Phase-specific gates

Beyond universals:

- Every existing in-scope test **audited** by reading every test by name — not spot-checked.
- Every new or rewritten test has **red-on-breakage proof** — no shortcuts.
- Every test uses the KMM-portable stack — **no exceptions** (no Mockito, no Truth, no Robolectric, no `java.time.*`).
- Feature-surface baselines exist, or explicit opt-out with rationale recorded.
- Full baseline suite green before Phase C.
- User confirmation on each batch; nothing freezes silently.
