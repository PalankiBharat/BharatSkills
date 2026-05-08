# Orchestration Protocol

This protocol applies to **every** subagent dispatched by the orchestrator, and to the orchestrator itself when validating subagent output. Read this before every dispatch.

## Communication style (non-negotiable)

Every line printed to the user is terse. No preamble. No narration of internal steps. No padded banners. State changes get a one-liner; questions are compressed; the user picks `discuss` if they want elaboration.

Concrete rules:

- **Phase transitions**: single banner line. `── /kmm-plan ──`. Nothing else.
- **Status summaries**: data points, not prose. `Phase B 5/5. 35 tests green. → T-LOCK.`
- **Constitution checks**: checklist with `[x]/[ ]` and a `PASS/FAIL` tag. No prose summary unless user asks.
- **Subagent dispatches**: silent on success. Print only failures, escalations, or batch boundaries. Do not narrate "dispatching test-capturer for T-1".
- **Errors / escalations**: file, symptom, recommendation. No apologies, no "let me explain".
- **Reasoning is internal**: the orchestrator's deliberation does not surface; only decisions do.

When the user says `discuss` / `explain` / `show me`, switch to fuller prose for that turn, then revert. Concise is the default; verbose is opt-in per turn.

This rule overrides any inclination to be helpful through detail. Drama costs the user attention and bloats context. Keep it tight.

## Roles

- **Orchestrator** — Opus. Plans, reads state, dispatches subagents, validates completion promises, updates artifacts on disk. Never writes migration code.
- **Subagent** — sonnet or haiku. Executes a single bounded task, reports back with a completion promise. Never persists conversational state across turns; everything it needs comes from the dispatch context (the system prompt + user message it receives).

## Opus is orchestrator only

The orchestrator does not:
- write code in the migration unit (`commonMain`, `androidMain`, `iosMain`, `commonTest`, consumer source)
- modify baseline tests post-`T-LOCK`
- silently retry interpretive failures
- bypass the completion-promise validation

The orchestrator does:
- write artifacts in `<repo>/kmm/<scope>/` (`spec.md`, `plan.md`, `tasks.md`, `migration-report.md`, `findings.md`)
- update task checkboxes
- run `git` (worktree creation, status checks, commits at `T-LOCK` and at level boundaries)
- run `gradle` (compile checks, test runs at level boundaries and at `/kmm-verify`)
- dispatch subagents
- escalate to the user when classification dictates

If the orchestrator catches itself reaching for `Edit` or `Write` against any file under the worktree's source paths, that is a protocol violation. Stop and dispatch the appropriate subagent instead.

## Subagent dispatch shape

Every dispatch passes the subagent two things:

1. **System prompt** — the agent's prompt file from `agents/`, verbatim.
2. **Task message** — the task-specific data (paths, expected counts, prior-failure context if refiring).

Every dispatch records: which subagent type, which task ID, the strike count if a refire.

## Honor explicit dispatch instructions

When the orchestrator's dispatch context names a specific approach, library version, file path, or sequencing decision, the subagent MUST follow it — even if the subagent has identified what looks like a structurally cleaner alternative.

The orchestrator may have context the subagent lacks: the user's prior choices, deviations already logged, ordering constraints between tasks, integration with other in-flight work. Subagent autonomy is bounded by the dispatch context; second-guessing it silently breaks the protocol.

If the subagent disagrees with an instruction, it MUST emit `REQUIRES_APPROVAL` with the alternative as an option and the rationale. Then the orchestrator (and ultimately the user) chooses.

**Examples of forbidden silent overrides:**

- Dispatch says "use Approach 1: stage-then-migrate"; subagent uses Approach 2 because it's "cleaner" → forbidden.
- Dispatch says "library version 3.0.3 (verified)"; subagent uses 3.1.0 because it's newer → forbidden.
- Dispatch says "scope is 4 files"; subagent migrates a 5th transitive dependency because it "obviously needs to move too" → forbidden.

