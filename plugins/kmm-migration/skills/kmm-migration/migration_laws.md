# Migration Laws

> Every subagent prompt in the kmm-migration skill begins with this file.
> Violations fail the task. YOU MUST read the rationalization table under
> each law before any action that could implicate it.

## Contents

- [Decision lens](#decision-lens)
- [Source-of-truth precedence](#source-of-truth-precedence)
- Law 01 — 1:1 PORT ONLY + SURGICAL CHANGES
- Law 02 — BASELINE IS IMMUTABLE DURING MIGRATION
- Law 03 — SCOPE IS THE FEATURE
- Law 04 — NO NEW DEPENDENCIES
- Law 05 — EVIDENCE BEFORE CLAIMS
- Law 06 — PHASE DISCIPLINE
- Law 07 — STOP ON BLOCKER
- Law 08 — REPORT FACTS
- Law 09 — NO NEW COMMENTS / TODOs / STUBS
- Law 10 — NO PRODUCTION-CODE CHANGES IN PHASES 1 OR 2
- Law 11 — FILE REFERENCES USE path:line FORMAT
- Law 12 — UNDERSTAND BEFORE ACTING; SURFACE CONFUSION
- Law 13 — LIVE KNOWLEDGE, NEVER TRAINING-DATA KNOWLEDGE
- Law 14 — SIMPLICITY FIRST; GOAL-DRIVEN EXECUTION
- Law 15 — CANONICAL KMP APPROACH OVER SHORT-TERM EXPEDIENCE (THE MOST IMPORTANT RULE)

---

## Decision lens

Every decision the skill makes or escalates is judged through three lenses, in priority order:

1. **User experience** — identical to OG UX (pixel, timing, interaction).
2. **Performance** — migrated code meets or beats OG performance.
3. **Code quality** — follows clean-code principles and whatever stack the `researcher` identifies as current community best practice.

If any choice trades off against any of these, the subagent STOPs and escalates with a `REQUIRES_APPROVAL`.

---

## Source-of-truth precedence

When a subagent is uncertain, it consults sources in this order:

1. **Behaviour / logic semantics** → legacy Android code at the baseline commit + baseline unit tests.
2. **Feature scope** → `kmm_migration/baseline/<feature>/` manifests.
3. **Migration intent** → `kmm_migration/plans/<feature>_migration_guide.md`.
4. **KMP workflow / ordering / project structure / source-set rules / interop pattern / library swap / iOS integration** → kotlinlang.org canonical docs FIRST, via WebFetch or context7 (whichever has the page indexed). Entry-point URLs in `references/knowledge_lookup_protocol.md`.
5. **Library behaviour for non-KMP-foundational topics, third-party APIs, framework-specific questions** → context7, then WebSearch (per Law 13).

Steps 4 and 5 are ordered: kotlinlang.org wins for KMP-shaped questions before any community source is consulted. This is the live-source corollary of Law 15.

If none answer the question, STOP and escalate as `NEEDS_CONTEXT`.

---

## Law 01 — 1:1 PORT ONLY + SURGICAL CHANGES

**1:1 PORT ONLY + SURGICAL CHANGES.** Zero behaviour changes. No bug fixes. No refactors. No API changes. No "while I'm here" improvements. **Every changed line must trace directly to a migration_guide entry.** Do not "improve" adjacent code, comments, formatting, or imports that your change did not itself make unused. Match existing style even if you'd write it differently. Exceptions exist only as named escape hatches (seam insertion, baseline rebase) with user approval.

### Law 01 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll just quickly fix this bug while I'm here" | That's a refactor. Log in `findings.md`, do not fix. |
| "This signature is weirdly named" | Out of scope. Leave it. |
| "I'll add a TODO to clean this up later" | TODOs are deferrals. Rule 9 violation. |
| "Probably behaves the same" | Probably isn't evidence. Run the baseline (rule 5). |
| "I'll stub this out for now" | Stubs are deferrals. Escalate with `REQUIRES_APPROVAL`. |
| "R.string.welcome doesn't resolve in commonMain so I'll inline 'Welcome'" | Inlining the literal is a 1:1-port violation — the user's resource value just got duplicated in a string literal that will drift from the canonical `strings.xml`. Move the resource to `composeResources/` first (Precondition R), switch to `Res.string.welcome`, then port the screen. NEVER inline. |
| "I'll just hardcode 12.dp instead of dimensionResource(R.dimen.padding_md) — Compose Multiplatform doesn't have dimen" | Hardcoding silently is a Law 1 violation. Either declare an `object Dimens` in commonMain that holds the values explicitly (canonical), or descope the screen until the resource layer is migrated. The reviewer greps for literal `.dp` / `.sp` values that came from a `dimen` source. |
| "I'll widen this from `internal` to `public` because the iOS code might need it" | Don't widen on extraction. `internal` carries across `commonMain` / `androidMain` / `iosMain` of the same module. Widening changes the public API surface — that's a refactor, not a port. |

---

## Law 02 — BASELINE IS IMMUTABLE DURING MIGRATION

**BASELINE IS IMMUTABLE DURING MIGRATION.** Tests, goldens, and flows captured in Phase 1 do not change mid-migration. If the migration fails them, the migration is wrong. Tolerance envelopes captured in Phase 1 remain fixed; the named `rebase_baseline` escape hatch is the only way to modify baselines, and it is a distinct, user-gated operation.

**Re-recording any baseline artifact is a Law 2 event.** This includes — but is not limited to — overwriting `*.png` / `*.webp` / `*.json` files under `**/snapshots/`, `**/screenshots/`, or `**/goldens/`; regenerating Roborazzi or Paparazzi reference images; updating tolerance constants; modifying any file under `kmm_migration/baseline/<feature>/`. "The migration changed pixel rendering" is precisely the case Law 2 exists to catch — it MUST surface as a `REQUIRES_APPROVAL` via `escape_hatch_rebase_baseline`, never as a silent re-record. Every code-producing subagent MUST run a `git diff --name-only` check on these paths before reporting and emit `STATUS: BLOCKED` if any baseline artifact has been modified.

### Law 02 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll just tweak the tolerance — it's barely off" | That's a silent baseline modification. Law 2 violation. Use the named `rebase_baseline` escape hatch, gated by user approval. |
| "The emulator must be flaky — let me re-record the golden" | Re-recording without an approved `rebase_baseline` is a Law 2 violation. Document the flakiness in `findings.md` and escalate. |
| "The migration changed pixel rendering so the golden needs updating" | Exactly the case Law 2 exists for. STOP, emit `STATUS: BLOCKED`, list the modified golden files. The orchestrator escalates via `escape_hatch_rebase_baseline`. Never silent. |
| "The test runner overwrote the goldens automatically" | Then the runner was misconfigured for migration mode. Revert the PNGs (orchestrator handles), reconfigure to fail-not-record, escalate. |
| "The golden is slightly off — I'll bump the threshold" | Threshold drift is never silent. The tolerance envelope was locked in Phase 1. STOP and escalate via `rebase_baseline`. |
| "The test was too strict anyway — I'll loosen it" | You do not have authority to redefine the baseline contract mid-migration. Only an approved `rebase_baseline` operation may do this. |
| "Small drift is probably fine — the feature still looks right" | Probably isn't evidence (Law 5). Any failure beyond tolerance is a migration bug, not a reason to adjust the baseline. |

---

## Law 03 — SCOPE IS WHAT THE USER CHOSE

**SCOPE IS WHAT THE USER CHOSE.** The user picks the migration scope at
Phase 0 bootstrap — whole feature, single module, single screen, or single
file — and the choice is recorded in `state.json` under `scope_type` and
`scope_targets`. The orchestrator and every subagent honour that scope
exactly. Touching anything outside the chosen scope requires
`REQUIRES_APPROVAL` — never silent expansion. The skill helps the user
decide a sensible scope based on dependency analysis of the actual codebase
and recommends a default, but the user picks; the skill never picks for
them.

### Law 03 — Rationalization table

| Thought | Reality |
|---|---|
| "The user said 'login' so they obviously meant the whole feature" | The user picks the scope explicitly at Gate 0 / Phase 0 — feature, module, screen, or file. The skill shows them options based on dependency analysis and recommends a default; it does not assume. |
| "While I'm here I'll tidy the related config" | Out of scope. Law 3 violation. Leave it and escalate if it blocks you. |
| "This unused import bothers me" | Leave it. Cleanup outside the chosen-scope boundary violates Law 1 and Law 3. |
| "I'm touching this file because it imports from the target" | Touching a file solely because it imports the migration target is scope creep. STOP and escalate. |
| "I need to fix one line in build.gradle to get it compiling" | Build file changes outside the chosen scope require escalation. STOP — do not make unilateral changes. |
| "Adjacent file has a typo I noticed" | Not your task. Log in `findings.md` and leave it. Law 3 forbids it. |
| "The user picked 'screen' but a string the screen uses lives in a parent module — I'll just expand to include the strings.xml" | That's silent expansion. Raise `REQUIRES_APPROVAL`: ask the user to expand scope explicitly OR descope the affected resources OR defer the migration. NEVER touch out-of-scope files without recorded approval. |
| "The user said 'this single file' but I see it depends on three other files in commonMain that aren't migrated yet — let me migrate those too" | Scope is what the user chose. If preconditions can't be met inside the chosen scope, raise `PRECONDITION_BLOCKED` and let the orchestrator ask the user. |

---

## Law 04 — NO NEW DEPENDENCIES

**NO NEW DEPENDENCIES** without live-sourced justification **and** orchestrator approval. The skill does not prescribe libraries; the `researcher` identifies current community best practice per invocation. Existing repo dependencies are preserved unless Android-only and literally incompatible.

**Carve-out — JetBrains-prescribed swaps are not "new" deps.** When a file
moves to `commonMain` and one of its imports is a JVM-only library that
JetBrains' canonical migration page (or a researcher-fetched current
docs page) names a multiplatform replacement for, replacing the import
is part of the port — not a new dependency addition. The replacement is
recorded in `kmm_migration/findings.md` with citation; the diff that
swaps the import is part of the migration's logical scope. This is
consistent with Law 15 (canonical KMP approach) and the per-file
Precondition D in `references/migration_preconditions.md`.

### Law 04 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll add this nice new lib that's not in the repo" | Law 4 violation unless the researcher's live lookup names it as the canonical replacement for a disqualified dep. Otherwise — escalate. |
| "The repo uses RxJava but I'd prefer Flow" | Preference doesn't justify a swap. The swap is justified because RxJava is JVM-only and the file is moving to commonMain — the researcher confirms the canonical replacement. Cite. |
| "I'll keep RxJava and bridge with kotlinx-coroutines-rxN inside commonMain" | Bridge in commonMain is a Law 4 violation in disguise — it imports a JVM-only construct (RxJava types) into shared code. The bridge is for the Android edge to non-migrated callers ONLY. |
| "I added a small util library to make this cleaner" | Out of scope. Either it's a researcher-named canonical replacement for a disqualified concern (record + cite + proceed) or it's a Law 4 violation. |

---

## Law 05 — EVIDENCE BEFORE CLAIMS

**EVIDENCE BEFORE CLAIMS.** No "tests pass" without runner output. No "UI matches" without diff output. No "done" without gate artifacts attached.

### Law 05 — Rationalization table

| Thought | Reality |
|---|---|
| "I'm pretty sure the tests passed" | Pretty sure is not evidence. Run the test suite and attach the output. |
| "The build looked green before my change" | Before your change is irrelevant. Run it now and attach the result. |
| "It compiled so the tests should still pass" | Compilation is not test execution. Run the tests. Attach the output. |
| "Obviously this matches the baseline" | Obviously is not a diff. Run the comparison tool and attach output. |
| "I'll check the screenshots later" | Later is not now. Attach evidence before marking the task done. |

---

## Law 06 — PHASE DISCIPLINE

**PHASE DISCIPLINE.** Execute ONLY the dispatched step. Never advance. Never start the next phase.

### Law 06 — Rationalization table

| Thought | Reality |
|---|---|
| "Let me just start the next batch while this review runs" | Law 6 violation. STOP. The gate must close before any advancement. |
| "I'll pre-draft the iOS port since I already understand the code" | You were not dispatched for Phase 5. Law 6 violation — discard that work. |
| "It's efficient to do inventory and plan in one pass" | Efficiency does not override phase gates. Execute the dispatched step only. |
| "The gate is a formality — let's advance" | Gates are not formalities. They are the mechanism that keeps baseline, plan, and migration in sync. STOP. |
| "I finished early so I'll tackle the next file" | Your dispatch defined your scope. Finishing early means reporting DONE, not advancing. |

---

## Law 07 — STOP ON BLOCKER

**STOP ON BLOCKER.** If a precondition is not met, STOP and escalate. Never improvise a workaround.

---

## Law 08 — REPORT FACTS

**REPORT FACTS.** File paths, test output, diff summaries. No interpretation beyond what was asked.

---

## Law 09 — NO NEW COMMENTS / TODOs / STUBS

**DEFAULT: NO NEW COMMENTS. NO TODOs. NO STUBS.** Add a comment **only** when a downstream migration phase (Phase 4 parity, Phase 5 iOS, Phase 6 closeout review) genuinely needs it to avoid misreading the code — e.g., a non-obvious `accepted_deltas` boundary at a specific line. When unavoidable, **one line, maximum**; no prose, no multi-line blocks, no docstrings. Well-named identifiers explain themselves — if the reader would need a comment, rename the identifier instead. Migration rationale belongs in `findings.md`, not in code. TODOs / FIXMEs / XXX / stubs are always forbidden (deferrals → rule 1 violation). If removing a line of comment would not confuse the next phase's subagents, delete it.

### Law 09 — Rationalization table

| Thought | Reality |
|---|---|
| "This logic is tricky — let me add a brief comment" | If a reader needs a comment to understand it, rename the identifier. Rule 9. |
| "I'll add a TODO for the iOS phase" | TODOs are deferrals — always forbidden. If Phase 5 genuinely needs it, put it in the migration_guide Phase-5 entry, not in code. |
| "Just a short multi-line docblock explaining why" | No multi-line anything. One line max, and only if a downstream subagent genuinely needs it. |
| "A future reviewer might wonder why we did this" | "Why" belongs in `findings.md` as a dated decision, not in code. |
| "The comment was there before, I'll keep it" | If it wasn't written for this migration and isn't load-bearing for the next phase, delete it alongside your change — unless deleting would be an out-of-scope edit under rule 1. In that case, leave untouched but never extend. |

---

## Law 10 — NO PRODUCTION-CODE CHANGES IN PHASES 1 OR 2

**NO PRODUCTION-CODE CHANGES in Phases 1 or 2.** Phase 1 adds tests only. Phase 2 produces plan documents only. Seam escape hatch exists via separate dispatch.

---

## Law 11 — FILE REFERENCES USE path:line FORMAT

**FILE REFERENCES USE `path:line` FORMAT.** e.g., `app/src/main/java/com/app/LoginViewModel.kt:42`.

---

## Law 12 — UNDERSTAND BEFORE ACTING; SURFACE CONFUSION

**UNDERSTAND BEFORE ACTING; SURFACE CONFUSION.** When confused, READ the source of truth first, understand it thoroughly, then act. Never "try change → fail → then check." **State assumptions explicitly** in your report. If multiple interpretations exist, list them and emit `STATUS: NEEDS_CONTEXT` rather than pick silently. Hiding confusion behind plausible prose is a rule 12 violation.

**Planning corollary — codebase-first, zero ambiguity.** Before drafting
the migration plan (Phase 2b), the planner MUST read every file in
`plan.files_to_touch` from the actual codebase. Every plan prescription
names a specific `file:line` change — never "somewhere in the module" /
"the relevant ViewModel" / "wherever appropriate". Generic prescriptions,
TBD markers, "implement later" comments, and hedging language ("probably
this should ...") are all Law 12 violations. The plan_critic rejects any
plan that contains them. The planner does NOT write the plan from
training-data assumptions about how the project is structured — it reads
the project AS IT EXISTS now and prescribes against the actual files.

### Law 12 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll write something and see what happens" | That is trial-and-error, not understanding. READ the source of truth first. Law 12 violation. |
| "Tests will tell me if I got it right" | Tests confirm — they do not replace understanding. Understand first, then act, then verify. |
| "Probably behaves like X, let me try" | Probably is not understanding. Read the source of truth. If still unclear, emit `STATUS: NEEDS_CONTEXT`. |
| "The code is too complex to fully understand — I'll work around it" | Complexity is not an excuse to guess. Surface the confusion explicitly; never hide it behind plausible prose. |
| "I'll figure it out as I go" | Law 12 violation. Name your assumptions explicitly before acting, or stop and escalate. |
| "I'll write a generic plan — the migrator will figure out the file-level details at port time" | Law 12 planning corollary — the plan MUST read the actual files and prescribe against `file:line`. Pushing details to "port time" is hidden ambiguity. The plan_critic rejects this. |
| "The repo probably uses MVVM — I'll plan against that pattern" | "Probably" is not "I read the codebase and confirmed." Open the files. Confirm the actual pattern. Plan against what's there, not what's typical. |
| "The migration_guide can say 'use a multiplatform networking lib' — the migrator will pick one" | Generic prescription. The plan must name the specific lib (researcher-resolved, cited) AND the specific file:line where it's wired in. Otherwise the migrator at port time has to make an architectural decision the planner should have made. |

---

## Law 13 — LIVE KNOWLEDGE, NEVER TRAINING-DATA KNOWLEDGE (THE MOST IMPORTANT RULE)

**LIVE KNOWLEDGE, NEVER TRAINING-DATA KNOWLEDGE (THE MOST IMPORTANT RULE).** Every KMM-related technology, library, version, framework, pattern, architectural choice, or migration technique is sourced live at invocation time. Priority order:

- **Priority 1** — `mcp__context7__resolve-library-id` + `mcp__context7__query-docs`.
- **Priority 2** — `WebSearch` / `find-docs` skill.
- **Priority 3** — training data, **only** if 1 and 2 failed, and **only** when the claim is flagged `⚠ TRAINING DATA — VERIFY`.

The skill ships **no** hardcoded library recommendations, version pins, or pattern preferences. If a subagent finds itself asserting "the standard KMP library is X" or "the common pattern is Y" without a live source, it is violating rule 13. KMP evolves faster than training data.

### Law 13 — Rationalization table

| Thought | Reality |
|---|---|
| "I know Mokkery is the KMP mocker" | You remembered that from training data. Rule 13: verify via context7 *now*. It may have been superseded. |
| "Everyone uses Koin" | Assertion from training data. Check context7 and the repo — may be Metro, may be kotlin-inject, may still be Koin. |
| "The standard tolerance is 0.01f" | Sourceless claim. Find the live recommendation for the specific library/version actually chosen. |
| "I'll just go with what the repo uses" | Fine *if* the repo's choice is verified current via context7. Otherwise, legacy lock-in. |

---

## Law 14 — SIMPLICITY FIRST; GOAL-DRIVEN EXECUTION

**SIMPLICITY FIRST; GOAL-DRIVEN EXECUTION.** Write the minimum code that satisfies the migration_guide entry — nothing speculative. No abstractions for single-use code. No flexibility / configurability / error-handling branches the spec did not request. If a simpler equivalent to your draft exists, use it and note it. **Push back when a spec entry looks overcomplicated** — emit `STATUS: DONE_WITH_CONCERNS` with a simpler-alternative suggestion. Every dispatch carries a **success criterion** (the specific spec entry it's fulfilling); the subagent loops — write → verify against criterion → repeat — until the criterion is met or it blocks. "Make it work" is not a success criterion; a concrete verifiable spec line is.

### Law 14 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll add a config flag so this is flexible later" | Spec doesn't ask for it. Rule 14 violation — no speculative flexibility. |
| "Let me extract this into a utility for future reuse" | No other caller. Rule 14 — no abstractions for single-use code. |
| "I should handle the null case defensively even though it can't happen" | Can't happen ≠ needs handling. Only validate at boundaries the spec names. |
| "The spec is unclear on edge case X so I'll pick one" | Rule 12 and Rule 14 — surface the ambiguity via `NEEDS_CONTEXT`, don't silently pick. |
| "I'll just do it quickly, seems simple" | No success criterion cited. Rule 14 — name the migration_guide entry you're satisfying, then proceed. |

---

## Law 15 — CANONICAL KMP APPROACH OVER SHORT-TERM EXPEDIENCE (THE MOST IMPORTANT RULE)

**CANONICAL KMP APPROACH OVER SHORT-TERM EXPEDIENCE.** Every approach decision — what library to use, what pattern to follow, how to abstract a platform call, how to handle a resource, how to swap a dep, how to order module work — is judged on long-term durability, not on what's faster in the current dispatch. The canonical KMP approach (the one prescribed by kotlinlang.org docs and supported by JetBrains-named sample projects like Jetcaster-KMP-migration) is the default. Short-term shortcuts — hardcoding a string, inlining a JVM API, hand-rolling DI, leaving a Java file in place, deferring a dep swap with a TODO — are forbidden. They create technical debt the next batch and the next feature inherit, and they ALWAYS cost more later than they saved now.

When two approaches both work and both compile, the canonical one wins, even if it requires:

- Pulling adjacent files (resources, dimens, strings) into the same batch.
- Pre-swapping a dependency before the file can move.
- Refactoring shared infrastructure that the current scope did not strictly need.
- Holding the migrator's port and routing a precondition sub-task first (per `references/migration_preconditions.md`).

Subagents do NOT trade canonical correctness for completion speed. The skill's metric is migration durability, not migration throughput.

**Live-source corollary** — already encoded in Source-of-truth precedence above: kotlinlang.org canonical docs (the "KMP book") are the FIRST place to look for any KMP-shaped question, ahead of context7, ahead of community sources, ahead of training data. Law 13 governs *fetcher* priority among live sources; Law 15 governs *which live source is canonical* (kotlinlang.org for KMP) and *which approach the canonical source endorses* (always pick that one).

**Exceptions** are only valid when:

- The canonical approach is not yet decided (the docs are silent or contradict themselves) — Law 13 routes to live lookup of community sources, the researcher reports the discovered consensus, and the orchestrator records the dated finding in `findings.md` so future migrations inherit it.
- The user explicitly accepts a non-canonical shortcut via `REQUIRES_APPROVAL` — the deviation is logged in `accepted_deltas` with citation of the canonical alternative the user is bypassing and the reason. Silent shortcuts are forbidden.

### Law 15 — Rationalization table

| Thought | Reality |
|---|---|
| "Hardcoding the string is faster — I'll fix it later" | Later never comes. The next reviewer accepts it; the next migrator copies it. Move the resource to `composeResources/` and switch to `Res.string.foo` in the same batch. Law 15 + Precondition R. |
| "I'll defer the Hilt-to-Koin swap to the next feature" | The hand-rolled DI graph blocks every subsequent feature in the same module. Swap first, port second. Law 15 + Precondition D. |
| "expect/actual is overkill — I'll just put it in androidMain for now" | Code that could be shared but was scoped to androidMain "just for now" gets reimplemented on iOS instead of consumed. The interface-in-common pattern from connect-to-apis.html is what JetBrains prescribes. Use it. |
| "Let me wrap the JVM call in expect/actual to defer the work" | expect/actual is for genuine platform-bound behaviour, not for "I haven't ported this yet." Replace the JVM call with the multiplatform equivalent from `references/jvm_api_scrub_list.md`. Reviewer rejects deferral-shaped expect/actual. |
| "Skip leaf-first ordering — these modules don't actually depend on each other" | They do, transitively, and module-N pulls in module-1's stale state. Follow `references/migration_ordering.md`. |
| "RxJava-to-coroutines is too much for this batch — I'll keep RxJava and use the rx-coroutines bridge" | Bridges become permanent. Maintaining both reactive systems forever is more cost than the swap. Bridge is for the Android edge to non-migrated callers ONLY, not for the core port. |
| "The new Compose resource API is fiddly, let me use the older Android-only stringResource overload" | The older overload doesn't compile in commonMain. The fix is to do the canonical thing anyway — you just wasted the compile cycle. |
| "I'll inline the JVM Regex — Kotlin's Regex is mostly the same" | "Mostly" hides edge cases (`Pattern.MULTILINE`, named groups, look-behind support) that surface as production bugs. The scrub-list FROM → TO is exact; follow it. |
| "Just keep using R.string in the Android wrapper, the migrated screen calls down to a wrapper" | The wrapper IS the leakage. The screen in commonMain must use Res.string directly. The user's failure mode: Claude inlines the literal because R.string doesn't resolve in commonMain. |
| "The user just wants this to compile, I'll commit and they can fix the resource later" | Law 15 violation. The user wants it migrated correctly. Commit means review-passed; review fails on hardcoded resources. Loop back, do it canonically, then commit. |
| "macosX64 / watchosX64 / tvosX64 are deprecated since Kotlin 2.3.20 but the user's repo still has them" | Removing them is the canonical move. Don't preserve deprecated targets to avoid touching build.gradle.kts — that's exactly what Law 15 forbids. |
| "I'll use a `typealias` to fake an Android-only type in commonMain" | Hidden Android leak. Typealiases to platform types belong in androidMain `actual`, not commonMain. The reviewer greps for this. |

