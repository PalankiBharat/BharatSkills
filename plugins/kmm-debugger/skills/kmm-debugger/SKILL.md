---
name: kmm-debugger
description: Investigation workflow and mindset for debugging bugs in a Kotlin Multiplatform (KMM) migration — when an Android-only codebase has been ported to KMM and post-migration regressions are surfacing. Use this skill whenever the user mentions debugging issues in a KMM-migrated SDK or its consumer app, post-upgrade crashes after consuming a KMM alpha, expect/actual wiring concerns, BuildKonfig flavor problems, Room KMP suspend DAO confusion, ObjectBox-to-Room migration questions, transitive Ktor/Kotlin version drift at the consumer, init-time coroutine leaks in commonMain/androidMain Sesame-style singletons, async cache races that didn't exist pre-migration, or any bug report against a recently-migrated KMM library. Also triggers when planning fixes for multi-defect regressions in commonMain/androidMain/iosMain code, or when investigating regressions across an SDK + consumer pair where the SDK was recently migrated to KMM. Apply this skill aggressively — KMM migration bugs are easy to misdiagnose by reading symptoms and bandaging the new machinery instead of asking whether the new machinery is needed at all. The skill closes every debugging session with a short retro that captures what worked, what didn't, and proposes concrete updates back to itself — pitfall catalog additions, mindset refinements, subagent prompt improvements — so the skill keeps sharpening with each real session.
---

# KMM Migration Debugger

## When this skill applies

The user is reporting bugs in code that has been recently migrated from Android-only to Kotlin Multiplatform. Symptoms look like crashes, wrong-backend traffic, UI regressions, memory leaks, or weird race conditions that didn't exist before the migration. The codebase typically has:

- A `commonMain` source set with Ktor + kotlinx.serialization + Room KMP
- An `androidMain` source set with the existing Android UI / consumers
- Optionally an `iosMain` source set with new iOS surface
- Either an `expect class` SDK entry point or a singleton like `Sesame` / `MySdk`
- A consumer Android app pulling the SDK as a published AAR

Pre-migration, the codebase used some subset of: AGP per-flavor `buildConfigField`, ObjectBox (or Realm), Retrofit + OkHttp + Gson, plain synchronous DAOs. Post-migration, those got replaced by: BuildKonfig, Room KMP, Ktor + kotlinx.serialization, suspend DAOs.

## The mindset (the most important part)

**Target: right KMM implementation + don't break prod.** That is *not* the same as "match pre-migration master" and *not* the same as "preserve what the migration author chose."

- **Pre-migration master is one reference point**, not the target. Master can have its own bugs and didn't see the new platform. For iOS-side questions, master is silent.
- **The migration's stated trade-offs in PR threads are author intent**, not validated correctness — especially when the PRs had limited or zero independent review (which is common for KMM migrations done by one engineer).
- **The migration's new machinery is fragile**. Default to questioning every new field, scope, observer, event, refetch, or async cache that was added during the migration. Ask: is this actually needed in KMM, or was it invented to bandage a non-problem?

For each defect, write down four things in order:

1. **What's the actual need?** State it in domain terms, not implementation terms. ("Per-flavor `SESAME_BASE_URL` readable from commonMain Ktor code across Android and iOS." Not: "Make BuildKonfig flavor wiring work.")
2. **What's the canonical KMM way to satisfy that need?** Think about each platform's native mechanism — `expect/actual` exists for exactly this. AGP has had per-flavor `BuildConfig` since 2014. Don't force a single tool across both platforms when each platform has a better-native option.
3. **Does the migration's current code implement (2)?** If yes, fix the implementation gap (e.g., the wiring that was claimed in a commit message but never actually committed). If no, replace it with (2) — even if it means restoring a pre-migration pattern.
4. **Does prod break during the change?** If yes, stage it (publish alpha, smoke-test, then iterate). If no, ship it.

**Don't write framing like:**
- "Master is the source of truth, subtract back to master" → wrong frame; master had its own bugs and didn't see iOS.
- "The PR's 'Known trade-offs' section means we have to live with X" → wrong; trade-offs in author-only PRs are not validated.
- "We can't change Y because the migration author was deliberate about it" → wrong; deliberate ≠ correct.

