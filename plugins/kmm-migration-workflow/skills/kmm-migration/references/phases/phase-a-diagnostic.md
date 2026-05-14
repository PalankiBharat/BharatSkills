# Phase A — Diagnostic

**Purpose.** Produce `plan.md` — the architectural design doc that answers every "how" question before Phase B (uniform structural relocation + baselines) and Phase D (KMM-ification) begin. Per-file analysis (surface, deps, seam strategies, Phase D plan, risks) + cross-file synthesis (Phase D migration order, DI plan, aggregated risk register, foundation `expect`/`actual` plan).

**No code written, no tests written.** Just the design that makes Phase B and D mechanical.

**Inputs:** `scope.md`, `plan.md` (if resuming), `project.md`, `coverage.md`, cached searches in `.kmm/searches/`.

---

## Sub-phases

### 1. Bulk pattern search (orchestrator)

Based on Phase 0 manifest, fire live searches:

- *"KMM migration `<file-type>` patterns 2026"* per file-type category in scope.
- *"Kotlin `<library>` KMM antipatterns"* per non-trivial dep surfaced.
- *"SKIE `<pattern>`"* for Swift-consumption concerns relevant to scope.
- Context7 lookups for KMM-native library API signatures (current).

Results cached in `.kmm/searches/<topic-hash>.md` — subagents consume from cache; future sessions don't re-search.

### 2. Per-file analysis (parallel Sonnet)

Per in-scope file:

- **Public surface** — methods, signatures, return types, exceptions, public properties.
- **Direct + transitive deps of concern** — Android-only / has-KMM-equivalent / no-equivalent.
- **Classification** — platform-free / -incidental / -essential, with cited justification.
- **Per-dep seam strategy** for each platform-touching dep:
  - **commonMain-ready** — dep is already KMM-portable (e.g., `kotlinx.datetime`, `kotlinx.serialization`). Migrate as-is.
  - **`expect`/`actual`** — dep needs platform-specific impl behind a common signature.
  - **Interface-and-adapter** — extract interface to commonMain, keep Android impl behind it in androidMain.
  - **Forces hold** — no clean KMM seam this session (e.g., Android-only SDK with no abstraction worth building yet).
  
  Pattern lookups inform each — Context7 for API specifics, web search for patterns (per SKILL.md Tooling discipline). No training-data guesses.
- **Phase D plan** for the file:
  - **`migrate`** — every dep has a non-`Forces hold` seam strategy. File will be relocated `androidMain` → `commonMain` in Phase D this session.
  - **`hold`** — at least one dep forces hold. File stays in `androidMain` after Phase B (post-relocation). Promotion deferred to a future session.
- **`expect`/`actual` sketch** if any (for Phase D foundation).
- **File-specific risks** — behavioral-divergence, iOS API ergonomics, concurrency.
- **Migration-order signal** — what this depends on (informs Phase D ordering for `migrate`-plan files).

### 3. Cross-file synthesis (Opus)

- **Phase D migration ordering** — topological for `migrate`-plan files: leaves first (Models, Mappers), layers up (Repositories, UseCases), Presentation last if in scope. `hold`-plan files don't participate in Phase D ordering.
- **DI module plan** — Koin module structure for destination per profile's DI stance and `test-discipline` MockK-default rules. Covers both `commonMain` bindings (for migrated files) and `androidMain` bindings (for held files).
- **Aggregated risk register** — dedup risks, group by category, each paired with the Phase B baseline test type that will catch it.
- **Consolidated `expect`/`actual` interfaces** — merge where multiple `migrate`-plan files need the same abstraction (one `Clock`, one `NumberFormatter`, etc.). **≥2-consumer test enforced** — single-consumer abstractions get inlined.
- **Phase D plan reassessment** — any file initially marked `migrate` that synthesis reveals is too risky / iOS-incomplete → flip to `hold` with rationale recorded. Scope itself doesn't change; only the per-file Phase D plan flips. User confirms each flip.

### 4. Self-review (skill principle #2 — clean code)

Before presenting:
- Every new interface has ≥2 consumers (or gets inlined).
- No abstractions "just in case."
- No `*Holder` / `*Manager` cruft.
- Self-review notes recorded explicitly:
  > *"Considered `FundsClock` interface but inlined `Clock.System` — single consumer."*

### 5. User review + confirmation

Batched per logical unit (per file, then synthesis). User accepts / edits / rejects each batch. `plan.md` status flips to complete on final confirmation.

---

## Output: `plan.md`

Living document. Contains:

- Header (status, tasks)
- Cached live-search results (patterns, antipatterns, KMM-native API references)
- Per-file analysis (one entry per file with the fields above, including `Phase D plan: migrate / hold` with rationale)
- **Per-file Phase D plan summary table** (file → `migrate` or `hold` → rationale) — feeds `coverage.md`'s Phase D plan column.
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
