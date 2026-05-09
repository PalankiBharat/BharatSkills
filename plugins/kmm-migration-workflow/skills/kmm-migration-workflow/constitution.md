# KMM Migration Constitution

Version: 2.2.0

This constitution governs any work whose stated goal is migrating code from a platform-native codebase into Kotlin Multiplatform shared code. It supersedes assistant defaults and project conventions for the duration of the migration. On non-migration work, normal conventions resume.

Principles are ordered. Earlier principles dominate later ones when they conflict.

## Principles

1. **Architecture before code. Design first, review the design, then plan, then write.** No code is written — not a `git mv`, not a stub, not a swap — until a target architecture exists on disk in `architecture.md` and an architecture-reviewer subagent has gated it. The architecture document names the target structure, identifies tech debt in the source that will be cleaned during the migration, declares behavior-preservation strategy (which baseline tests cover which behaviors), and locks the refactor boundary. **Prevention beats cure**: design-time decisions are an order of magnitude cheaper than fixing bad shape after the migrator has applied it. If a migration is started without `architecture.md`, that is the bug — stop and run `/kmm-architect`.

2. **Understand before acting. Research first, think first, act later.** Read the source of truth before porting. Never try-fail-check. Every plan entry names a specific `file:line`. "TBD" and "somewhere in the module" are not valid entries. If behaviour is unclear, stop and read — do not guess from the call site. **The default cadence is research → think → act, never the opposite.** When an agent finds itself acting before understanding, that's the bug; correct it by stopping and going back to research.

3. **No assumptions when stuck.** Anything not covered by the spec, architecture, or plan is presented to the user with: the problem, candidate solutions, recommended solution, and why — biased toward long-term canonical KMM, never toward speed. The user decides. No silent decisions, no deferrals disguised as suggestions.

