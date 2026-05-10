# KMM Migration Constitution

Version: 3.1.0

Governs work whose stated goal is migrating code from a platform-native codebase into Kotlin Multiplatform shared code. Supersedes assistant defaults for the duration of the migration.

Principles are ordered. Earlier principles dominate later ones when they conflict.

## Principles

1. **Architecture before code.** No code is written — not a `git mv`, not a stub, not a swap — until `architecture.md` exists on disk and `architecture-reviewer` has gated it. The architecture names target structure, identifies tech debt the migration will clean, declares behaviour-preservation strategy, and locks the refactor boundary.

2. **Understand before acting. Research → think → act, never the opposite.** Read the source of truth before porting. Every plan entry names a specific `file:line`. "TBD" and "somewhere in the module" are rejected. If behaviour is unclear, stop and read — never guess from the call site.

3. **No assumptions when stuck.** Anything not covered by spec / architecture / plan is presented to the user with: problem, candidate solutions, recommended solution, and why — biased toward long-term canonical KMM. The user decides.

4. **Live sources only; never training data.** Every framework version, library API, configuration option, and pattern is sourced live at the moment it's invoked. Priority: Context7 → official vendor docs → web search → training data only as last resort, flagged inline as `⚠ TRAINING DATA — VERIFY`. This applies everywhere live data could be older than memory: architecture decisions, plan-time research, per-file swap citations, user-facing options, mid-flight surprises, verification grep patterns. If a recommendation cannot cite a live source, reject it.

5. **Drift detection.** Phrases like "I recall…", "typically you…", "usually…", "should be…" are signals of training-data substitution. Each is a hard stop — run a live lookup, then proceed.

6. **Scope is what the user chose. Refactor lives inside scope, never outside.** No silent expansion. No half-migrated classes with platform shims leaking into shared code. If a file requires more than the architecture-approved refactors, more than one new dependency, or any change to the unit's public API, stop and surface the cost. A refactor entry may restructure the *internal* shape of a single in-scope file; it may not pull a new file into scope, change another file's public API, or extend the migration's surface.

7. **Clean code first; refactor when the source isn't clean, surgical when it is. Behaviour preserved either way.** Highest-priority output principle.

   The migration is the cheapest moment to fix tech debt the source carries — the unit is being rewritten, baseline tests cover its behaviour, consumers will compile against the result regardless. Carrying badness forward "to keep the diff small" is the failure mode this principle exists to prevent.

   **Decision tree, applied per file at architect-time:**
   - **Source is already clean** (clear naming, single responsibility, no dead branches, no mechanism-named members): port surgically — only library swaps, only `expect/actual`, only architecture-approved structural changes. Surgical is the default.
   - **Source has tech debt the migration can fix without expanding scope**: refactor is allowed. Each refactor enumerated in `architecture.md` with: clean-code violation it addresses, behaviour-preservation invariant (which baseline tests prove behaviour unchanged), boundary (the file or contiguous block).
   - **Source has tech debt the migration cannot fix without expanding scope**: log it as a follow-up note in `findings.md`, do NOT touch it.

   **Hard rules for both paths:**
   - **Public API is preserved.** Method names, parameter names, parameter order, parameter types, return types, visibility — byte-identical to source.
   - **Behaviour is preserved.** Baseline test suite (captured pre-migration on source) passes against migrated form. Post-migration test changes require explicit user-approved deviation per §8.
   - **No "while I'm here" expansion.** Refactor stays inside the architecture-approved boundary.
   - **No new dependencies to enable a refactor.** Only libraries already declared in `findings.md`.
   - **No new comments.** Names express intent; comments don't compensate for unclear shape.

   **Clean-code citations** in refactor entries reference: naming (intent over mechanism, domain over generic), functions (one thing, single abstraction level), structure (no scaffolding without behaviour, no holders without justification, no incidental complexity).

   If the source has a logic bug, the **default** is to preserve it. A bug fix is allowed only when `architecture.md` explicitly authorises it as a Refactor entry with user approval; the baseline test for the bugged behaviour is then updated as a RATIFIED deviation.

8. **Baseline is immutable. Tests first, always.** Before any file is migrated, exhaustive tests are written for it on the pre-migration source — every public method, every edge case, every error path. Tests pass on master before migration begins. Each migration unit declares the master SHA its baseline was captured against; if master changes a scope file before the unit lands, the baseline re-captures and the migration replans. After migration, if a test fails, the migrated code is fixed; the test is never modified to make a failing migration pass. Re-recording requires explicit user approval and is logged as a deviation.

   **Clock-bound code without an injection seam.** A class whose public API forbids a `Clock` / `Random` / `IO` parameter cannot be exhaustively unit-tested on master — its hidden branches are gated behind non-deterministic input. T-1 captures only what IS deterministic on master (public-API surface invariants, smoke tests over the valid output set). Behaviour-preservation tests for hidden branches are introduced post-migration alongside an architecture-approved refactor (typically: extract pure mapping into an `internal` helper that `commonTest` can exercise exhaustively). Logged as a structural deviation with `closure: { type: "manual" }`. Forcing a `Clock` parameter into the public API would violate §7.

