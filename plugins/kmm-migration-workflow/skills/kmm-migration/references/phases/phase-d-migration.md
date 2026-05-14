# Phase D — KMM-ification

**Purpose.** For files with `Phase D plan: migrate` (per Phase A's plan.md), abstract Android deps via foundation interfaces and `git mv` from `<dest>/androidMain` to `<dest>/commonMain` via surgical, compiler-driven edits. Baselines act as the equivalence contract throughout; any baseline regression mid-migration is a divergence to investigate, not a flake. **Batched by topological layer for speed; commits stay per-file for reviewability.**

Files with `Phase D plan: hold` are not touched in Phase D — they stay in `<dest>/androidMain` with frozen baselines in `<dest>/androidUnitTest`. Their promotion to `commonMain` is deferred to a future session.

**Inputs:** all prior session files (`scope.md`, `plan.md`, `audit.md`, `freeze.md` complete), `project.md`, `coverage.md`, `references/test-discipline.md` (for any new tests written during foundation work).

---

## Sub-phases

### D.0 — Foundation setup (one-time per session)

Per plan.md's `expect`/`actual` and DI plans:

- **Opus** finalizes consolidated `expect`/`actual` interfaces in destination `commonMain`. ≥2-consumer check enforced.
- **Sonnet** writes interface declarations + **working `actual` impls** in `androidMain` AND `iosMain` — no `NotImplementedError` stubs. Done-means-done applies to foundation too.
- **Sonnet** sets up or extends destination Koin module per plan.md DI plan. Covers both `commonMain` bindings (for files about to migrate) and `androidMain` bindings (for held files that stay platform-specific).
- **Pre-flight: destination module builds clean** with all Phase B relocations + the new commonMain foundation. Catches infra issues (missing Koin dep, wrong source-set wiring, BuildKonfig misconfigured) before they compound across files. ~30s investment; saves 10+ min of debugging compounded issues mid-batch.
- **Haiku** runs gradle build; **Sonnet** addresses any compile errors with Context7 / web-search citations (per SKILL.md Tooling discipline).
- Baselines green after foundation (Haiku runs full `<dest>/androidUnitTest` suite).
- Commit foundation as a separate atomic change. SHA logged in `migration.md`.

### D.1 — Per-batch KMM-ification + commonMain promotion

Operates on **`migrate`-plan files only**, in plan.md's topological order (leaves first, then layers up). Files in the same layer don't depend on each other → safe to migrate together. **Build cost dominates**; batching reduces gradle invocations dramatically.

For each layer-batch — files committed individually within the batch:

1. **`git mv` files from `<dest>/src/androidMain/...` to `<dest>/src/commonMain/...`** (Haiku, parallel). Intra-module move. Content preserved bit-for-bit; git rename detection works; history preserved.

2. **Update package declarations** if conventions differ between source sets (Haiku, parallel). Usually a no-op — Kotlin source sets in the same module typically share package namespaces.

3. **Apply known plan.md substitutions before first build** (Sonnet). Predetermined fixes (`Locale.US` → injected `NumberFormatter` interface, `Instant.now()` → `Clock.System.now()`, Moshi adapter → `kotlinx.serialization`, Android-specific imports → commonMain-portable equivalents) applied as part of the move — **eliminates ~half the compile-fix iterations** because predetermined fixes aren't rediscovered via compile errors.

4. **Build → fix compile errors loop.**
   - Haiku runs gradle, parses errors.
   - Sonnet selects routine fixes; Opus handles complex substitutions where live-search is needed.
   - Minimal edit — only what compiler flagged. **Never read-and-rewrite the file** — surgical edits only.
   - Each substitution logged in `migration.md` with citation (Context7 result, web-search result, or plan.md reference per SKILL.md Tooling discipline).
   - Repeat until destination compiles.

5. **Self-review** on any new code (Sonnet) per principle #2. Cruft check, KISS, DRY. Notes captured in decisions log.

6. **Targeted baselines** via `--tests` filter for batch files only (Haiku). Run in `<dest>/androidUnitTest`. Must be green.

   **Migration-exception flow if baseline fails on intentional divergence** (library-substitution semantics, timezone math, JSON ordering, etc.):
   - **Opus** confirms divergence is intentional per plan.md risk register.
   - User signs off.
   - Exception file created at `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` with: what changed, why, risk, sign-off.
   - Baseline edited under the exception reference; commit message includes `[migration-exception <id>]`.
   - Continue.
   
   Otherwise → real bug, investigate.

7. **Lightweight iOS check** (Haiku) — compile `commonMain` + `iosMain` targets only. ~30s. Fast safety net. Full XCFramework check happens at D.2.

8. **Consumer impact check** (Sonnet). Intra-module moves typically don't change FQN — no consumer updates required. If the project has package conventions that differ between source sets, Sonnet drafts the FQN search-replace plan, Haiku applies, diff-confirmed. After any updates, baselines re-green via Haiku gradle run.

9. **Commit per file** (staged `git add` + `git commit` cycles within the batch). Sonnet composes messages. One file per commit, or coherent unit per commit.

10. **`migration.md` updated** per file (Haiku structured fields + Sonnet prose rationale).

If iOS check (step 7) fails irrecoverably for a file this session → Phase D plan flip proposed (D.3).

### D.2 — Integration verification (after all batches)

- **Haiku** runs full baseline suite (`<dest>/androidUnitTest`). Green required.
- **Haiku** assembles full XCFramework. Clean — no SKIE warnings.
- **Sonnet** runs deferral grep across all migrated files (`TODO`, `FIXME`, `HACK`, suspect `@Suppress`). Clean required.
- **Opus** reviews `migration.md` for completeness — every `migrate`-plan file has every sub-step done, every substitution cited.

Any failure → not done. Investigate, fix, or flip affected file to `hold` with user approval (see D.3).

### D.3 — Phase D plan flip (`migrate` → `hold`) — if invoked during D.1 or D.2

For a file initially marked `migrate` that proves unmigratable cleanly this session:

- **Opus** confirms `migrate` → `hold` flip is the right call (vs. extending session, escalating, or pursuing migration-exception).
- User confirms.
- The file's **Phase B relocation commit stays** — code is correctly in `<dest>/androidMain`, that's its valid hold position.
- Any Phase D commits for this file (commonMain mv, partial substitutions) are reverted via `git revert`.
- `plan.md` Phase D plan flips `migrate` → `hold` for this file (diff-confirmed, rationale captured in decisions log).
- `coverage.md` for this file: status stays `frozen`; Phase D plan column flips to `hold`; final code path = `<dest>/androidMain/...`.
- Phase D continues with remaining `migrate`-plan files.

A flip is **not a session abandonment** — it's a per-file deferral. The rest of the session proceeds normally.

---

## Output: `migration.md`

Living document. Contains:

- Header (status, per-file task checklist)
- Foundation setup log (D.0 — interfaces created, DI module, commit SHA)
- Per-file entries (one per `migrate`-plan file):
  - Old path (`<dest>/androidMain/...`) → new path (`<dest>/commonMain/...`)
  - Compile errors encountered + resolutions (with Context7 / web-search citations)
  - Self-review notes
  - iOS-consumability check result (compile, SKIE warnings, Swift surface notes)
  - Consumer impact summary (typically no-op for intra-module move)
  - Commit SHA
- Held files summary (one line per `hold`-plan file: "Phase D plan: hold per plan.md — code stays in `<dest>/androidMain/...`")
- Integration verification (D.2) — full suite + framework results
- Phase D plan flips (D.3) — files flipped `migrate` → `hold`, rationale
- Migration-exceptions invoked (with links to `.kmm/exceptions/`)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase C complete (`freeze.md` status = complete; detekt enforcement live).
- Every `migrate`-plan file moved via **`git mv` then edit** — never read-rewrite-replace.
- Baselines green at every commit boundary (with exception refs for sanctioned divergences).
- iOS-consumability check passes per `migrate`-plan file (lightweight per-batch; full at D.2) before status flips `frozen` → `migrated`.
- **No new `TODO` / `FIXME` / stub / deferral** introduced in any migrated file. (Pre-existing such items in held files are out of scope — they didn't move.)
- Self-review documented for any new code.
- D.2 integration check passes before Phase E.
- Held files (`Phase D plan: hold`) have **no Phase D commits**; their relocation from Phase B is their final state this session.
