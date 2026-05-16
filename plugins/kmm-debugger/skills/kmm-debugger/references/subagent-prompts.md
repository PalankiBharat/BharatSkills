# Subagent prompts for KMM migration investigation

The investigation workflow in `SKILL.md` relies on well-structured Opus subagent prompts. Each subagent should be self-contained — it doesn't see the parent conversation, so all context must be in the prompt.

Key properties of good investigation prompts:
- **Self-contained.** Include repo paths, branch names, prior findings the subagent needs to skip duplication, and all the file:line refs they should start from.
- **Hypothesis-driven, not conclusion-driven.** Tell the subagent the hypothesis to *test*, not the conclusion to *confirm*. They should validate or refute, not echo.
- **Output-format-constrained.** Specify section headings, word limit (~700 words), citation format (`file:line`).
- **Read-only by default.** Investigation subagents should not edit code unless explicitly tasked. State this upfront.
- **Tool guidance.** Mention which tools to prefer (knowledge graph if available, `git show <branch>:<path>` for cross-branch inspection) and which to avoid (`gh pr diff` fails on >300 files).

---

## Mandatory bias-guard preamble (include verbatim in every subagent prompt)

Every subagent prompt — regardless of template — MUST include this preamble at the top, right after the read-only directive. Skipping it defeats the entire point of the consensus dispatch: without the preamble, subagents echo the parent agent's biases instead of breaking them.

```
**Bias guard.** Do NOT treat the existing implementation, prior diagnoses, or prior fix attempts as correct. The parent agent has biases toward (a) defending the current code as roughly right and (b) proposing minimal patches over root-cause fixes — your job is to investigate with a fresh lens. If your reading suggests the existing implementation is wrong, or that a deletion is the right shape, or that the proper fix is much larger than a patch, say so plainly. Do not soften findings to align with prior work or to reduce blast radius.

If the parent agent told you "the bug is X" or "the previous fix tried Y", treat those as hypotheses to test, not anchors to defend.
```

When a prompt body below shows `[BIAS-GUARD PREAMBLE]`, paste the preamble above verbatim at that marker.

For sessions recovering from a fix-didn't-fully-resolve loop, append the fresh-lens addendum from `fix-loop-protocol.md` step 3.

---

## Template 1: Bug investigation (one per reported bug, runs in A/B pair)

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Identify the proximate cause of a user-reported regression in our KMM-migrated SDK, with file:line precision.

## Context

I migrated <SDK_NAME> from Android-only to KMM on branch `<MIGRATION_BRANCH>` of repo `<REPO_PATH>`. Consumer app `<CONSUMER_NAME>` consumes it via `<CONSUMER_PATH>` on branch `<CONSUMER_BRANCH>`.

Pre-migration master uses: <list pre-migration tech: ObjectBox, Retrofit, Gson, etc.>
Post-migration uses: <list post-migration tech: Room KMP, Ktor, kotlinx.serialization, etc.>

## The bug to investigate

<Verbatim bug report from the user. Don't paraphrase — let the subagent see what the user actually said.>

User's stated hypothesis (if any): <The user's guess, framed as "to test", not "to confirm".>

## What I need from you

1. **Locate the proximate cause.** Trace from the user-visible symptom backward to the specific commonMain / androidMain / iosMain code that's misbehaving. Cite file:line.
2. **Identify the migration-introduced surface area.** What in the failing code path is new since the migration vs. pre-existing on master? Use `git diff master..<MIGRATION_BRANCH> -- <suspected paths>` to be precise.
3. **Cross-check against the catalog.** Does this map to one of the common KMM migration pitfalls (commonMain reading AGP BuildConfig, Room KMP suspend DAO race, ObjectBox→Room refetch, init-time scope leak, transitive dep drift, multi-flavor publish, latent invariant in annotation-driven schema)? If yes, name the pitfall and explain how the symptom fits.
4. **Note adjacent suspect areas.** If the proximate cause is X but you also see code that *could* exhibit a similar bug under different conditions, flag it briefly.

## Tool guidance

- Prefer the knowledge-graph MCP (`semantic_search_nodes`, `query_graph`) over Grep for symbol lookups if available.
- Use `git show master:<path>` / `git log master -- <path>` to inspect pre-migration code without checkout.
- Use `git diff master..<BRANCH> -- <path>` to see what the migration changed in a specific file.
- Don't use `gh pr diff` for the migration PR (fails on PRs with >300 files).

## Output

