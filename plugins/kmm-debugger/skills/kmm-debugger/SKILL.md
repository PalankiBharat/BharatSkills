---
name: kmm-debugger
description: Investigation workflow and mindset for debugging bugs in a Kotlin Multiplatform (KMM) migration — when an Android-only codebase has been ported to KMM and post-migration regressions are surfacing. Use this skill whenever the user mentions debugging issues in a KMM-migrated SDK or its consumer app, post-upgrade crashes after consuming a KMM alpha, expect/actual wiring concerns, BuildKonfig flavor problems, Room KMP suspend DAO confusion, ObjectBox-to-Room migration questions, transitive Ktor/Kotlin version drift at the consumer, init-time coroutine leaks in commonMain/androidMain Sesame-style singletons, async cache races that didn't exist pre-migration, or any bug report against a recently-migrated KMM library. Also triggers when planning fixes for multi-defect regressions in commonMain/androidMain/iosMain code, or when investigating regressions across an SDK + consumer pair where the SDK was recently migrated to KMM. Apply this skill aggressively — KMM migration bugs are easy to misdiagnose by reading symptoms and bandaging the new machinery instead of asking whether the new machinery is needed at all. The skill applies the bias guard (do not anchor on existing implementation or prior fix attempts), the consensus dispatch (A/B subagent pairs per topic for ambiguous bugs), the "is this even our bug?" question (check upstream contract violations first), and Doctrine 3 (prefer clean long-term solutions over hotfixes and iterative patches). Also triggers on "patches keep failing", "the fix didn't work", "we keep iterating", "latent invariant", "BE contract violation", "consensus dispatch", "reverse the diagnosis", "fresh-lens investigation", "is this even our bug". The skill closes every debugging session with a short retro that captures what worked, what didn't, and proposes concrete updates back to itself so it keeps sharpening with each real session.
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

## Three doctrines (the spine of this skill)

**Anchor: right KMM implementation + don't break prod.** That's *not* the same as "match pre-migration master" and *not* the same as "preserve what the migration author chose." Pre-migration master is one reference point, not the target — master can have its own bugs and didn't see iOS. The migration's stated trade-offs in author-only PRs are author intent, not validated correctness. The migration's new machinery is fragile; default to questioning every new field, scope, observer, event, refetch, or async cache that was added during the migration.

These doctrines override Claude's default debugging instincts. Read `references/doctrines.md` for the deep explanation, anti-pattern catalog (named phrases to refuse), and right-framing replacements — all load-bearing for any non-trivial bug.

### Doctrine 1 — No bias toward existing implementation

Treat the existing code as one data point, not a baseline to defend. Claude's default is to assume current code is roughly right and look for a minimal patch — override that deliberately. When briefing subagents (Phase 1), include the bias-guard preamble verbatim so they investigate with a fresh lens, not an inherited frame.

*Why this matters:* the deviant implementation IS often the source of the bug. Defending it is exactly what keeps the investigation stuck.

### Doctrine 2 — Deep investigation before any plan or execution

Phase 1 (parallel consensus investigation, A/B pairs per topic) is a hard gate. No diagnosis, plan, recommendation, or code edit before it completes. The only exception is a single-symptom bug with a one-line fix obvious from the symptom — and even then, explicitly state "skipping Phase 1 because <reason>" before proceeding.

If a shipped fix doesn't fully resolve the symptom: do NOT patch the patch. Stop, re-fire Phase 1 with a fresh-lens addendum. See `references/fix-loop-protocol.md`.

*Why this matters:* the patches-after-patches loop is what burns sessions. Catching it requires breaking out of the "I already investigated, I just need to refine" frame — re-firing Phase 1 is the way out.

### Doctrine 3 — Always prefer the clean long-term solution

The skill's bias is toward deletion of unnecessary machinery, convergence to the right shape (often the sibling platform's), and root-cause fixes at the right layer. Hotfix only when both: (a) production is actively burning, AND (b) the clean fix is genuinely multi-day. Even then ship the hotfix with a tracking issue and named deadline for the clean follow-up.

