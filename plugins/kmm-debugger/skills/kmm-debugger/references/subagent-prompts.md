# Subagent prompts for KMM migration investigation

The investigation workflow in `SKILL.md` relies on well-structured Opus subagent prompts. Each subagent should be self-contained — it doesn't see the parent conversation, so all context must be in the prompt.

Key properties of good investigation prompts:
- **Self-contained.** Include repo paths, branch names, prior findings the subagent needs to skip duplication, and all the file:line refs they should start from.
- **Hypothesis-driven, not conclusion-driven.** Tell the subagent the hypothesis to *test*, not the conclusion to *confirm*. They should validate or refute, not echo.
- **Output-format-constrained.** Specify section headings, word limit (~700 words), citation format (`file:line`).
- **Read-only by default.** Investigation subagents should not edit code unless explicitly tasked. State this upfront.
- **Tool guidance.** Mention which tools to prefer (knowledge graph if available, `git show <branch>:<path>` for cross-branch inspection) and which to avoid (`gh pr diff` fails on >300 files).

## Template 1: Bug investigation (one per reported bug, run in parallel)

```
**Read-only investigation, no code edits.** Identify the proximate cause of a user-reported regression in our KMM-migrated SDK, with file:line precision.

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
3. **Cross-check against the catalog.** Does this map to one of the common KMM migration pitfalls (commonMain reading AGP BuildConfig, Room KMP suspend DAO race, ObjectBox→Room refetch, init-time scope leak, transitive dep drift)? If yes, name the pitfall and explain how the symptom fits.
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
**Read-only investigation, no code edits.** Mine the original KMM migration PR for the design rationale behind decisions that are now manifesting as regressions, so we can plan fixes without re-litigating resolved trade-offs — but treat findings as context, not constraint.

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
**Read-only investigation, no code edits.** Establish how the pre-migration master branch handled the code paths that are now misbehaving, so we know whether the migration introduced new machinery vs. broke an existing semantic.

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
**Read-only investigation, no code edits.** Assess the feasibility of <PROPOSED_FIX> before we commit to it.

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

## Spawning the subagents

When the investigation phase begins, spawn all subagents in a single message with multiple `Agent` tool calls. Don't spawn them sequentially — that wastes wall time. If you have 4 reported bugs + 1 PR archeology + 1 baseline comparison, that's 6 subagents in one batch.

Run with `subagent_type: general-purpose` and `model: opus` for KMM investigations — these benefit from the larger model's careful reasoning. Use `run_in_background: true` so the parent agent can do other prep work (drafting evals, reading critical files inline) while the subagents work.

Capture findings as they return; surface a brief summary to the user with each completion ("Agent X done — key finding: <one sentence>"). Don't wait for all to complete before reporting initial signal — early findings can reshape the plan before all subagents finish.

## What NOT to put in subagent prompts

- **Your conclusions.** The subagent should validate or refute, not echo.
- **Your fix proposals.** That's the parent agent's job after synthesis.
- **Vague tasks** like "investigate the codebase". Be specific about file paths, branches, comparison targets.
- **Open-ended word counts.** ~700 words keeps reports focused; longer reports tend to ramble.
- **Project-specific jargon without definition.** If the SDK has unusual terminology, define it inline.
