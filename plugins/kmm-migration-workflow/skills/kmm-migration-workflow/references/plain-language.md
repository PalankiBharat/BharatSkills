# Plain language — writing audit trails reviewers actually read

Constitution §15 mandates plain language across every artifact, user prompt, PR body, and commit message. This file is the working reference: a swap list of common buzzwords with plain replacements, plus worked examples drawn from real migrations.

## Why this exists

A migration's audit trail is read by people who do not have the skill loaded into their head. The reviewer at 5pm on Friday, the engineer onboarding next quarter, the user a year from now trying to understand why a deviation was accepted — none of them want to decode "scope-disproportionate" before they can grasp what happened. They will skim. And a skimmed sentence in a deviation log is how a missing safety check ships unnoticed.

The cost of plain prose is one minute per artifact. The cost of jargon prose is the audit trail going stale.

## Swap list

| Don't write | Write instead |
|---|---|
| "scope-disproportionate" | "more ceremony than this scope warrants" / "overkill for one file" |
| "structurally infeasible" | "won't compile because the dependency goes the wrong way" |
| "constitutionally clean" | "the principles are followed" |
| "constitutional accommodation" | "we accept this as a trade-off" |
| "mechanical extract" | "the function is moved into a helper without changing what it does" |
| "behaviour-preservation invariant" | "the test that proves the migrated code returns the same value" |
| "behaviour is preserved" | "the migrated code still does the same thing" |
| "the diff specification" | "the line-by-line plan for editing this file" |
| "auto-close the deviation" | "the skill marks this resolved when <concrete condition>" |
| "scope expansion" | "this would pull in files we said were out of scope" |
| "rubber-stamped" | "approved without real review" |
| "rubber-stamping" | "approving without real review" |
| "load-bearing" | "important enough that other things depend on it" |
| "first-class behaviour" | "the skill handles this directly instead of as a workaround" |
| "interpretive failure" | "the subagent didn't understand what to do" |
| "BLOCKER finding" | "a problem that must be fixed before continuing" |
| "auto-routing" | "the skill picks the next step automatically" |
| "deferred as out-of-reach" | "left for a future migration" |
| "seam-creating refactor" | "a refactor that adds a place tests can hook into" |
| "non-blocking finding" | "a note that doesn't stop the migration" |
| "reviewability threshold" | "the size at which a PR becomes hard to review" |

The list is not exhaustive. The pattern is: when a phrase reads like a category label invented for this skill, replace it with the everyday phrase a developer would say to a coworker.

## What to keep technical

Some terms ARE the skill's vocabulary and removing them would make text vaguer, not plainer:

- **Phase names**: specify, architect, plan, tasks, implement, verify, pr, bundle. Readers will see these across artifacts; they're labels.
- **Constitution principle numbers**: §1, §6, §7, §13, §14, §15. They're citations.
- **Deviation status**: OPEN, CLOSED, RATIFIED, SUPERSEDED. They're states with structural meaning.
- **Identifiers**: `T-LOCK`, `M-1`, `R-1`, `D-N`, `CP-K`. They appear in tasks.md and migration-report.md and would be harder to scan if rewritten.
- **Technical terms with no plainer synonym**: `expect/actual`, `commonMain`, `androidMain`, `kotlinx-datetime`, `Hilt`, `Koin`, `Mutex`, `Flow`. The reader either knows them or needs to look them up; rewriting won't help.

The rule is: keep terms that are nouns referring to concrete things. Replace terms that are abstract category-labels.

## Worked examples

### Example 1 — Deviation log entry

**Before** (jargon-heavy):

> D-2 — Specify-phase runtime test sweep waived (scope-disproportionate)
>
> Status: RATIFIED. Root cause: The mandated full-suite runtime sweep is designed to surface pre-existing failures so `/kmm-verify` doesn't fail mid-flight. For this migration the runtime sweep is disproportionate: in-scope is 1 self-contained file, 0 transitive runtime dependencies inside the module, trivial calendar-hour-to-enum logic. `/kmm-verify` per constitution runs scope-focused tests (`--tests <fqn>`), not the full suite, so an unrelated runtime failure surfaced now would not block verify anyway.