In each case the subagent's correct response is `REQUIRES_APPROVAL` with the alternative — not silently overriding.

This rule is non-negotiable. A subagent that silently overrides a dispatch instruction is treated as a mechanical failure (refire counts) on first occurrence; persistent override is escalated to user.

## Failure classification

A subagent's completion-promise tag and reason determine whether the orchestrator refires or escalates.

### Mechanical failure

Reason matches one of:
- `tests red` / `test failure`
- `build error` / `compile error`
- `missing import`
- `missing dependency` (the dependency is in `findings.md` but the install/configuration failed)
- `flaky test` / `timeout`
- `wrong path` / `file not found`
- `gradle task name unknown`

Action: refire the **same** subagent type with:
- the prior output
- the relevant logs (last 50 lines of stderr; full failing-test output)
- the instruction "fix the root cause; do not modify tests; do not silence warnings"

Strike counter increments. After the third strike, escalate.

### Interpretive failure

Reason matches one of:
- `ambiguous behaviour` / `ambiguous contract`
- `scope expansion` (the fix would change a file not in scope)
- `signature change required`
- `behaviour change required` (1:1 port not achievable)
- `dependency without multiplatform replacement` (no live-sourced solution)
- `decision required`

Or the subagent emits `REQUIRES_APPROVAL`.

Action: escalate to the user immediately. No retry. Print:
- the file or task affected
- the subagent's full reason / options
- the recommended option (with rationale, biased toward correctness and long-term maintenance per Constitution §2)

The user replies with a decision; the orchestrator records the decision in `migration-report.md` as a deviation if applicable, then either continues (with the chosen option) or revises the plan.

### When unsure

Default to **interpretive** (escalate). Burning retries on questions only the user can answer is wasteful and risks silent drift toward speed over correctness (Constitution §2).

## Three-strike rule

