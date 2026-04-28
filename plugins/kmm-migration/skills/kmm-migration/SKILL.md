---
name: kmm-migration
description: >-
  Use when the user is migrating an existing Android feature to Kotlin
  Multiplatform — extracting business logic to commonMain, sharing code
  with iOS, or converting Android-only implementations into KMP-compatible
  ones. Enforces a baseline-first, 1:1-port workflow with hard gates.
  Not an encyclopedia — an orchestrator that drives all labour through
  subagents. Triggers: "migrate to KMM", "share with iOS", "move to
  commonMain", "port Android code to Kotlin Multiplatform", "extract
  shared module", "KMP migration", "KMM migration".
when_to_use: >-
  Active Android → Kotlin Multiplatform migration work on a feature-by-feature
  basis. Not for greenfield KMP scaffolding. Not for KMP-version bumps.
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

> Orchestrator for Android → Kotlin Multiplatform feature migrations.
> Baseline-first, 1:1-port, subagent-driven, hard quality gates.
> See `skills/kmm-migration/migration_laws.md` for the 14 iron laws YOU MUST follow.

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
- [Dispatch bundles](#dispatch-bundles)
- [Resume flow](#resume-flow)
- [Named escape hatches](#named-escape-hatches)
- [Self-contained — no external skill dependencies](#self-contained--no-external-skill-dependencies)

## Orchestration flow

kmm-migration is an orchestrator skill. The main Claude context (Opus) never
edits code, never reads source files, and never runs build commands. All labour
flows through subagents — Sonnet for heavy work (planning, migrating,
reviewing), Haiku for deterministic checks (gate validation, diff auditing,
parity verification). Six phases, five user gates, one worktree per migration.
Every phase transition requires concrete, verifiable artifacts — no silent
advancement. Every code-producing output is reviewed by two independent lenses
(spec compliance then code quality) before the task is complete. Every KMM
technology decision is live-sourced per invocation — no hardcoded stack. The
14 iron laws in `skills/kmm-migration/migration_laws.md` are the absolute
authority.

## Required reading for the orchestrator on invocation

YOU MUST read these files BEFORE taking any action on an invocation:

- `skills/kmm-migration/migration_laws.md`
- `skills/kmm-migration/references/knowledge_lookup_protocol.md`
- `skills/kmm-migration/references/worktree_conventions.md`
- `skills/kmm-migration/references/subagent_status_contract.md`
- `skills/kmm-migration/formats/requires_approval.md`
- `skills/kmm-migration/schemas/state_schema.md`
- `kmm_migration/state.json` (at the target repo root — if exists)
- `kmm_migration/findings.md` (at the target repo root — if exists)

## Phase 0 — Bootstrap

Read `kmm_migration/state.json`:

- **No state** — ask feature name, base branch, and goal ONE question at a
  time. Dispatch `00_worktree_initializer` (Haiku), which follows
  `references/worktree_setup_protocol.md` to create ONE worktree at
  `.worktrees/kmm-migrate-<feature>/` on branch `kmm-migrate/<feature>`.
  Record `worktree_path` and `worktree_branch` in `state.json`. Every
  subsequent subagent operates inside this single worktree — no other subagent
  creates its own.

- **Existing state with `status != complete`** — dispatch `state_inspector`
  (Haiku) to validate worktree existence, branch, and cleanliness. Present a
  `REQUIRES_APPROVAL` with options: resume, inspect, or abandon.

Also read `kmm_migration/findings.md` — decisions from prior migrations apply.

## Phase 1 — Baseline

1. `01_feature_inventory_scanner` (Sonnet) — enumerates feature files,
   dependencies, Android APIs → `reports/<feature>/01_inventory.md`.
2. `06_researcher` in minimal mode — baseline-tooling pre-pass: which unit /
   screenshot / E2E tool stack applies? Output → `tech_stack_snapshot.md`.
3. Three parallel tracks (each Sonnet, migration worktree):
   - `02_baseline_unit_author` — characterization tests on OG code, ≤5 source
     files per batch, all green.
   - `03_baseline_screenshot_recorder` — goldens from OG UI with per-platform
     tolerance envelope, ≤5 screens per batch.
   - `04_baseline_e2e_author` — E2E flows green vs OG APK, retry policy
     recorded.
4. After each of 02 / 03 / 04: `spec_compliance_reviewer` THEN
   `code_quality_reviewer`. Task is complete only after BOTH PASS.
5. `05_baseline_gate_validator` (Haiku) — all three suites green and
   committed; tolerance envelopes captured; `tech_stack_snapshot.md` recorded.

**Gate 1** — `REQUIRES_APPROVAL` → user freezes baseline.

## Phase 2 — Plan

**Phase 2a — Research:** `06_researcher` (Sonnet, read-only, full mode) —
context7 + WebSearch + find-docs. Writes `reports/<feature>/research_notes.md`
with every non-obvious migration question answered via a live source; populates
`accepted_deltas`.

**Phase 2b — Plan:** `07_migration_planner` (Sonnet, no code tools) — writes
`plans/<feature>_migration_guide.md`, per-file structured spec using the stack
from research. `TBD` / `TODO` / `implement later` are forbidden.

**Phase 2c — Dual review:**
- `08_plan_critic` (Sonnet) — 10-check rule-compliance audit; flags any
  assertion not live-sourced (Law 13).
- `09_plan_reviewer` (Sonnet) — spec-quality audit: ambiguity, completeness,
  explicitness.

Both MUST PASS. **Hard cap: 2 revision cycles.** After the second
ISSUES_FOUND verdict, the orchestrator MUST raise `REQUIRES_APPROVAL` —
continuing past 2 cycles is forbidden. Gate options the user sees:
(a) accept the current plan with the listed gaps documented in
`accepted_deltas`; (b) drop scope from `plan.files_to_touch` to make the
plan reachable; (c) abandon. The orchestrator does NOT silently re-dispatch
the planner a third time.

**Gate 2** — `REQUIRES_APPROVAL` → user approves plan.

## Phase 3 — Migrate

The orchestrator owns ALL git mutations in this phase. Migrators have
`Bash(git commit *)`, `Bash(git add *)`, `Bash(git push *)`, and reset/rebase
on their tool denylist (see `dispatch_templates/10_migrator.md`). Read-only
git inspection (`status`, `diff`, `log`) remains allowed.

1. Orchestrator splits `plan.files_to_touch` into batches of ≤5 files by
   dependency topology. Each batch gets an explicit file list — never "the rest."
   The orchestrator records this in-scope list in the dispatch prompt verbatim.
2. Parallel dispatch of `10_migrator` (Sonnet, migration worktree) per batch.
   Every prompt carries a concrete success criterion (Law 14) naming the
   specific `migration_guide` entry the subagent must satisfy.
3. **Post-dispatch scope-allowlist verification (orchestrator).** Before
   dispatching reviewers, the orchestrator runs `git diff --name-only` in the
   worktree and intersects against the dispatch's in-scope list:
   - **Out-of-scope paths** (Law 3 violation) → `git checkout -- <path>` for
     each, log to `reports/<feature>/scope_violations.md` with batch ID, then
     re-dispatch the migrator with a stricter prompt naming the violations.
   - **Modified baseline artifacts** under `**/snapshots/`, `**/screenshots/`,
     `**/goldens/`, or `kmm_migration/baseline/<feature>/` (Law 2 event) →
     `REQUIRES_APPROVAL` via `escape_hatch_rebase_baseline`. Never silently
     accept a re-recorded golden.
4. After scope verification: `spec_compliance_reviewer` THEN
   `code_quality_reviewer` (fail-fast — quality runs only after spec
   compliance PASS).
5. Either reviewer reports issues → re-dispatch migrator with MODIFIED prompt
   carrying review findings. Never retry with identical prompt. Max 2 fix
   cycles per batch, then `REQUIRES_APPROVAL`.
6. Both reviewers PASS → orchestrator stages the in-scope diff and commits
   with a message naming the batch and the migration_guide entries satisfied.
7. Three distinct failed approaches → migrator writes
   `reports/<feature>/strikes/<ts>_migrator.md` + emits `STATUS: BLOCKED`.
   Orchestrator dispatches `debug_investigator`.

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

1. `14_ios_porter` (Sonnet, migration worktree) — `iosMain` actuals + Swift-
   interop wrapper per researcher's recommendation + iOS goldens + iOS E2E runs.
2. `spec_compliance_reviewer` THEN `code_quality_reviewer` follow.
3. `12_parity_verifier` — iOS suites only.

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

## Dispatch bundles

Authoritative table. Orchestrator reads this before every dispatch and
constructs the prompt with must-read and forbidden-to-read lists explicitly.

### 10_migrator (highest-risk — full bundle)

```yaml
phase: 3_migrate
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/kmm_technology_lookup.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/worktree_conventions.md
  - skills/kmm-migration/references/three_strike_protocol.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/schemas/migration_guide_schema.md
  - kmm_migration/findings.md
  - kmm_migration/baseline/<feature>/tech_stack_snapshot.md
  - kmm_migration/plans/<feature>_migration_guide.md
  - kmm_migration/reports/<feature>/research_notes.md
forbidden_to_read:
  - skills/kmm-migration/references/baseline_capture_protocol.md
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - <source code in appropriate source set>
  - kmm_migration/reports/<feature>/10_migrate_batch<N>.md
```

### spec_compliance_reviewer (crosscutting — full bundle)

```yaml
phase: crosscutting  # after every code-producing dispatch
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/code_review_criteria.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/schemas/review_verdict_schema.md
  - <task spec passed in the dispatch prompt>
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/<task>_spec_review.md
```

### code_quality_reviewer (crosscutting — full bundle)

```yaml
phase: crosscutting  # after spec_compliance PASS only — fail-fast ordering
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/code_review_criteria.md
  - skills/kmm-migration/references/behavioral_guidelines.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - skills/kmm-migration/schemas/review_verdict_schema.md
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/<task>_quality_review.md
```

### 16_kmm_focused_final_reviewer (high-risk — full bundle)

```yaml
phase: 6_closeout
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/code_review_criteria.md
  - skills/kmm-migration/references/behavioral_guidelines.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - kmm_migration/plans/<feature>_migration_guide.md
  - kmm_migration/reports/<feature>/research_notes.md
  - kmm_migration/findings.md
  - kmm_migration/reports/<feature>/ (all prior review reports)
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
must_write:
  - kmm_migration/reports/<feature>/16_kmm_focused_final_review.md
```

### 14_ios_porter (full bundle)

```yaml
phase: 5_ios
model: sonnet
works_in: migration_worktree
must_read_before_start:
  - skills/kmm-migration/migration_laws.md
  - skills/kmm-migration/references/platform_interop_patterns.md
  - skills/kmm-migration/references/knowledge_lookup_protocol.md
  - skills/kmm-migration/references/worktree_conventions.md
  - skills/kmm-migration/references/three_strike_protocol.md
  - skills/kmm-migration/references/behavioral_guidelines.md
  - skills/kmm-migration/references/subagent_status_contract.md
  - kmm_migration/findings.md
  - kmm_migration/plans/<feature>_migration_guide.md
  - kmm_migration/reports/<feature>/research_notes.md
forbidden_to_read:
  - skills/kmm-migration/dispatch_templates/*
  - skills/kmm-migration/references/baseline_capture_protocol.md
must_write:
  - <iosMain source files>
  - kmm_migration/reports/<feature>/14_ios_porter.md
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

### Abbreviated bundles for remaining dispatch templates

Full must_read lists are in each template's own frontmatter. Core rule:
every template reads `migration_laws.md` and `subagent_status_contract.md`
at minimum; none read `dispatch_templates/*`.

| Template | Model | Phase | Key extra reads |
|---|---|---|---|
| `00_worktree_initializer` | haiku | 0 | `worktree_conventions.md` |
| `01_feature_inventory_scanner` | sonnet | 1 | `findings.md`, `01_inventory.md` |
| `02_baseline_unit_author` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `03_baseline_screenshot_recorder` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `04_baseline_e2e_author` | sonnet | 1 | `baseline_capture_protocol.md`, `tech_stack_snapshot.md` |
| `05_baseline_gate_validator` | haiku | 1 | `tech_stack_snapshot.md` |
| `06_researcher` | sonnet | 2a | `kmm_technology_lookup.md`, `knowledge_lookup_protocol.md` |
| `07_migration_planner` | sonnet | 2b | `migration_guide_schema.md`, `research_notes.md` |
| `08_plan_critic` | sonnet | 2c | `plan_review_criteria.md`, `migration_guide.md` |
| `09_plan_reviewer` | sonnet | 2c | `plan_review_criteria.md`, `migration_guide.md` |
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

Both go through `spec_compliance_reviewer` and `code_quality_reviewer` with
extra-strict checks after dispatch.

## Self-contained — no external skill dependencies

kmm-migration has NO external skill dependencies. Three patterns previously sourced from the superpowers plugin are now inlined:

- Worktree setup — `references/worktree_setup_protocol.md` (invoked by `00_worktree_initializer`).
- Evidence-based completion — `references/verification_protocol.md` (applied by every reviewer and gate validator).
- Root-cause investigation — `references/root_cause_protocol.md` (applied by `debug_investigator` on three-strike).

See `references/self_contained_design.md` for the design rationale.
