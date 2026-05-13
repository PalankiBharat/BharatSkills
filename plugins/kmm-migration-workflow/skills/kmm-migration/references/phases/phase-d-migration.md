# Phase D — Migration

**Purpose.** Move in-scope files to the destination module and make them KMM-compatible via surgical, compiler-driven edits. Baselines act as the equivalence contract throughout; any baseline regression mid-migration is a divergence to investigate, not a flake. **Batched by topological layer for speed; commits stay per-file for reviewability.**

**Inputs:** all prior session files (`scope.md`, `plan.md`, `audit.md`, `freeze.md` complete), `project.md`, `coverage.md`, `references/test-discipline.md` (for any new tests written during foundation work).

---

## Sub-phases

### D.0 — Foundation setup (one-time per session)

Per plan.md's `expect`/`actual` and DI plans:

- **Opus** finalizes consolidated `expect`/`actual` interfaces in destination `commonMain`. ≥2-consumer check enforced.
- **Sonnet** writes interface declarations + **working `actual` impls** in `androidMain` AND `iosMain` — no `NotImplementedError` stubs. Done-means-done applies to foundation too.
- **Sonnet** sets up or extends destination Koin module per plan.md DI plan.
- **Pre-flight: destination module builds clean** before any file is moved. Catches infra issues (missing Koin dep, wrong source-set wiring, BuildKonfig misconfigured) before they compound across files. ~30s investment; saves 10+ min of debugging compounded issues mid-batch.
- **Haiku** runs gradle build; **Sonnet** addresses any compile errors with live-search citations.
- Baselines green after foundation (Haiku runs full suite).
- Commit foundation as a separate atomic change. SHA logged in `migration.md`.

### D.1 — Per-batch migration loop (topological-layer batches from plan.md)

plan.md's migration ordering naturally groups files by dependency layer (leaves first, then layers up). Files in the same layer don't depend on each other → safe to migrate together. **Build cost dominates**; batching reduces gradle invocations dramatically.

For each layer-batch — files committed individually within the batch:

1. **`git mv` all files in batch** (Haiku, parallel). Content preserved bit-for-bit; git rename detection works; history preserved.

2. **Update package declarations** to match new location (Haiku, parallel).

3. **Apply known plan.md substitutions before first build** (Sonnet). Predetermined fixes (`Locale.US` → `NumberFormatter` interface, `Instant.now()` → `Clock.System.now()`, Moshi adapter → `kotlinx.serialization`, etc.) applied as part of the move — **eliminates ~half the compile-fix iterations** because predetermined fixes aren't rediscovered via compile errors.

4. **Build → fix compile errors loop.**
   - Haiku runs gradle, parses errors.
   - Sonnet selects routine fixes; Opus handles complex substitutions where live-search is needed.
   - Minimal edit — only what compiler flagged. **Never read-and-rewrite the file** — surgical edits only.
   - Each substitution logged in `migration.md` with citation (search result or plan.md reference).
   - Repeat until destination compiles.

5. **Self-review** on any new code (Sonnet) per principle #2. Cruft check, KISS, DRY. Notes captured in decisions log.

6. **Targeted baselines** via `--tests` filter for batch files only (Haiku). Must be green.

   **Migration-exception flow if baseline fails on intentional divergence** (library-substitution semantics, timezone math, JSON ordering, etc.):
   - **Opus** confirms divergence is intentional per plan.md risk register.
   - User signs off.
   - Exception file created at `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` with: what changed, why, risk, sign-off.
   - Baseline edited under the exception reference; commit message includes `[migration-exception <id>]`.
   - Continue.
   
   Otherwise → real bug, investigate.

7. **Lightweight iOS check** (Haiku) — compile `commonMain` + `iosMain` targets only. ~30s. Fast safety net. Full XCFramework check happens at D.2.

8. **Consumer-side imports** updated in `app/` (Sonnet drafts FQN search-replace plan, Haiku applies, diff-confirmed). Skipped if package path is unchanged.

9. **Baselines re-green** after consumer update (Haiku gradle run).

10. **Commit per file** (staged `git add` + `git commit` cycles within the batch). Sonnet composes messages. One file per commit, or coherent unit per commit.

11. **`migration.md` updated** per file (Haiku structured fields + Sonnet prose rationale).

If iOS check (step 7) fails irrecoverably this session → hold-back proposed (D.3).

### D.2 — Integration verification (after all batches)

- **Haiku** runs full baseline suite. Green required.
- **Haiku** assembles full XCFramework. Clean — no SKIE warnings.
- **Sonnet** runs deferral grep across all migrated files (`TODO`, `FIXME`, `HACK`, suspect `@Suppress`). Clean required.
- **Opus** reviews `migration.md` for completeness — every file has every sub-step done, every substitution cited.

Any failure → not done. Investigate, fix, or hold-back affected file with user approval.

### D.3 — Hold-back handling (if invoked during D.1)

For a file that proves unmigratable cleanly this session:

- **Opus** confirms hold-back is the right call (vs. extending session, escalating).
- User confirms.
- `git revert` the file's commits — this also reverts the `migration.md` entries for that file (they were in the same commits).
- `scope.md`, `plan.md`, `audit.md`, `coverage.md` updated to remove the file from this session (each diff-confirmed; rationale captured in decisions log).
- Phase D resumes without that file. Returns to the next pending batch.

---

## Output: `migration.md`

Living document. Contains:

- Header (status, per-file task checklist)
- Foundation setup log (D.0 — interfaces created, DI module, commit SHA)
- Per-file entries:
  - Old path → new path
  - Compile errors encountered + resolutions (with live-search citations)
  - Self-review notes
  - iOS-consumability check result (compile, SKIE warnings, Swift surface notes)
  - Consumer-side update diff summary
  - Commit SHA
- Integration verification (D.2) — full suite + framework results
- Hold-backs (D.3) — files removed, rationale
- Migration-exceptions invoked (with links to `.kmm/exceptions/`)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase C complete (`freeze.md` status = complete; enforcement live).
- Every file migrated via **`git mv` then edit** — never read-rewrite-replace.
- Baselines green at every commit boundary (with exception refs for sanctioned divergences).
- iOS-consumability check passes per file (lightweight per-batch; full at D.2) before status = migrated.
- **No `TODO` / `FIXME` / stub / deferral** in any migrated file.
- Self-review documented for any new code.
- D.2 integration check passes before Phase E.
