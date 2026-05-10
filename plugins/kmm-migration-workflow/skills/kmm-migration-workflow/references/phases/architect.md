---
description: Design the target architecture before any code is touched. Identify tech debt the migration can clean (Constitution §7), declare behaviour-preservation strategy, lock the refactor boundary. Architecture-reviewer gates approval. Produces architecture.md.
---

# Phase: architect

You are Opus. Design is your role, not a subagent's. You read the source, decide the target shape, dispatch only `architecture-reviewer` to gate the result.

Read `constitution.md` and `references/code-graph.md` first.

## Inputs

- `<repo>/kmm/<scope>/spec.md`
- The worktree at `<repo>/.worktrees/kmm-<scope>/`
- The codebase as of the baseline SHA

## Steps

### 0. Graph freshness check

Per `references/code-graph.md` § "Freshness check". Print one line: `Graph: fresh / refreshed / stale, falling back`.

### 1. Read every in-scope file end-to-end with a clean-code lens

For each in-scope file capture:

- **Intent** — file's responsibility in one sentence, in domain language. If you can't say it in one sentence, that's a finding.
- **Shape concerns** — concrete observations against Constitution §7's clean-code rules. Cite `file:line`. Examples:
  - `AuthSdkHolder` (file:12) wraps `AuthSdk` and adds no behaviour — pass-through holder.
  - `processData` (file:47) does three things: parse, validate, emit — name encodes mechanism, not intent.
  - Branch at file:88–95 unreachable in any baseline test.
  - `UserManagerImpl` (file:1) — name encodes pattern, not role.
- **Public surface** — methods/properties consumers depend on. Immutable across the migration.
- **Behaviour invariants** — for each shape concern, the externally-observable behaviour that baseline tests must pin.

Use the graph (`get_review_context`, `query_graph`) first; fall back to `Read` only when the graph doesn't expose body content.

### 2. Decide the target architecture (per file)

Three paths per Constitution §7:

- **Surgical** — source is already clean. Migrate by swap and `expect/actual` only. No internal restructuring. Default.
- **Refactor** — source has tech debt the migration can fix without expanding scope. Each refactor is a numbered entry (R-1, R-2, …) in the file's section, with these fields:
  - **Title** — one line naming the violation.
  - **Clean-code violation** — citation to Constitution §7 (`§naming.intent-over-mechanism`, `§functions.one-thing`, `§structure.no-scaffolding-without-behaviour`).
  - **Source citation** — `file:line` range of the bad shape in master.
  - **Target shape** — concrete description of what replaces it (pseudocode if necessary). Names, members, surrounding context.
  - **Boundary** — file or contiguous block being refactored. Cannot extend outside the in-scope file (Constitution §6). Cross-file refactors → defer as out-of-reach.
  - **Behaviour-preservation invariant** — externally-observable behaviour that must remain identical, expressed as test invariants. Refactors whose invariant cannot be turned into a test are rejected — no proof of preservation.
  - **Risk** — `LOW` (rename, dead-code removal, mechanical extract) / `MEDIUM` (split into multiple methods, internal data-flow change) / `HIGH` (state-management, concurrency, error paths). HIGH-risk requires explicit user approval in step 4.
- **Out of reach** — tech debt this migration cannot fix without expanding scope. Record as `path: surgical`; append note to `architecture.md § Out-of-reach tech debt` and `findings.md`.

Default is **surgical**. Refactor must be earned by a concrete clean-code citation; aesthetic preferences are not authorised.

**Public API stays.** If a refactor entry naturally wants to rename a public member, escalate — that is a scope decision, not architecture detail.

### 3. Cross-file design

- **Module boundaries** — does the unit factor into sub-units (`auth-data`, `auth-domain`, `auth-platform`)? Cite `file:line`.
- **Layering** — which files depend on which in the target shape. Compare to source DAG (computed formally at plan-phase). Differences are themselves refactors.
- **Boundary mechanism per platform-bound dependency** — multiplatform library → expect/actual → interface+DI per Constitution platform-boundary §1–3. Decision recorded here.
- **Naming model** — if source uses `*Manager` / `*Service` / `*Holder` everywhere, propose a coherent target naming model in domain terms. Renames cannot extend public API.

