# Phase: plan

Read by `/kmm` when state-detection routes to plan. `architecture.md` must exist and be reviewer-approved (Constitution §1).

You are Opus. Plan-time work is per-file diff-spec generation against architecture-approved swaps and refactors. The plan **operationalises** the architecture; it does not re-decide refactor boundaries or library choices.

Read `constitution.md` and `references/code-graph.md` first.

## Inputs

- `<repo>/kmm/<scope>/spec.md` — declared scope
- `<repo>/kmm/<scope>/architecture.md` — target architecture, refactor entries, checkpoint plan (REQUIRED)
- The worktree, the codebase as of the baseline SHA

## Steps

### 0. Graph freshness check

Per `references/code-graph.md` § "Freshness check". Print one line.

### 1. Read every in-scope file end-to-end

Graph-first per `references/code-graph.md`:
- `get_review_context(<file>)` for public API surface.
- `query_graph(callees_of=<file>)` for external dependencies.
- `query_graph(callers_of=<file>)` for consumers.
- Fall back to `Read` only for raw body content the graph doesn't expose.

Document: full public API surface, external dependencies, Android-only/JVM-only APIs used, callbacks, places state is held.

If any file's behaviour is unclear, stop and ask (Constitution §2).

### 2. Identify the dependency DAG

For each in-scope file, list which other in-scope files it depends on. Build topological order: files with no in-scope dependencies migrate first.

Reject cycles. Surface to user — co-migrate atomically (rare and risky), shrink the unit, or revise scope.

### 3. Identify required scaffolding

For each external dependency outside the in-scope list:
- Multiplatform replacement exists → record swap; verify via researcher.
- Dependency cannot be cleanly abstracted → `REQUIRES_APPROVAL`.

### 4. Live-source every library decision

For every library swap candidate, dispatch `researcher` (one per library, parallel where possible):

```
Dispatch: agents/researcher.md
Task: Look up current KMP support and recommended version for <library>.
      Cite Context7 first; fall back to vendor docs; fall back to web search.
      Return: { kmp-supported, recommended-version, source, last-verified, notes }
Model: sonnet
```

`RESEARCH_COMPLETE` → record in `findings.md § Library Versions`.

`RESEARCH_BLOCKED` → escalate to user with options:

> Library `<library>` — no live source found.
>
> A) Hold off — pick a different library with live-sourced KMP support
> B) Defer this file — drop from in-scope, log deviation, migrate later
> C) Provide the source yourself — paste a URL the researcher missed
>
> Recommended: A or B depending on whether the file blocks the unit.
> Why: per Constitution §4, recommendations without a live source are rejected. Picking from training data is the most common path to silent breakage.
>
> Reply: A / B / C / discuss

### 5. Write `migration-guide.md`

One entry per in-scope file. Use `templates/migration-guide.md`. Fields:

