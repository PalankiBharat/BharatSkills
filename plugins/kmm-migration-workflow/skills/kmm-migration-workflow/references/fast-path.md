# Trivial-migration fast-path

Read by the `/kmm` orchestrator at the end of specify-phase. Constitution §14 (Proportionality) mandates that trivial migrations route through this recipe instead of the full architect→plan→tasks→implement pipeline.

The fast-path is **not** a relaxation of constitutional principles. Every clean-code-first rule, public-API preservation rule, and deviation-logging rule still applies. The fast-path collapses the *ceremony* — fewer phases, fewer subagent dispatches, fewer user gates, fewer gradle invocations — while preserving the structural protections that make migrations trustworthy.

## When to use this recipe

The fast-path triggers when **all** of these hold at the end of specify-phase:

| Condition | Why it matters |
|---|---|
| ≤3 in-scope files | The DAG is trivial; planning ceremony adds little signal |
| 0 `expect/actual` declarations needed | Boundary mechanism is level-1 (multiplatform library); no platform-bound design decisions |
| 0 cross-file refactors | Refactor entries (if any) are file-internal — architecture-reviewer's cross-file checks become no-ops |
| 0 HIGH-risk refactors | Per Constitution §7, HIGH-risk refactors require explicit user approval; fast-path skipping that gate would violate §7 |
| All library swaps reference `gradle/libs.versions.toml` declarations | No live-source library research is needed; researcher subagent's role collapses to a citation lookup |

If **any** condition fails, fall back to the full pipeline. The orchestrator must record the trivial-detection decision in `findings.md § Decisions` so it's auditable.

## What collapses

### Phases

The full pipeline runs seven phases (specify → architect → plan → tasks → implement → verify → pr). The fast-path keeps three:

```
specify  →  bundle  →  verify  →  pr
            ↑
            (architect + plan + tasks + implement
             generated as a single auto-bundle pass,
             then atomic-migrate executed inline)
```

`bundle` is not a new phase file — it's a routing target inside the orchestrator. It does the work of architect, plan, tasks, and implement in one pass, emitting all four phase docs at once.

### Subagent dispatches

Full pipeline: `researcher` (per library, sequential), then `architecture-reviewer`, then `plan-analyzer`, each gating their phase.

Fast-path: skip `researcher` (no library research needed by definition); dispatch `architecture-reviewer` and `plan-analyzer` **in parallel** after the bundle write; only `BLOCKER` and `HIGH` findings block. `MEDIUM` findings auto-log as deviations with `closure: { type: "manual" }` without a re-edit cycle.

### User gates

Full pipeline (typical): scope confirm → architecture approval → plan approval → PR-open confirmation = ≥4 prompts.

Fast-path: scope confirm → combined architecture+plan approval (one prompt with both summaries) → PR-open confirmation = 3 prompts.

### Master health sweep

Full pipeline at specify-phase: per-target compile + full unit test runtime sweep.

Fast-path: per-target compile only (mandatory). Runtime sweep is opt-in and explicitly NOT recommended for ≤3-file scopes — pre-existing runtime failures unrelated to the migration cannot block `/kmm-verify` because verify runs scope-focused tests (`--tests <fqn>`), not the full suite. Time saved: typically 5–10 min per migration.

### androidMain staging

Full pipeline: T-1 stages files into `shared/src/androidMain/...` so commonTest baselines run against the staged form pre-swap.

Fast-path: when an in-scope file's external imports resolve to a module that depends on `:shared` (verified in specify-phase step 1.5), staging-in-androidMain is structurally infeasible — the moved file cannot resolve its dependency. T-1, T-LOCK, and M-1 collapse into a single atomic operation that goes directly app→commonMain with the swap and refactor applied. Tests are written against the post-migration shape; behaviour preservation is established by visual diff inspection (R-1 mechanical-extract bodies are byte-identical) plus the post-migration exhaustive test.

When dependencies are platform-portable (no `:app` direction; e.g., the file imports only from `:shared` itself or from third-party libs already in commonMain), full-pipeline staging still applies even on the fast-path.

## What does NOT collapse

These are non-negotiable on the fast-path:

- **All audit-trail documents are still written.** `spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md`, `migration-report.md` all exist with the same structure. They're generated in one orchestrator pass, but the forensic record is identical to the full pipeline. Reading the docs alone (without conversation history) must still recover full context.
- **Public API preservation.** Every method name, parameter name, parameter order, parameter type, return type, and visibility byte-identical to source. Refactor entries that would change the public surface are still rejected.
- **Reviewer subagents.** `architecture-reviewer` and `plan-analyzer` still run. They run in parallel and have a higher block threshold (HIGH vs. MEDIUM), but BLOCKER and HIGH findings still gate.
- **Deviation logging.** Every off-spec change is still logged in `migration-report.md` with structured closure type. The fast-path itself is recorded as a `RATIFIED` deviation entry on first invocation per scope so the audit trail explains why the pipeline collapsed.
- **Constitution principles.** Every principle from §1 to §14 still applies. Fast-path is a routing decision, not a principle override.

## Routing logic

The `/kmm` orchestrator's state-detection (`commands/kmm.md`) gains an additional check after specify-phase completes. Pseudocode:

```
if specify_phase_completed_and_no_fast_path_decision_recorded:
    decide = evaluate_trivial_heuristic(spec.md, in-scope-files)
    if decide.trivial:
        record_decision_in_findings(decide)
        route_to: bundle  (architect + plan + tasks + implement in one pass)
    else:
        route_to: architect  (full pipeline)
```