**Do write framing like:**
- "What is the cleanest implementation for this need in KMM, given commonMain / androidMain / iosMain native mechanisms?"
- "Does the migration's current approach satisfy that, or does it have a structural limitation (one-flavor-per-Gradle-invocation, never-cancelled scope, redundant init-time network call)?"
- "If the migration's approach has a limitation, the fix is to use the right approach for the need — not bandage the wrong approach."

The subtractive bias matters: layering fixes (sync-seed-on-top-of-async-cache, retry-on-top-of-silent-swallow, cancel-prior-job-on-top-of-singleton-scope) preserves the migration's broken assumptions and grows the surface area. Often the right fix is to delete the machinery entirely and restore a simpler shape that satisfies the actual need.

## Investigation workflow (do all four in order)

### Phase 1 — Parallel bug investigation via Opus subagents

For each reported bug, spawn one Opus subagent. Run them in parallel via a single message with multiple `Agent` tool calls. Why parallel: independent bug reports usually trace to different defects; sequential investigation wastes wall time. Each subagent should be self-contained — see `references/subagent-prompts.md` for the template.

Each subagent's job is to identify the proximate cause with `file:line` precision, not to propose fixes. Their output should be ~700 words, structured, citing specific files.

### Phase 2 — PR archeology (treat as context, not constraint)

Read the PR threads of the original KMM migration PR. Specifically look for:

- The PR body's "Known trade-offs" / "Limitations" section — this is where the migration author acknowledged gaps. Often the user-reported bugs map directly to these.
- Single-author / zero-review PRs — these have much lower confidence in correctness. Their stated rationale is author intent, not validated design.
- Resolved review threads in the defect area — what was discussed? What was deferred?
- Commit messages that *claim* certain wiring but where the actual diff doesn't contain that wiring (common slip in KMM migrations — the author intended to wire X but it was lost between commits).

**Critical: treat PR findings as context, not as constraints.** If a defect's root cause is "the author chose to use BuildKonfig everywhere and the wiring was never committed," the right fix is what's right for KMM — not what preserves the author's BuildKonfig choice. See `references/subagent-prompts.md` for the PR archeology prompt template.

### Phase 3 — Pre-migration baseline comparison

For each suspected defect, investigate how the pre-migration master branch handled this path:

- Did master have an equivalent? (Often the migration introduced new machinery with no master equivalent — a strong signal it might not be needed at all.)
- Was master's approach correct? (Don't assume yes.)
- What KMM constraint, if any, prevents porting master's approach directly to commonMain/androidMain/iosMain?

Use `git show master:<path>` and `git log master -- <path>` rather than checking out master. See `references/subagent-prompts.md` for the baseline-comparison prompt template.

### Phase 4 — Feasibility analysis for proposed fixes

Before committing to a fix direction, validate the technical feasibility:

- **Transitive dep downgrade?** Check published Gradle Module Metadata `compiler_version` floors. iOS klibs declare a `compiler_version` in their manifest; Android transitives via Gradle Module Metadata variants.
- **Data migration skippable?** Investigate what each pre-migration storage entity stored. Distinguish client-only data (lost forever without a migrator) from server-recoverable data (just a UX gap). Most KMM migrations dropping ObjectBox/Realm find that >90% of stored state is server-recoverable.
- **Function signature preservable?** `runBlocking { dao.getById(id) }` on a local primary-key Room read is microseconds — the rejection of `runBlocking` in many KMM patterns applies to network calls, not local DB. Don't take the rejection as universal.

See `references/subagent-prompts.md` for the feasibility-analysis prompt template.

## Per-defect analysis pattern

Once Phase 1-4 produce findings, apply the four-question framework (above) per defect. Then write the defect summary using this exact structure:

```
## Defect N — [one-line symptom]

**The actual need.** [What the system genuinely needs to do, in domain terms.]

**What KMM legitimately requires.** [The KMM-imposed constraint, if any. State it precisely — "commonMain can't read AGP BuildConfig" is precise; "we need cross-platform config" is too vague.]

**What's broken.** [The proximate cause with file:line refs. Identify what the migration introduced that's failing.]

**Right KMM implementation.** [The canonical pattern. Often `expect/actual`, often a synchronous read where the migration added async machinery, often a deletion of speculative event/cache infrastructure.]

### Changes
[Numbered, with file paths and minimal diffs. Be specific.]

### Critical files
- `/abs/path/to/file.kt:LINE-LINE` (what changes)
```

