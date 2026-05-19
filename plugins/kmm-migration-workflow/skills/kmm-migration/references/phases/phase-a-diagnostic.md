# Phase A — Diagnostic

**Purpose.** Produce `plan.md` — the architectural design doc that answers every "how" question before Phase B (uniform structural relocation + baselines) and Phase D (KMM-ification) begin. Per-file analysis (surface, deps, seam strategies, Phase D plan, risks) + cross-file synthesis (Phase D migration order, DI plan, aggregated risk register, foundation `expect`/`actual` plan).

**No code written, no tests written.** Just the design that makes Phase B and D mechanical.

**Inputs:** `scope.md`, `plan.md` (if resuming), `project.md`, `coverage.md`, cached searches in `.kmm/searches/`, `references/expect-actual-boundaries.md` (seam-strategy rubric).

---

## Sub-phases

### 1. Library-substitution decisions (discussion-first)

Before any bulk search, lock the library substitution direction for every Android-only dep in scope. Searches that run against a moving target produce subagent context drops (a subagent doesn't see the resolved decision and re-derives it incorrectly).

- Skill enumerates candidate library substitutions from Phase 0 scope (Retrofit, Joda, Gson, Paging <3.5, etc.).
- For each, present as a **discrete user decision**: *"Found Retrofit usage in 7 files. Plan to substitute with Ktor (commonMain-compatible). Confirm direction?"*
- User confirms / pushes back / picks a different target lib.
- Confirmed substitutions land in `plan.md` decisions log AND feed the per-file `lib-swap` classifier in sub-phase 2 (Path A — contract baseline / Path B — defer to Phase D / `none` — no swap).
- **No bulk search until every lib-swap direction is locked.** This protocol is the cause-of-truth for subagent prompts in sub-phase 2.

### 2. Bulk pattern search (orchestrator)

Based on Phase 0 manifest + locked lib-swap decisions, fire live searches:

- *"KMM migration `<file-type>` patterns 2026"* per file-type category in scope.
- *"Kotlin `<library>` KMM antipatterns"* per non-trivial dep surfaced.
- *"SKIE `<pattern>`"* for Swift-consumption concerns relevant to scope.
- Context7 lookups for KMM-native library API signatures (current).

Results cached in `.kmm/searches/<topic-hash>.md` — **subagents consume from cache** (per SKILL.md Subagent-mediated exploration; the cache exists for cross-session reuse, not main-context bloat). Future sessions don't re-search.

### 3. Per-file analysis (parallel Sonnet)

**Subagent prompt template — mandatory prefix.** Every per-file analysis subagent dispatch in this sub-phase is prefixed with a `## Resolved decisions (from Phase 0 + Phase A sub-phase 1)` block. The skill assembles this block once at the start of the sub-phase from `plan.md`'s decisions log (Paging version locked, Retrofit→Ktor confirmed, etc.) and reuses it across every parallel dispatch. Subagents are instructed to **apply** these decisions, **never re-derive** substitution choices. This prevents the failure mode where one subagent miscalls a file because the deciding context wasn't in its prompt.

Per in-scope file:

- **Public surface** — methods, signatures, return types, exceptions, public properties.
- **Direct + transitive deps of concern** — Android-only / has-KMM-equivalent / no-equivalent.
- **Classification** — platform-free / -incidental / -essential, with cited justification.
- **`lib-swap` classification** — applies if this file uses any of the libraries locked for substitution in sub-phase 1:
  - **`path-a`** — SUT output is assertable without referencing the old-lib types (use MockWebServer / hand-rolled HTTP fake / date-string outputs / round-tripped objects). Baseline in Phase B survives the swap unchanged. **Default**.
  - **`path-b`** — SUT public surface unavoidably exposes old-lib types (e.g., RemoteStore method returning `Result<T, retrofit2.HttpException>`, DTO whose contract IS its `@SerializedName` annotation surface). Defer baseline to Phase D — tracked in `phase-d-followups.md`.
  - **`none`** — no lib swap touches this file.
  
  Decision rule: if a baseline can be written that compiles unchanged before and after the lib swap → `path-a`. Only otherwise → `path-b`. Bias hard toward `path-a`. See `test-discipline/migration-baselines.md` §Library-substitution.
- **Per-dep seam strategy** for each platform-touching dep:
  - **commonMain-ready** — dep is already KMM-portable (e.g., `kotlinx.datetime`, `kotlinx.serialization`). Migrate as-is.
  - **`expect`/`actual`** — dep needs platform-specific impl behind a common signature.
  - **Interface-and-adapter** — extract interface to commonMain, keep Android impl behind it in androidMain.
  - **Forces hold** — no clean KMM seam this session (e.g., Android-only SDK with no abstraction worth building yet).
  
  **Consult `references/expect-actual-boundaries.md`** for the decision rubric between `expect`/`actual` vs interface-and-adapter (rule of thumb: interface when tests / DI / lifecycle / runtime selection matter; `expect`/`actual` for simple compile-time platform specialization). Pattern lookups inform each — Context7 for API specifics, web search for patterns (per SKILL.md Tooling discipline). No training-data guesses.
- **Phase D plan** for the file:
  - **`migrate`** — every dep has a non-`Forces hold` seam strategy. File will be relocated `androidMain` → `commonMain` in Phase D this session.
  - **`hold`** — at least one dep forces hold. File stays in `androidMain` after Phase B (post-relocation). Promotion deferred to a future session.
- **`expect`/`actual` sketch** if any (for Phase D foundation).
- **File-specific risks** — behavioral-divergence, iOS API ergonomics, concurrency.
- **SUT test-classpath gaps** — if the SUT compiles against any dep that's `compileOnly` or platform-only (e.g., `retrofit2.HttpException`, `androidx.paging`), record the gap so Phase B's B.0 source-set bootstrap can preempt it (add `testImplementation` early, not retroactively when B.4 compile breaks).
- **Migration-order signal** — what this depends on (informs Phase D ordering for `migrate`-plan files).

### 4. Cross-file synthesis (Opus)

- **Phase D migration ordering** — topological for `migrate`-plan files: leaves first (Models, Mappers), layers up (Repositories, UseCases), Presentation last if in scope. `hold`-plan files don't participate in Phase D ordering.
- **DI module plan** — Koin module structure for destination per profile's DI stance and `test-discipline/index.md` MockK-default rules. Covers both `commonMain` bindings (for migrated files) and `androidMain` bindings (for held files).
- **Aggregated risk register** — dedup risks, group by category, each paired with the Phase B baseline test type that will catch it.
- **Consolidated `expect`/`actual` interfaces** — merge where multiple `migrate`-plan files need the same abstraction (one `Clock`, one `NumberFormatter`, etc.). **≥2-consumer test enforced** — single-consumer abstractions get inlined.
- **Phase D plan reassessment** — any file initially marked `migrate` that synthesis reveals is too risky / iOS-incomplete → flip to `hold` with rationale recorded. Scope itself doesn't change; only the per-file Phase D plan flips. User confirms each flip.

### 5. Self-review (skill principle #2 — clean code)

Before presenting:
- Every new interface has ≥2 consumers (or gets inlined).
- No abstractions "just in case."
- No `*Holder` / `*Manager` cruft.
- Self-review notes recorded explicitly:
  > *"Considered `FundsClock` interface but inlined `Clock.System` — single consumer."*

### 6. User review + confirmation

Batched per logical unit (per file, then synthesis). User accepts / edits / rejects each batch. `plan.md` status flips to complete on final confirmation.

### 7. Phase A retro
Before marking Phase A complete, amend `retro.md` with a `## Phase A — Diagnostic (captured YYYY-MM-DD)` section: five-bullet structure per SKILL.md. User can skip with `skip retro`.

---

## Mid-phase scope amendment protocol

During per-file analysis, a subagent may surface an in-scope file referencing something **not in scope.md** (e.g., a foundation extension function, a date helper, a model used outside the scoped layer). When this happens:

1. Skill pauses per-file analysis on that file.
2. Present the discovery: *"Found: `<in-scope-file>` references `<symbol>` at `<location>`. Not in scope.md. Add to migration? (y/n)"*
3. If **yes**: amend `scope.md` (additions appended under `## Discovered mid-phase` section with date), regen `plan.md` entry for the new file (run the new file through sub-phase 3 itself), resume Phase A from where it paused. Per-file Phase D plan summary table updated.
4. If **no**: log to `phase-d-followups.md` as `out-of-scope-dependency` with the reference site, to be reconsidered post-migration.

This protocol replaces ad-hoc improvisation when out-of-scope deps surface late. Phase 0 catches the typical case (full dep walk); this catches the residue.

---

## Output: `plan.md`

Living document. Contains:

- Header (status, tasks)
- **Locked library substitutions** (from sub-phase 1) — table: source-lib → target-lib → file count → confirmed-by-user date.
- Cached live-search results (patterns, antipatterns, KMM-native API references)
- Per-file analysis (one entry per file with the fields above, including `Phase D plan: migrate / hold` and `lib-swap: path-a / path-b / none` with rationale)
- **Per-file Phase D plan summary table** (file → `migrate` or `hold` → `lib-swap` → rationale) — feeds `coverage.md`'s Phase D plan column and the `phase-d-followups.md` deferred-baseline list.
- **SUT test-classpath gaps** (aggregated) — deps that need `testImplementation` added at Phase B's B.0 source-set bootstrap. Surfaced here so B.0 preempts compile blockers.
- Cross-file synthesis (Phase D migration order for `migrate`-plan files, DI plan, risk register)
- Foundation `expect`/`actual` plan (consolidated interfaces with their ≥2 consumers)
- Self-review notes
- Decisions log

---

## Phase-specific gates

Beyond universals:

- **Context7-first for library/SDK/API specifics, web search for patterns** (per SKILL.md Tooling discipline) before any architectural decision. No training-data assumptions about KMM patterns or library behavior.
- Every classification and seam strategy cites evidence (search finding, dep analysis, profile rule).
- Every in-scope file has a recorded `Phase D plan` (`migrate` / `hold`) with rationale.
- New interfaces meet the ≥2-consumer test or get inlined.
- **No `TODO` / stub / deferred-work in the plan.** *"We'll figure this out in Phase D"* is not allowed — Phase A is where it's figured out. Quality of Phase A directly determines speed of Phase D.
- `Phase D plan: hold` decisions surface to user explicitly with rationale; not silent.

## A note on Phase A quality vs Phase D speed

**Phase D's batched compile-fix loop depends on plan.md predetermining the substitutions.** Incomplete planning here → more non-trivial decisions surface during Phase D → more Opus invocations + user discussion → slower migration. Spend the time here; D pays it back.
