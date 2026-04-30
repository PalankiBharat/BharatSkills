---
name: kmm-migration
description: >-
  Use when the user is migrating Android code to Kotlin Multiplatform —
  extracting business logic to commonMain, sharing code with iOS, or
  converting Android-only implementations into KMP-compatible ones. The
  user picks the scope (whole feature, single module, single screen,
  single file) at bootstrap; the skill suggests a default based on
  codebase dependency analysis but never forces. Follows JetBrains'
  canonical migration workflow (libs first → business logic → UI, leaf-first
  modules within each step) sourced live from kotlinlang.org per
  invocation. Enforces per-file preconditions (resources moved before
  screen ports, JVM-only APIs replaced before logic ports, disqualified
  deps swapped before code moves) so the canonical KMP approach beats
  short-term shortcuts. Not an encyclopedia — an orchestrator that drives
  all labour through subagents with conditional dispatch injection.
  Triggers: "migrate to KMM", "share with iOS", "move to commonMain",
  "port Android code to Kotlin Multiplatform", "extract shared module",
  "KMP migration", "KMM migration".
when_to_use: >-
  Active Android → Kotlin Multiplatform migration work at any user-chosen
  scope (feature / module / screen / file). Not for greenfield KMP
  scaffolding. Not for KMP-version bumps.
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Bash(git *)
  - Bash(./gradlew *)
  - Bash(xcodebuild *)
  - Bash(gh *)
  - Bash(maestro *)
  - WebSearch
  - mcp__context7__*
paths:
  - "**/build.gradle.kts"
  - "**/settings.gradle.kts"
  - "**/*.kt"
  - "**/*.kts"
argument-hint: "<feature-name> [--from-branch <branch>]"
---

# kmm-migration Skill

> Orchestrator for Android → Kotlin Multiplatform migrations at user-chosen
> scope (feature / module / screen / file). Canonical-KMP-first, baseline-first,
> 1:1-port, subagent-driven, hard quality gates.
> See `skills/kmm-migration/migration_laws.md` for the 15 iron laws YOU MUST
> follow — Law 15 (canonical KMP approach over short-term expedience) is the
> soul of the skill.

## Contents

