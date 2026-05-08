# KMM Migration Constitution

Version: 1.0.0

This constitution governs any work whose stated goal is migrating code from a platform-native codebase into Kotlin Multiplatform shared code. It supersedes assistant defaults and project conventions for the duration of the migration. On non-migration work, normal conventions resume.

Principles are ordered. Earlier principles dominate later ones when they conflict.

## Principles

1. **Understand before acting. Research first, think first, act later.** Read the source of truth before porting. Never try-fail-check. Every plan entry names a specific `file:line`. "TBD" and "somewhere in the module" are not valid entries. If behaviour is unclear, stop and read — do not guess from the call site. **The default cadence is research → think → act, never the opposite.** When an agent finds itself acting before understanding, that's the bug; correct it by stopping and going back to research.

2. **No assumptions when stuck.** Anything not covered by the spec or plan is presented to the user with: the problem, candidate solutions, recommended solution, and why — biased toward long-term canonical KMM, never toward speed. The user decides. No silent decisions, no deferrals disguised as suggestions.

3. **Live sources only; never training data.** Every framework version, library API, configuration option, and pattern is sourced live at the moment it is invoked. Priority: Context7 (version-pinned library docs) → official vendor docs → web search (release notes, issue trackers, working-group threads) → training data as last resort, flagged inline as `⚠ TRAINING DATA — VERIFY`. If a recommendation cannot cite a live source, reject it.

   **This applies everywhere live data could be older than memory:**
   - Plan-time library research and version pins.
   - Per-file migration-guide entries (every swap citation has a live URL + verification date).
   - **User-facing questions and blockers.** Every option presented to the user must be live-sourced; every recommendation cites the live source. The user's choice deserves to be informed by the latest data, not by an agent's recall. If a question can't be live-sourced, dispatch the `researcher` subagent and wait — then ask.
   - Mid-flight surprises during execution (e.g., a missed Platform API): research before presenting options.
   - Verification-time grep patterns (the swapped-in library's package name comes from the live-sourced finding, not from memory).

4. **Drift detection.** Catch yourself on phrases like "I recall…", "typically you…", "the API is usually…", "I think this works…", "should be…". Each such phrase is a signal that training data is being substituted for live sources. Stop, run a live lookup (Principle 3), then proceed. Drift is the most common path to silent breakage; treat it as a hard stop, not a soft preference.

5. **Scope is what the user chose; abort if it can't be met.** No silent expansion. No patchwork hybrids — code moves to shared in complete units or stays native. Half-migrated classes with platform-specific shims leaking into shared code are rejected. If a file requires more than one direct expect/actual declaration, more than one new dependency, or any change to the unit's public API to migrate, stop. Surface the cost, propose deferring the file or shrinking the unit, let the user decide.

6. **1:1 port, surgical changes only.** The migrated file is **byte-identical to master** except for the edits enumerated in the file's **Diff specification** (in `migration-guide.md`, written by Opus at `/kmm-plan` time). Nothing else changes — even when the alternative looks cleaner. If a desired change isn't in the spec, the spec is the bug to fix, not the file. Reopen `/kmm-plan` for that file rather than improvising.

   The diff spec is the contract. Each entry cites a swap (a `Library swaps` entry, a `Platform APIs` entry, or a RATIFIED deviation). Lines not listed in the spec are byte-identical to master. The migrator's job is to apply the spec verbatim; it is a typist, not an author.

   If the source has a logic bug, the spec preserves it (no Modify entry "fixes" it). The bug ports as-is by virtue of its line being in an unchanged range. A subsequent migration can fix it through normal change control.

7. **Baseline is immutable. Tests first, always.** Before any file is migrated to commonMain, exhaustive tests are written for it on the pre-migration source of truth — every public method, every edge case, every error path. Tests must pass on master before migration begins. Each migration unit declares the master SHA its baseline was captured against; if master changes a scope file before the unit lands, the baseline is re-captured against the new SHA and the migration replans — never silently rebased. After migration, if a test fails, the migrated code is fixed; the test is never modified to make a failing migration pass. Re-recording a baseline requires explicit user approval and is logged as a deviation.

8. **No new dependencies, comments, stubs, or TODOs.**
   - *Dependencies*: only with live-sourced justification and explicit user approval. Carve-out: when a file moves into shared code and an import is platform-bound, the vendor-prescribed multiplatform replacement is part of the port (record the swap with citation in `findings.md`). Bridges to legacy async/threading models live only on the platform edge to non-migrated callers, never in shared code.
   - *Comments*: default is none. One line max, only when the *why* is genuinely non-obvious — a hidden constraint, a subtle invariant, a platform quirk that would surprise a future reader. Never explain the *what*; identifier names already do that. Migration-tracking comments (`// Phase N:`, `// was X, now Y`, `// removed X`) are stripped before any commit.
   - *TODO / FIXME / XXX / stubs / no-op real implementations*: always forbidden in migrated code. Audit trail lives in commits and `migration-report.md`.

9. **Canonical patterns over short-term expedience.** Judge by long-term durability, not speed. Forbidden: hardcoded values that should be resources; platform-specific APIs leaking into shared code; deferring dependency swaps with TODOs; leaving legacy-language files inside the migrated unit; deferral-shaped boundary declarations; type aliases that re-export platform types into shared code.

10. **Concurrency at the boundary is `kotlinx.coroutines` only.** RxJava, LiveData, Combine, completion handlers, and platform schedulers stay on their respective platform edges. Adapters live in platform code, never in shared. No threading model crosses the shared boundary except as `Flow`, `StateFlow`, or `suspend fun`.

11. **Documents are the contract; everything outside them gets logged.** The planning artifacts (`spec.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md`) describe what will happen. Anything done that is NOT directly specified in those documents — a scope amendment, a swap not in the migration-guide, a workaround the agent applied, a temporary fix the orchestrator made — is recorded as a numbered deviation in `migration-report.md` with a structured closure. The deviation log is the audit trail; reading the documents alone (without conversation history) is sufficient to recover full context. If the migrator, verifier, or any subagent finds itself doing something not in the documents, it stops and logs a deviation BEFORE proceeding, never after.

## Platform-boundary priority

When shared code needs platform-specific behaviour, walk top-down. First match wins. Never skip levels for convenience. Default is the simplest level that fits — heavier mechanisms require justification.

1. **Multiplatform library that already abstracts it** — preferred when one exists and is live-verified per Principle 3.
2. **Direct boundary declaration (`expect`/`actual`)** — for narrow cases (single function or value, no lifecycle).
3. **Interface in shared code + platform implementations injected at composition** — for stateful or lifecycle-bound cases. Wire through the unit's existing DI; do not introduce a new DI framework just to handle a boundary.

Every level-2 declaration is recorded in `migration-guide.md` for the relevant file with a one-line justification.

## Compatibility

Library compiler, plugin, and dependency versions must be compatible with the consumer's. Bumping past the consumer's floor causes runtime symbol-resolution failures and metadata-format mismatches that surface only at consumer build or runtime. Raise versions only when consumers raise theirs; record the floor in `findings.md` at `/kmm-plan` time.

## Process discipline

- **Constitution check at every command.** `/kmm-specify`, `/kmm-plan`, `/kmm-tasks`, `/kmm-implement`, `/kmm-verify`, and `/kmm-pr` each end with an explicit pass/fail constitution check listing which principles were touched and how. A passing check is a precondition for the next command.
- **One file = two tasks, ordered.** Every migrating file produces exactly two tasks in `tasks.md`: `T-N: Capture baseline tests for <file>` then `T-M: Migrate <file>` (M may be later than N+1; capture is fully done before any migration begins). Test capture is never folded into the migration task, never deferred, never batched across files in a way that loses per-file traceability.
- **`/kmm-plan` entries cite `file:line`.** Reject plan output containing "the X module", "somewhere in", or class-only references without line numbers.
- **`/kmm-specify` declares negative scope.** Every spec lists "explicitly out of scope" alongside "in scope". Files mentioned in neither default to out-of-scope and are not touched.
- **Migration report is a tracked artifact.** `migration-report.md` per scope holds the deviations log, updated whenever a deviation is taken, reviewed at `/kmm-verify` for closure status before `/kmm-pr`.

## Verification

A file is migrated when:
1. Baseline tests pass against the migrated code.
2. All declared shared targets build clean — no warnings demoted, no `@Suppress` added during migration.
3. The consumer compiles on every declared target without source changes outside the migrated scope.

A scope is complete when, in addition:
4. The full pre-migration test suite passes against the migrated scope as a whole.
5. `/kmm-verify` returns `VERIFY_COMPLETE_PASS` — every plan entry's claimed work is reflected in actual codebase state, no stubs/TODOs introduced, no out-of-scope changes outside the approved deviation log.

Anything less is incomplete, regardless of how the diff looks in review.

## Deviations

Every deviation from spec or plan is recorded in `migration-report.md` with:

- numbered entry (D-1, D-2, …)
- title (one line)
- status: `OPEN` / `CLOSED` / `RATIFIED` / `SUPERSEDED`
- date (ISO)
- principle bumped (or "ratified product decision")
- root cause and the constraint that forced it
- replacement or closure path

Forensic record is retained after closure. Every `OPEN` deviation must be closed (or explicitly RATIFIED with user approval) before `/kmm-pr` can run.

## Governance

Amendments to this constitution require a written diff, rationale citing which principle is clarified, expanded, or relaxed, and explicit user approval. Versioning is semantic:

- **MAJOR** — backward-incompatible governance change or principle removal
- **MINOR** — new principle or materially expanded guidance
- **PATCH** — clarifications

When the bump is ambiguous, propose reasoning before finalizing.

The goal is not KMM migration for its own sake. It is a long-term maintainable, clean migration — not a short-term expedited one.