The structure forces the right thinking: actual-need first, then constraints, then root-cause, then fix. If you find yourself unable to fill "what KMM legitimately requires" with something precise, that's a signal the change probably isn't required and the migration invented unnecessary machinery.

## Common KMM migration pitfalls

A short summary — see `references/pitfalls.md` for the detailed catalog (symptom → root cause → right fix for each).

1. **commonMain can't read AGP `BuildConfig`** — forces config tooling. The mistake: using BuildKonfig everywhere instead of `expect/actual` with platform-native config.
2. **Room KMP suspend DAOs in commonMain** — non-Android targets require suspend. The mistake: building async cache + observer infrastructure to bridge to a previously-sync API, when `runBlocking` on a local DB read would do.
3. **ObjectBox → Room (or similar)** — no in-place data migration available. The mistake: building speculative init-time refetch + event-emitter infrastructure to compensate, when the user's normal journey screens already hydrate the new DB via their own `saveInDb` paths.
4. **Init-time coroutine machinery** — singleton scopes, never-cancelled observers, event chains for failure handling. The mistake: silently leaking collectors across re-inits; emitting events that no host actually handles.
5. **Transitive dep version drift at consumer** — POM pulls higher versions than consumer's declared pins. The mistake: not realizing the consumer's resolved Ktor / Kotlin is now different from what they pinned.
6. **Multi-flavor publishing limitations** — some KMM tools (e.g. BuildKonfig 0.17.0) generate one file per Gradle invocation, so multi-flavor publish silently produces wrong-flavor AARs. The mistake: not detecting it because the build doesn't error.

When investigating a bug, scan this list first. The pitfall framing often gets to the root cause faster than tracing the symptom forward.

## Subagent prompts for investigation

