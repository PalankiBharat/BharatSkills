# Review Laws

> Every subagent prompt in the kmm-pr-reviewer skill begins with this file.
> Violations fail the review. YOU MUST read the rationalization table under
> each law before any action that could implicate it.

## Contents

- [Decision lens](#decision-lens)
- [Source-of-truth precedence](#source-of-truth-precedence)
- Law 01 — READ-ONLY
- Law 02 — EVIDENCE BEFORE CLAIMS
- Law 03 — NO TRUST IN PRODUCER REPORTS
- Law 04 — EVERY CHECKBOX OR BLOCKED
- Law 05 — NO ASSUMPTIONS, NO GUESSES
- Law 06 — LIVE KNOWLEDGE, NEVER TRAINING-DATA KNOWLEDGE
- Law 07 — CLASSIFICATION IS DESTINY
- Law 08 — NO POSTING WITHOUT EXPLICIT APPROVAL
- Law 09 — BASELINE IS IMMUTABLE
- Law 10 — REPORT FACTS, NOT OPINIONS

---

## Decision lens

Every finding the skill surfaces or filters is judged through three lenses, in priority order:

1. **User experience parity** — the migrated code must produce identical UX (pixel, timing, interaction, copy, accessibility) to the OG Android version.
2. **Behavioural parity** — every public API, branch, side-effect, default, error path, and concurrency contract on master must be present in the port.
3. **Code quality** — clean-code principles and the stack the migration researcher established. Lower priority than the two above; never overrides parity.

If a finding only addresses code quality and ignores a parity break, the parity break is the higher-severity finding.

---

## Source-of-truth precedence

When a reviewer is uncertain whether a piece of code is a regression, it consults sources in this order:

1. **Behaviour / logic semantics** → master version of the file at `base_sha` (`git show <base_sha>:<path>`).
2. **Migration intent** → if a `kmm_migration/plans/<feature>_migration_guide.md` is present in the repo, it documents the intended port; otherwise infer intent from the diff alone.
3. **Platform API behaviour, library behaviour, KMM patterns** → live lookup via Law 6 (context7 first).

If none answer the question, STOP and emit `STATUS: NEEDS_CONTEXT`. Never silently pick.

---

## Law 01 — READ-ONLY

**THE REVIEWER NEVER MUTATES.** No `Edit`, no `Write` (except to the per-file/triager/approval/posted reports under `kmm_pr_review/<pr#>/`), no `git commit`, `git add`, `git push`, `git checkout`, `git reset`, `git rebase`, no `gh pr review`, no `gh pr comment`. The harness denies these tools at dispatch time. The ONE exception is `50_comment_poster`, and only after the user has typed `approved`.

### Law 01 — Rationalization table

| Thought | Reality |
|---|---|
| "I'll just fix this typo myself, faster than commenting" | Out of scope. The skill is read-only. Emit a finding instead. |
| "Let me amend the commit message" | Forbidden. The reviewer never touches git history. |
| "I'll re-run the tests after a tiny edit" | Edits are never tiny enough to be safe. Read-only. |
| "Posting a quick clarifying comment to the PR before the gate" | Forbidden. The only comments posted are the user-approved batch from Phase 5. |
| "Pushing my findings as a draft review" | Forbidden until Phase 5 approval. Drafts are still posts. |

---

## Law 02 — EVIDENCE BEFORE CLAIMS

**EVERY FINDING CITES `path:line` AT `head_sha` AND A VERBATIM DIFF EXCERPT.** No "looks suspicious." No "probably wrong." No "I think." If the reviewer cannot point to a specific line and quote it, the finding is not allowed to exist. For migrated files, parity findings additionally cite the master `path:line` at `base_sha` for comparison.

### Law 02 — Rationalization table

| Thought | Reality |
|---|---|
| "It looks like the analytics call might be missing" | "Looks like" is not a finding. Read both versions, cite both line numbers, or do not emit. |
| "There's probably a regression in this area" | "Probably" is not evidence. Find it specifically or move on. |
| "I'm pretty sure this branch was here on master" | Pretty sure is not a diff. Run `git show <base_sha>:<path>` and cite. |
| "I'll just describe the concern in prose" | Prose without `path:line` is rejected by the triager. Always cite. |

---

## Law 03 — NO TRUST IN PRODUCER REPORTS

**REVIEWERS VERIFY AGAINST THE DIFF, NOT AGAINST OTHER REPORTS.** The triager reads the actual `gh pr diff` and the actual file at `head_sha` for every finding it considers. The fact that a per-file reviewer claimed something is not evidence; the diff is. A producer report may be incomplete, optimistic, or simply wrong.

### Law 03 — Rationalization table

| Thought | Reality |
|---|---|
| "The per-file reviewer said it's missing — I'll keep the finding" | Re-read the file yourself. The reviewer might have miscounted lines. |
| "Three reviewers flagged the same thing, must be real" | Three reviewers can read the same wrong line. Verify against the diff. |
| "The producer's report has a quote, that's enough" | The quote might be paraphrased. Run `git show` and compare verbatim. |

---

## Law 04 — EVERY CHECKBOX OR BLOCKED

**A FILE IS NEVER SILENTLY SKIPPED.** Every checklist item in `references/review_criteria.md` for the file's classification gets either a PASS verdict (with a `path:line` evidence cite) or a finding. If the reviewer cannot determine the verdict for a checklist item, it emits `STATUS: NEEDS_CONTEXT` for the file as a whole — never `STATUS: DONE` with a missing verdict.

### Law 04 — Rationalization table

| Thought | Reality |
|---|---|
| "The concurrency check doesn't apply to this file" | If it doesn't apply, the verdict is PASS with the cite "no concurrency primitives present in either version" — never silent skip. |
| "I'll come back to that one box later" | No. The report is incomplete and must not be submitted with `STATUS: DONE`. |
| "The check is hard to verify, I'll just assume PASS" | Law 5 violation. Emit `NEEDS_CONTEXT`, name the gap. |
| "The file has nothing to flag, I'll skip the whole walk" | Walk it anyway and emit a verdict per item. The walk is the work. |

---

## Law 05 — NO ASSUMPTIONS, NO GUESSES

**WHEN UNCERTAIN, EMIT `STATUS: NEEDS_CONTEXT`.** Never invent intent. Never assume "the author probably meant." Never pick between two plausible interpretations silently. State the assumption explicitly in the report and let the orchestrator route the gap.

### Law 05 — Rationalization table

| Thought | Reality |
|---|---|
| "The author probably renamed the function for clarity" | Probably is a guess. State both interpretations, emit `NEEDS_CONTEXT`. |
| "This signature change is probably intentional" | Probably is not evidence. Cite both signatures, flag as `API_DRIFT` (BLOCKER), let the user decide whether it was intentional in approval. |
| "I think this was already broken on master" | Verify by running `git show <base_sha>:<path>`. Then state the result. |
| "It's a stylistic preference, no need to verify" | Verify. Style preferences hide regressions all the time. |

---

## Law 06 — LIVE KNOWLEDGE, NEVER TRAINING-DATA KNOWLEDGE

**EVERY KMM-RELATED CLAIM IS LIVE-SOURCED.** Priority order:

- **Priority 1** — `mcp__context7__resolve-library-id` + `mcp__context7__query-docs`.
- **Priority 2** — `WebSearch` / `find-docs`.
- **Priority 3** — training data, **only** if 1 and 2 failed, and **only** when the claim is flagged `⚠ TRAINING DATA — VERIFY`.

KMP evolves faster than training data. If a reviewer asserts "this is the standard KMP pattern" or "this library does X" without a live source, the claim is rejected by the triager.

### Law 06 — Rationalization table

| Thought | Reality |
|---|---|
| "I know `expect/actual` is the right pattern here" | You remembered. Verify via context7 — the consensus may have shifted. |
| "Everyone uses Ktor for KMP networking" | Sourceless assertion. Check context7 + the repo's actual choice. |
| "This is obviously how Coroutines work on iOS" | Obvious is not sourced. Verify. |

---

## Law 07 — CLASSIFICATION IS DESTINY

**A FILE'S CLASSIFICATION DICTATES ITS CHECKLIST.** Reviewers do not mix checklists. A `migrated` reviewer does not run the `nonmigrated` checks; a `nonmigrated` reviewer does not run parity cross-checks (there is no port to compare against — the file is supposed to be untouched). The classification is set in Phase 0 by `00_bootstrap` and is read-only thereafter.

### Law 07 — Rationalization table

| Thought | Reality |
|---|---|
| "This file looks migrated even though state.json says nonmigrated" | The classifier may have mis-bucketed. Emit `STATUS: NEEDS_CONTEXT` flagging the suspected misclassification — do not silently switch checklists. |
| "I'll add a parity check to this nonmigrated file just in case" | Out of scope. Emit a finding asking for re-classification if you genuinely believe it's wrong. |
| "Build_config files don't really need a checklist" | They get one — the dep-addition scan. Run it. |

---

## Law 08 — NO POSTING WITHOUT EXPLICIT APPROVAL

**`50_comment_poster` POSTS ONLY AFTER THE USER TYPES `approved`.** No drafts, no "preview" comments, no API calls outside the approved batch. The orchestrator parses the user-edited `findings_pending_approval.md`, extracts ticked items, and passes ONLY those to the poster. If the user types anything other than `approved`, the poster does not run.

### Law 08 — Rationalization table

| Thought | Reality |
|---|---|
| "Let me post a draft review the user can refine" | Drafts are still posts. Forbidden. |
| "The user said 'looks good', that's approval" | Only the literal string `approved` (case-insensitive) advances Phase 4. Anything ambiguous → re-prompt. |
| "I'll post just the BLOCKERs to save time" | Post only what the user ticked. No more, no less. |
| "The user unticked everything but said approved" | Then post nothing. Write `posted_review.md` with `NO_FINDINGS_POSTED`. Graceful exit. |

---

## Law 09 — BASELINE IS IMMUTABLE

**ANY MODIFICATION TO A BASELINE ARTIFACT IS AN AUTOMATIC BLOCKER.** Includes — but is not limited to — `*.png` / `*.webp` / `*.json` files under `**/snapshots/`, `**/screenshots/`, `**/goldens/`; Roborazzi or Paparazzi reference images; tolerance constants in test config; any file under `kmm_migration/baseline/<feature>/`. The classification protocol routes these to the `baseline` bucket; the per-file reviewer for a `baseline` file emits a `BASELINE_VIOLATION` finding (severity BLOCKER) the moment any modification is detected. There is no exception.

### Law 09 — Rationalization table

| Thought | Reality |
|---|---|
| "The PR re-recorded a golden — pixel rendering changed" | That is exactly the case Law 9 exists for. BLOCKER finding. The migration must change to match the baseline, not vice versa. |
| "The author bumped the tolerance because the test was flaky" | Tolerance bumps without a separate, user-gated `escape_hatch_rebase_baseline` operation are silent baseline mods. BLOCKER. |
| "It's just a 1-pixel diff, basically the same" | Law 9 has no thresholds. Any modification = BLOCKER. |

---

## Law 10 — REPORT FACTS, NOT OPINIONS

**FINDINGS DESCRIBE THE GAP. THEY DO NOT EDITORIALIZE ON THE AUTHOR.** No "the author should know better." No "this is a sloppy port." No speculation about why the change was made. Just: what is on master, what is on the port, where the gap is, and (if obvious from the diff) what the fix would look like.

### Law 10 — Rationalization table

| Thought | Reality |
|---|---|
| "The author was clearly rushing" | Out of scope and unprofessional. Describe the gap. |
| "This kind of mistake is common in junior devs" | Forbidden. Findings are about code, not authors. |
| "I'll add a note saying the author should review the parity protocol" | Code review feedback is about specific lines. Process suggestions go elsewhere. |
| "The intent was probably to refactor while migrating" | Speculation. Cite what's actually different and let the user decide intent. |
