---
description: Design the target architecture before any code is touched. Identify tech debt that the migration can clean (Constitution §7), declare behaviour-preservation strategy, lock the refactor boundary. Architecture-reviewer subagent gates approval. Produces architecture.md — required input to plan-phase.
---

# /kmm-architect

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` and `references/code-graph.md` first.

This is the **prevention step**. Constitution §1: architecture before code. The skill exists in part because of a prior incident — an SDK migration that compiled but introduced redundant holders and short-term scaffolding into shared code. That kind of failure is design-time, not implementation-time, so this is where we catch it.

You are Opus and you do this work directly — design is your role, not a subagent's. **You do not dispatch sonnet/haiku for the design itself**; you read the source, decide the target shape, and only dispatch the `architecture-reviewer` subagent to gate the result.

## Inputs

- `<repo>/kmm/<scope>/spec.md` — declared scope and goal
- The worktree at `<repo>/.worktrees/kmm-<scope>/`
- The codebase as of the baseline SHA

## What you do

### 0. Graph freshness check.

Same as `plan-phase` step 0. Confirm the `code-review-graph` is current; if stale, refresh; if refresh fails, log under "Graph fallback" in `architecture.md` and proceed with `Read`/`Grep`. Print one line: `Graph: fresh / refreshed / stale, falling back`.

### 1. Read every in-scope file end-to-end with a clean-code lens.

This is a different read than `plan-phase`'s. `plan-phase` extracts the public API and library surface; **`/kmm-architect` looks at the *shape*** — does each file express its intent clearly, or is it scaffolded with mechanism-named members, holder classes, dead branches, multi-purpose functions, and incidental complexity?

For each in-scope file, capture:

- **Intent** — what is this file's responsibility, in one sentence, in domain language? If you can't say it in one sentence, that is itself a finding.
- **Shape concerns** — concrete observations against `references/clean-code.md` (loaded next step). Cite `file:line` for each. Examples:
  - "`AuthSdkHolder` (file:12) wraps `AuthSdk` and adds no behaviour — a thin pass-through that exists only because the original code wanted dependency-injection symmetry."
  - "`processData` (file:47) does three things: parsing, validating, and emitting — function name encodes mechanism (`process`) not intent."
  - "Branch at file:88–95 is unreachable in any baseline test — likely dead since the previous refactor."
  - "`UserManagerImpl` (file:1) — name encodes the pattern (`Manager`/`Impl`), not the role."
- **Public surface** — methods/properties consumers depend on. Public surface is **immutable across the migration** (Constitution §7). Capture it now so the architecture decision separates "what consumers see" (untouchable) from "what we can refactor" (the file's internals).
- **Behaviour invariants** — for each shape concern, name the externally-observable behaviour the baseline tests will need to pin down. If the concern is "function does two things", the behaviour invariants are the two outputs and their preconditions; the baseline tests must cover both.

Use the graph (`get_review_context`, `query_graph(callers_of=…)`, `query_graph(callees_of=…)`) first. Fall back to `Read` only when the graph doesn't expose the body content you need.

### 2. Read the clean-code reference.

Read `skills/kmm-migration-workflow/references/clean-code.md`. This is a short, domain-specific summary of the clean-code principles relevant to migration decisions: naming (intent over mechanism, domain over generic), functions (one thing, single abstraction level), structure (no scaffolding without behaviour, no holders without justification, no incidental complexity). It is the lens through which Step 1's findings are evaluated.

### 3. Decide the target architecture.

For each in-scope file, decide one of three paths per Constitution §7:

- **Surgical** — source is already clean. Migrate by swap and `expect/actual` only. No internal restructuring. Record as `path: surgical` in `architecture.md`.
- **Refactor** — source has tech debt the migration can fix without expanding scope. Enumerate each refactor as a numbered entry in the file's `Refactors` section of `architecture.md`. Each entry carries:
  - **Title** — one line, naming the violation (`Remove redundant AuthSdkHolder wrapper`, `Split processData into parse/validate/emit`, `Rename UserManagerImpl → UserDirectory`).
  - **Clean-code violation** — citation to `references/clean-code.md` (`§naming.intent-over-mechanism`, `§functions.one-thing`, `§structure.no-scaffolding-without-behaviour`).
  - **Source citation** — `file:line` range of the bad shape in master.
  - **Target shape** — a concrete description of what replaces it, in code-form pseudocode if necessary. Names, member shape, surrounding context.
  - **Boundary** — the file or contiguous block being refactored. The boundary cannot extend outside the in-scope file (Constitution §6). If a refactor's natural boundary crosses files, it is scope expansion — defer it as a follow-up note in `findings.md` and record `path: surgical` for this migration.
  - **Behaviour-preservation invariant** — the externally-observable behaviour that must remain identical, expressed as one or more test invariants the baseline `commonTest` will cover (e.g., "for any input X, parse(X) must produce the same `ParseResult` as the master form's `processData(X)` extracted via the parsing branch"). The `test-capturer` will use these invariants to write the baseline tests; any refactor whose invariant cannot be turned into a test is rejected — there is no proof of preservation.
  - **Risk** — `LOW` (rename, dead-code removal, simple extraction with mechanical-only edits) / `MEDIUM` (split into multiple methods, internal data-flow change) / `HIGH` (touches state-management, concurrency, error-paths). HIGH-risk refactors require explicit user approval at step 5 below.
- **Out of reach** — source has tech debt this migration cannot fix without expanding scope. Record as `path: surgical` for the migration, append a note to `architecture.md` under `Out-of-reach tech debt` (file:line + observation + why it's out of reach), and cross-post to `findings.md` so it survives into the post-migration record.

The default is **surgical**. Refactor must be earned by a concrete clean-code citation; no refactor entry is added because "it would be nicer". Aesthetic preferences (one expression style over another, equivalent idioms) are not authorised refactor reasons.

**Public API stays.** Method names, parameter names, parameter order, parameter types, return types, and visibility of every public member are byte-identical to source after the architecture is applied. If a refactor entry naturally wants to rename a public member, escalate to the user — the API change is itself a scope decision (Constitution §6), not an architecture detail.

### 4. Identify the target structure of the migrated unit (cross-file design).

Beyond per-file refactors, the architecture also describes how the in-scope files relate to each other in the migrated form:

- **Module boundaries** — does the unit factor into sub-units (e.g., `auth-data`, `auth-domain`, `auth-platform`)? If so, what's in each? Cite source `file:line` for the proposed grouping.
- **Layering** — which files depend on which, in the target shape. Compare to the source DAG (which `plan-phase` will compute formally). If the target layering differs from source, that itself is a refactor — list it under cross-file refactors with the same fields as per-file refactors.
- **Boundary mechanism per platform-bound dependency** — for each external dependency that doesn't have a multiplatform replacement, decide the boundary level per Constitution platform-boundary §1–3 (multiplatform library → expect/actual → interface+DI). The decision is recorded here at architecture time so `plan-phase` doesn't re-decide it; `plan-phase` only verifies and operationalises.
- **Naming model** — if the source uses a confused or mechanism-led naming model (everything is `*Manager`, `*Service`, `*Holder`), the architecture proposes a coherent target naming model in domain terms. Each rename in this model must satisfy Principle 6: it cannot extend the public API.

### 5. Surface user-input-required decisions.

Before writing `architecture.md`, escalate any decision the orchestrator cannot make alone (per `references/orchestration-protocol.md` § "User question style"). Common gates:

- **HIGH-risk refactor approval.** Each HIGH-risk refactor entry is presented to the user with: source `file:line`, the violation, the proposed target shape, the behaviour-preservation invariant, and the alternative (defer the refactor and ship surgically). Recommend per Constitution §7 (clean shape over short-term expedience) but never silently apply a HIGH-risk refactor without user `y`.
- **Naming-model proposals.** If the cross-file architecture renames public types (e.g., `UserManagerImpl` → `UserDirectory`), the rename touches every consumer. Surface as one option-shaped question: A) apply the rename and update consumers (recommended if the source name actively misleads), B) keep the source name (if rename is purely aesthetic, default to keep). The user decides.
- **Module-boundary proposals.** If the architecture proposes splitting the unit into sub-modules, surface explicitly — that is a user decision, not an automatic call. Recommend the simplest grouping that survives the next 12 months of likely change, not the most clever one.

One question at a time. Each question carries options + recommended + why. The user's answers populate `architecture.md`'s relevant sections.

### 6. Estimate scope-size and propose checkpoints.

Constitution §13 — checkpoint PRs for reviewability. Compute the size signal:

- in-scope file count
- whether any HIGH-risk refactor entries exist
- whether any cross-file refactors (renames, module splits) exist
- declared library swap count from a quick `findings.md` scan (if `plan-phase` hasn't run, estimate from the source's import statements)

Apply the heuristic: if **>10 files** OR **any HIGH-risk refactor** OR **any cross-file rename touching ≥3 consumers** OR **swaps touching >3 files** → propose a checkpoint plan.

The default split (Constitution §13):

1. **Pure relocation** — `git mv` files into `androidMain`, capture commonTest baselines, lock baseline. Reviewable in minutes.
2. **Library swaps + `expect/actual`** — apply swaps named in `findings.md`. Public API preserved. Tests still green.
3. **Architecture-approved refactors** — apply the refactors enumerated in `architecture.md`. Tests still green.
4. **(Optional) Sub-unit splits** — for very large units, sub-divide further along module boundaries from step 4.

Each checkpoint is master-mergeable: declared targets compile, consumers compile, no checkpoint depends on a later one. The single exception: every checkpoint after the first depends on the prior checkpoint's branch having merged (or being mergeable), since they stack.

Surface the proposed checkpoint plan to the user as one question:

> Question: **Migration size suggests a checkpointed PR sequence**
>
> Estimate: `<N>` files / `<M>` library swaps / `<R>` refactors. A single PR would be hard to review.
>
> Proposed checkpoints:
>   1. `<scope>-relocation` — `git mv` + commonTest baselines + baseline lock. Estimated diff: `<X>` files moved, `<Y>` test files added.
>   2. `<scope>-swaps` — apply `<M>` library swaps and `<expect/actual>` declarations. Public API preserved.
>   3. `<scope>-refactors` — apply `<R>` architecture-approved refactors. Tests green.
>
> Options:
>   A) Approve checkpoints as proposed (recommended — each PR reviewable in <30 min)
>   B) Single PR (recommended only if the team accepts one heavy review)
>   C) Discuss — adjust the boundaries
>
> Recommended: A. Why: per Constitution §13, large single-PR migrations are where rubber-stamping enters; checkpoints make each step independently auditable.
>
> Reply: A / B / C

Record the user's choice in `architecture.md` under `## Checkpoint plan`. If A, list each checkpoint by name and content. If B, record a single checkpoint entry called `<scope>` with all phases bundled. The downstream `plan-phase`, `tasks-phase`, `implement-phase`, `pr-phase` honour this plan.