- **Source** — exact path to the Android file
- **Target** — exact path in `commonMain` (or `androidMain` if `migrate-expect-actual` and a piece stays platform-bound)
- **Path** — `surgical` | `refactor` | `out-of-reach` (verbatim from `architecture.md`)
- **Classification** — `migrate-pure` | `migrate-expect-actual` | `delete`
- **Public API** — every public method/property with full signature, exactly as in source. **Preserved byte-identical post-migration** (Constitution §7).
- **Library swaps** — exact replacements with verified versions from `findings.md`
- **Platform APIs** — every Android-only/JVM-only API with `file:line` and verified replacement
- **expect/actual** — each declaration with one-line justification per platform-boundary §2
- **Refactor entries** — only when `Path: refactor`. Copy R-N entries from `architecture.md` verbatim with all six fields. **Orphan refactors are rejected as `BLOCKER`.**
- **Migrate after** — DAG predecessors
- **Consumers** — files outside the in-scope list whose imports must update
- **Expected tests** — minimum count + explicit list (1+ per public method, plus error paths, plus edge cases, **plus one per refactor's behaviour-preservation invariant**)
- **Rules** — file-specific constraints overriding defaults
- **Checkpoint** — checkpoint name from `architecture.md`

Every entry cites `file:line`. "TBD", "if needed", "minor changes" are rejected.

### 5b. Compute the diff specification per file

For every in-scope file, walk master line-by-line and produce the **Diff specification** field. This is the migrator's contract — every line in the migrated output is either a verbatim line from master or an explicit Remove / Add / Modify / Refactor entry with citation.

For each file:
1. `git show <baseline-master-sha>:<source-path>`.
2. For each line, classify:
   - **Unchanged** (default): `Lines X–Y: unchanged`.
   - **Remove**: cite which swap removes it.
   - **Add**: cite which swap adds it.
   - **Modify**: write master form and migrated form verbatim; cite the swap; note what's preserved (variable name, signature shape, line position).
   - **Refactor** (only when `Path: refactor`): show master and migrated forms verbatim; cite `architecture.md §R-N`; list the behaviour-preservation invariant from `Expected tests`.
3. Verify every Remove/Add/Modify/Refactor has a citation. Orphan edits → reject.
4. Verify every master line appears exactly once in the spec.
5. **Refactor scope guard.** Migrated form does not introduce or reference identifiers outside the file's scope. If a refactor's natural shape would touch outside the file, reject — kick back to architect-phase.

The migrator applies the spec verbatim. Variable/parameter/member names from master STAY unless the name encodes the swapped library's name as a token, OR the rename is part of an architecture-approved Refactor entry.

### 6. Write `plan.md`

Use `templates/plan.md`. Sections:
- Title and one-line context (from `spec.md`)
- Migration unit goal (verbatim from `spec.md`)
- Baseline SHA
- Declared shared and consumer targets
- Verification command set: exact `gradle` invocations `/kmm-verify` runs
- Dependency DAG diagram (text-art is fine)
- Required scaffolding interfaces
- Checkpoint plan — copy from `architecture.md`
- Open questions

### 7. Write `findings.md`

Use `templates/findings.md`. Sections:
- **Decisions made during planning** — each library/architecture decision with options, choice, rationale, source URL, date verified
- **Library versions** — every pinned version with source
- **Compatibility notes** — consumer toolchain floor (Kotlin, Gradle, AGP, Xcode)
- **Gotchas** — non-obvious project-specific issues

### 8. Self-review against the constitution

Before presenting to the user, walk the constitution check yourself. Catch missing `file:line`, missing live-source citations, orphan refactors, scope creep before the user sees the artifact. The architecture-reviewer already gated the architecture; the plan adds operational details that need the same prevention discipline applied to them.

If you find a gap, fix it. The user shouldn't be the first reviewer.

### 9. Present to user

Print **summary** — not the full file:

- Title and one-line context
- File count and breakdown by classification (`12 files: 9 migrate-pure, 2 migrate-expect-actual, 1 delete`)
- Path breakdown (`8 surgical, 3 refactor, 1 out-of-reach`)
- Refactor entry count by risk
- DAG depth
- Library swaps with verified versions (one line each)
- `expect/actual` declaration count
- Scaffolding interface count + names
- Checkpoint plan: per-checkpoint file count
- Deviations logged so far
- Path to full plan, migration-guide, findings

Single approval prompt:

> Plan ready. Approve? [y / step / discuss]

### 10. Constitution check

Touched: §1, §2, §4 + §5, §6, §7, §8, §13, platform-boundary §2.

Checklist:
- `[ ]` `architecture.md` exists and reviewer-approved
- `[ ]` Every in-scope file has a complete migration-guide entry
- `[ ]` Every entry cites `file:line` for every claim
- `[ ]` Every Refactor entry traces to an `architecture.md` R-N parent
- `[ ]` Every Refactor entry has a behaviour-preservation test
- `[ ]` Every library version live-sourced with URL
- `[ ]` Dependency DAG has no cycles
- `[ ]` Checkpoint plan recorded; every file assigned
- `[ ]` User approved

### 11. Next

Auto-advance to tasks-phase via `/kmm` chain.

## Failure modes

- **`architecture.md` missing** — refuse to run; route back to architect.
- **A file's behaviour is unclear** — stop and ask.
- **Researcher cannot find a live source** — reject the swap; escalate. Never fall back to training data.
- **DAG has a cycle** — surface to user.
- **Refactor's natural shape requires touching another file** — reject; route back to architect.
- **Required scaffolding doesn't fit one expect/actual / one new dep / no public API change** — stop, surface cost, propose deferring the file or shrinking scope.
