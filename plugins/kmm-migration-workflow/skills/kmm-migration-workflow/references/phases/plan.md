# Phase: plan

Read by the `/kmm` orchestrator when state-detection routes to the **plan** phase. Architecture must be approved (Constitution §1) before this phase runs — `architecture.md` must exist.

Read `skills/kmm-migration-workflow/constitution.md` and `references/code-graph.md` first.

This is the heaviest planning step. You are Opus and you do this work directly — planning is your role, not a subagent's. **You do not dispatch sonnet/haiku for plan drafting**; you read code yourself, write the plan yourself, and only dispatch agents for live-source research and gap analysis.

The plan **operationalises** the architecture. It does not re-decide refactor boundaries or library choices — those live in `architecture.md` and `findings.md`. Plan-time work is per-file diff-spec generation against architecture-approved swaps and refactors.

## Inputs

- `<repo>/kmm/<scope>/spec.md` — declared scope
- `<repo>/kmm/<scope>/architecture.md` — target architecture, refactor entries, checkpoint plan (REQUIRED)
- The worktree at `<repo>/.worktrees/kmm-<scope>/`
- The codebase as of the baseline SHA

## What you do

### 0. Graph freshness check.

Before any graph-first reads, confirm the `code-review-graph` is current. Per `references/code-graph.md`:

1. Call `list_graph_stats_tool` — capture `Last updated`.
2. Get the worktree's HEAD commit time: `git -C <worktree-path> log -1 --format=%ai`.
3. If `Last updated` is older than HEAD time (or shows `never`), call `build_or_update_graph_tool` once.
4. Re-call `list_graph_stats_tool`. If still stale (update failed or graph still behind HEAD), log a warning in `findings.md` under "Live-source audit" and fall back to `Read` / `Grep` for the rest of this `plan-phase` invocation. The `completeness-verifier` will note the graph fallback at `/kmm-verify` time.
5. If fresh, proceed graph-first.

Print one line: `Graph: fresh` / `Graph: refreshed` / `Graph: stale, falling back`. No further detail unless user asks.

### 1. Read every in-scope file end to end.

Use the graph-first protocol per `references/code-graph.md`. For each in-scope file:

- `get_review_context(<file>)` for the public API surface (methods/properties with signatures) — token-efficient vs. full `Read`.
- `query_graph(callees_of=<file>)` to enumerate external dependencies (filter for callees outside the in-scope list — these are swap or scaffolding candidates).
- `query_graph(callers_of=<file>)` to enumerate consumers (becomes the `Consumers` field).
- Fall back to `Read` only if you need raw body content for behaviour analysis the graph doesn't expose.

Document: full public API surface (method names, parameter names, parameter order, return types, visibility), every external dependency, every Android-only or JVM-only API used, every callback parameter, every place state is held.

If any file's behaviour is unclear from the source, **stop and ask**. Constitution §1: never guess from the call site.

### 2. Identify the dependency DAG.

For each in-scope file, list which other in-scope files it depends on. A file F depends on G if F imports something from G or calls into G. Build a topological order: files with no in-scope dependencies migrate first.

Reject cycles. If two files mutually depend, surface the cycle to the user — either both files must migrate atomically (one task pair, atypical) or one must shrink to break the cycle, or scope must be revised.

### 3. Identify required scaffolding.

For each external dependency a file uses (a class or interface from outside the in-scope list, including Android SDK, third-party libraries, project-internal infrastructure):

- If the dependency has a multiplatform replacement, record the swap in the file's migration-guide entry. Verify the replacement is current via the researcher subagent — never rely on training-data assumptions about which library to use.
- If the dependency does **not** have an in-scope file and the migrating file calls into it directly, an interface seam may be needed in `commonMain` so `commonTest` can fake it. List the required scaffolding interface as a separate task in the upcoming `tasks.md`.
- If the dependency cannot be cleanly abstracted, surface as `REQUIRES_APPROVAL` to the user before continuing.