Once the decision is recorded, subsequent `/kmm` invocations honour it without re-evaluating. A user can override via `/kmm --full-pipeline` (forces the full pipeline regardless of heuristic) or `/kmm --fast-path` (forces the fast-path regardless; user accepts that bypass conditions may not hold and any structural surprise is logged as a deviation).

## Bundle phase — what it does

The bundle phase runs the work of architect, plan, tasks, and implement in one orchestrator pass:

1. **Read** every in-scope file end-to-end with the clean-code lens (architect's job).
2. **Decide** per-file path (`surgical` / `refactor` / `out-of-reach`) and write `architecture.md` with all per-file entries, refactor entries (LOW-risk only — HIGH-risk would have failed the heuristic), boundary-mechanism decisions, and the single-checkpoint plan.
3. **Operationalise** the architecture into `migration-guide.md`: per-file diff specifications covering every line of master, library swap citations, expected-tests lists. Compute the dependency DAG (trivial: usually one level). Write `findings.md` with library version pins (citations from `libs.versions.toml`) and verification command names (live-sourced via `:tasks --all`).
4. **Generate** `tasks.md` with the collapsed atomic-migrate task structure (CP-1/atomic instead of CP-1/T-1 + CP-1/T-LOCK + CP-1/M-1) when androidMain staging is bypassed; otherwise the standard T-1/T-LOCK/M-1 structure.
5. **Write** `plan.md` as the high-level summary, including the verification command set.
6. **Dispatch** `architecture-reviewer` and `plan-analyzer` in parallel. Wait for both. Surface only BLOCKER + HIGH findings to the user. MEDIUM findings auto-log as `D-N` entries with `closure: { type: "manual" }`.
7. **Pause** for the combined architecture+plan approval gate (one user prompt presenting both summaries side-by-side).
8. **Execute** the migration: write the migrated file (with swap + refactor), write the commonTest files per `migration-guide.md § Expected tests`, run the per-target compile sweep + scope-focused tests + consumer compile, lock baseline (commit + record SHA in `spec.md`).
9. **Auto-advance** to verify-phase.

If any step uncovers a surprise that violates the trivial heuristic (e.g., an unexpected `expect/actual` requirement surfaces during step 2), the bundle aborts and falls back to the full pipeline starting from architect-phase, preserving all artifacts written so far. The fall-back is logged as a `RATIFIED` deviation in `migration-report.md`.

## Estimated time savings

Based on the GreetingUseCase migration (sniper-v2-android consumer-repo PR #369):

| Activity | Full pipeline | Fast-path | Saved |
|---|---|---|---|
| Master full-suite test sweep | ~5–10 min | 0 (compile-only default) | 5–10 min |
| androidMain staging + revert + atomic-migrate redesign | ~10 min | 0 (atomic from start) | ~10 min |
| Architecture-reviewer + plan-analyzer (sequential) | ~6 min | ~3 min (parallel) | ~3 min |
| Plan approval round trip (user prompt + nit-fixing edits) | ~5 min | 0 (combined with architecture approval) | ~5 min |
| `.broken` rename ceremony + revert | ~5 min | 0 (sentinel commit auto-reverted at pr-phase; see specify-phase D step) | ~5 min |
| **Total wall-clock saved** | | | **~28–33 min** |

Token cost is also reduced (fewer subagent dispatches; fewer user round-trips; less document churn), though this is harder to measure precisely.

## When to fall back from the fast-path mid-flight

The fast-path is permissive at entry but strict during execution. Any of these conditions, surfaced after entering the bundle phase, falls back to the full pipeline starting from architect-phase:

- A scope file's behaviour is genuinely unclear from the source (Constitution §2 — never guess from the call site)
- A library swap candidate has no live-sourced version available (would require `researcher` dispatch)
- An `expect/actual` requirement surfaces (invalidates the level-1 boundary assumption)
- A refactor's natural boundary crosses files (Constitution §6)
- `architecture-reviewer` or `plan-analyzer` returns BLOCKER or HIGH findings that require user input

Fall-back is logged as `D-N: Fast-path aborted at <step>; falling back to full pipeline. Reason: <one line>` in `migration-report.md` with `closure: { type: "manual" }`. The fall-back is not a failure; it's the structural protection that makes the fast-path safe to take.

## Failure modes

- **Heuristic mis-classifies a non-trivial scope as trivial** — the architecture-reviewer or plan-analyzer should catch it (BLOCKER findings trigger fall-back). If both reviewers miss it, completeness-verifier at verify-phase catches it (constitutional violations are still BLOCKER per its existing checks).
- **User insists on fast-path for a scope that doesn't qualify** — `/kmm --fast-path` honours the user's explicit override but logs a `RATIFIED` deviation noting which heuristic conditions failed. The reviewers still run; constitutional violations still block.
- **Audit trail is thinner than full pipeline** — false. The fast-path emits the same documents; the difference is generation cadence, not content. If the docs are thinner, that's a bug in the bundle phase, not a feature of the fast-path.

## See also

- `constitution.md` §14 (Proportionality)
- `references/phases/specify.md` — trivial-detection step at end of phase
- `commands/kmm.md` — orchestrator routing
- `references/phases/architect.md` — full-pipeline architect; bundle phase reuses its decision logic but emits as part of the bundle
- `references/phases/pr.md` — `.broken` sentinel auto-revert (see commit 5 in this PR)