### 4. User-input-required decisions

Escalate before writing `architecture.md`:

- **HIGH-risk refactor approval.** Each presented with: source `file:line`, violation, proposed target shape, behaviour-preservation invariant, alternative (defer + ship surgically). Recommend per Constitution §7; never silently apply.
- **Naming-model proposals** that rename public types — touches every consumer.
- **Module-boundary proposals** — splitting the unit into sub-modules.

One question at a time. Each carries options + recommended + why.

### 4b. Declare the smoke test

Per Constitution Verification §8, every migration ships with a mandatory JVM smoke test that exercises runtime wiring. The architect declares its shape; the test-capturer writes it; the completeness-verifier runs it.

The smoke test is a single test class in the consumer module's JVM test source set that:
1. Boots the DI graph (Koin or whichever module system the consumer uses).
2. Resolves every migrated public type whose runtime wiring matters.
3. Calls one happy-path public method on each resolved type.
4. Confirms no crash, no init-order failure, no missing binding.

Decide:

- **Test class FQN.** Convention: `<consumer.package>.<scope>SmokeTest` in `:<consumer-module>/src/test/kotlin/...`.
- **DI bootstrap.** Which Koin/DI modules does the test load? Read the consumer's existing test setup; usually the consumer already has an `appModule` or scoped test module — reuse it.
- **Types to resolve.** For each migrated file whose type is exposed to consumers via DI, list the type FQN and one happy-path public method to invoke. Pure data classes / value types without DI wiring are skipped (they have no runtime wiring to break).
- **Instrumented variant.** Default: `none`. Enable only when the migrated feature has Android-platform-specific runtime behaviour the JVM smoke can't exercise (Context-bound init, Android-only crypto, etc.). When enabled, the test runs via `./gradlew :<consumer>:connectedDebugAndroidTest` — slow, requires an emulator.

Record in `architecture.md § Smoke test` per the template.

If no migrated type is wired through DI (rare — purely functional helpers, value types), the JVM smoke degrades to a "DI graph still boots cleanly" check: load the modules, confirm no exception. That's still a meaningful gate against missing-binding crashes.

### 5. Estimate scope and propose checkpoints

Constitution §13 heuristic: if **>10 files** OR **any HIGH-risk refactor** OR **any cross-file rename touching ≥3 consumers** OR **swaps touching >3 files** → propose checkpoints.

Default split:
1. **Pure relocation** — `git mv` files into `androidMain`, capture commonTest baselines, lock baseline.
2. **Library swaps + `expect/actual`** — apply swaps. Public API preserved.
3. **Architecture-approved refactors** — apply enumerated refactors.

Each checkpoint master-mergeable: declared targets compile, consumers compile, no checkpoint depends on a later one.

Surface as one question:

> Migration size: `<N>` files / `<M>` swaps / `<R>` refactors.
>
> Proposed checkpoints:
>   1. `<scope>-relocation` — `git mv` + commonTest baselines + lock. Diff: `<X>` files moved, `<Y>` test files added.
>   2. `<scope>-swaps` — `<M>` library swaps + `<expect/actual>` declarations. Public API preserved.
>   3. `<scope>-refactors` — `<R>` architecture-approved refactors.
>
> A) Approve as proposed (recommended — each PR reviewable in <30 min)
> B) Single PR (only if team accepts one heavy review)
> C) Discuss
>
> Reply: A / B / C

If the size signal doesn't trip, record as a single checkpoint and skip the question.

### 6. Write `architecture.md`

Use `templates/architecture.md`. Required sections:

