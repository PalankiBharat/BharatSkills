# Orchestration Protocol

Read this before every dispatch — by the orchestrator, by every subagent.

## Communication style

Every line printed to the user is terse. No preamble. No narration. No padded banners.

- **Phase transitions**: single banner. `── plan-phase ──`.
- **Status summaries**: data, not prose. `Phase B 5/5. 35 tests green. → T-LOCK.`
- **Constitution checks**: checklist with `[x]/[ ]` and `PASS/FAIL`. No prose.
- **Subagent dispatches**: silent on success. Print only failures, escalations, batch boundaries.
- **Errors / escalations**: file, symptom, recommendation. No apologies.
- **Reasoning is internal**: deliberation does not surface; only decisions do.

When the user says `discuss` / `explain` / `show me`, switch to fuller prose for that turn, then revert.

### Plain language (Constitution §15)

User-facing text — questions, summaries, PR bodies, deviation log entries — must read on the first pass to someone who does not have this skill's vocabulary loaded. Avoid jargon, or pair it with a plain gloss in the same sentence.

Common swaps:
- "scope-disproportionate" → "more ceremony than this scope warrants"
- "structurally infeasible" → "won't compile because <concrete reason>"
- "constitutionally clean" → "the principles are followed"
- "mechanical extract" → "the function is moved into a helper without changing what it does"
- "behaviour-preservation invariant" → "the test that proves the migrated code returns the same value"
- "the diff specification" → "the line-by-line plan for editing this file"
- "auto-close the deviation" → "the skill marks this deviation resolved when <X>"
- "scope expansion" → "this would pull in files we said were out of scope"

Question text is plain. Option labels can use technical proper nouns (fast-path, T-LOCK, expect/actual); each option's description explains what happens in plain English.

## Roles

- **Orchestrator** — Opus. Plans, reads state, dispatches subagents, validates completion promises, updates artifacts on disk. Never writes migration code (no `commonMain`, `androidMain`, `iosMain`, `commonTest`, consumer source).
- **Subagent** — sonnet or haiku. Executes a single bounded task, reports back with a completion promise. No conversational state across turns; everything comes from the dispatch context.

The orchestrator does:
- write artifacts in `<repo>/kmm/<scope>/`
- update `tasks.md` checkboxes
- run `git` (worktree, status, commits at level boundaries)
- run `gradle` (compile checks, test runs at level boundaries and `/kmm-verify`)
- dispatch subagents
- escalate to the user when classification dictates

If the orchestrator catches itself reaching for `Edit` or `Write` against a worktree source path, that is a protocol violation. Stop and dispatch a subagent.

## Subagent dispatch

Every dispatch passes the subagent two things:

1. **System prompt** — the agent's prompt file from `agents/`, verbatim.
2. **Task message** — task-specific data (paths, expected counts, prior failure context if applicable).

## Honor explicit dispatch instructions

When the dispatch context names a specific approach, library version, file path, or sequencing decision, the subagent MUST follow it — even if the subagent has identified what looks like a structurally cleaner alternative. The orchestrator may have context the subagent lacks.

If the subagent disagrees, it MUST emit `REQUIRES_APPROVAL` with the alternative and rationale. Silent override is forbidden.

Examples of forbidden silent overrides:
- Dispatch says "use Approach 1: stage-then-migrate"; subagent uses Approach 2 because it's "cleaner" → forbidden.
- Dispatch says "library version 3.0.3 (verified)"; subagent uses 3.1.0 because it's newer → forbidden.
- Dispatch says "scope is 4 files"; subagent migrates a 5th transitive dependency → forbidden.

## Failure classification (prevention > cure)

A subagent's completion-promise tag and reason determine whether the orchestrator escalates.

**Mechanical failure** — `tests red`, `build error`, `missing import`, `missing dependency`, `flaky test`, `wrong path`, `gradle task name unknown`.

Action: the subagent emits `*_BLOCKED` with the relevant logs. The orchestrator escalates to the user immediately. **Do not silently refire.** A recurring mechanical failure usually means the architecture or plan missed something — re-architecting silently in cure mode hides the real bug. Surface to the user with the failing subagent's reason and the recommended next step (typically: revisit `architecture.md` or `migration-guide.md`).

