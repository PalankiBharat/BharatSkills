# Migration Ordering — Libraries First, Logic Second, UI Third

> JetBrains' canonical migration sequence is opinionated. Inside that sequence,
> module work proceeds leaf-first. This file encodes both rules. The orchestrator
> consults it during Phase 2 planning AND Phase 3 batching. The plan_critic
> rejects any plan that violates the ordering without a documented user-approved
> deviation.
>
> Canonical source:
> https://kotlinlang.org/docs/multiplatform/migrate-from-android.html
>
> Worked example: https://github.com/kotlin-hands-on/jetcaster-kmp-migration

## Contents

- [The three-step migration sequence](#the-three-step-migration-sequence)
- [Leaf-first module ordering within each step](#leaf-first-module-ordering-within-each-step)
- [Scope-aware ordering](#scope-aware-ordering)
- [When the codebase suggests a different order](#when-the-codebase-suggests-a-different-order)
- [How the orchestrator uses this file](#how-the-orchestrator-uses-this-file)

## The three-step migration sequence

JetBrains, verbatim from migrate-from-android.html:

> 1. Migrate to multiplatform libraries
> 2. Transition your business logic to KMP
> 3. Transition your UI code to Compose Multiplatform

This is not a suggestion. The order is structural — each step removes a class
of obstacles the next step would otherwise hit:

- **Step 1 — Libraries first.** Replace each JVM-only library with its current
  canonical KMP-capable equivalent. The researcher resolves which libraries
  to swap and which replacements to use live each invocation from
  kotlinlang.org per Law 13 — this file does NOT pin specific FROM → TO
  pairs because they're version-bound. The migrated app stays on Android-only
  during this step; every swap is a same-platform change validated against
  the existing Android baseline. Reason: you cannot move logic into
  `commonMain` while it imports a JVM-only DI framework or reactive library;
  the swap has to happen first.

- **Step 2 — Business logic second.** Move repositories, use-cases, domain
  models, view-models (the parts not bound to Compose `@Composable` decoration)
  into `commonMain`. UI stays on Android. Reason: ViewModel-shaped state holders
  consume the shared logic; UI consumes the ViewModel; if UI moved first, it
  would re-bind to Android-only logic and the UI move would have to redo every
  binding.

- **Step 3 — UI third.** Move composables to `commonMain` using Compose
  Multiplatform. Resources move WITH the composable per Precondition R in
  `references/migration_preconditions.md`. Reason: at this point the logic
  layer is already shared; the UI move is the smallest possible diff.

Ports that bypass this order — moving UI before logic, moving logic while a
JVM-only library is still imported — are Law 15 violations. They produce code
that compiles but contains hidden Android dependencies that surface as build
breaks the next time someone touches the file.

## Leaf-first module ordering within each step

Within each of the three steps, modules migrate leaf-first. JetBrains, verbatim:

> Start with a module that has the fewest other modules depending on it. ...
> Pick the next module in the dependency tree and repeat the process.

The Jetcaster sample's order is the canonical worked example
(github.com/kotlin-hands-on/jetcaster-kmp-migration):

```
Step 1 (libraries):     swap deps app-wide first (one batch)
Step 2 (business logic): :core:data → :core:data-testing
                       → :core:domain → :core:domain-testing
                       → :core:designsystem
Step 3 (UI / screens):   PodcastDetails screen → Home screen → Player screen
```

Read this as: "data is a leaf — no other module depends on it being moved
first; data-testing depends on data; domain depends on data; etc." Within
the screens batch, leaf-first means migrate the screen with the simplest
dependency graph first (the one with the fewest ViewModels / repositories /
shared composables it pulls in).

**The orchestrator's batching rule (Phase 3):**

1. Compute the dependency graph for the in-scope file/module list.
2. Identify the leaf set — items with zero dependents inside scope.
3. Dispatch the leaf set as Batch 1.
4. Once Batch 1 commits, recompute the leaf set against the remaining files.
5. Dispatch the new leaf set as Batch 2. Repeat.

**Forbidden:** picking files alphabetically, by directory, by author, or by
"easiest first" if "easiest" is not actually the leaf. Law 15 — short-term
shortcuts cost more later.

## Scope-aware ordering

User-chosen scope (`scope_type` in `state.json`) constrains which steps and
modules are in play:

| `scope_type` | Steps in scope | Module ordering |
|---|---|---|
| `feature` | All three steps for the feature's modules | Full leaf-first across the feature's modules |
| `module` | Step matches module's role (data → Step 2; UI → Step 3) | Leaf-first across files inside the module |
| `screen` | Step 3 only (UI), with Step 2 deps verified per Precondition D/P | Leaf-first across composables inside the screen tree |
| `file` | Step matches file's role | Single-file batch — file's own deps verified per preconditions |

If the user's chosen scope is a single screen but Precondition R (resources)
or Precondition D (deps) requires touching upstream modules, the orchestrator
raises `REQUIRES_APPROVAL` to ask whether to expand scope or defer. The skill
NEVER expands scope silently — Law 03.

## When the codebase suggests a different order

Sometimes the canonical order doesn't fit the codebase as-is — e.g., a
business-logic module already imports a Compose `@Composable` for inline
preview support, so Step 2 cannot proceed without first untangling that.

The migration_planner reads the actual files in scope (Law 12 — codebase-first)
and produces a plan that names every such snag with `file:line` evidence. If
the canonical order cannot be honoured cleanly, the plan documents:

- The specific files that block the canonical order.
- The minimum refactor required to honour it (move the inline composable into
  Step 3 territory, etc.).
- The user-visible deviation and its cost.
- The proposed alternative order, with rationale.

The plan is presented at Gate 2 with the deviation flagged. The user picks:
honour canonical (do the refactor), accept deviation (logged in
`accepted_deltas`), or abandon. The skill never picks for them.

## How the orchestrator uses this file

- **Phase 2a (researcher):** reads this file as part of its scope-mapping pass.
  The researcher's `tech_stack_snapshot.md` includes a derived "ordering
  feasibility" section noting any obstacles to canonical order.
- **Phase 2b (planner):** reads this file. The plan's table of contents lists
  files in the order they will be ported, grouped by step (1 → 2 → 3) and
  ordered leaf-first within each step. The planner also reads every in-scope
  file's actual contents from disk before drafting prescriptions (Law 12).
- **Phase 2c (plan_critic):** runs the rule check. Any plan that lists Step-3
  work before Step-2 work, or non-leaf modules before leaves within a step,
  is `ISSUES_FOUND` with a specific re-ordering suggestion.
- **Phase 3 (orchestrator batching):** computes batches per the leaf-first
  rule above, never by file count or directory.
- **Final review (16_kmm_focused_final_reviewer):** verifies the commit
  history honours the ordering — commits land step-1-then-2-then-3, with
  leaf-first within each. Out-of-order commits without a documented deviation
  are `ISSUES_FOUND`.

## Citation

Cite as: `(source: kotlinlang.org/docs/multiplatform/migrate-from-android.html,
fetched <YYYY-MM-DD>; worked example: github.com/kotlin-hands-on/jetcaster-kmp-migration)`