*Why this matters:* "we'll clean it up later" almost never happens. The hotfix becomes the permanent shape, and the next bug compounds on top of the unclean shape.

The most common deletion sequence in a real KMM cleanup: delete the async cache + observer collector (Pitfall #2 fix), delete the singleton-scope perpetual launches in `initialize()` (Pitfall #4 fix), delete the speculative event class + the host's no-op handler (Pitfall #3 downstream), reshape one remaining init-time launch as a slim self-completing one-shot (Pitfall #3 fix). Net delta: ~150 lines deleted, ~30 lines added.

See `references/doctrines.md` for the anti-pattern catalog (named phrases like "let's just add this null check" that signal the bias is winning).

## The 5 per-defect questions

For each defect, answer these in order. Stuck on a question = signal you don't have enough investigation; return to Phase 1.

**Q0 — Is this even our bug?** Could an upstream contract have been violated? Contract-violation symptoms (`UniqueViolationException`, `MissingFieldException`, schema-constraint failures, sudden regressions in unchanged code) demand this question first. If yes: escalate upstream first, ship a client shield in parallel — do NOT patch the client and call it done. See Pitfall #7.

**Q1 — What's the actual need?** State it in domain terms, not implementation terms. ("Per-flavor `SESAME_BASE_URL` readable from commonMain Ktor code across Android and iOS." Not: "Make BuildKonfig flavor wiring work.")

**Q2 — What's the canonical KMM way to satisfy that need?** Per-platform native mechanism. `expect/actual` exists for exactly this kind of question. AGP has had per-flavor `BuildConfig` since 2014. Don't force a single tool across both platforms when each platform has a better-native option.

**Q3 — Does the current code implement (2)?** If yes, fix the implementation gap (e.g., wiring claimed in a commit message but never actually committed). If no, *replace* it with (2) — don't patch the wrong shape, even if the right shape means deleting weeks of migration work. Doctrine 3 applies.

**Q4 — Does prod break during the change?** If yes, stage it (publish alpha, smoke-test, then iterate). If no, ship the clean shape — not the smaller safer shape that accumulates debt.

## Per-defect analysis pattern

Once Phase 1 completes and you've answered Q0-Q4 for each defect, write the defect plan using this exact structure (the structure forces the right thinking — actual-need first, then constraints, then root-cause, then fix):

```
## Defect N — [one-line symptom]

**The actual need.** [What the system genuinely needs to do, in domain terms.]

**What KMM legitimately requires.** [The KMM-imposed constraint, if any. Precise — "commonMain can't read AGP BuildConfig" is precise; "we need cross-platform config" is too vague.]

**What's broken.** [Proximate cause with file:line refs. Identify what the migration introduced that's failing.]

**Right KMM implementation.** [Canonical pattern. Often `expect/actual`, often a synchronous read where migration added async machinery, often a deletion of speculative event/cache infrastructure. Doctrine 3 applies.]

### Changes
[Numbered, with file paths and minimal diffs. Be specific.]

### Critical files
- `/abs/path/to/file.kt:LINE-LINE` (what changes)
```

If you can't fill "What KMM legitimately requires" with something precise, that's a signal the change probably isn't required and the migration invented unnecessary machinery — re-examine Q2 and Q3.

## Phase 1 — Parallel consensus investigation (hard gate)

You MUST complete this phase before any diagnosis, plan, recommendation, or code edit (Doctrine 2). Skipping is a skill failure.

**The dispatch.** Use `scripts/dispatch.sh` to generate pre-filled subagent prompts with the bias-guard preamble baked in. The script takes the bug summary + repo paths and prints the templates ready to paste into `Agent` tool calls. This saves significant tokens vs. reassembling templates from `references/subagent-prompts.md` each time.

For **ambiguous bugs** (root cause not nameable in one sentence; multiple subsystems plausibly involved; intermittent failures; "I'm pretty sure it's X" with no evidence cited), spawn A/B pairs for all 4 angles — **8 subagents minimum**, all in one message:

- Forensic A/B (Template 1) — first-principles trace from symptom to proximate cause
- Reverse-the-diagnosis A/B (Template 5) — argue *against* the SDK being broken
- PR archeology A/B (Template 2) — when did the failing code path last change
- Right-design-from-scratch A/B (Template 6) — ignore current code; what's the ideal shape

For **unambiguous bugs** (single clear failure mode, one suspected file, root cause nameable in one sentence), A/B pair of Template 1 is sufficient — 2 subagents minimum. Single-subagent dispatch is forbidden.

Templates 3 (pre-migration baseline) and 4 (feasibility analysis) are optional angles — use selectively when a defect's root cause might trace to a master pattern or when a proposed fix has technical risk. They don't always need A/B pairs.

*Why A/B pairs:* a single subagent inherits the parent's framing. A/B disagreement within an angle is the earliest signal the framing is biased or the angle is under-explored.

See `references/subagent-prompts.md` for the full template bodies, the mandatory bias-guard preamble, the consensus synthesis discipline (within A/B pair first, then across angles), and the anti-pattern of faking consensus.

## Per-fix shipped summary (after every push / PR / publish)

After every fix that reaches a remote — commit pushed, PR opened or updated, alpha published, tag pushed — produce this summary before continuing with new work. The Cons section is the most important: it catches when you've defaulted to a patch instead of a clean fix.

```
### Fix N — [one-line symptom]

**Problem.** Proximate cause with file:line. Root cause location (SDK / upstream / consumer / infra).

**Solution.** What changed (commit SHA). Why this is the clean long-term shape — or, if it's a hotfix per Doctrine 3, name that explicitly and link the tracking issue for the clean follow-up.

**Pros.** What makes this the right shape vs. alternatives. Sibling-platform convergence, deletion, root-cause-at-right-layer.

**Cons / risks / gaps.** Ruthless. What this doesn't cover. What's deferred. What the user needs to validate. Upstream escalation status if Q0 was yes.
```

Use `scripts/per_fix_summary.sh <fix-num> "<symptom>" <commit-sha>` to print the template skeleton.

If you can't name a single con or risk, you haven't thought hard enough — keep thinking.

**If a shipped fix doesn't fully resolve the symptom:** do NOT write Fix N+1 as a patch on Fix N. Read `references/fix-loop-protocol.md` and follow the protocol (stop, declare Fix N's diagnosis invalidated, re-fire Phase 1 with a fresh-lens addendum). This is the patches-after-patches loop the skill is built to prevent.