4. **Live sources only; never training data.** Every framework version, library API, configuration option, and pattern is sourced live at the moment it is invoked. Priority: Context7 (version-pinned library docs) → official vendor docs → web search (release notes, issue trackers, working-group threads) → training data as last resort, flagged inline as `⚠ TRAINING DATA — VERIFY`. If a recommendation cannot cite a live source, reject it.

   **This applies everywhere live data could be older than memory:**
   - Architecture-time pattern selection and library shortlists.
   - Plan-time library research and version pins.
   - Per-file migration-guide entries (every swap citation has a live URL + verification date).
   - **User-facing questions and blockers.** Every option presented to the user must be live-sourced; every recommendation cites the live source. The user's choice deserves to be informed by the latest data, not by an agent's recall. If a question can't be live-sourced, dispatch the `researcher` subagent and wait — then ask.
   - Mid-flight surprises during execution (e.g., a missed Platform API): research before presenting options.
   - Verification-time grep patterns (the swapped-in library's package name comes from the live-sourced finding, not from memory).

5. **Drift detection.** Catch yourself on phrases like "I recall…", "typically you…", "the API is usually…", "I think this works…", "should be…". Each such phrase is a signal that training data is being substituted for live sources. Stop, run a live lookup (Principle 4), then proceed. Drift is the most common path to silent breakage; treat it as a hard stop, not a soft preference.

6. **Scope is what the user chose; abort if it can't be met. Refactor lives inside scope, never outside.** No silent expansion. No patchwork hybrids — code moves to shared in complete units or stays native. Half-migrated classes with platform-specific shims leaking into shared code are rejected. If a file requires more than the architecture-approved refactors, more than one new dependency, or any change to the unit's public API to migrate, stop. Surface the cost, propose deferring the file or shrinking the unit, let the user decide.

   **Refactor is not a license to expand.** A refactor entry in `migration-guide.md` may restructure the *internal* shape of a single in-scope file (the architecture-approved tech-debt fix); it may not pull a new file into scope, change another file's public API, or extend the migration's surface. If a refactor's behaviour-preservation can only be proven by reaching outside the in-scope set, that is scope expansion — escalate to the user, never silently include.

7. **Clean code first; refactor when the source isn't clean, surgical when it is. Behaviour preserved either way.** This is the highest-priority output principle.

   The migration is the cheapest moment to fix tech debt the source carries: the unit is being rewritten, the baseline tests cover its behaviour, and consumers will compile against the result regardless. Carrying badness forward "to keep the diff small" is the failure mode this principle exists to prevent — the prior incident (an SDK migrated with redundant holder classes and other short-term scaffolding just to make it compile on the new platform) is exactly what is forbidden.

   **Decision tree, applied per file at `/kmm-architect` time:**
   - **Source is already clean** (clear naming, single responsibility, no dead branches, no mechanism-named members, no incidental complexity): port surgically — only library swaps, only `expect/actual`, only the architecture-approved structural changes. Surgical is the default when the source already passes a clean-code read.
   - **Source has tech debt the migration can fix without expanding scope**: refactor is **allowed and encouraged**. Each refactor is enumerated in `architecture.md` with: the clean-code violation it addresses (e.g., "name encodes mechanism, not intent"; "duplicated `Holder` wrapper that adds no behaviour"; "dead branch never reached by any test"; "function does two things"), the behaviour-preservation invariant (which baseline tests prove behaviour is unchanged), and the boundary (the file or contiguous block being refactored).
   - **Source has tech debt the migration cannot fix without expanding scope**: log it as a follow-up note in `findings.md` (`Tech debt — out of current scope`), do NOT touch it, and do NOT carry the bad shape into shared code by expanding it; if the bad shape blocks the migration, escalate per Principle 6.

   **Hard rules that hold for both surgical and refactor paths:**
   - **Public API is preserved.** Method names, parameter names, parameter order, parameter types, return types, and visibility are byte-identical to source. Internal refactor cannot leak through the public surface.
   - **Behaviour is preserved.** The baseline test suite (captured pre-migration on the source) passes against the migrated form. Post-migration test changes require an explicit user-approved deviation per Principle 8.
   - **No "while I'm here" expansion.** Refactor stays inside the architecture-approved boundary. Anything beyond that is scope expansion (Principle 6).
   - **No new dependencies to enable a refactor.** A refactor may only use the libraries already declared in `findings.md`'s Library Versions table.
   - **No new comments.** Refactor follows Principle 9 — names express intent; comments don't compensate for unclear shape.

   The diff specification (the migrator's contract in `migration-guide.md`) supports both paths: a clean source produces an Unchanged-heavy spec with a few swap-cited Modify entries; a refactored file produces a spec with explicit `Refactor` entries — each citing its architecture.md justification and the baseline test that proves behaviour preservation. The migrator applies the spec verbatim either way; it does not author refactors itself.

   If the source has a logic bug, the **default** is to preserve it (the bug ports as-is via an unchanged range, and a follow-up migration fixes it through normal change control). A bug fix is allowed only when `architecture.md` explicitly authorises it as a `Refactor` entry with user approval — at which point the baseline test for the bugged behaviour must be updated as a RATIFIED deviation alongside the code fix.

8. **Baseline is immutable. Tests first, always.** Before any file is migrated to commonMain, exhaustive tests are written for it on the pre-migration source of truth — every public method, every edge case, every error path. Tests must pass on master before migration begins. Each migration unit declares the master SHA its baseline was captured against; if master changes a scope file before the unit lands, the baseline is re-captured against the new SHA and the migration replans — never silently rebased. After migration, if a test fails, the migrated code is fixed; the test is never modified to make a failing migration pass. Re-recording a baseline requires explicit user approval and is logged as a deviation.

   **Clock-bound code without an injection seam.** A class whose public API forbids a `Clock` / `Random` / `IO` parameter (e.g., a no-arg constructor consumers depend on, where adding a parameter would break Principle 7's public-API preservation) cannot be exhaustively unit-tested on master — its hidden branches are gated behind a non-deterministic input. The skill recognises this as a structural gap, not a process gap. T-1 captures only what IS deterministic on master (the public-API surface invariants, smoke tests over the valid output set). Behaviour-preservation tests for the hidden branches are introduced post-migration alongside an architecture-approved refactor (typically: extract the pure mapping into an `internal` helper that `commonTest` can exercise exhaustively). Logged as a structural deviation with `closure: { type: "manual" }`. The mitigation is the architect-approved refactor's LOW-risk classification (mechanical extract; body verbatim) plus visual diff inspection plus the post-migration exhaustive test. Forcing a `Clock` parameter into the public API to satisfy this principle would violate Principle 7 — the gap is accepted, documented, and structurally bounded.

9. **No new dependencies, comments, stubs, or TODOs.**
   - *Dependencies*: only with live-sourced justification and explicit user approval. Carve-out: when a file moves into shared code and an import is platform-bound, the vendor-prescribed multiplatform replacement is part of the port (record the swap with citation in `findings.md`). Bridges to legacy async/threading models live only on the platform edge to non-migrated callers, never in shared code.
   - *Comments*: default is none. One line max, only when the *why* is genuinely non-obvious — a hidden constraint, a subtle invariant, a platform quirk that would surprise a future reader. Never explain the *what*; identifier names already do that. Migration-tracking comments (`// Phase N:`, `// was X, now Y`, `// removed X`) are stripped before any commit.
   - *TODO / FIXME / XXX / stubs / no-op real implementations*: always forbidden in migrated code. Audit trail lives in commits and `migration-report.md`.

10. **Canonical patterns over short-term expedience. Prevention beats cure.** Judge by long-term durability, not speed. Forbidden: hardcoded values that should be resources; platform-specific APIs leaking into shared code; deferring dependency swaps with TODOs; leaving legacy-language files inside the migrated unit; deferral-shaped boundary declarations; type aliases that re-export platform types into shared code; **scaffolding patterns added solely to make a port compile** (redundant holder classes, wrapper objects with no behaviour, indirection layers that exist only to soften a swap). When the choice is between a structurally-correct shape that costs more design time and a quick-to-write shape that creates tech debt, the correct shape wins — every time. Tech debt created during a migration is harder to retire than tech debt that pre-existed.

11. **Concurrency at the boundary is `kotlinx.coroutines` only.** RxJava, LiveData, Combine, completion handlers, and platform schedulers stay on their respective platform edges. Adapters live in platform code, never in shared. No threading model crosses the shared boundary except as `Flow`, `StateFlow`, or `suspend fun`.

12. **Documents are the contract; everything outside them gets logged.** The planning artifacts (`spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md`) describe what will happen. Anything done that is NOT directly specified in those documents — a scope amendment, a swap not in the migration-guide, a workaround the agent applied, a refactor not enumerated in architecture.md, a temporary fix the orchestrator made — is recorded as a numbered deviation in `migration-report.md` with a structured closure. The deviation log is the audit trail; reading the documents alone (without conversation history) is sufficient to recover full context. If the migrator, verifier, or any subagent finds itself doing something not in the documents, it stops and logs a deviation BEFORE proceeding, never after.

13. **Checkpoint PRs for reviewability.** A PR a human cannot review is a PR a human will rubber-stamp; rubber-stamped migrations are where tech debt enters shared code unnoticed. When the architect phase estimates a migration will exceed the reviewability threshold (heuristic: more than ~10 in-scope files, or any architecture-approved refactor entries present, or library swaps that touch more than 3 files), it proposes a **checkpoint plan**: the migration is split into a sequence of master-mergeable checkpoints, each with its own goal and PR, each independently shippable. A typical split:

    - **Checkpoint 1 — Pure relocation.** `git mv` files into `androidMain` (no behaviour change, no swap). Capture commonTest baselines. Lock the baseline. This PR is reviewable in minutes — the diff is moves and tests.
    - **Checkpoint 2 — Library swaps and `expect/actual`.** Apply the swaps named in `findings.md`. Public API preserved. Tests still green.
    - **Checkpoint 3 — Architecture-approved refactors.** Apply the clean-code refactors enumerated in `architecture.md`. Tests still green.
    - Additional checkpoints when the unit is large or has independent sub-units.

    Each checkpoint is a separate branch off the previous (or off master once the previous lands). Each runs its own verify-phase and pr-phase. The user approves the checkpoint plan once at architect-time; the `/kmm` orchestrator executes the rest sequentially, surfacing per-checkpoint state. **A checkpoint is master-mergeable**: it does not depend on later checkpoints, all declared targets compile, and consumers compile clean. Mid-checkpoint partial states are not allowed — a checkpoint either lands as a unit or is reverted as a unit.

14. **Proportionality. Migration overhead must scale with migration scope.** A 1-file extract+swap migration that walks through architect→plan→tasks→implement→verify→pr with full subagent dispatches, runtime test sweeps, androidMain staging, T-LOCK ceremony, and the full audit-trail document set is overkill — and the overhead becomes its own failure mode (rubber-stamped reviews, abandoned migrations, friction tax that pushes contributors back to ad-hoc ports). The skill recognises **trivial migrations** at the end of specify-phase and routes them through a fast-path that preserves all the structural protections (clean-code-first, public-API preservation, deviation logging, reviewer subagents) while collapsing the workflow's ceremony.

    **Trivial-migration heuristic** (all must hold):
    - ≤3 in-scope files
    - 0 `expect/actual` declarations needed
    - 0 cross-file refactors (file-internal LOW-risk refactors are allowed)
    - 0 HIGH-risk refactors
    - All library swaps reference dependencies already declared in `gradle/libs.versions.toml`

    **What the fast-path collapses:**
    - architect→plan→tasks→implement become a single auto-bundle phase that emits all four phase docs in one orchestrator pass.
    - architecture-reviewer + plan-analyzer subagents dispatch in parallel; only `BLOCKER` and `HIGH` findings block; `MEDIUM` findings are logged automatically without a re-edit cycle.
    - User gates collapse to: scope confirm → combined architecture+plan approval → PR-open confirmation. Three prompts instead of seven.
    - Master health sweep defaults to compile-only (per-target shared compile + test-source-set compile); runtime full-suite sweep is opt-in.
    - androidMain staging is skipped when in-scope file dependencies resolve to modules that depend on `:shared` (the migration goes directly app → commonMain in a single atomic operation; T-1/T-LOCK/M-1 collapse).

    **What the fast-path preserves (non-negotiable):**
    - Every constitutional principle still applies. Public API is preserved. Refactor entries still cite `references/clean-code.md`. Deviations are still logged. Tests are still written.
    - All audit-trail documents (`spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md`, `migration-report.md`) are still written and committed — they're generated in one pass instead of several, but the forensic record is identical.
    - Reviewer subagents still run.

    See `references/fast-path.md` for the full recipe and the orchestrator's routing logic.

    **The default is still the full pipeline.** Fast-path requires explicit detection of the trivial heuristic. Any uncertainty (scope ambiguity, surprise dependency, swap-needs-research) falls back to the full pipeline.

15. **Plain language. Write so a busy reviewer can skim and get it.** Migration artifacts (`spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `migration-report.md`, `findings.md`, `tasks.md`), user-facing prompts, PR bodies, and commit messages are read by people who do not have the constitution loaded into their head. Every sentence that requires decoding is a sentence that gets skimmed and missed — and a missed sentence in a deviation log or PR body is how the audit trail silently breaks.

    The bar: a reader who knows software but does **not** know this skill's vocabulary should understand each sentence on the first read. Constitutional citations and structured labels (deviation IDs, principle numbers, RATIFIED/CLOSED states, phase names) are fine — they're labels, not arguments. But the *reasoning* should be in plain English.

    **Phrases to avoid (or always pair with a plain gloss in the same sentence):**

    - "scope-disproportionate" → say "more ceremony than this scope warrants" or "overkill for one file"
    - "structurally infeasible" → say "won't compile because <concrete reason>"
    - "constitutional accommodation" / "constitutionally clean" → say "we accept this as a trade-off" or "the principles are followed"
    - "mechanical extract" → say "the function is moved into a helper without changing what it does"
    - "behaviour-preservation invariant" → say "the test that proves the migrated code returns the same value"
    - "the diff specification" → say "the line-by-line plan for editing this file"
    - "auto-close the deviation" → say "the skill marks this deviation resolved when <X>"
    - "scope expansion" → say "this would pull in files we said were out of scope"
    - "rubber-stamped" → say "approved without real review"

    See `references/plain-language.md` for the full swap list and worked examples drawn from real migrations.

    **User-facing questions: the question text is plain.** Option labels can use technical terms when those are the skill's proper nouns (e.g., "fast-path", "T-LOCK", "expect/actual") — readers will see them again across the skill — but every option's *description* explains in plain English what happens if the user picks it. A user who has not read this constitution should be able to pick correctly.

    **PR bodies: the Summary section is plain language for the 30-second skim.** Technical terms appear in the table-of-contents-style sections (Files changed, Deviations, Verification) where they're labels. Every load-bearing claim in the Summary is restated in plain English at least once.

    **Commit messages: same rule.** The first sentence of the body explains what changed in plain language. Subsequent paragraphs can use technical terms because the reader has now opted into depth.

    Plain language is not dumbing down. It is the difference between an audit trail that survives a year and one that goes stale the moment context changes. When in doubt, write the version a tired reviewer at 5pm on Friday can read in 30 seconds.

## Platform-boundary priority

When shared code needs platform-specific behaviour, walk top-down. First match wins. Never skip levels for convenience. Default is the simplest level that fits — heavier mechanisms require justification.

1. **Multiplatform library that already abstracts it** — preferred when one exists and is live-verified per Principle 4.
2. **Direct boundary declaration (`expect`/`actual`)** — for narrow cases (single function or value, no lifecycle).
3. **Interface in shared code + platform implementations injected at composition** — for stateful or lifecycle-bound cases. Wire through the unit's existing DI; do not introduce a new DI framework just to handle a boundary.

Every level-2 declaration is recorded in `migration-guide.md` for the relevant file with a one-line justification. Holder/wrapper indirection added solely to "make the swap compile" is forbidden by Principle 10 — if you find yourself reaching for it, the boundary is either at the wrong level or the architecture didn't account for it; stop and revisit `architecture.md`.

## Compatibility

Library compiler, plugin, and dependency versions must be compatible with the consumer's. Bumping past the consumer's floor causes runtime symbol-resolution failures and metadata-format mismatches that surface only at consumer build or runtime. Raise versions only when consumers raise theirs; record the floor in `findings.md` at plan-phase time.

## Process discipline

- **Constitution check at every phase.** Specify, architect, plan, tasks, implement, verify, and pr each end with an explicit pass/fail constitution check listing which principles were touched and how. A passing check is a precondition for the next phase.
- **Architecture precedes plan.** The plan phase refuses to run without `architecture.md` present and architecture-reviewer-approved.
- **One file = two tasks, ordered.** Every migrating file produces exactly two tasks in `tasks.md`: `T-N: Capture baseline tests for <file>` then `T-M: Migrate <file>` (M may be later than N+1; capture is fully done before any migration begins). Test capture is never folded into the migration task, never deferred, never batched across files in a way that loses per-file traceability.
- **Plan entries cite `file:line`.** Reject plan output containing "the X module", "somewhere in", or class-only references without line numbers.
- **Spec declares negative scope.** Every spec lists "explicitly out of scope" alongside "in scope". Files mentioned in neither default to out-of-scope and are not touched.
- **Migration report is a tracked artifact.** `migration-report.md` per scope holds the deviations log, updated whenever a deviation is taken, reviewed at verify-phase for closure status before pr-phase.
- **Refactor entries trace to architecture.md.** Every `Refactor` entry in `migration-guide.md` cites the matching authorisation in `architecture.md` (`§<section>`). Orphan refactors — refactor entries without architecture authorisation — are rejected by `plan-analyzer` as `BLOCKER`.

## Verification

A file is migrated when:
1. Baseline tests pass against the migrated code.
2. All declared shared targets build clean — no warnings demoted, no `@Suppress` added during migration.
3. The consumer compiles on every declared target without source changes outside the migrated scope.
4. Public API matches `migration-guide.md` byte-for-byte (refactors are internal-only).
5. Every `Refactor` entry traces to `architecture.md` and the baseline-test invariant it cited still holds.

A scope is complete when, in addition:
6. The full pre-migration test suite passes against the migrated scope as a whole.
7. `/kmm-verify` returns `VERIFY_COMPLETE_PASS` — every plan entry's claimed work is reflected in actual codebase state, no stubs/TODOs introduced, no out-of-scope changes outside the approved deviation log, no orphan refactors.

A checkpoint is mergeable when, in addition:
8. The checkpoint's declared targets compile cleanly *as a unit* (independent of later checkpoints).
9. Consumers compile cleanly against the checkpoint's HEAD (the next checkpoint may not be required to make the previous one valid).

Anything less is incomplete, regardless of how the diff looks in review.

## Deviations

Every deviation from spec, architecture, or plan is recorded in `migration-report.md` with:

- numbered entry (D-1, D-2, …)
- title (one line)
- status: `OPEN` / `CLOSED` / `RATIFIED` / `SUPERSEDED`
- date (ISO)
- principle bumped (or "ratified product decision")
- root cause and the constraint that forced it
- replacement or closure path

Forensic record is retained after closure. Every `OPEN` deviation must be closed (or explicitly RATIFIED with user approval) before pr-phase can run.

## Governance

Amendments to this constitution require a written diff, rationale citing which principle is clarified, expanded, or relaxed, and explicit user approval. Versioning is semantic:

- **MAJOR** — backward-incompatible governance change or principle removal
- **MINOR** — new principle or materially expanded guidance
- **PATCH** — clarifications

### v2.1.0 — Proportionality + clock-bound clause (2026-05-09)

- **New §14 — Proportionality**: trivial migrations route through a fast-path that collapses workflow ceremony while preserving every structural protection. See `references/fast-path.md`.
- **§8 expanded — clock-bound code without an injection seam**: the master-untestability of clock-bound public APIs is recognised as a structural gap; behaviour-preservation tests for hidden branches are introduced post-migration alongside an architecture-approved seam-creating refactor.
- Lessons sourced from the GreetingUseCase migration in `sniper-v2-android` (consumer-repo PR #369): D-2 (scope-disproportionate runtime sweep), D-4 (clock-bound testability gap), D-5 (androidMain staging infeasible) are now first-class behaviours of the skill rather than ad-hoc deviations.

### v2.2.0 — Plain language (2026-05-09)

- **New §15 — Plain language**: artifacts, user prompts, PR bodies, and commit messages are written so a busy reviewer can skim and understand them on the first read. Adds a swap list of common buzzwords and their plain replacements. See `references/plain-language.md`.
- Motivation: the GreetingUseCase migration's audit trail (#369) was constitutionally clean but dense — phrases like "scope-disproportionate" and "structurally infeasible" appeared throughout. A reviewer without the skill's vocabulary loaded would skim past the load-bearing reasoning. The principle exists to keep the audit trail readable a year later when context has rotted.

When the bump is ambiguous, propose reasoning before finalizing.

The goal is not KMM migration for its own sake. It is a long-term maintainable, clean migration — not a short-term expedited one. **A migration that ships short-term scaffolding into shared code has failed even if the build is green.**