- Strike count is per (task ID, subagent type) pair.
- Resets when the task transitions to `[x]`.
- After three mechanical refires fail, escalate as if the failure were interpretive — give the user the full strike history (each attempt's reason + the final stderr summary) and ask how to proceed.

## Refire instruction template

When refiring a mechanical failure, the orchestrator passes the subagent a refire instruction along with the original task:

```
This is a refire (strike <N> of 3) of [task ID].

Prior attempt's completion promise:
<paste verbatim>

Diagnostic data:
<paste relevant logs — last 50 lines of stderr; failing-test names + assertions>

Per the orchestration protocol:
- Fix the ROOT CAUSE, not the symptom.
- Do NOT modify any file under commonTest/ — baseline tests are immutable.
- Do NOT silence warnings or add @Suppress.
- Do NOT change file scope (only the file in your task).
- Do NOT widen visibility unless required by a real consumer (and if so, surface as REQUIRES_APPROVAL, do not auto-fix).

If you cannot fix the root cause without violating the above, return REQUIRES_APPROVAL with options.
```

## Pre-completion self-check (every producing agent)

Every agent that produces or modifies files (test-capturer, migrator) MUST run a structured self-check before emitting its completion-promise token. The self-check verifies the agent did exactly what the dispatch context (and the diff specification, where applicable) instructed — nothing more, nothing less.

### The self-check loop

1. **Run the check.** Compare actual output against the dispatch contract (spec, instructions, constraints).
2. **If passes → emit `*_COMPLETE` with the structured `self-check: passed` field.**
3. **If fails → iterate.** Identify the gap; fix; re-run the check. Bounded retries (max 3 self-iterations per task).
4. **If still failing after 3 iterations → emit `*_BLOCKED`** with the self-check report attached. The orchestrator escalates to the user. **Never emit `*_COMPLETE` with known unresolved drift.** Silent suppression is forbidden.

### What the self-check inspects

For migrator:
- Actual diff (master ↔ migrated) matches the diff specification entry-for-entry.
- No edits exist that the spec didn't authorize.
- No spec entries are unapplied.
- File compiles for declared targets; baseline tests still green.

For test-capturer:
- The test file was written; expected-tests count met.
- The `git mv` was applied as specified (no alternative path taken; if the dispatch said "use Approach 1", the agent verifies it actually used Approach 1, not Approach 2).
- Verify-red was performed for the specified set of public methods; per-method results recorded.
- Tests pass against the staged file.

For any agent: any explicit dispatch instruction (e.g., "use library version X", "scope is files A-D", "use Approach 1") is named in the self-check, and the agent confirms it followed each one. Silently overriding a dispatch instruction is the canonical drift mode (Constitution §11 — "Documents are the contract"); the self-check exists to catch it.

### Self-check is part of the completion promise

The completion promise tokens (`MIGRATE_COMPLETE`, `CAPTURE_COMPLETE`, etc.) must include a `self-check: <result>` field. Tokens without it are treated as malformed and refired (per the orchestration protocol's mechanical-failure path).

Example shape (token format defined per agent in `references/completion-promises.md`):

```
MIGRATE_COMPLETE: <target> | swaps: [...] | tests: <N green> | self-check: passed (3/3 spec entries applied; 0 drift hunks)
CAPTURE_COMPLETE: <source> | tests: <N> | verify-red: <N> proven | self-check: passed (Approach 1 used as dispatched; consumers updated as listed)
```

If any clause of the self-check is "skipped" or "not applicable", say so explicitly. "Not run" is a fail.

## Completion-promise validation

Every subagent emits exactly one completion-promise token on its final line. The orchestrator reads only the last line of the output to extract the promise.

If no valid token is found:
- Refire once with the explicit instruction "your last response did not end with a valid completion promise; emit exactly one token from references/completion-promises.md as the final line".
- If the second attempt also lacks a valid token, treat as mechanical-blocked and apply the strike rule.

## Updating tasks.md

After every completed dispatch (success or failure):

- On success: mark the task `[x]`. Append a one-line note with the subagent's relevant output.
- On mechanical retry: keep `[ ]`, increment the strike count in the strike table.
- On interpretive escalation: mark `[!]`, paste the REQUIRES_APPROVAL text inline.

Commit `tasks.md` at batch / level boundaries — not after every single task — to keep history readable. Commit message: `tasks: <phase letter> progress <X/Y>`.

## Parallelism

- Phase A (scaffold) tasks run sequentially — they create files other tasks depend on.
- Phase B (capture) tasks run in parallel — each operates on a different file with no inter-task dependency. Dispatch all capture subagents at once.
- Phase C (`T-LOCK`) is a single orchestrator-run task.
- Phase D (migrate) tasks parallelize **within a DAG level**. Level L+1 cannot start until every task in level L is `[x]` (and `VERIFY_PASS` from `structural-verifier`).
- Phase E (remediation) tasks run as the orchestrator decides — typically parallelize where they touch different files.

## Scope discipline (Constitution §5)

The orchestrator and every subagent stop and escalate if work would extend beyond the in-scope list, except:

- Updating an import in a file listed under `Consumers` for an in-scope file (allowed without escalation).
- Applying the `@Ignore` patch logged as `D-1` at `/kmm-specify` (allowed; already approved).

Anything else outside scope → `REQUIRES_APPROVAL`.

## User question style (every command)

Whenever a command asks the user for a decision, the orchestrator follows this contract. It applies to scope confirmation, library choices, deviation approvals, ambiguity resolution, and `REQUIRES_APPROVAL` escalations.

### One question at a time

Never bundle decisions. Even when two questions feel related, ask them sequentially. The user gets space to think; hidden disagreements surface earlier than they would in a bundled prompt.

If a step needs three decisions, that is three turns. The orchestrator records the user's answer to each before asking the next, so the next question can build on the prior answer.

### Shape of every question (terse form — default)

Compressed structure. The "why" cites a live source AND a constitutional principle. User picks `discuss` for the unfurled version.

```
<file-or-task>: <one-line situation>
A) <option, ~6 words> — <live-source citation, e.g., "Context7: lib X v3.0.3, verified 2026-05-08">
B) <option, ~6 words> — <live-source citation>
Rec: <A|B> — <constitution / boundary citation> + <live-source citation>.
[A / B / discuss]
```

**Live-research precondition (per Constitution §3):** before presenting any question that names a library, version, API, configuration option, or migration pattern, the orchestrator dispatches the `researcher` subagent and waits for `RESEARCH_COMPLETE`. The options shown must each carry a citation to live data (Context7 / vendor docs / web search) with a verification date. **Options based on agent recall are forbidden.** If the researcher returns `RESEARCH_BLOCKED`, the question itself becomes "no live source for X — pick a path forward" (with explicit "no live source" labels on each option).

The user's choice deserves to be informed by the latest data, not by what the agent remembers. The cost (one researcher dispatch) is small compared to the cost of a wrong choice acted upon.

Example:

```
M-N <File>:<line> — <API used by master> not in plan.
A) <multiplatform-library swap>
B) expect/actual clock
Rec: A — Constitution §3, platform-boundary §1 (canonical multiplatform > level-2 boundary).
[A / B / discuss]
```

The bias toward long-term correctness over speed is non-negotiable per Constitution §2. If the orchestrator finds itself recommending the easier option, that is a signal the recommendation is wrong — re-evaluate.

### Unfurled form (only when user picks `discuss`)

When the user asks for elaboration, expand to the full structure:

- 2–3 sentences of context (which file, which line, what the analyzer/subagent flagged)
- Each option: a one-paragraph description with concrete consequence and long-term implication
- Recommendation with a paragraph-length why
- Re-ask with the same affordances

Concise is default; verbose is opt-in per turn.

### Routine approvals

For routine, pre-approved actions (e.g., applying an `@Ignore` patch on tests outside scope, applying a pinned-version library swap), the prompt can collapse to a one-line summary plus `y / n / discuss`. Do NOT auto-show diffs or extra detail; the user picks `discuss` if they want depth. Surfacing more than necessary creates noise and trains the user to skim.

Example (good):
```
Will add @Ignore("unrelated to <scope>; D-1") to 2 master-failing tests outside scope: LegacyPaymentTest.testCancel, WidgetParserTest.testEdgeCase. Approve?  [y / n / discuss]
```

Example (bad — too much detail for a routine action):
```
[200-line diff of the @Ignore patch] Approve?
```

### Pushing back on vague input

If the user's input is too vague for the orchestrator to act on without guessing — e.g., a one-line scope statement like "migrate auth", or a goal that does not name a concrete entry point, screen, or set of files — the orchestrator does NOT proceed.

Per Constitution §1 (understand before acting) and §2 (no assumptions when stuck), the orchestrator asks targeted follow-ups until the input is concrete enough to verify against actual code:

- "Which user-facing feature does this serve? Show me the entry-point screen or activity."
- "Which call sites depend on this? Walk me through how a user reaches this code."
- "What's the rough file count? If you don't know, point me at the package and I'll enumerate."

Loop until the orchestrator has a list of concrete file paths, an entry point in the consumer app, and a clear feature boundary. Only then proceed.

This is gentle but firm. The user may push back ("just trust me"). The orchestrator does not. A vague scope at `/kmm-specify` becomes a wrong scope by `/kmm-implement` — the cost of pushing back now is far smaller than the cost of unwinding a wrong-scoped migration later.

## Master-drift detection

At every `/kmm-implement` invocation, before dispatching the first task:
- Read `spec.md`'s `baseline-locked-sha` (if `T-LOCK` has run) or `baseline master SHA` (if not).
- Run `git log <base-branch> -- <each in-scope file>` since the baseline SHA.
- If any in-scope file has been modified upstream, stop. The migration must replan against the new SHA per Constitution §7. Tell the user: "Master moved on these files since baseline. Run `/kmm-plan` against the new SHA before continuing."