**After** (plain):

> D-2 — Skipped the full unit test sweep at specify-phase
>
> Status: RATIFIED. Why: the full unit test sweep is meant to catch pre-existing failures so verify doesn't fail later. For this migration that sweep is overkill — it's one self-contained file with simple calendar-to-greeting logic. The verify step only runs the new tests for this migration (`--tests <fqn>`), not the full suite, so a pre-existing failure somewhere else couldn't block it anyway.

The structural information (deviation ID, status, principle implied) is identical. The reasoning is now scannable in 15 seconds instead of 45.

### Example 2 — User-facing question

**Before**:

> Master health sweep — what to do with the in-flight full test suite run?
>
> A) Kill it, proceed (Recommended). Stop the running test. Accept compile-only sweep as sufficient for a 1-file migration. Log the skipped runtime sweep as deviation D-2 (RATIFIED — scope-disproportionate; mandated full sweep waived because the migration's blast radius is a single self-contained file with no transitive runtime dependencies).

**After**:

> The full test suite is still running. What should I do?
>
> A) Kill it and move on (Recommended). The compile checks already passed. For a one-file migration with no other moving parts, running the full suite adds time without catching anything the smaller checks miss. I'll log this as D-2 RATIFIED so the audit trail explains why we skipped it.

### Example 3 — PR body summary

**Before**:

> Migrates GreetingUseCase to commonMain. R-1 LOW-risk refactor extracts internal helper for behaviour-preservation invariant testing. Public API byte-identical post-migration per Constitution §7. Five deviations RATIFIED — see migration-report.md. /kmm-verify VERIFY_COMPLETE_PASS.

**After**:

> Moves `GreetingUseCase` from `:app` to shared code (`commonMain`) so iOS can use it. The hour-to-greeting mapping is pulled out into a small helper (R-1) so we can test it across all 24 hours; the public class signatures are unchanged. Five trade-offs are recorded in `migration-report.md` (all accepted). The skill's verify step passed.

The PR reviewer who has 30 seconds gets the goal, the shape of the change, and where to look for details.

## Self-test

Before committing any artifact, read it once with this question: *if I had not written this and did not have the constitution loaded, would each sentence make sense on a first read?*

If yes — ship.

If no — the sentence likely contains a buzzword, a category-label, or a structural shorthand that needs replacing. Use the swap list. If the swap list doesn't cover it, write the everyday-English version a developer would say to a coworker and use that.

## When this rule does NOT apply

- **Code identifiers**: variable names, function names, type names follow `references/clean-code.md` (domain-led, intent-over-mechanism). Plain language is for prose, not code.
- **Comments in code**: still rare per Constitution §9; when they exist, they explain the *why* in plain English already.
- **Inline test names**: camelCase function names per `references/test-discipline.md` are not English sentences and don't need plain-language polish — `greetingForHour_returnsExpectedGreetingForEveryHourOfDay` is a label, not prose.
- **Quoted error messages, gradle task names, file paths, library APIs**: these are exact strings. Don't paraphrase them.

## Failure mode this principle exists to prevent

The skill's prior versions produced audit trails that were technically perfect — every principle cited, every deviation classified, every closure type structured — but functionally opaque. A reviewer skimming the migration-report would see "RATIFIED — scope-disproportionate" and skip past it without questioning whether the trade-off was right. A reader six months later, opening the same file with the constitution unloaded, would lose the reasoning entirely.

A jargon-heavy audit trail looks rigorous but it isn't. Rigour means a reader can reconstruct the decision and either agree or push back. Plain language is the mechanism that makes rigour available to readers who weren't in the room.
