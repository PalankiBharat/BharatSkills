# Trivial-migration fast-path

Constitution §14. Read by the orchestrator at the end of specify-phase to decide whether to route through this recipe instead of the full pipeline.

The fast-path is **not** a relaxation of constitutional principles. Every clean-code, public-API, and deviation-logging rule still applies. The fast-path collapses *ceremony*, not protections.

## When to use (all must hold)

| Condition | Why |
|---|---|
| ≤3 in-scope files | DAG is trivial |
| 0 `expect/actual` declarations | Boundary mechanism is level-1 (multiplatform library) |
| 0 cross-file refactors | Refactors are file-internal |
| 0 HIGH-risk refactors | §7 requires explicit approval; fast-path skipping that gate would violate §7 |
| All swaps reference declared `gradle/libs.versions.toml` entries | No live-source library research needed |

If any condition fails, fall back to the full pipeline. Record the trivial-detection decision in `findings.md § Decisions`.

## What collapses

### Phases

```
specify  →  bundle  →  verify  →  pr
            ↑
            (architect + plan + tasks + implement
             generated as a single auto-bundle pass)
```

`bundle` is a routing target inside the orchestrator, not a separate phase file. It does the work of architect, plan, tasks, and implement in one pass.

### Subagents

Full pipeline: `researcher` (per library, sequential), then `architecture-reviewer` gating.

Fast-path: skip `researcher` (no library research needed by definition); dispatch `architecture-reviewer` once after the bundle write. Only `BLOCKER` and `HIGH` findings block. `MEDIUM` auto-logs as deviations with `closure: { type: "manual" }`.

### User gates

Full: scope confirm → architecture approval → plan approval → PR-open = ≥4 prompts.
Fast-path: scope confirm → combined architecture+plan approval → PR-open = 3 prompts.

### Master health sweep

Compile-only is mandatory. Full-suite runtime sweep is opt-in (default skipped). `/kmm-verify` runs scope-focused tests via `--tests <fqn>`, so pre-existing runtime failures unrelated to the migration cannot block verify on a trivial scope.

### androidMain staging

When an in-scope file's external imports resolve to a module that depends on `:shared` (verified at specify-phase), staging is infeasible — the moved file cannot resolve its dependency. T-1, T-LOCK, and M-1 collapse into a single atomic operation that goes directly app→commonMain with the swap and refactor applied. Tests written against the post-migration shape; behaviour-preservation by visual diff inspection (R-1 mechanical-extract bodies are byte-identical) plus the post-migration exhaustive test.

When dependencies are platform-portable (e.g., file imports only from `:shared` itself), full-pipeline staging applies even on the fast-path.

## What does NOT collapse

- **All audit-trail documents written**: `spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `tasks.md`, `findings.md`, `migration-report.md`. Generated in one pass; forensic record identical.
- **Public API preservation.** Refactors that would change the public surface are still rejected.
- **Reviewer subagents.** `architecture-reviewer` runs.
- **Deviation logging.** Off-spec changes still logged. Fast-path itself is recorded as `RATIFIED` deviation on first invocation per scope.
- **Constitution principles.** Every principle still applies. Fast-path is routing, not override.

## Routing logic

```
if specify_phase_completed_and_no_fast_path_decision_recorded:
    decide = evaluate_trivial_heuristic(spec.md, in-scope-files)
    if decide.trivial:
        record_decision_in_findings(decide)
        route_to: bundle
    else:
        route_to: architect (full pipeline)
```

Once recorded, subsequent `/kmm` invocations honour it. CLI overrides: `/kmm --full-pipeline` (force full), `/kmm --fast-path` (force fast-path; user accepts that any structural surprise is logged as deviation).

## Bundle phase steps

1. **Read** every in-scope file end-to-end with the clean-code lens.
2. **Decide** per-file path (`surgical` / `refactor` / `out-of-reach`); write `architecture.md` with per-file entries, refactor entries (LOW-risk only), boundary decisions, single-checkpoint plan.
3. **Operationalise** into `migration-guide.md`: per-file diff specs covering every line of master, swap citations, expected-tests lists. Compute DAG. Write `findings.md` with library version pins (citations from `libs.versions.toml`) and verification command names.
4. **Generate** `tasks.md` with collapsed atomic-migrate task structure (when staging is bypassed) or standard T-1/T-LOCK/M-1 (otherwise).
5. **Write** `plan.md` summary and verification command set.
6. **Dispatch** `architecture-reviewer`. Surface only BLOCKER + HIGH findings. MEDIUM auto-logs as `D-N` with `closure: { type: "manual" }`.
7. **Pause** for combined architecture+plan approval (one user prompt, both summaries).
8. **Execute**: write the migrated file, write `commonTest` files per `Expected tests`, run per-target compile + scope-focused tests + consumer compile, lock baseline (commit + record SHA in `spec.md`).
9. **Auto-advance** to verify-phase.

If any step uncovers a surprise that violates the trivial heuristic (unexpected `expect/actual`, cross-file refactor required, no live-sourced version), the bundle aborts and falls back to the full pipeline starting from architect-phase. Fall-back is logged as `RATIFIED` deviation.

## When to fall back mid-flight

- Scope file's behaviour is genuinely unclear from source (Constitution §2).
- Library swap candidate has no live-sourced version (would require researcher dispatch).
- `expect/actual` requirement surfaces (invalidates level-1 assumption).
- Refactor's natural boundary crosses files (Constitution §6).
- `architecture-reviewer` returns BLOCKER or HIGH findings requiring user input.

Fall-back logged as `D-N: Fast-path aborted at <step>; falling back to full pipeline. Reason: <one line>` with `closure: { type: "manual" }`.

## Failure modes

- **Heuristic mis-classifies a non-trivial scope** — the architecture-reviewer catches it (BLOCKER triggers fall-back). Completeness-verifier at verify-phase is the safety net (constitutional violations still BLOCKER).
- **User insists on `--fast-path` for non-qualifying scope** — honour the override but log RATIFIED deviation noting which conditions failed. Reviewer still runs; constitutional violations still block.