If the size signal does not trip the heuristic, record `## Checkpoint plan` as a single checkpoint and skip the question.

### 7. Write `architecture.md`.

Use `templates/architecture.md`. Required sections:

- **Goal** — one paragraph from `spec.md`'s goal, plus the one-line statement of the target architecture.
- **Constitution version** — the version this architecture is governed by.
- **Per-file architecture** — one entry per in-scope file:
  - `path: surgical | refactor | out-of-reach`
  - **Intent** — one-sentence statement of the file's responsibility in domain language.
  - **Shape concerns** — citations from Step 1 (file:line, observation, clean-code reference).
  - **Refactors** (only if `path: refactor`) — numbered list (R-1, R-2, …) with all six fields from Step 3.
  - **Out-of-reach tech debt** (only if relevant) — observations not addressed in this migration; cross-posted to `findings.md`.
- **Cross-file architecture** — module boundaries, layering, boundary-mechanism decisions per dependency, naming model.
- **Behaviour-preservation strategy** — for each refactor (per-file or cross-file), the test invariants the `test-capturer` will write into `commonTest` to prove behaviour preservation.
- **Checkpoint plan** — from Step 6.
- **Open questions** — any decision the user owes before `plan-phase`. (Should be empty after Step 5; if not, that's the bug — re-run Step 5.)

Constitution version pin: copy the version string verbatim from `constitution.md` Line 3.

### 8. Dispatch `architecture-reviewer`.

```
Dispatch: agents/architecture-reviewer.md
Task: Review architecture.md against constitution.md and references/clean-code.md.
      Find every BLOCKER, HIGH, MEDIUM. Return ARCHITECTURE_ANALYSIS report.
Model: sonnet
Mode: read-only (no Write/Edit)
```

The reviewer checks:
- Every `Refactor` entry has all six fields and a clean-code citation.
- Every behaviour-preservation invariant is concrete enough to become a `@Test`.
- No refactor extends scope (touches another file's public API; pulls a new file into scope; depends on an out-of-scope behaviour).
- No refactor is purely aesthetic.
- Public API for every file is preserved (Constitution §6, §7).
- HIGH-risk refactors carry explicit user approval (recorded in the architecture's open-questions resolution).
- Checkpoint plan is sequential and each checkpoint is master-mergeable.
- The cross-file naming model is coherent (no leftover `*Manager`/`*Holder` unless authorised by intent).

If `BLOCKER` or `HIGH` issues are found, classify each:

- **Orchestrator-fixable** — missing field, wrong citation, ambiguous invariant. Update `architecture.md` directly and re-dispatch.
- **User-input-required** — a refactor's behaviour invariant requires user clarification (the source's intended behaviour is ambiguous), or a checkpoint boundary should be moved. Per Constitution §3 & §4, dispatch `researcher` first to live-source any library/version/API named in the proposed options, then ask one question at a time.

Loop until `BLOCKER: 0, HIGH: 0`. Three full re-dispatch cycles without convergence → escalate to user with the analyzer report and the strike history.

`MEDIUM` issues do not block. Each MEDIUM is logged in `migration-report.md` as a `D-N` with status `OPEN` and a structured `Closure:` field per `templates/migration-report.md` § "Closure types".

### 9. Present the architecture to the user.

Print a **summary** in chat — not the full file. Format:

- Title and one-line goal (from `architecture.md`).
- Per-file path counts (e.g., `12 files: 8 surgical, 3 refactor (5 entries), 1 out-of-reach`).
- Refactor entries by risk (`LOW: 3, MEDIUM: 2, HIGH: 0`).
- Cross-file decisions in one line each (e.g., `Module: auth-domain + auth-platform`, `Naming model: domain-led (UserDirectory, AuthSession)`).
- Checkpoint plan: `1. relocation → 2. swaps → 3. refactors`.
- Path to full architecture: `<repo>/kmm/<scope>/architecture.md`.

End with one approval prompt:

> Architecture ready. Approve? [y / step / discuss]

On `y`:
- Auto-advance to `plan-phase` if reached via the `/kmm` chain. Print: `── plan-phase ──`.
- Otherwise: `Approved. Run plan-phase to draft the per-file plan.`

On `step`:
- `Step mode. Run plan-phase when ready.`

On `discuss`:
- Open the artifact (paste relevant excerpts) and re-ask.

The user's `y` here is binding for downstream commands. `plan-phase` will not re-litigate architecture decisions; it operationalises them.

### 10. Constitution check.

- Touched: §1 (architecture before code), §4 + §5 (live-sourced where applicable), §6 (refactor stays in scope), §7 (clean-code-first decision tree applied per file), §13 (checkpoint plan recorded).
- Pass/fail checklist:
  - `[ ]` Every in-scope file has a `path` declaration
  - `[ ]` Every `refactor` file has 1+ `Refactor` entries with all six fields
  - `[ ]` Every refactor cites `references/clean-code.md`
  - `[ ]` Every behaviour-preservation invariant is test-shaped
  - `[ ]` No refactor extends scope (architecture-reviewer verified)
  - `[ ]` Public API for every file preserved
  - `[ ]` HIGH-risk refactors carry user approval
  - `[ ]` Checkpoint plan recorded
  - `[ ]` `architecture-reviewer` returned `BLOCKER: 0, HIGH: 0`
  - `[ ]` User approved the architecture
- On fail: STOP. Report which checks failed.

### 11. Next step.

"Architecture approved. Run `plan-phase` to draft the per-file plan." (or auto-advance via `/kmm` chain).

## What you do NOT do

- Do not write `plan.md`, `migration-guide.md`, or any code. Architecture decisions are recorded in `architecture.md` only; `plan-phase` operationalises them.
- Do not author refactors aesthetically. Every refactor cites a concrete violation.
- Do not extend scope. If a refactor's natural boundary crosses files, defer the refactor as out-of-reach.
- Do not modify `commonTest/`, `commonMain/`, `androidMain/`, or any consumer file.
- Do not commit code. Only `architecture.md` and (if escalations changed it) `migration-report.md` are written.

## Failure modes

- **A file's behaviour is unclear** — stop and ask the user; never guess (Constitution §2).
- **A refactor's behaviour invariant cannot be expressed as a test** — reject the refactor; keep `path: surgical` and log the tech debt as out-of-reach.
- **A refactor's natural boundary crosses files** — defer; do not silently expand scope (Constitution §6).
- **Architecture-reviewer finds an orphan refactor** (no clean-code citation, no source citation) — fix or remove the refactor; re-dispatch.
- **User declines a HIGH-risk refactor** — drop the refactor entry, record `path: surgical` for that file, log the tech debt under "Out-of-reach" in `architecture.md` and `findings.md`.