### 4. Live-source every library decision.

For every library swap candidate, dispatch the `researcher` subagent (one dispatch per library, parallel where possible):

```
Dispatch: agents/researcher.md
Task: Look up current KMP support and recommended version for <library>.
      Cite Context7 first; fall back to vendor docs; fall back to web search.
      Return: { kmp-supported: yes/no, recommended-version: x.y.z, source: <url>, last-verified: <ISO date>, notes: <any caveats> }
Model: sonnet
```

Subagent returns `RESEARCH_COMPLETE` with the verified version and source URL. Record in `findings.md` under "Library Versions".

**Never fall back to training data.** Per Constitution §3, missing live source → reject the recommendation. If the researcher returns `RESEARCH_BLOCKED`, do NOT pick a version yourself. Escalate to the user (one question, options-shape per `references/orchestration-protocol.md`):

> Question: **Library `<library>` — no live source found**
>
> Researcher walked Context7 → vendor docs → web search and could not find authoritative KMP support / version information. Three paths:
>
> Options:
>   A) Hold off — pick a different library that does have live-sourced KMP support, even if the API shape is less ideal
>   B) Defer this file — drop it from the in-scope list, log as deviation, migrate later when the library matures
>   C) Provide the source yourself — paste a URL or doc reference the researcher missed (e.g., a private SDK doc, an internal wiki)
>
> Recommended: A or B depending on whether the file is a hard blocker for the unit.
> Why: per Constitution §3, recommendations without a live source are rejected. Picking a version from training data is the most common path to silent breakage; deferring or substituting is the correct long-term move.
>
> Reply: A / B / C / discuss

If multiple equally-valid replacements exist (researcher returned more than one viable option), present them as a user question with the same shape — recommendation biased toward long-term canonical KMM, never toward the easier or faster path.

### 5. Write `migration-guide.md`.

One entry per in-scope file. Use `templates/migration-guide.md`.

Required fields per entry (lean set):