**Interpretive failure** — `ambiguous behaviour`, `scope expansion`, `signature change required`, `behaviour change required`, `dependency without multiplatform replacement`, `decision required`, or `REQUIRES_APPROVAL`.

Action: escalate immediately. Print: file or task affected, subagent's reason / options, recommended option (with rationale, biased toward correctness per §2). User replies; orchestrator records the decision in `migration-report.md` as a deviation if applicable, then continues or revises the plan.

When unsure, default to interpretive (escalate).

## Completion-promise validation

Every subagent emits exactly one completion-promise token on its final line. The orchestrator reads only the last line.

If no valid token is found, the subagent's output is treated as `*_BLOCKED` with reason `malformed-completion-promise`. Escalate to user with the malformed output.

## Updating tasks.md

After every completed dispatch:
- On success: mark `[x]`. Append a one-line note with the subagent's relevant output.
- On block / interpretive escalation: mark `[!]`, paste the BLOCKED or REQUIRES_APPROVAL text inline. Wait for user direction.

Commit `tasks.md` at level / checkpoint boundaries — not after every task. Commit message: `tasks: <phase letter> progress <X/Y>`.

## Parallelism

- Scaffold tasks run sequentially — they create files other tasks depend on.
- Capture tasks run in parallel — each operates on a different file with no inter-task dependency.
- T-LOCK is a single orchestrator-run task.
- Migrate tasks parallelize within a DAG level. Level L+1 cannot start until every task in level L is `[x]`.

## Scope discipline (Constitution §6)

The orchestrator and every subagent stop and escalate if work would extend beyond the in-scope list, except:

- Updating an import in a file listed under `Consumers` for an in-scope file (allowed without escalation).
- Applying the `@Ignore` patch logged as `D-1` at specify-phase (allowed; already approved).

Anything else outside scope → `REQUIRES_APPROVAL`.

## User question style

Whenever a command asks the user for a decision, follow this contract.

### One question at a time

Never bundle decisions. Even when two questions feel related, ask sequentially. Hidden disagreements surface earlier.

### Shape

Compressed structure. Each option carries a live-source citation. User picks `discuss` for the unfurled version.

```
<file-or-task>: <one-line situation>
A) <option, ~6 words> — <live-source citation, e.g., "Context7: lib X v3.0.3, verified 2026-05-08">
B) <option, ~6 words> — <live-source citation>
Rec: <A|B> — <constitution / boundary citation> + <live-source citation>.
[A / B / discuss]
```

**Live-research precondition (Constitution §4):** before presenting any question that names a library, version, API, configuration option, or migration pattern, dispatch the `researcher` subagent and wait for `RESEARCH_COMPLETE`. Each option carries a live-source citation with verification date. Options based on agent recall are forbidden.

### Routine approvals

For routine pre-approved actions (applying an `@Ignore` patch on tests outside scope, applying a pinned-version library swap), collapse to a one-line summary plus `y / n / discuss`. Don't auto-show diffs; user picks `discuss` for depth.

### Pushing back on vague input

If the user's input is too vague to act on without guessing — e.g., a one-line scope statement like "migrate auth" — do NOT proceed.

Per Constitution §2 + §3, ask targeted follow-ups until the input is concrete enough to verify against actual code:
- "Which user-facing feature does this serve? Show me the entry-point screen or activity."
- "Which call sites depend on this? Walk me through how a user reaches this code."
- "What's the rough file count? Point me at the package and I'll enumerate."

Loop until you have a list of concrete file paths, an entry point in the consumer app, and a clear feature boundary. A vague scope at specify-phase becomes a wrong scope by implement-phase.

## Master-drift detection

At every implement-phase invocation, before dispatching the first task:
- Read `spec.md`'s `baseline-locked-sha` (if T-LOCK has run) or `baseline master SHA` (if not).
- Run `git log <base-branch> -- <each in-scope file>` since the baseline SHA.
- If any in-scope file has been modified upstream, stop. Tell the user: "Master moved on these files since baseline. Run `plan-phase` against the new SHA before continuing."