## Common KMM migration pitfalls — index

Scan this list when investigating; the pitfall framing often gets to root cause faster than tracing the symptom forward. Use `scripts/pitfall_match.sh "<symptom-phrase>"` to look up candidates without loading the full catalog.

1. **commonMain can't read AGP `BuildConfig`** — forced BuildKonfig everywhere, wrong-flavor AARs in multi-flavor publish.
2. **Room KMP suspend DAOs in commonMain** — async cache + observer machinery to bridge a sync API; race window after init.
3. **ObjectBox/Realm → Room with no in-place data migration** — init-time refetch + event chains that no host handles.
4. **Init-time coroutine machinery** — singleton scopes never cancelled; observer collectors accumulating across re-inits.
5. **Transitive dep version drift at consumer** — POM pulls higher versions than consumer's declared pins.
6. **Multi-flavor publishing limitations** — BuildKonfig 0.17.0 generates one file per Gradle invocation; silent wrong-flavor AARs.
7. **Latent invariant in expect/actual or annotation-driven schemas** — SDK encodes a load-bearing invariant on an undocumented BE contract; contract drift surfaces as an SDK crash. Patching the SDK removes the early-warning signal.

See `references/pitfalls.md` for the detailed catalog (symptom → root cause → right investigation → right fix → verification, per pitfall).