- [Orchestration flow](#orchestration-flow)
- [Required reading](#required-reading-for-the-orchestrator-on-invocation)
- [Phase 0 — Bootstrap](#phase-0--bootstrap)
- [Phase 1 — Baseline](#phase-1--baseline)
- [Phase 2 — Plan](#phase-2--plan)
- [Phase 3 — Migrate](#phase-3--migrate)
- [Phase 4 — Verify Android parity](#phase-4--verify-android-parity)
- [Phase 5 — iOS target (optional)](#phase-5--ios-target-optional)
- [Phase 6 — Closeout](#phase-6--closeout)
- [Phase boundaries — clear recommendations](#phase-boundaries--clear-recommendations)
- [User gates](#user-gates)
- [Pre-gate investigation](#pre-gate-investigation)
- [Conditional dispatch injection](#conditional-dispatch-injection)
- [Foundational dispatch bundles](#foundational-dispatch-bundles)
- [Resume flow](#resume-flow)
- [Named escape hatches](#named-escape-hatches)
- [Self-contained — no external skill dependencies](#self-contained--no-external-skill-dependencies)

## Orchestration flow

kmm-migration is an orchestrator skill. The main Claude context (Opus) never
edits code, never reads source files, and never runs build commands. All labour
flows through subagents — Sonnet for heavy work (planning, migrating,
porting), Haiku for deterministic checks (gate validation, diff auditing,
parity verification, sanity-grep tripwires). Six phases, five user gates, one
worktree per migration. Every phase transition requires concrete, verifiable
artifacts — no silent advancement. The 15 iron laws in
`skills/kmm-migration/migration_laws.md` are the absolute authority — Law 15
(canonical KMP approach over short-term expedience) is the soul of the skill.

**User-chosen scope.** The user picks the migration scope at Phase 0 — whole
feature, single module, single screen, or single file. The skill suggests a
default based on a codebase dependency-analysis pass and shows the user the
options, but the user picks (Law 03). The chosen `scope_type` and
`scope_targets` are recorded in `state.json` and honoured by every subagent.

**Self-audit replaces 2-stage review.** Code-producing subagents (`10_migrator`,
`14_ios_porter`) run a comprehensive self-audit checklist
(`references/migrator_self_audit_checklist.md`) BEFORE emitting `STATUS: DONE`,
in the same dispatch. The orchestrator then runs a deterministic diff-grep
tripwire (`references/orchestrator_diff_grep.md`, no LLM call) to catch
dishonest checklists. Phase 6 keeps a holistic cross-batch reviewer
(`16_kmm_focused_final_reviewer`) that the per-batch self-audit cannot replace.

**Conditional dispatch injection.** Each dispatch's `must_read` is computed by
the orchestrator at dispatch time — not pre-baked into a static bundle.
Routing depends on subagent role × phase × in-scope file classification
(Compose UI / business logic / test / build-config / iOS port). A migrator
working a screen file gets the Compose + resources + JVM-scrub references
but NOT the Cocoapods integration docs; a baseline-test-author gets only the
baseline capture protocol and status contract. See [Conditional dispatch
injection](#conditional-dispatch-injection).

**Knowledge stays in the docs.** This skill ships behaviours, ordering rules,
and pointers — NOT specific library names, version numbers, or FROM → TO
tables. Anything version-bound is researcher-resolved from kotlinlang.org per
invocation per Law 13 + Law 15. The skill does not go stale because the
knowledge isn't pinned in the skill.

## Required reading for the orchestrator on invocation

YOU MUST read these files BEFORE taking any action on an invocation:

- `skills/kmm-migration/migration_laws.md`  (15 laws, Law 15 is foundational)
- `skills/kmm-migration/references/knowledge_lookup_protocol.md`  (kotlinlang.org first)
- `skills/kmm-migration/references/migration_ordering.md`  (libs→logic→UI, leaf-first)
- `skills/kmm-migration/references/migration_preconditions.md`  (per-file gates the migrator runs)
- `skills/kmm-migration/references/migrator_self_audit_checklist.md`  (replaces 2-stage review)
- `skills/kmm-migration/references/orchestrator_diff_grep.md`  (post-dispatch tripwire)
- `skills/kmm-migration/references/kmp_invariants.md`  (structural rules only — no version-bound)
- `skills/kmm-migration/references/worktree_conventions.md`
- `skills/kmm-migration/references/subagent_status_contract.md`
- `skills/kmm-migration/formats/requires_approval.md`
- `skills/kmm-migration/schemas/state_schema.md`
- `kmm_migration/state.json` (at the target repo root — if exists)
- `kmm_migration/findings.md` (at the target repo root — if exists; cross-feature decisions live here)

## Phase 0 — Bootstrap

Read `kmm_migration/state.json`.

**No state — fresh migration.** Ask the user ONE question at a time, in this
order:

1. **What do you want to migrate?** Free-form (e.g., "the login feature",
   "the Profile screen", "the UserRepository file", "the :core:data module").
2. **Base branch?** (default: master / main — confirm with the user).
3. **What's the goal?** (e.g., "share with iOS", "extract logic for testing",
   "incremental KMP adoption").

Then dispatch `01_codebase_scope_analyzer` (Sonnet) — reads the codebase to
classify what the user named, computes the dependency graph, and produces
a scope-options report at `reports/<feature>/00_scope_options.md`. Options
shape (the analyzer fills in the actual numbers from the codebase):

- **Whole feature** — everything the user-named entry-point transitively
  depends on, with file count, module count, screen count.
- **Single module** — one Gradle module (named).
- **Single screen** — one composable / activity / fragment + its
  tightly-coupled deps and resources.
- **Single file** — one specific `.kt` file + only its directly-imported
  deps and resources.

Show options with the analyzer's recommended default and rationale. Raise
`REQUIRES_APPROVAL` — user picks. Record in `state.json`:

```json
{
  "scope_type": "feature" | "module" | "screen" | "file",
  "scope_targets": ["<path-or-identifier>", ...],
  "scope_recommended_default": "...",
  "scope_user_chose": "..."
}
```

Then dispatch `00_worktree_initializer` (Haiku) per
`references/worktree_setup_protocol.md`. Worktree at
`.worktrees/kmm-migrate-<scope-name>/` on branch `kmm-migrate/<scope-name>`.

**Existing state with `status != complete`** — dispatch `state_inspector`
(Haiku) to validate worktree existence, branch, scope-recorded fields, and
cleanliness. Present a `REQUIRES_APPROVAL`: resume, inspect, or abandon.

Also read `kmm_migration/findings.md` — cross-feature decisions (named
library swaps, AGP-9 plugin verdict, iOS integration mechanism, etc.)
apply.

## Phase 1 — Baseline

Scope-aware: every step below operates ONLY against `state.scope_targets`.

1. `01_feature_inventory_scanner` (Sonnet) — enumerates in-scope files,
   dependencies, Android APIs → `reports/<feature>/01_inventory.md`. Note:
   the codebase analyzer in Phase 0 produced a scope graph; this step is a
   deeper inventory of the chosen scope.
2. `06_researcher` in baseline-tooling-pre-pass mode — which unit /
   screenshot / E2E tool stack applies for the in-scope code? Output →
   `tech_stack_snapshot.md`.
3. Three parallel tracks (each Sonnet, migration worktree):
   - `02_baseline_unit_author` — characterization tests on OG code, ≤5 source
     files per batch, all green.
   - `03_baseline_screenshot_recorder` — goldens from OG UI with per-platform
     tolerance envelope, ≤5 screens per batch.
   - `04_baseline_e2e_author` — E2E flows green vs OG APK, retry policy
     recorded.
4. Each of 02 / 03 / 04 runs the migrator self-audit checklist
   (`references/migrator_self_audit_checklist.md`, baseline-author variant
   — Sections 4 and 6 only since Sections 1-3 don't apply to baseline-capture)
   before emitting `STATUS: DONE`.
5. `05_baseline_gate_validator` (Haiku) — all three suites green and
   committed; tolerance envelopes captured; `tech_stack_snapshot.md` recorded.

**Gate 1** — `REQUIRES_APPROVAL` → user freezes baseline.

## Phase 2 — Plan

**Phase 2a — Research (kotlinlang.org first).** `06_researcher` (Sonnet,
read-only, full mode). Source priority: kotlinlang.org canonical docs
(Priority 0 per Law 15) → context7 → WebSearch → find-docs. Writes
`reports/<feature>/research_notes.md` with every non-obvious migration
question answered via a cited live source. Specifically resolves and
records:

- Current iOS target tier list and which targets are deprecated in this
  Kotlin version.
- Current Compose Multiplatform version + breaking changes affecting the
  in-scope files.
- Current FROM → TO mapping for every disqualified-dep concern detected
  in the in-scope files (Precondition D resolution).
- Current named-canonical replacement for every JVM-only construct
  detected (Precondition A resolution).
- iOS integration mechanism — Podfile-detected default (CocoaPods) vs
  no-Podfile default (Direct), with stability tiers from the current docs.
- AGP version — if ≥ 9.0, the plugin id migration plan; if < 9.0, no-op.

The output also populates `accepted_deltas` for any case where the
canonical approach can't be honoured cleanly and the user will be asked
at Gate 2.

**Phase 2b — Plan (codebase-first, zero ambiguity).** `07_migration_planner`
(Sonnet, read-only). Per Law 12 planning corollary: the planner MUST read
every file in `plan.files_to_touch` from the actual codebase BEFORE drafting
prescriptions. Every prescription names a specific `file:line` change.

The plan organises file-level prescriptions per the
`references/migration_ordering.md` rule — Step 1 (libs), Step 2 (logic),
Step 3 (UI), leaf-first within each. Generic prescriptions ("use a
multiplatform networking library", "the migrator will figure out the
abstraction at port time"), TBD markers, "implement later" comments, and
hedging language are forbidden.

**Phase 2c — Plan critique:** `08_plan_critic` (Sonnet, single dispatch
that combines spec-compliance audit + ambiguity audit + ordering audit —
no separate `09_plan_reviewer` dispatch). Checks:

- Every assertion is live-sourced (Law 13).
- Every prescription names file:line; no ambiguity (Law 12 planning
  corollary).
- Files are ordered Step 1 → 2 → 3 with leaf-first within each (Law 15
  + migration_ordering).
- Every disqualified-dep concern has a researcher-resolved FROM → TO.
- Every JVM-only construct has a researcher-resolved replacement.
- Every Compose UI file has its resources accounted for (Precondition R).
- Scope honours `state.scope_targets` exactly (Law 03).

Verdict: `STATUS: DONE` or `STATUS: ISSUES_FOUND` with the specific failed
checks. **Hard cap: 2 revision cycles.** After the second ISSUES_FOUND,
raise `REQUIRES_APPROVAL` — continuing past 2 cycles is forbidden. Gate
options: (a) accept the current plan with documented `accepted_deltas`;
(b) reduce scope; (c) abandon.

**Gate 2** — `REQUIRES_APPROVAL` → user approves plan.

## Phase 3 — Migrate

The orchestrator owns ALL git mutations in this phase. Migrators have
`Bash(git commit *)`, `Bash(git add *)`, `Bash(git push *)`, and reset/rebase
on their tool denylist (see `dispatch_templates/10_migrator.md`). Read-only
git inspection (`status`, `diff`, `log`) remains allowed.

**Batching follows the canonical ordering** — the orchestrator computes
batches per `references/migration_ordering.md`:

1. Step 1 batches first — dep-swap batches before any commonMain code moves.
2. Step 2 batches second — business logic, ordered leaf-first across in-scope
   modules.
3. Step 3 batches third — UI / composables, ordered leaf-first across screens
   inside scope. Each Step 3 batch includes the resources the screen
   references (Precondition R) — moved together, never split.

Each batch gets an explicit file list — never "the rest". The orchestrator
records the in-scope list in the dispatch prompt verbatim.

**Per-batch flow:**

1. Orchestrator computes the next batch from the leaf-first set.
2. Dispatch `10_migrator` (Sonnet, migration worktree). The dispatch prompt
   includes the file list, the migration_guide entries to satisfy, and the
   `must_read` computed by [Conditional dispatch injection](#conditional-dispatch-injection)
   based on file classification.
3. **Migrator runs preconditions BEFORE porting** per
   `references/migration_preconditions.md`. Any precondition emitting
   `PRECONDITION_BLOCKED` halts the port; orchestrator routes the
   unblocking sub-task (resource move, Java conversion, dep swap, JVM-API
   replacement, platform-type abstraction) before re-dispatching.
4. Migrator does the port AND runs the
   `references/migrator_self_audit_checklist.md` BEFORE emitting
   `STATUS: DONE`. Failed audit items → `STATUS: ISSUES_FOUND`, fix in
   the same dispatch, re-run checklist. Three failure cycles on the same
   item → escalate per three-strike protocol.
5. **Orchestrator post-dispatch tripwire.** On `STATUS: DONE`, the
   orchestrator runs `references/orchestrator_diff_grep.md` (no LLM —
   pure grep). Any pattern match → override verdict to `ISSUES_FOUND`,
   re-dispatch with the matched evidence in the prompt. Counts as one
   fix cycle for three-strike.
6. **Scope-allowlist verification.** Orchestrator runs
   `git diff --name-only` and intersects against the dispatch's in-scope
   list:
   - Out-of-scope paths (Law 3 violation) → `git checkout -- <path>`,
     log to `scope_violations.md`, re-dispatch with stricter prompt.
   - Modified baseline artifacts under `**/snapshots/`, `**/screenshots/`,
     `**/goldens/`, `kmm_migration/baseline/<feature>/` (Law 2 event) →
     `REQUIRES_APPROVAL` via `escape_hatch_rebase_baseline`.
7. PASS → orchestrator stages the in-scope diff and commits with a
   message naming the batch (Step 1/2/3, leaf position) and the
   migration_guide entries satisfied.
8. Three distinct failed approaches on the same batch → migrator writes
   `reports/<feature>/strikes/<ts>_migrator.md` + emits `STATUS: BLOCKED`.
   Orchestrator dispatches `debug_investigator`.

**Reviewer escape hatch.** The legacy `spec_compliance_reviewer` and
`code_quality_reviewer` dispatch templates remain in `dispatch_templates/`
as escape hatches. The orchestrator invokes them ONLY when the user
disputes a self-audit verdict via `REQUIRES_APPROVAL` ("the migrator's
checklist passed but I see X — please run an independent review").
Default flow does NOT invoke them.

## Phase 4 — Verify Android parity

1. `11_plan_diff_auditor` (Haiku) — end-of-phase scope check: git diff ∩ plan.
   Safety net for any batch-level Sonnet reviewer hallucinations.
2. `12_parity_verifier` (Haiku) — runs all three baseline suites against
   migrated code, respecting `accepted_deltas`; captures runner output. Then
   performs a runtime smoke launch (`adb install` + `am start` + logcat scan
   for `FATAL EXCEPTION`) against the migrated APK. Compile-only and
   unit/golden/E2E suites do not exercise the runtime DI graph; the smoke
   launch is what catches Hilt / Koin / source-set wiring crashes that
   otherwise escape every gate.
3. `13_parity_gate_validator` (Haiku) — all three suites GREEN within
   tolerance, smoke launch produced no FATAL EXCEPTION, accepted_deltas
   honoured?

Any red beyond tolerance OR any runtime crash within 8s of launch →
`REQUIRES_APPROVAL`: re-migrate or abandon. Never silently update the
baseline (Law 2 — no exceptions).

**Gate 3** — `REQUIRES_APPROVAL` → iOS now, or defer?

## Phase 5 — iOS target (optional)

1. `14_ios_porter` (Sonnet, migration worktree) — `iosMain` actuals + Swift /
   SwiftUI / UIKit interop wrapper per researcher's recommendation + iOS
   goldens + iOS E2E runs. iOS integration mechanism follows the tiered default
   from `references/platform_interop_patterns.md` (Podfile present →
   CocoaPods; otherwise Direct integration; SPM/Swift export require user
   opt-in).
2. Migrator runs `references/migrator_self_audit_checklist.md` (full)
   before emitting `STATUS: DONE`. No separate reviewer dispatches.
3. Orchestrator runs `references/orchestrator_diff_grep.md` tripwire on
   the diff.
4. `12_parity_verifier` — iOS suites only.

**Gate 4** — `REQUIRES_APPROVAL` → iOS parity confirmed.

## Phase 6 — Closeout

Gate 5 is REFUSED unless all five steps below emit `STATUS: DONE` and step 1
is GREEN. Reverification failure → `REQUIRES_APPROVAL` (re-migrate or invoke
`escape_hatch_rebase_baseline`, which requires its own `REQUIRES_APPROVAL`).

1. `15_final_baseline_reverifier` (Haiku) — HARD PRECONDITION: re-runs every
   baseline suite (Android + iOS if Phase 5 was pursued) against final HEAD,
   respecting tolerance envelopes and `accepted_deltas`.
2. `16_kmm_focused_final_reviewer` (Sonnet) — holistic review: consistency of
   platform-interop pattern, correct source-set placement, iOS interop
   correctness, no Android-only types in shared code, `accepted_deltas`
   respected, no Law 13 violations. Live-verifies via context7. `ISSUES_FOUND`
   routes back to the producer; max 2 fix cycles, then `REQUIRES_APPROVAL`.
3. `17_pr_body_composer` (Sonnet) — writes `kmm_migration/pr/<feature>/body.md`
   and `heatmap.md` per `pr_body_schema.md`. Every claim concrete and linked.
4. `18_pr_creator` (Haiku) — `gh pr create` via heredoc; records URL in
   `kmm_migration/pr/<feature>/pr_url.txt`. Fails loudly if `gh` auth missing.
5. `19_closeout_reporter` (Haiku) — `reports/<feature>/closeout.md`, updates
   `findings.md` with stack decisions, archives baselines.

**Gate 5** — `REQUIRES_APPROVAL` → user approves the PR for merge. The skill
does not merge — merge is always user-driven.

## Phase boundaries — clear recommendations

| Boundary | Suggestion | Why |
|---|---|---|
| Phase 1 → Phase 2 | `RECOMMEND_CLEAR` | Baseline done; planning is a different cognitive mode. |
| Phase 2 → Phase 3 | `RECOMMEND_CLEAR` | Plan on disk; migration benefits from clean orchestrator. |
| Phase 3 → Phase 4 | `KEEP_CONTEXT` | Parity fires immediately; fix cycles route back to Phase 3. |
| Phase 4 → Phase 5 | `RECOMMEND_CLEAR` | Android done; iOS is a distinct surface. |
| Phase 5 → Phase 6 | `KEEP_CONTEXT` | Closeout flows tightly: reverification → review → PR. |
| After Phase 6 | `RECOMMEND_CLEAR` | Feature complete; new migration starts fresh. |

These suggestions are advisory. If the user clears mid-phase, re-orient from
`state.json` + the most recent subagent report.

## User gates

Five gates. All use the `NEEDS YOUR CALL` format from
`skills/kmm-migration/formats/requires_approval.md`. Gate text is authored by
`gate_investigator` and relayed verbatim by Opus — never re-authored or
summarized by the orchestrator.

| Gate | When | Blocks until |
|---|---|---|
| 1 | End of Phase 1 | User freezes baseline |
| 2 | End of Phase 2 | User approves plan |
| 3 | End of Phase 4 | User decides: iOS now, or defer? |
| 4 | End of Phase 5 | User confirms iOS parity |
| 5 | End of Phase 6, after PR created | User approves PR for merge |

Skipping a gate is architecturally impossible — `state.json` only advances
through orchestrator-written approval artifacts.

## Pre-gate investigation

A gate is NEVER raised to the user straight from a subagent's `ISSUES_FOUND`
or `BLOCKED` report. Before any `NEEDS YOUR CALL` message reaches the user,
Opus dispatches `gate_investigator` (Sonnet) to:

1. Read the raising subagent's report in full.
2. Consult source-of-truth per Law 12 precedence (legacy code → baseline
   manifests → migration guide → live context7/WebSearch for platform claims).
3. Verify each option is actionable, sourced, and does not silently violate a
   law (Laws 5, 8, 12, 13 especially).
4. Identify any live-sourced option the raising subagent did not propose.
5. Cite the specific skill rule(s) driving the recommendation — by name.
6. Write evidence to `reports/<feature>/<gate>_investigation.md`.
7. Produce the final `NEEDS YOUR CALL` text for Opus to relay verbatim.

If `gate_investigator` cannot cite a specific skill rule, it presents option C:
"skill has no rule for this, please decide from context." Opus never injects
its own judgment.

## Conditional dispatch injection

Each dispatch's `must_read` is computed by the orchestrator at dispatch time
based on the subagent role × phase × in-scope file classification. Pinned
bundles per agent (below) are the FOUNDATIONAL items every dispatch of that
role gets. Additional references are added per the routing table.

**Always-foundational** (every dispatch reads these — no exceptions):

- `migration_laws.md`
- `references/subagent_status_contract.md`
- `references/knowledge_lookup_protocol.md`

**Forbidden-to-read for every dispatch** (avoids prompt-injection / agent
introspection): `dispatch_templates/*`.

**File-classification matrix.** The orchestrator inspects the in-scope file
list, classifies each file, and unions the resulting reference sets:

| Classification | Detected by | Inject |
|---|---|---|
| `compose-ui` | imports `androidx.compose.*` OR file in `**/ui/**` OR layout XML | `references/migration_preconditions.md`, `references/kmp_invariants.md` (Compose section), `references/migration_ordering.md`, `references/jvm_api_scrub_list.md` |
| `business-logic` | repository / use-case / view-model / domain-model / data-mapper | `references/migration_preconditions.md`, `references/kmp_invariants.md`, `references/jvm_api_scrub_list.md`, `references/platform_interop_patterns.md` |
| `test` | file in `**/test/**` OR `**/Test/**` OR `**/*Test.kt` | `references/migration_preconditions.md`, `references/kmp_invariants.md` (tests section), `references/jvm_api_scrub_list.md` (test-idiom row) |
| `build-config` | `build.gradle.kts` / `settings.gradle.kts` / `libs.versions.toml` | `references/kmp_invariants.md` (project structure), `references/migration_ordering.md` |
| `ios-port` | path under `iosMain/` | `references/platform_interop_patterns.md`, `references/kmp_invariants.md` (iOS sections), `references/migration_preconditions.md` |
| `baseline-capture` | dispatched from Phase 1 baseline tracks | `references/baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `resource-only` | XML / drawable / strings / dimens move | `references/migration_preconditions.md` (Precondition R only), `references/kmp_invariants.md` (Compose resources) |

**Phase-specific injection:**

| Phase | Injection |
|---|---|
| 0 (Bootstrap) | `references/worktree_conventions.md`, `schemas/state_schema.md` |
| 2a (Research) | `references/kmm_technology_lookup.md`, `kmm_migration/findings.md` |
| 2b (Plan) | `references/migration_ordering.md`, `references/migration_preconditions.md`, `schemas/migration_guide_schema.md`, every in-scope source file (read-only) |
| 2c (Plan critique) | `references/migration_ordering.md`, `references/migration_preconditions.md`, the plan being audited |
| 3 (Migrate, code-producing) | `references/migrator_self_audit_checklist.md`, `references/migration_preconditions.md`, `references/migration_ordering.md`, `references/three_strike_protocol.md`, `kmm_migration/findings.md`, `kmm_migration/plans/<feature>_migration_guide.md` |
| 4 (Verify) | baseline manifests, `tech_stack_snapshot.md`, `migration_guide.md` |
| 5 (iOS) | `references/migrator_self_audit_checklist.md`, `references/platform_interop_patterns.md`, `kmm_migration/findings.md` |
| 6 (Closeout, holistic reviewer) | every prior report, `migration_guide.md`, `research_notes.md`, `findings.md` |

**Always-NEVER-inject for migrators / porters / final-reviewers:**
`references/baseline_capture_protocol.md` (its presence conflates capture
and port). For baseline authors, the inverse is true.

The orchestrator builds the dispatch prompt as: foundational + role-bundle
(below) + classification rows + phase row, deduplicated.

## Foundational dispatch bundles

These are the FOUNDATIONAL must_read per role — the slim base on top of
which Conditional Dispatch Injection adds the classification / phase rows.

### 10_migrator

```yaml
phase: 3_migrate
model: sonnet
works_in: migration_worktree
must_read_foundational:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/migrator_self_audit_checklist.md
  - skills/kmm-migration/references/migration_preconditions.md
  - kmm_migration/findings.md
  - kmm_migration/plans/<feature>_migration_guide.md
forbidden_to_read:
  - skills/kmm-migration/references/baseline_capture_protocol.md
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - <source code in appropriate source set>
  - kmm_migration/reports/<feature>/10_migrate_batch<N>.md  (with self-audit transcript)
  - kmm_migration/reports/<feature>/<batch>_preconditions.md
status_contract: must run self-audit checklist before STATUS: DONE
```

### spec_compliance_reviewer (escape-hatch only)

This dispatch is NOT in the default flow. It is invoked ONLY when the user
disputes a self-audit verdict via `REQUIRES_APPROVAL`.

```yaml
phase: crosscutting (escape-hatch)
model: sonnet
works_in: migration_worktree
invoked_when: user_disputes_self_audit
must_read_foundational:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/references/migrator_self_audit_checklist.md
  - skills/kmm-migration/references/migration_preconditions.md
  - skills/kmm-migration/schemas/review_verdict_schema.md
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/<task>_disputed_review.md
```

### code_quality_reviewer (escape-hatch only)

Same conditions as spec_compliance_reviewer. Not in default flow.

```yaml
phase: crosscutting (escape-hatch)
model: sonnet
works_in: migration_worktree
invoked_when: user_disputes_self_audit
must_read_foundational:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/references/code_review_criteria.md
  - skills/kmm-migration/references/behavioral_guidelines.md
  - skills/kmm-migration/schemas/review_verdict_schema.md
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/<task>_disputed_quality_review.md
```

### 16_kmm_focused_final_reviewer (holistic cross-batch review)

```yaml
phase: 6_closeout
model: sonnet
works_in: migration_worktree
purpose: holistic cross-batch review the per-batch self-audit cannot perform
must_read_foundational:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/migration_ordering.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/kmp_invariants.md
  - kmm_migration/plans/<feature>_migration_guide.md
  - kmm_migration/reports/<feature>/research_notes.md
  - kmm_migration/findings.md
  - kmm_migration/reports/<feature>/ (all prior batch reports + self-audit transcripts)
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/16_kmm_focused_final_review.md
```

### 14_ios_porter

```yaml
phase: 5_ios
model: sonnet
works_in: migration_worktree
must_read_foundational:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/migrator_self_audit_checklist.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/migration_preconditions.md
  - kmm_migration/findings.md
  - kmm_migration/plans/<feature>_migration_guide.md
  - kmm_migration/reports/<feature>/research_notes.md
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
  - skills/kmm-migration/references/baseline_capture_protocol.md
must_write:
  - <iosMain source files>
  - kmm_migration/reports/<feature>/14_ios_porter.md  (with self-audit transcript)
status_contract: must run self-audit checklist before STATUS: DONE
```

### escape_hatch_seam_inserter (full bundle — extra strict)

```yaml
phase: 1_baseline  # user-gated; named exception to Law 1
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/behavioral_guidelines.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - <user approval artifact>
precondition: user REQUIRES_APPROVAL artifact MUST be present — no approval = BLOCKED
must_write:
  - <exactly one interface file>
  - kmm_migration/findings.md (seam entry appended)
```

### escape_hatch_rebase_baseline (full bundle — extra strict)

```yaml
phase: any  # user-gated; named exception to Law 2
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/baseline_capture_protocol.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - <user approval artifact>
  - kmm_migration/baseline/<feature>/ (all manifests)
precondition: user REQUIRES_APPROVAL artifact MUST be present — no approval = BLOCKED
must_write:
  - kmm_migration/baseline/<feature>/ (updated manifests ONLY — no production code)
  - kmm_migration/findings.md (dated rebase entry with live source)
```

### Foundational reads for the remaining dispatch templates

Each template's full bundle = always-foundational + role-foundational
(below) + classification rows from the matrix above + phase row.

| Template | Model | Phase | Role-foundational additions |
|---|---|---|---|
| `00_worktree_initializer` | haiku | 0 | `worktree_conventions.md` |
| `01_codebase_scope_analyzer` | sonnet | 0 | `findings.md` |
| `01_feature_inventory_scanner` | sonnet | 1 | `findings.md`, `01_inventory.md` |
| `02_baseline_unit_author` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `03_baseline_screenshot_recorder` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `04_baseline_e2e_author` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `05_baseline_gate_validator` | haiku | 1 | `tech_stack_snapshot.md` |
| `06_researcher` | sonnet | 2a | `kmm_technology_lookup.md`, `knowledge_lookup_protocol.md`, `findings.md` |
| `07_migration_planner` | sonnet | 2b | `migration_guide_schema.md`, `research_notes.md`, `migration_ordering.md`, `migration_preconditions.md`, every in-scope source file (read-only) |
| `08_plan_critic` | sonnet | 2c | `plan_review_criteria.md`, `migration_guide.md`, `migration_ordering.md`, `migration_preconditions.md` |
| `11_plan_diff_auditor` | haiku | 4 | `migration_guide.md`, baseline manifests |
| `12_parity_verifier` | haiku | 4/5 | `migration_guide.md`, baseline manifests |
| `13_parity_gate_validator` | haiku | 4 | parity verifier output |
| `15_final_baseline_reverifier` | haiku | 6 | all baseline manifests, `tech_stack_snapshot.md` |
| `17_pr_body_composer` | sonnet | 6 | all reports, `pr_body_schema.md`, `git diff --stat` |
| `18_pr_creator` | haiku | 6 | `pr_body/body.md`, `pr_url.txt` target |
| `19_closeout_reporter` | haiku | 6 | all reports, `closeout_schema.md` |
| `debug_investigator` | sonnet | crosscutting | `three_strike_protocol.md`, strikes report |
| `gate_investigator` | sonnet | crosscutting | `requires_approval.md`, raising subagent report |
| `state_inspector` | haiku | 0 (resume) | `state.json`, `worktree_conventions.md` |

The `09_plan_reviewer` dispatch template is REMOVED — `08_plan_critic`
combines spec compliance + ambiguity + ordering audits in a single
dispatch (Phase 2c restructure).

## Resume flow

Resume is user-triggered — no auto-detection hooks. When the user re-invokes
the skill with an active migration:

1. Orchestrator reads `kmm_migration/state.json`.
2. If `status != complete`, dispatch `state_inspector` (Haiku) to validate:
   `state.worktree_path` exists on disk, is checked out to
   `state.worktree_branch`, is not in detached-HEAD or unexpected-dirty state,
   and baselines under `kmm_migration/baseline/<feature>/` are untouched.
   Also checks for dangling commits without a completion report.
3. Present `REQUIRES_APPROVAL`:
   - A) Re-dispatch last in-flight subagent (worktree reset to last clean commit)
   - B) Inspect worktree (dump diff to `reports/<feature>/resume_inspect.md`)
   - C) Skip in-flight task, proceed to next
   - D) Abandon migration entirely

Everything in `kmm_migration/` persists across session exit, `/clear`, context
compaction, and machine reboot.

## Named escape hatches

- **Seam insertion** — `skills/kmm-migration/dispatch_templates/escape_hatch_seam_inserter.md`
  (named exception to Law 1). User `REQUIRES_APPROVAL` before dispatch.
  One file. Interface-only. Zero behaviour change. Logged in `findings.md`.

- **Baseline rebase** — `skills/kmm-migration/dispatch_templates/escape_hatch_rebase_baseline.md`
  (named exception to Law 2). User `REQUIRES_APPROVAL` before dispatch.
  Only baseline artifacts change. New tolerance envelope must be live-sourced
  (Law 13). Logged in `findings.md` with dated entry and source.

Both run the migrator self-audit checklist with extra-strict items
flagged before STATUS: DONE; the orchestrator's diff-grep tripwire applies
identically. Escape-hatch reviewers are invoked ONLY if the user disputes
the self-audit verdict via REQUIRES_APPROVAL.

## Self-contained — no external skill dependencies

kmm-migration has NO external skill dependencies. Three patterns previously sourced from the superpowers plugin are now inlined:

- Worktree setup — `references/worktree_setup_protocol.md` (invoked by `00_worktree_initializer`).
- Evidence-based completion — `references/verification_protocol.md` (applied by every reviewer and gate validator).
- Root-cause investigation — `references/root_cause_protocol.md` (applied by `debug_investigator` on three-strike).

See `references/self_contained_design.md` for the design rationale.