9. **No new dependencies, comments, stubs, or TODOs.**
   - *Dependencies*: only with live-sourced justification and explicit user approval. Carve-out: when an import is platform-bound, the vendor-prescribed multiplatform replacement is part of the port (record swap with citation in `findings.md`). Bridges to legacy async/threading models live only on the platform edge to non-migrated callers, never in shared code.
   - *Comments*: default is none. One line max, only when the *why* is genuinely non-obvious. Never explain the *what*; identifier names already do that. Migration-tracking comments (`// Phase N:`, `// was X, now Y`, `// removed X`) are stripped before any commit.
   - *TODO / FIXME / XXX / stubs / no-op real implementations*: forbidden in migrated code. Audit trail lives in commits and `migration-report.md`.

10. **Canonical patterns over short-term expedience. Prevention beats cure.** Judge by long-term durability, not speed. Forbidden: hardcoded values that should be resources; platform-specific APIs leaking into shared code; deferring dependency swaps with TODOs; type aliases that re-export platform types into shared code; **scaffolding patterns added solely to make a port compile** (redundant holder classes, wrapper objects with no behaviour, indirection layers that exist only to soften a swap). Tech debt created during a migration is harder to retire than tech debt that pre-existed.

11. **Concurrency at the boundary is `kotlinx.coroutines` only.** RxJava, LiveData, Combine, completion handlers, and platform schedulers stay on their respective platform edges. Adapters live in platform code, never in shared. No threading model crosses the shared boundary except as `Flow`, `StateFlow`, or `suspend fun`.

12. **Documents are the contract; everything outside them gets logged.** `spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md` describe what will happen. Anything done that is NOT directly specified — a scope amendment, a swap not in the migration-guide, a workaround applied, a refactor not enumerated — is recorded as a numbered deviation in `migration-report.md` with structured closure. Reading the documents alone (without conversation history) recovers full context. If the migrator, verifier, or any subagent finds itself doing something not in the documents, it stops and logs the deviation BEFORE proceeding.

13. **Checkpoint PRs for reviewability.** When the architect estimates a migration will exceed reviewability (heuristic: more than ~10 in-scope files, OR any architecture-approved refactor entries, OR library swaps touching more than 3 files), it proposes a checkpoint plan: the migration is split into a sequence of master-mergeable checkpoints, each with its own goal and PR. Typical split:

    - **Checkpoint 1 — Pure relocation.** `git mv` files into `androidMain`, capture commonTest baselines, lock baseline.
    - **Checkpoint 2 — Library swaps and `expect/actual`.** Apply the swaps named in `findings.md`. Public API preserved.
    - **Checkpoint 3 — Architecture-approved refactors.** Apply the clean-code refactors enumerated in `architecture.md`.

    Each checkpoint is master-mergeable: declared targets compile, consumers compile, no checkpoint depends on a later one. Mid-checkpoint partial states are not allowed.

14. **Proportionality. Migration overhead must scale with scope.** Trivial migrations route through a fast-path (`references/fast-path.md`).

    **Trivial heuristic** (all must hold): ≤3 in-scope files; 0 `expect/actual` declarations; 0 cross-file refactors; 0 HIGH-risk refactors; all library swaps reference dependencies already declared in `gradle/libs.versions.toml`.

    **Fast-path collapses:** architect→plan→tasks→implement become a single auto-bundle phase emitting all four phase docs in one orchestrator pass. `architecture-reviewer` runs once at the bundle. User gates collapse to: scope confirm → combined architecture+plan approval → PR-open confirmation. Master health sweep defaults to compile-only. Any uncertainty during execution falls back to the full pipeline.

    **Fast-path preserves (non-negotiable):** every constitutional principle. Public API. Refactor entries still cite §7. Deviations still logged. Tests still written. All audit-trail documents still emitted.

