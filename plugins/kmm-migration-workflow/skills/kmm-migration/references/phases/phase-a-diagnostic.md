# Phase A — Diagnostic

**Purpose.** Produce `plan.md` — the architectural design doc that answers every "how" question before Phase B baselines and Phase D edits begin. Per-file analysis (surface, deps, classification, seams, risks) + cross-file synthesis (migration order, DI plan, aggregated risk register, `expect`/`actual` plan).

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
- **Seam decisions** per platform-touching dep:
  - `commonMain` directly (KMM-portable already)
  - `expect`/`actual`
  - Interface-and-adapter (interface in commonMain, impl in androidMain)
  - Hold back (stay androidMain this session)
  
  Pattern lookups inform each — no training-data guesses.
- **`expect`/`actual` sketch** if any.
- **File-specific risks** — behavioral-divergence, iOS API ergonomics, concurrency.
- **Migration-order signal** — what this depends on (informs ordering).

### 3. Cross-file synthesis (Opus)

- **Migration ordering** — topological: leaves first (Models, Mappers), layers up (Repositories, UseCases), Presentation last if in scope.
- **DI module plan** — Koin module structure for destination per profile's DI stance and `test-discipline` MockK-default rules.
- **Aggregated risk register** — dedup risks, group by category, each paired with the Phase B baseline test type that will catch it.
- **Consolidated `expect`/`actual` interfaces** — merge where multiple files need the same abstraction (one `Clock`, one `NumberFormatter`, etc.). **≥2-consumer test enforced** — single-consumer abstractions get inlined.
- **Hold-back reassessment** — any file now revealed as too risky / iOS-incomplete → propose hold-back to user with rationale. Scope-update is explicit.

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
- Per-file analysis (one entry per file with the fields above)
- Cross-file synthesis (migration order, DI plan, risk register)
- `expect`/`actual` plan (consolidated interfaces with their ≥2 consumers)
- Hold-back proposals + rationale (if any)
- Self-review notes
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Live search done before any architectural decision. **No training-data assumptions** about KMM patterns or library behavior.
- Every classification and seam decision cites evidence (search finding, dep analysis, profile rule).
- New interfaces meet the ≥2-consumer test or get inlined.
- **No `TODO` / stub / deferred-work in the plan.** *"We'll figure this out in Phase D"* is not allowed — Phase A is where it's figured out. Quality of Phase A directly determines speed of Phase D.
- Hold-back decisions surface to user explicitly; scope updates are not silent.

## A note on Phase A quality vs Phase D speed

**Phase D's batched compile-fix loop depends on plan.md predetermining the substitutions.** Incomplete planning here → more non-trivial decisions surface during Phase D → more Opus invocations + user discussion → slower migration. Spend the time here; D pays it back.