- **Source** — exact path to the Android file
- **Target** — exact path in `commonMain` (or `androidMain` if classification is `migrate-expect-actual` and a piece stays platform-bound)
- **Path** — `surgical` | `refactor` | `out-of-reach` (verbatim from `architecture.md`'s per-file declaration; do not re-decide here)
- **Classification** — `migrate-pure` (all deps have multiplatform equivalents) | `migrate-expect-actual` (needs platform boundary) | `delete` (dead/duplicate)
- **Public API** — every public method/property with full signature, exactly as it appears in the source. This is the contract; **preserved byte-identical post-migration** even when `Path: refactor` (Constitution §7).
- **Library swaps** — exact replacements with verified versions from `findings.md` (no version comes from training data)
- **Platform APIs** — every Android-only/JVM-only API used, with `file:line` and the verified replacement (live-sourced)
- **expect/actual** — list each declaration needed (class/function/value); justification per Constitution platform-boundary §2
- **Refactor entries** — only when `Path: refactor`. Copy the `R-N` entries from `architecture.md` for this file verbatim. Each entry retains its six fields: title, clean-code violation, source citation, target shape, boundary, behaviour-preservation invariant, risk. **Orphan refactors (refactor entries without an `architecture.md` parent) are rejected by `plan-analyzer` as `BLOCKER`.**
- **Migrate after** — DAG predecessors (in-scope files this depends on)
- **Consumers** — files outside the in-scope list whose imports must update (paths only)
- **Expected tests** — minimum count, with explicit list (1+ per public method, plus error paths, plus edge cases, **plus one per refactor's behaviour-preservation invariant when `Path: refactor`**). The `test-capturer` and `migrator` subagents reject under-tested files.
- **Rules** — file-specific constraints that override defaults (e.g., "DO NOT combine `login(email)` and `login(phone)` into one method")
- **Checkpoint** — the checkpoint name from `architecture.md`'s checkpoint plan that this file's migration belongs to. Files within a checkpoint can be parallelised; checkpoints are sequential. (When the checkpoint plan is a single bundle, every file gets the same checkpoint name.)

Every entry must cite `file:line` for every claim. "TBD", "if needed", "minor changes" are rejected per Constitution §1.

Optional fields — include only if the file has them:
- **Callbacks** — only if the file has callback/lambda parameters that consumers wire actions into
- **Serialization** — only if the file touches JSON

UI-related fields (UI strategy, screen mapping) are not in this template by design. UI is out of scope for this skill.

### 5b. Compute the diff specification per file (precaution-first).

For every in-scope file, walk master line-by-line and produce the **Diff specification** field in `migration-guide.md` (see `templates/migration-guide.md`). This is the migrator's contract — every line in the migrated output is either a verbatim line from master or an explicit Remove / Add / Modify / **Refactor** entry with a citation.

Procedure for each file:

1. Fetch master content: `git show <baseline-master-sha>:<source-path>`.
2. For each line, decide its disposition:
   - **Unchanged** (default): goes into a `Lines X–Y: unchanged` range. No further work.
   - **Remove**: cite which swap removes it (an import line for a removed library, a removed annotation, etc.).
   - **Add**: cite which swap adds it (an import for the new library, a constructor parameter for a RATIFIED staging seam, etc.).
   - **Modify**: write both master form and migrated form verbatim; cite the swap; explicitly note what is preserved (variable name, method-signature shape, line position).
   - **Refactor** (only when `Path: refactor`): the line(s) are restructured per an `architecture.md` `R-N` entry. The diff entry shows the master form, the migrated form (verbatim, exact code), cites `architecture.md §R-N`, and lists the behaviour-preservation invariant (the test name in `Expected tests` that pins this behaviour). A Refactor entry can span multiple master lines (e.g., extracting a method).
3. Verify every Remove / Add / Modify / Refactor cites:
   - Remove/Add/Modify: a swap from the file's `Library swaps` or `Platform APIs` field, OR a RATIFIED deviation from `migration-report.md`.
   - Refactor: an `R-N` entry in `architecture.md` for this file, AND a behaviour-preservation invariant present in the `Expected tests` list.
   Orphan edits (no citation) → reject; revise the spec.
4. Verify every line in the master file appears exactly once in the spec (either inside a `Lines X–Y: unchanged` range or as a Remove/Modify/Refactor entry). Untouched master lines that aren't covered by an unchanged range → reject; revise.
5. **Refactor scope guard.** For each Refactor entry, verify that the migrated form does not introduce or reference any identifier outside the file's existing scope (no new files, no consumer-side changes). If a refactor's natural shape would touch outside the file, reject — kick back to the architect phase to either narrow the boundary or defer the refactor (Constitution §6).

The spec is the authoritative description of the migration for that file. The migrator applies it verbatim. The structural-verifier checks the actual diff matches it.

Variable/parameter/member naming preservation: per Constitution §7, names from master STAY unless the name literally encodes the swapped library's name as a token, OR the rename is part of an architecture-approved Refactor entry. The diff spec MUST mark each Modify entry with what is preserved (e.g., "preserve `<name>` from master") and each Refactor entry with the architecture citation that authorises any rename.

This step is the heaviest part of plan-phase — typically 30–50% of plan-time per file. The cost buys precaution: the migrator cannot drift because there is nothing creative left to interpret. **Refactor entries amplify this guarantee**: by encoding the new shape into the diff spec (verbatim target code), the architect's intent flows through to the migrator without re-interpretation.

### 6. Write `plan.md`.

Higher-level than `migration-guide.md`. Use `templates/plan.md`.

Sections:
- Title and one-line context (from `spec.md`)
- Migration unit goal (verbatim from `spec.md`)
- Baseline SHA (from `spec.md`)
- Declared shared targets and consumer targets (from `spec.md`)
- Verification command set: the exact `gradle` invocations `/kmm-verify` will run (per declared targets)
- Dependency DAG diagram (text-art is fine — files in topological levels)
- Required scaffolding interfaces (created in `commonMain` before capture begins)
- **Checkpoint plan** — copy from `architecture.md`. Each checkpoint lists: name, goal, files included, expected diff size. Tasks generation will batch by checkpoint (Constitution §13).
- Open questions — anything you want the user to decide before tasks-phase advances

### 7. Write `findings.md`.

Use `templates/findings.md`. Sections:
- **Decisions made during planning** — each library/architecture decision with options considered, choice, rationale (live-sourced), source URL, date verified
- **Library versions** — every pinned version with source
- **Compatibility notes** — consumer toolchain floor (Kotlin, Gradle, AGP, Xcode)
- **Gotchas** — non-obvious project-specific issues found while reading the codebase

### 8. Dispatch `plan-analyzer`.

```
Dispatch: agents/plan-analyzer.md
Task: Review spec.md, plan.md, migration-guide.md, findings.md against constitution.md.
      Find every BLOCKER, HIGH, MEDIUM. Return PLAN_ANALYSIS report.
Model: sonnet
Mode: read-only (no Write/Edit)
```

If `BLOCKER` or `HIGH` issues are found, classify each:

- **Orchestrator-fixable** — missing field, wrong path, missing DAG edge, typo, missing citation, file:line off-by-one. The orchestrator updates the artifact directly (re-reading source if needed) and re-dispatches `plan-analyzer`.
- **User-input-required** — scope amendment (e.g., a transitive dependency surfaces that wasn't in the in-scope list), library-choice ambiguity, an `expect/actual` boundary that could be defined multiple ways, behaviour ambiguity that needs the user to clarify intent.

For user-input-required findings, dispatch `researcher` first to live-source any library / version / API / pattern named in the proposed options. Wait for `RESEARCH_COMPLETE`. Per Constitution §3, options presented to the user must carry live-source citations — never recall-based.

Then ask one question at a time (per `references/orchestration-protocol.md` § "User question style"):

> Question: **<one-line title of the finding>**
>
> <2–3 sentences of context: which file, which line, what the analyzer flagged.>
>
> Options:
>   A) <option with concrete consequence>
>   B) <option with concrete consequence>
>
> Recommended: <A or B>
> Why: <one line — biased toward long-term canonical KMM, NEVER toward speed.>
>
> Reply: A / B / discuss

On the user's answer, the orchestrator amends the relevant artifact (e.g., adds a file to `spec.md`'s in-scope list and gives it a `migration-guide.md` entry), records a deviation in `migration-report.md` if the change is structural (e.g., scope expansion → `D-N` with status `RATIFIED`), and re-dispatches `plan-analyzer`.