The investigation workflow relies on well-structured subagent prompts. The key properties: self-contained (no shared context), file:line specific (so subagents don't drift), and output-format-constrained (~700 words, structured sections, citations).

See `references/subagent-prompts.md` for the templates:
- Bug investigation (one per reported bug, run in parallel)
- PR archeology (one per migration PR, treats findings as context not constraint)
- Pre-migration baseline (one per source-set, restores what the old code did)
- Feasibility analysis (one per proposed fix that has technical risk)

## Execution workflow

After the plan is approved, execute defect-by-defect, with these discipline checkpoints:

1. **Per-defect commits.** Each defect (or each tight group of related deletions) gets its own commit. Commit messages explain *why* the change is right for KMM, not just *what* changed. Reference defect numbers / PR threads where useful.

2. **Local Maven first.** Before any remote publish, run `./gradlew publishToMavenLocal` on the SDK and rebuild the consumer against `~/.m2`. This catches API breakage before it hits Nexus.

3. **AAR sanity checks for per-flavor BuildConfig.** Unzip the produced AAR and inspect its `BuildConfig.class` via `javap -c -constants <path>/BuildConfig.class | grep -E "<FIELD_NAME>"`. Verify the production AAR contains the production values, staging AAR contains staging values. This is the only way to catch the multi-flavor BuildKonfig silent-wrong-AAR class of bugs.

4. **Fresh worktrees, not stale orphans.** When working against a different branch than the live repo is on, use `git worktree add <path> <branch>` for a fresh checkout from current branch tip. Don't dig into old worktrees — they accumulate transitive-dep drift (e.g., `finance_chart_version` might be months behind the current branch). Confirm with `git status` and key version pins after creating the worktree.

5. **Authorization gates for risky actions.** These are one-way / shared-state actions that need explicit user authorization, even within a session where the user said "go end-to-end":
   - `./gradlew publish` to Nexus / Maven Central
   - `git push` to remote (visible to PR reviewers)
   - PR amendments / force-push
   - `git worktree remove --force` on directories that may have user work-in-progress

   File edits, local builds, `publishToMavenLocal`, and local commits are typically fine without re-authorization mid-session.

6. **Comment discipline on committed code.** Match the project's existing comment density — most KMM SDK codebases are already comment-light. Don't add KDoc / docstrings / inline rationale blocks on new code unless you see the surrounding code uses them heavily. The intent of a change lives in the commit message, not the code.

## Communication discipline during the session

- **`file:line` refs always.** Never "in some file" or "around there." If you can't cite a line, you haven't read closely enough.
- **Diff-driven.** When showing changes, surface `git diff` rather than describing prose. Surface diffs at each defect boundary, not just at the end.
- **One-sentence status updates between actions.** Don't narrate internal deliberation. State the next action, then take it. Major findings warrant a paragraph; routine progress warrants a sentence.
- **No-comment default on new code.** Match the codebase's existing comment density.

## Closing retro (run at session end)

When the user signals the debugging session is wrapping up — fixes shipped, alpha published, PRs updated, "we're done", "thanks", or otherwise — run a short retro that captures what worked and what didn't, then propose concrete updates back to this skill. The retro is what keeps the catalog and the workflow sharp across real-world sessions. Skipping it means the skill calcifies around its initial assumptions and stops learning.

**Trigger conditions** (any of):
- User explicitly signals closure ("we're done", "ship it", "good work", "thanks")
- All planned fixes are committed/pushed/published
- The user-reported bugs have been validated as resolved (or queued for QA validation with no further session-level action expected)

The retro is ~5 minutes of conversation, not a full postmortem. Ask in this order:

1. **Did the pitfall catalog map correctly?** For each user-reported bug, did the catalog in `references/pitfalls.md` predict the root cause? If yes, which pitfall number. If no, what was the actual shape — and is it a new pitfall to add?
2. **Where did the mindset framing land or miss?** Did the "right KMM + don't break prod" anchor hold throughout, or did you have to correct toward a different framing mid-session? The mid-session reframings are usually the highest-value learnings.
3. **Which subagent prompts produced sharp findings vs. fluff?** Specifically: were any prompt templates too generic? Did any over-constrain the subagent and miss findings? Did the parallel-subagent dispatch help wall time, or was the synthesis bottleneck the real cost?
4. **What surprised you?** Any defect with a non-obvious root cause not predicted by the catalog or the four-question framework — even if you ultimately found it. The surprises are where the skill is silent.
5. **What would you do differently if this session started over?** This is the most important question. If you'd skip a phase, reorder one, or use a different framing for a particular defect — that's a workflow refinement worth codifying.

Based on the answers, propose concrete edits — see `references/retro-questions.md` for the answer-to-action mapping. Categories of edits:

- **`SKILL.md` edits** — mindset corrections, workflow step adjustments, new framing guidance
- **`references/pitfalls.md` edits** — new pitfall entries, refinements to existing ones (sharper symptom→root cause matches, better fix snippets)
- **`references/subagent-prompts.md` edits** — better prompt templates, new prompt types if a new phase emerged

**Show the proposed edits before applying.** Diff format if multi-line, inline if single-sentence. Let the user approve, modify, or skip each one. Don't auto-apply — the user is the curator of the skill's accuracy.

**Session log (optional but recommended).** Write a one-paragraph entry to `sessions/YYYY-MM-DD-<short-slug>.md` inside the skill directory capturing: bug surface investigated, pitfalls that matched, mindset corrections (if any), and links to the resulting catalog updates (if any). Keep entries under 200 words — they're a learning trail, not a postmortem archive. The trail also helps the *next* session recognize when a current bug pattern-matches a previously-seen one.

If the user declines the retro ("no, let's skip it"), respect that — but make a note that the retro was offered and declined. If they ask to come back to it later, the trigger conditions above apply at any point in a future session.

## When you're confused about a defect's root cause

If a bug doesn't fit one of the catalog pitfalls and the investigation isn't converging, the right move is usually one of:

- **Reverse the diagnosis.** Ask: "What if the migration's choice for this area is correct and the bug is elsewhere?" Sometimes the bug is in a downstream consumer behavior that the migration exposed but didn't introduce.
- **Read the runtime behavior.** Get a Logcat / strace / network capture. Symptoms in distributed/async systems are often misleading and direct observation cuts through faster than more code reading.
- **Re-anchor in pre-migration master.** Was this code path even reached pre-migration? If the migration introduced a new code path (e.g., refetch on init), the bug may live entirely in the new path with no master equivalent — meaning deletion is on the table.

The skill's bias toward deletion is deliberate. If in doubt, lean toward asking "is this new machinery needed at all?" before "how do I patch this new machinery?"