15. **Plain language. Write so a busy reviewer can skim and get it.** Migration artifacts, user-facing prompts, PR bodies, and commit messages are read by people who do not have the constitution loaded. Every sentence requiring decoding is a sentence that gets skimmed and missed.

    Bar: a reader who knows software but does NOT know this skill's vocabulary should understand each sentence on the first read. Constitutional citations and structured labels (deviation IDs, principle numbers, RATIFIED/CLOSED states, phase names) are fine — they're labels. Reasoning should be in plain English.

    **Phrases to avoid (or always pair with a plain gloss):**
    - "scope-disproportionate" → "more ceremony than this scope warrants"
    - "structurally infeasible" → "won't compile because <concrete reason>"
    - "constitutionally clean" → "the principles are followed"
    - "mechanical extract" → "the function is moved into a helper without changing what it does"
    - "behaviour-preservation invariant" → "the test that proves the migrated code returns the same value"
    - "the diff specification" → "the line-by-line plan for editing this file"
    - "auto-close the deviation" → "the skill marks this deviation resolved when <X>"
    - "scope expansion" → "this would pull in files we said were out of scope"
    - "rubber-stamped" → "approved without real review"

    **User-facing questions:** the question text is plain. Option labels can use technical terms (they're proper nouns); every option's description explains in plain English what happens if the user picks it.

    **PR bodies:** Summary section is plain language for the 30-second skim. Technical terms appear in the labelled sections (Files changed, Deviations, Verification).

## Platform-boundary priority

When shared code needs platform-specific behaviour, walk top-down. First match wins. Default is the simplest level that fits.

1. **Multiplatform library that already abstracts it** — preferred when one exists and is live-verified per §4.
2. **Direct boundary declaration (`expect`/`actual`)** — for narrow cases (single function or value, no lifecycle).
3. **Interface in shared code + platform implementations injected at composition** — for stateful or lifecycle-bound cases. Wire through the unit's existing DI.

Every level-2 declaration is recorded in `migration-guide.md` for the relevant file with a one-line justification. Holder/wrapper indirection added solely to "make the swap compile" is forbidden by §10 — if you find yourself reaching for it, the boundary is at the wrong level; revisit `architecture.md`.

## Compatibility

Library compiler, plugin, and dependency versions must be compatible with the consumer's. Raise versions only when consumers raise theirs; record the floor in `findings.md` at plan-phase time.

## Process discipline

- **Constitution check at every phase.** Specify, architect, plan, tasks, implement, verify, pr each end with a pass/fail check listing principles touched. A passing check is a precondition for the next phase.
- **Architecture precedes plan.** Plan-phase refuses to run without `architecture.md` approved.
- **One file = two tasks, ordered.** Every migrating file produces exactly two tasks in `tasks.md`: capture baseline, then migrate. Test capture is never folded into the migration task.
- **Plan entries cite `file:line`.** Reject "the X module", "somewhere in", or class-only references without line numbers.
- **Spec declares negative scope.** Every spec lists "explicitly out of scope" alongside "in scope". Files mentioned in neither default to out-of-scope.
- **Refactor entries trace to architecture.md.** Every Refactor entry in `migration-guide.md` cites the matching authorisation in `architecture.md`. Orphan refactors are rejected as `BLOCKER`.

## Verification

A file is migrated when:
1. Baseline tests pass against the migrated code.
2. All declared shared targets build clean — no warnings demoted, no `@Suppress` added.
3. Consumer compiles on every declared target without source changes outside the migrated scope.
4. Public API matches `migration-guide.md` byte-for-byte.
5. Every `Refactor` entry traces to `architecture.md` and the baseline-test invariant cited still holds.

A checkpoint is mergeable when, additionally:
6. Checkpoint's declared targets compile cleanly *as a unit*.
7. Consumers compile cleanly against the checkpoint's HEAD.
8. **Smoke test passes.** A single consumer-side JVM test boots the DI graph, resolves every migrated type declared in `architecture.md § Smoke test`, and invokes one happy-path public method on each — without crashing. Catches runtime issues that compile and unit tests don't (missing DI bindings, `expect/actual` mismatches, init-order crashes). The instrumented variant (`androidTest`) is opt-in per scope; the JVM variant is mandatory. Smoke is gated per-checkpoint, not just at scope-end — runtime breakage introduced in CP-2 is found at CP-2, not after CP-3 ships.

A scope is complete when, additionally:
9. Full pre-migration test suite passes against migrated scope as a whole.
10. `/kmm-verify` returns `VERIFY_COMPLETE_PASS`.

## Deviations

Every deviation from spec, architecture, or plan is recorded in `migration-report.md` with:

- numbered entry (D-1, D-2, …)
- title (one line)
- status: `OPEN` / `CLOSED` / `RATIFIED` / `SUPERSEDED`
- date (ISO)
- principle bumped (or "ratified product decision")
- root cause and the constraint that forced it
- replacement or closure path

Forensic record is retained after closure. Every `OPEN` deviation must be closed (or explicitly RATIFIED) before pr-phase runs.

## Governance

Amendments require a written diff, rationale citing which principle is clarified, and explicit user approval. Versioning is semantic: MAJOR for backward-incompatible governance change, MINOR for new principle, PATCH for clarifications. Changelog: see `CHANGELOG.md` in the plugin root.

The goal is not KMM migration for its own sake. It is a long-term maintainable, clean migration. **A migration that ships short-term scaffolding into shared code has failed even if the build is green.**