Loop until `BLOCKER: 0, HIGH: 0`. Three full re-dispatch cycles without convergence → escalate to user with the analyzer report and the strike history; this means the plan needs human triage, not another retry.

`MEDIUM` issues do not block. Each MEDIUM is logged in `migration-report.md` as `D-N` with status `OPEN` and a **structured Closure field** per `templates/migration-report.md` § "Closure types" — most commonly `binding:present` (for missing Koin bindings the migrator will add), `grep:zero` (for residual imports/APIs to be removed), or `test:exists` (for test additions). Use `manual` only when the closure is genuinely fuzzy. The structured form lets `/kmm-verify` auto-close deterministically when the migrator's work meets the condition.

### 9. Present the plan to the user.

Print a **summary** in chat — not the full file. The summary is for fast scanning; the user opens the artifacts if they want depth.

- Title and one-line context (from `spec.md`'s goal)
- File count and breakdown by classification (e.g., "12 files: 9 migrate-pure, 2 migrate-expect-actual, 1 delete")
- Path breakdown (e.g., "8 surgical, 3 refactor, 1 out-of-reach")
- Refactor entry count by risk (LOW/MEDIUM/HIGH)
- Dependency-level depth (e.g., "4 levels")
- Library swaps with verified versions (one line each: `<from>` → `<to>` `<version>`)
- `expect/actual` declaration count
- Scaffolding interface count + names
- Checkpoint plan: per-checkpoint file count
- Deviations logged so far (from `migration-report.md`, by status)
- Path to full plan: `<repo>/kmm/<scope>/plan.md`, `migration-guide.md`, `findings.md`

End with a single approval prompt:

> Plan ready. Approve? [y / step / discuss]

On `y`:
- If reached via the `/kmm` chain, advance to the **tasks** phase. Print: `── tasks ──`. (Earlier versions required a `/clear` here; the simpler model lets the user invoke `/kmm` once and the orchestrator runs through to PR confirmation. If context pressure is a concern, the user can manually `/clear` and re-run `/kmm` to resume — state-detection picks up correctly.)

On `step`:
- Print: `Step mode. Re-run /kmm to advance to the tasks phase.`
- Stop.

On `discuss`:
- Open the artifacts (paste relevant excerpts) and re-ask.

The user's `y` here approves the plan and is the green light for the downstream auto-chain (tasks → implement → verify). The only remaining user gate is the PR confirmation at the pr-phase.

Wait for explicit approval before advancing.

### 10. Constitution check.

- Touched: §1 (architecture.md present and approved), §2 (every plan entry has `file:line`), §4 + §5 (every library decision live-sourced; no training-data fallbacks), §6 (scope unchanged from `spec.md`; refactor entries inside scope only), §7 (clean-code-first decision tree honored; refactor entries trace to architecture.md; public API preserved), §8 (baseline tests planned per file with expected counts; behaviour-preservation tests for refactors), §13 (checkpoint plan recorded), platform-boundary §2 (every `expect/actual` documented).
- Pass/fail checklist:
  - `[ ]` `architecture.md` exists and is reviewer-approved
  - `[ ]` Every in-scope file has a complete migration-guide entry
  - `[ ]` Every entry cites `file:line` for every claim
  - `[ ]` Every Refactor entry traces to an `architecture.md` `R-N` parent
  - `[ ]` Every Refactor entry has a behaviour-preservation test in `Expected tests`
  - `[ ]` Every library version is live-sourced with URL in `findings.md`
  - `[ ]` Dependency DAG has no cycles
  - `[ ]` Checkpoint plan recorded; every file assigned to a checkpoint
  - `[ ]` `plan-analyzer` returned `BLOCKER: 0, HIGH: 0`
  - `[ ]` User approved the plan
- On fail: STOP. Report which checks failed.

### 11. Next step.

Auto-advance via `/kmm` chain to **tasks** phase, or print "Plan approved. Re-run `/kmm` to advance to the tasks phase." in step mode.

## What you do NOT do

- Do not re-decide architecture. Refactor entries, library choices, and checkpoint boundaries come from `architecture.md`.
- Do not move any code yet.
- Do not write tests yet.
- Do not generate `tasks.md` — that is the tasks phase.
- Do not commit `tasks.md` or trigger any subagent labour.

## Failure modes

- **`architecture.md` is missing** — refuse to run; route the orchestrator back to the architect phase.
- **A file's behaviour is unclear** — stop and ask the user; never guess.
- **Researcher cannot find a live source for a library version** — reject the swap; escalate to user with options. Never fall back to training data.
- **DAG has a cycle** — surface to user; either co-migrate atomically (rare and risky), shrink the unit, or revise scope.
- **A Refactor entry's natural shape requires touching another file** — reject; route back to the architect phase to either narrow the boundary or defer the refactor (Constitution §6).
- **Required scaffolding doesn't fit one expect/actual / one new dep / no public API change** (Constitution §6) — stop, surface cost, propose deferring the file or shrinking the scope.