- **Goal** — one paragraph from `spec.md`'s goal + one-line target architecture statement.
- **Constitution version** — verbatim from `constitution.md` Line 3.
- **Per-file architecture** — one entry per file: path declaration, intent, shape concerns, refactor entries (if `path: refactor`), out-of-reach notes (if relevant).
- **Cross-file architecture** — module boundaries, layering, boundary-mechanism decisions, naming model.
- **Behaviour-preservation strategy** — for each refactor, the test invariants `test-capturer` will write.
- **Smoke test** — from step 4b. Test class FQN, DI bootstrap modules, types-to-resolve with happy-path methods, instrumented opt-in status.
- **Checkpoint plan** — from step 5.
- **Open questions** — anything the user owes before plan-phase. (Should be empty after step 4.)

### 7. Dispatch `architecture-reviewer`

```
Dispatch: agents/architecture-reviewer.md
Task: Review architecture.md against constitution.md.
      Find every BLOCKER, HIGH, MEDIUM. Return ARCHITECTURE_ANALYSIS.
Model: sonnet
Mode: read-only
```

The reviewer checks:
- Every `Refactor` entry has all six fields and a clean-code citation.
- Every behaviour-preservation invariant is test-shaped.
- No refactor extends scope.
- No refactor is purely aesthetic.
- Public API for every file preserved.
- HIGH-risk refactors carry user approval.
- Checkpoint plan is sequential and each checkpoint is master-mergeable.

If `BLOCKER` or `HIGH` found:
- **Orchestrator-fixable** (missing field, wrong citation, ambiguous invariant) — update directly and re-dispatch.
- **User-input-required** — dispatch `researcher` first to live-source any library/version named in proposed options, then ask one question at a time.

If the reviewer keeps surfacing the same issue across re-dispatches, escalate to user with the analyzer report. Repeated mechanical surfacing is a signal of missing prevention upstream — surface, don't loop.

`MEDIUM` issues do not block. Each is logged in `migration-report.md` as `D-N` with status `OPEN` and structured `Closure:` per `templates/migration-report.md`.

### 8. Present to user

Print **summary** in chat — not the full file:

- Title and one-line goal.
- Per-file path counts (`12 files: 8 surgical, 3 refactor (5 entries), 1 out-of-reach`).
- Refactor entries by risk (`LOW: 3, MEDIUM: 2, HIGH: 0`).
- Cross-file decisions in one line each.
- Checkpoint plan: `1. relocation → 2. swaps → 3. refactors`.
- Path to full architecture.

Single approval prompt:

> Architecture ready. Approve? [y / step / discuss]

The user's `y` is binding for downstream commands.

### 9. Constitution check

Touched: §1, §4 + §5 (where applicable), §6, §7, §13.

Checklist:
- `[ ]` Every in-scope file has a `path` declaration
- `[ ]` Every `refactor` file has 1+ `Refactor` entries with all six fields
- `[ ]` Every refactor cites a clean-code rule
- `[ ]` Every behaviour-preservation invariant is test-shaped
- `[ ]` No refactor extends scope (architecture-reviewer verified)
- `[ ]` Public API for every file preserved
- `[ ]` HIGH-risk refactors carry user approval
- `[ ]` Checkpoint plan recorded
- `[ ]` Smoke test declared (FQN, DI modules, types-to-resolve with happy-path methods)
- `[ ]` `architecture-reviewer` returned `BLOCKER: 0, HIGH: 0`
- `[ ]` User approved the architecture

### 10. Next

Auto-advance to plan-phase via `/kmm` chain. In `--step` mode, stop.

## Failure modes

- **A file's behaviour is unclear** — stop and ask (Constitution §2).
- **A refactor's invariant cannot be expressed as a test** — reject; keep `path: surgical`, log as out-of-reach.
- **A refactor's natural boundary crosses files** — defer (Constitution §6).
- **Architecture-reviewer finds an orphan refactor** — fix or remove; re-dispatch.
- **User declines a HIGH-risk refactor** — drop entry, record `path: surgical`, log as out-of-reach.