## Execution discipline (when shipping fixes)

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

## Closing retro (hard gate — auto-fire on remote-visible actions)

Fire the retro proactively after any of:
- `git push` to remote
- PR opened or updated
- `./gradlew publish` to Nexus / Maven Central
- Alpha tagged and pushed
- All planned fixes for the session shipped
- Phase 1 re-fired due to fix-didn't-fully-resolve loop (highest-value retro signal)

Do NOT wait for the user to signal "we're done" or "thanks" or to invoke `/skill-feedback`. The user-signaled trigger is one of many, not the only one. By the time the user signals closure, the session context is decaying and the highest-value lessons are already harder to recall.

The retro is ~5 minutes of conversation — not a full postmortem. Walk through proposed edits one at a time (diff format for multi-line, inline for single-sentence); don't bundle all questions' edits into one mega-diff. The user approves, modifies, or skips each edit. Apply only after approval — the user is the curator of the skill's accuracy.

See `references/retro-questions.md` for the 6 questions and the answer-to-action mapping.

**Session log (optional but recommended).** Write a one-paragraph entry to `sessions/YYYY-MM-DD-<short-slug>.md` capturing: bug surface investigated, pitfalls matched, mindset corrections (if any), surprises, skill updates from this session, outcome. Keep under 200 words — it's a learning trail, not a postmortem archive. The trail helps the next session recognize when a current bug pattern-matches a previously-seen one. See `references/retro-questions.md` for the exact template.

**If the user declines the retro** ("no, skip it" / "later"), respect that — but make a note that the retro was offered and declined. If they ask to come back to it later, the trigger conditions above apply at any point in a future session.

## When you're confused about a defect's root cause

If a bug doesn't fit one of the catalog pitfalls and the investigation isn't converging:

- **Reverse the diagnosis.** Ask: "What if the migration's choice for this area is correct and the bug is elsewhere?" Sometimes the bug is in a downstream consumer behavior, upstream contract drift (Pitfall #7), or a recent non-migration commit — that the migration exposed but didn't introduce. This is the discipline Template 5 (Reverse-the-diagnosis) formalizes — re-fire Phase 1 with that template prominent.
- **Read the runtime behavior.** Get a Logcat / strace / network capture. Symptoms in distributed / async systems mislead; direct observation cuts through faster than more code reading.
- **Re-anchor in pre-migration master.** Was this code path even reached pre-migration? If the migration introduced a new code path (e.g., refetch on init), the bug may live entirely in the new path with no master equivalent — meaning deletion is on the table.

The skill's bias toward deletion is deliberate. If in doubt, lean toward "is this new machinery needed at all?" before "how do I patch this new machinery?" (Doctrine 3.)

---

## Reference files

- `references/doctrines.md` — Deep explanation of the 3 doctrines + anti-pattern catalog + right-framing examples
- `references/subagent-prompts.md` — 6 subagent templates + mandatory bias-guard preamble + consensus dispatch with A/B pairs
- `references/pitfalls.md` — Detailed 7-pitfall catalog (symptom → root cause → right fix → verification)
- `references/fix-loop-protocol.md` — Recovery procedure when a shipped fix doesn't fully resolve the symptom
- `references/retro-questions.md` — 6 retro questions + hard-gate trigger conditions + answer-to-action mapping + session log format

## Scripts

- `scripts/dispatch.sh <ambiguous|unambiguous> "<bug-summary>" "<repo-path>" "<branch>" "<consumer-path>"` — Generates pre-filled subagent prompts for Phase 1 dispatch
- `scripts/pitfall_match.sh "<symptom-phrase>"` — Returns candidate pitfall numbers + one-liners
- `scripts/per_fix_summary.sh <fix-num> "<symptom>" <commit-sha>` — Prints summary template skeleton