Under ~700 words. Structure:
- **Proximate cause** — file:line, brief description of the failing logic
- **Migration delta in this code path** — what's new vs. pre-existing
- **Catalog pitfall match** — none / pitfall N + how it fits
- **Adjacent suspects** — (optional) brief list

File:line refs are required. No code edits. Treat my stated hypothesis as something to test, not confirm.
```

## Template 2: PR archeology (read the migration PR for context, not constraint)

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Mine the original KMM migration PR for the design rationale behind decisions that are now manifesting as regressions, so we can plan fixes without re-litigating resolved trade-offs — but treat findings as context, not constraint.

## Context

The PR: <PR_URL>
Repo: <REPO_PATH> — `gh` works from there.

Four user-reported regressions (or whatever the actual list is):
1. <bug 1>
2. <bug 2>
3. <bug 3>
4. <bug 4>

## What I need from you

For each regression area:

1. **Design intent.** What was the migration author trying to do? Cite the PR body, design-doc references, commit messages, review-thread comments. Quote verbatim where load-bearing.
2. **Explicitly accepted trade-offs.** Look in the PR body for a "Known trade-offs" / "Limitations" section, or commits that say "we accept X because Y". List them.
3. **Reviewer pushback that was resolved.** Search the resolved review threads for the defect area. Was the issue flagged? What was the resolution?
4. **Open follow-ups named in the PR.** "TODO post-merge" / "before release" / "revisit when X" callouts.

Also surface, for the PR overall:
- **Reviewer identities and count.** Was this a single-author PR with no reviewers? Reviewer-light PRs have much lower confidence in correctness — surface that signal.
- **Validation status.** Did the PR get merged? Is there a "last validated alpha" marker that's behind the current head?

## Tool guidance

- `gh pr view <PR_NUM> --repo <ORG>/<REPO> --comments` for PR body + top-level comments.
- `gh api repos/<ORG>/<REPO>/pulls/<PR_NUM>/reviews` for review states.
- `gh api repos/<ORG>/<REPO>/pulls/<PR_NUM>/comments --paginate` for inline review comments.
- `gh api graphql -F query='query{repository(owner:"<ORG>",name:"<REPO>"){pullRequest(number:<PR_NUM>){reviewThreads(first:100){nodes{isResolved,comments(first:30){nodes{body,path,line,author{login}}}}}}}}'` for resolved/unresolved threads with structure.
- Don't use `gh pr diff` (fails on PRs with >300 files).
- Watch for GitHub secondary rate limits — slow down rather than retry.

## Output

Under ~800 words. One section per regression area, plus a closing "PR overall" section.

**Critical: treat findings as context, NOT constraint.** If the author accepted a trade-off that's now causing user pain, the right fix is what's right for KMM — not preserving the trade-off because the author chose it. The skill that's calling you will be applying the "right KMM + don't break prod" framing to whatever you find.

Quote PR comments verbatim where they're load-bearing. Cite URLs / commit SHAs / file:line. No code edits.
```

## Template 3: Pre-migration baseline comparison

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Establish how the pre-migration master branch handled the code paths that are now misbehaving, so we know whether the migration introduced new machinery vs. broke an existing semantic.

## Context

Repo: <REPO_PATH>
- Branch `master` = pre-migration (Android-only)
- Branch `<MIGRATION_BRANCH>` = current state being investigated for regressions

The reported regressions trace to these proximate causes (from Phase 1 investigation):
1. <defect 1 with file:line>
2. <defect 2 with file:line>
3. <defect 3 with file:line>
4. <defect 4 with file:line>

## What I need from you

For each defect:

1. **Did master have an equivalent code path?** Find it via `git show master:<path>` / `git log master -- <path>`. If master had no equivalent (e.g., the migration introduced a startup refetch that didn't exist), state that — it's a strong signal the new machinery might not be needed.

2. **How did master implement it?** Read the master source. Describe the implementation precisely — was it synchronous? Did it use ObjectBox? Was there a singleton scope? Were there init-time coroutines?

3. **What KMM constraint, if any, prevents porting master's approach directly?** Be precise. Examples:
   - "commonMain can't see AGP `BuildConfig` (Android-only generated class)" — real constraint
   - "Room KMP DAO methods in commonMain must be suspend for non-Android targets" — real constraint
   - "We need a single source-of-truth across platforms" — not a real constraint; usually a design preference

4. **If KMM doesn't prevent porting master's pattern, what shape would the ported version take?** Sketch it briefly. Often this involves `expect/actual` (per-platform native mechanism) or `runBlocking` on a local DB read (when the migration over-rotated to async).

## Tool guidance

- `git show master:<path>` and `git log master -- <path>` to inspect master without checkout.
- Use `code-review-graph` MCP if available — but note the graph is built on the current branch, so for master content use `git show` via Bash.
- Search master with `git grep <term> master -- <path>` to constrain.

## Output

Under ~700 words. One section per defect:
- **Master equivalent** — exists / absent, with file:line on master if exists
- **Master implementation** — precise description
- **KMM constraint** — real / not-real, with the precise reason
- **Shape of ported version** — (only if KMM constraint is real; otherwise restate master's pattern)

File:line refs to master content using `master:path:line` style. No code edits. Be skeptical — verify, don't echo prior summaries.
```

## Template 4: Feasibility analysis (for fixes with technical risk)

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Assess the feasibility of <PROPOSED_FIX> before we commit to it.

## Context

The proposed fix: <DESCRIBE_THE_FIX_AND_RATIONALE>

The risk: <WHAT_COULD_GO_WRONG — e.g., "downgrading the SDK's Ktor pin from 2.3.11 to 2.2.2 might break the SDK because it uses Ktor 2.3-only APIs", "skipping the ObjectBox-to-Room data migrator might lose user state that's not server-recoverable", etc.>

## What I need from you

<Question 1, specific to the fix>
<Question 2, specific to the fix>
<Question 3, specific to the fix>

(For a transitive-pin downgrade: which Ktor APIs does the SDK use? Which were added in 2.3? Are any in the SDK's call sites?)

(For a data-migration skip: list every pre-migration entity. Classify each field as client-only vs server-recoverable. Identify any client-only fields that would be lost.)

(For a sync-API preservation via `runBlocking`: what's the underlying DAO call shape? Is it a local primary-key read or does it cross a network boundary?)

## Tool guidance

- For published Gradle Module Metadata transitive floors: inspect `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/<hash>/*.module` (JSON) — variants[*].attributes.org.jetbrains.kotlin.platform.type and variants[*].dependencies[*].
- For iOS klib `compiler_version` floors: inspect `default/manifest` inside the `.klib` file.
- For ObjectBox/Realm entity schemas on master: `git show master:<repo-root>/objectbox-models/default.json`.

## Output

Under ~700 words. Structure:
- **Per-question findings** with citations
- **Verdict**: mechanical / moderate-change / blocked
- **Recommendation** with one-paragraph rationale

If the verdict is "blocked", identify the specific blocker and propose an alternative. Be quantitative where possible (line counts, version numbers, file paths). No code edits.
```

## Template 5: Reverse-the-diagnosis (argue against the SDK being broken)

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Your job is to argue *against* the hypothesis that the SDK is broken. Build the strongest steelman case you can for one of these alternative loci of fault: backend contract violation, consumer misuse, infrastructure regression, recent non-migration commit, or cross-platform asymmetry where the sibling platform is the correct one.

## Context

I migrated <SDK_NAME> from Android-only to KMM on branch `<MIGRATION_BRANCH>` of repo `<REPO_PATH>`. The current investigation is anchored on "the SDK is broken" — your job is to push back on that anchor.

## The bug

<Verbatim bug report. Include the exception type and stack trace — most "is this our bug" questions are answered by what the exception type implies about the locus of fault.>

The current SDK-is-broken hypothesis (which you are pushing back against): <one-sentence summary of what the parent agent currently believes>

## What I need from you

For each alternative locus, build a steelman argument and cite evidence:

1. **Backend contract violation.** What contract does the SDK encode in this code path — via annotations, schemas, expect/actual declarations, or non-nullable types? Has the BE recently violated that contract? Check recent BE deploys (last 30 days), recent schema changes, response shape diffs. If the exception type is contract-violation-shaped (`UniqueViolationException`, `MissingFieldException`, schema-constraint failures), this locus deserves the highest priority. (See Pitfall #7 in `pitfalls.md`.)

2. **Consumer misuse.** Is the consumer app calling the SDK in a way the API doesn't support? Wrong threading, wrong lifecycle, wrong call ordering, stale cached SDK instance, missing required `initialize()` call, double-initialization?

3. **Infrastructure regression.** Has a shared dep (Gradle, AGP, Kotlin compiler, Xcode, OkHttp, Ktor), CDN, or platform component changed recently? Are other apps in the org seeing similar symptoms?

4. **Recent non-migration commit.** `git log --since="30 days ago" --not <MIGRATION_BRANCH>~50` — is there a more recent commit (outside the original migration) that's the real cause?

5. **Cross-platform asymmetry.** If the SDK is multi-platform, does the sibling platform (iOS / Android) handle this code path differently? If yes, which one is the deviant — and why? Often the sibling has already implemented the correct shape; the deviant is the bug.

For each: cite evidence. If evidence is thin, say so — don't fabricate a case. The point is to ensure we've actually challenged the SDK-is-broken framing, not echoed it.

## Tool guidance

- `git log --all --since=<date> -- <path>` for recent changes in the area
- `gh api repos/<ORG>/<REPO>/deployments` if BE deploys are tracked there
- `git log -S "<symbol>" --all` to find when a load-bearing symbol was introduced
- Inspect annotations: `grep -rn "@DbUnique\|@Id\|@Entity\|@Serializable" <commonMain path>`
- For klib / Gradle Module Metadata transitive checks, see Template 4's tool guidance

## Output

Under ~700 words. One section per alternative locus, with:
- **Steelman argument** (2-3 sentences)
- **Evidence** (file:line refs, commit SHAs, log timestamps)
- **Confidence** (high / medium / low / thin)

End with a **Confidence ranking**: which locus has the strongest non-SDK case? What would it take to confirm/refute it? If the SDK-is-broken hypothesis still looks strongest after this exercise, say so — but say *why* the alternatives are weaker.

Be combative. The default frame the parent agent will use is "SDK is broken". Your job is to make that frame defend itself.
```

## Template 6: Right-design-from-scratch (ignore current code, propose ideal shape)

```
**Read-only investigation, no code edits.**

[BIAS-GUARD PREAMBLE]

Ignore the current implementation of <AREA>. Propose what the right design would look like if you were building this area today, from scratch, with full KMM knowledge — explicitly NOT trying to minimize divergence from the current code.

## Context

The area: <describe the subsystem — e.g., "Scrip storage and dedup", "session token lifecycle", "init-time data hydration">

Current behavior (briefly): <one paragraph — what the area does today, what its responsibilities are. Do NOT include current implementation details beyond this paragraph; the parent will share them only if you need them.>

The bug surfacing in this area: <one sentence — symptom only, not diagnosis>

## What I need from you

Without reading the current implementation in detail (read it only enough to understand the area's responsibilities), propose the ideal shape:

1. **What is the actual need?** Domain terms, not implementation terms.
2. **What's the canonical KMM way to satisfy that need?** Consider native mechanisms per platform — `expect/actual`, AGP `BuildConfig`, Room KMP suspend DAOs, business-key upserts, etc.
3. **What's the minimal data model?** Entities, fields, invariants. Be explicit about which invariants are load-bearing on remote contracts vs. local guarantees.
4. **What's the minimal API surface?** Public functions, their signatures, threading expectations.
5. **What's the minimal lifecycle?** Init, hot path, cleanup. What runs at what time, in what scope.
6. **Cross-platform parity check.** Does iOS (or Android) already have a version of this? If yes, what shape does it use? Often the sibling platform has already solved the problem better — converge to that rather than designing something new.

## What NOT to do

- Do NOT propose patches to the current implementation. That's not your job.
- Do NOT defend the current implementation. You're designing greenfield.
- Do NOT engage with PR archeology / migration history. That's other subagents' jobs.
- Do NOT propose new architecture for the sake of newness — if the simplest shape is "delete the new machinery and restore master's pattern", say so.
- Do NOT soften the design to "stay close to current code" — that's the bias the bias-guard preamble names. Design from scratch.

## Output

Under ~600 words. Structure:
- **Need** (1 paragraph)
- **Right shape** (numbered list — data model, API, lifecycle, cross-platform notes)
- **Comparison to current** (1 paragraph — where the current implementation diverges from the right shape, and which divergences look load-bearing on the bug. Be honest about how far the current code is from ideal.)
- **Deletion candidates** (bulleted list — code in the current implementation that wouldn't exist in the right shape)
- **Clean-fix size estimate** (rough LOC delta + risk: small / medium / large. Useful for Doctrine 3 decisions on whether a clean fix is feasible now or genuinely multi-day.)

This template is the foil for the others. The bug investigation finds what's broken; this template finds what would never have been there to break.
```

---

## Consensus dispatch with A/B pairs (mandatory for any non-trivial bug)

Single subagent dispatch is forbidden. Every investigation angle must run with at least 2 subagents in parallel (subagent-A and subagent-B), using the same prompt and independent context. The redundancy is the point: A/B disagreement within an angle is the earliest signal that the angle is under-explored or the framing is biased.

### Dispatch matrix for ambiguous bugs (8 subagents)

| Angle | Template | Subagents |
|---|---|---|
| Forensic | Template 1 | A, B |
| Reverse-the-diagnosis | Template 5 | A, B |
| PR archeology | Template 2 | A, B |
| Ideal design from scratch | Template 6 | A, B |

Fire all 8 in a single message with 8 `Agent` tool calls. Yes, this is expensive in tokens and wall time — that's the discipline. Cutting corners on the dispatch is what produces the patches-after-patches loop (see `fix-loop-protocol.md`).

Use `scripts/dispatch.sh` to generate the pre-filled prompts so the templates don't have to be reassembled from this file each time.

### Dispatch matrix for unambiguous bugs (2 subagents)

| Angle | Template | Subagents |
|---|---|---|
| Forensic | Template 1 | A, B |

Even unambiguous bugs get an A/B pair. The redundancy catches false confidence — the exact failure mode that Doctrine 1 is built to prevent.

### Heuristic for "is this bug ambiguous?"

- Multiple subsystems plausibly involved → ambiguous, use the 8-subagent matrix
- Crash exception type maps to multiple known root causes → ambiguous
- Bug is intermittent or environment-dependent → ambiguous
- "I'm pretty sure it's X" with no evidence cited → treat as ambiguous (false confidence is exactly when consensus dispatch is most valuable)
- Single clear failure mode, one suspected file, you can name the root cause in one sentence → unambiguous, A/B Template 1 is sufficient

### Synthesis (after all subagents return)

1. **Within each A/B pair, check agreement first.**
   - A and B agree → high-confidence finding within the angle, promote to cross-angle synthesis
   - A and B disagree → angle is incomplete. Spawn a 3rd subagent on the same template, or surface the disagreement to the user as "we need to choose between X and Y, here's what each implies"

2. **Then synthesize across angles.**
   - All four angles agree → cross-validated root cause. Highest confidence. Propose a fix grounded in this.
   - Angles disagree → surface explicitly to the user. Do NOT collapse into a clean single narrative; that's one frame winning, not consensus.

3. **Single-source claims** (only one subagent across the whole dispatch saw it) → flag as "not corroborated". Verify by hand before acting; could be insight, could be noise.

### Anti-pattern: faking consensus

A clean narrative that resolves all A/B and cross-angle disagreement is usually the parent agent collapsing the signal. If you're tempted to write "all subagents agreed that X", check the raw outputs first — verbatim agreement is rare, and editorial smoothing is exactly the bias the dispatch is meant to defeat. Better to surface "Forensic-A and Forensic-B agree, but Reverse-A disagrees, here's the disagreement" than to fake unanimity.

### Fix-didn't-fully-resolve protocol

When an iteration of "fix → doesn't fully work" happens, do NOT spawn a single subagent to refine the prior diagnosis. Re-fire the full consensus dispatch with the fresh-lens addendum (see `fix-loop-protocol.md` step 3). The whole point is to break out of the patch-the-patch loop that Doctrine 3 prohibits.

---

## Spawning the subagents

When the investigation phase begins, spawn all subagents in a single message with multiple `Agent` tool calls. Don't spawn them sequentially — that wastes wall time. If you have 4 bug angles × 2 (A/B) + 1 PR archeology pair + 1 baseline comparison, that's 10 subagents in one batch.

Run with `subagent_type: general-purpose` and `model: opus` for KMM investigations — these benefit from the larger model's careful reasoning. Use `run_in_background: true` so the parent agent can do other prep work (drafting evals, reading critical files inline) while the subagents work.

Capture findings as they return; surface a brief summary to the user with each completion ("Agent X done — key finding: <one sentence>"). Don't wait for all to complete before reporting initial signal — early findings can reshape the plan before all subagents finish.

---

## What NOT to put in subagent prompts

- **Your conclusions.** The subagent should validate or refute, not echo.
- **Your fix proposals.** That's the parent agent's job after synthesis.
- **Vague tasks** like "investigate the codebase". Be specific about file paths, branches, comparison targets.
- **Open-ended word counts.** ~700 words keeps reports focused; longer reports tend to ramble.
- **Project-specific jargon without definition.** If the SDK has unusual terminology, define it inline.
- **Softening language.** Don't say "see if you can find" — say "find" or "report that you couldn't". Subagents calibrate to the prompt's epistemic confidence.
- **Anything that contradicts the bias-guard preamble.** Don't tell the subagent the current implementation is roughly right after telling it not to defend the current implementation.
