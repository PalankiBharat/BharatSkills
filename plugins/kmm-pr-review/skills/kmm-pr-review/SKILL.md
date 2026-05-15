---
name: kmm-pr-review
description: Rigorous, citation-required PR review for Kotlin Multiplatform repos. Reviews shared code (commonMain, expect/actual, Koin) plus Android (Compose) and iOS (SwiftUI, SKIE) consumers against canonical JetBrains, Android, and SKIE docs. Tiered specialist subagent swarm (correctness, idiom, master-grounded) reviews each file with conditional rule loading. Persistent plan and findings on disk guarantee coverage. Master baseline grounding enables attribution-aware prioritization (P0-P3) — pre-existing issues never block. For migration PRs, iOS readiness is checked aggressively.
disable-model-invocation: true
---

# KMM PR Review

A multi-agent, citation-required PR review for Kotlin Multiplatform projects.

## Why this skill exists

Generic code review misses what makes KMP fail in production:

- Types that compile in commonMain but break the iOS build (`java.*`, non-KMP `androidx.*`, JDK time/IO).
- Public surface that compiles for iOS but produces unusable Swift (generic interfaces, inline classes, `Result<T>` erasure, `suspend` without `@Throws`).
- Coroutines and scopes that work on Android but leak on iOS (hardcoded dispatchers, unscoped `CoroutineScope`, plain Flow without SKIE).
- SKIE configuration drift (plugin not applied, annotations without the dependency, runtime casts on `SkieKotlin*Flow`).
- Migration drift — files moved to `:shared` with the Android-only original still in place, missing iOS consumer wiring, Paparazzi baselines not carried over.

The skill applies named rules with stable IDs against canonical JetBrains / Android / SKIE docs. No rule firing without a citation. No citation, no finding.

## Workflow

Six phases, enforced by the scripts and schemas in this skill.

| Phase | What | Driver |
|---|---|---|
| 0. Ingest | Detect PR source (URL, branch, pasted diff); compute diff against master; copy master baselines into state directory; capture PR title/body (via `gh pr view`) for migration-keyword detection | `scripts/ingest.sh` |
| 1. Plan | Classify each file (surface, role, change_type), detect migration (path heuristic + PR text keywords), flag ambiguous cases, materialize sibling baselines (capped at 5), determine swarm tier and rules to load, write `plan.json` | `scripts/classify.py` |
| 2. Cache | Skip files where `(content_hash, rules_hash)` matches a prior run | inline |
| 3. Swarm | Dispatch tiered Sonnet/Haiku specialists. **Threshold-gated**: if pending files ≤ 30, dispatch **per file** using single-file prompts (existing flow). If > 30, run `scripts/build_batches.py` and dispatch one specialist per **batch** using `*-specialist-batched.md` prompts. Specialists load `_index.md` + the always-loaded rule files in full, and lazy-load conditional rule bodies only when a candidate fires | orchestrator (Opus) |
| 4. Aggregate | Interview the user on any ambiguous migrations (Phase 1 output); dedupe by `(rule_id, file, line)`; **verify each finding via `scripts/verify_finding.py` (drops hallucinated findings)**; collapse derivative findings under their root cause (per `references/derivative-map.md`); apply attribution gate; assign final priority | `scripts/dedupe_findings.py` + `scripts/verify_finding.py` + orchestrator |
| 5. Verify | Assert every plan entry is `done` or `cache-hit`; fail loudly otherwise | `scripts/verify_plan_complete.py` |
| 6. Report | Severity-bucketed markdown to stdout (and optionally a file). Parent findings list collapsed derivatives inline. | orchestrator |

The plan is the contract. Phase 5 fails the run if any plan entry was skipped. Coverage is not best-effort.

## The rule index — why specialists are fast

Naively loading every rule for every file means a `sonnet-3-new` specialist consumes ~1000 lines of rules upfront, most of which never fire. Instead:

1. The specialist always loads `references/rules/_index.md` (one terse line per rule across all rule files) plus the small "always-loaded" set (`_base.md`, `hygiene.md`, the role file).
2. While scanning `current_content`, it identifies candidate rules whose one-liner trigger looks plausible.
3. Only for each candidate does it read the full rule body via the Read tool. The body confirms or disconfirms; the specialist emits or drops.

Result: most candidates are confirmed-or-rejected against ~10 lines of rule body each, instead of having all 100+ rules in context the whole time. The prompts in `prompts/` enforce this flow. The index is in `references/rules/_index.md`.

## Persistent state

State lives outside the repo at `~/.kmm-pr-review/<repo-hash>/<branch>/`:

```
plan.json                                # the file-level plan with status
findings/<file-hash>.json                # per-file specialist output
cache/<content-hash>-<rules-hash>.json   # cached output for re-runs
master-baselines/<file-path>             # master version of every touched file
report.md                                # final report
```

Outside the repo on purpose: no gitignore pollution, keyed by repo+branch so parallel work on different branches doesn't collide. Re-runs are idempotent — content + applicable rules unchanged means cache hit, no Sonnet call.

## Core principle: cite or drop

Every finding ships with a `Source:` line. Either:
1. A rule in `references/rules/*.md` that cites a canonical URL, or
2. A URL fetched live during the review.

No source → drop the finding. This is enforced by `schemas/finding.schema.json`.

When a pattern looks suspicious but isn't in the rule files:
1. Context7 for the relevant library (kotlinx.coroutines, Koin, Ktor, SqlDelight, SKIE, Paparazzi, Roborazzi, etc.)
2. Web search filtered to tier-1 sources in `references/canonical-sources.md`
3. Still no authoritative source → drop. Note the skipped concern in the report appendix.

The reason: hallucinated rules in code review produce confidently-stated bad advice. Better to miss a real issue than to surface a fabricated one that erodes trust in the whole review.

## Swarm tiers

Tier comes from `change_type` (assigned in Phase 1). Role determines which rule files load alongside `_base.md`.

| change_type | Tier | Agents | Lenses | Batch cap (files/agent, above threshold) |
|---|---|---|---|---|
| `RELOCATION` (pure move ≥95% similarity) | haiku-1 | 1 Haiku | Directory correctness only. No rule sweep. | 40 |
| `TEST`, `BUILD` | sonnet-1 | 1 Sonnet | Role rules only. | 15 |
| `MODIFIED` | sonnet-2 | 2 Sonnets | A: correctness (loads `_base`, role rules, `ios-readiness` if commonMain). B: idiom (Kotlin conventions, `hygiene`). | 10 each |
| `NEW` in commonMain | sonnet-3-new | 3 Sonnets | A + B + C: master-grounded specialist in **necessity mode** (loads `new-commonmain-file`, `new-file-clean-code`; reads sibling master files to assess duplication/conventions). | A: 6, B: 6, C: 3 |
| `MIGRATION` (drift detected) | sonnet-3-migration | 3 Sonnets | A + B + C: master-grounded specialist in **drift mode** (loads `migration-drift`, `ios-readiness` with iOS-blocking findings auto-promoted to P0). | A: 6, B: 6, C: 2 |

Two lenses (A correctness + B idiom) rather than four identical Sonnets: real variance comes from different rule slices and framing, not from running the same prompt twice. The master-grounded specialist (C) is the same Sonnet role with two preambles — necessity for NEW files, drift for MIGRATION — to avoid prompt-drift between near-identical agents.

See the prompt files in `prompts/` for the exact instructions each specialist receives. Below the batching threshold, the single-file `*-specialist.md` prompts run; above it, `*-specialist-batched.md`.

## Batching

Per-file dispatch doesn't scale to migration-sized PRs (1000+ files). Phase 3 batches **only when pending files exceed 30** (the threshold). Below that, the orchestrator skips batching entirely and uses the existing per-file flow — small PRs are bit-identical to the pre-batching skill.

When triggered, `scripts/build_batches.py` groups Phase-2 cache-miss files by `(lane, swarm_tier, rules_hash, role, surface, package_root)` and greedy-fills per-tier file-count and token caps. The orchestrator then dispatches **one specialist per batch** instead of per file.

| Tier | Lane(s) | Files/batch | Token cap (chars/4) |
|---|---|---|---|
| `haiku-1` | haiku-relocation | 40 | 60,000 |
| `sonnet-1` | correctness | 15 | 100,000 |
| `sonnet-2` | correctness, idiom | 10 each | 90,000 |
| `sonnet-3-new` | correctness, idiom | 6 each | 80,000 |
| `sonnet-3-new` | master-grounded-necessity | 3 | 70,000 |
| `sonnet-3-migration` | correctness, idiom | 6 each | 80,000 |
| `sonnet-3-migration` | master-grounded-drift | 2 | 60,000 |

**Grouping rationale.** `rules_hash` is the amortizer — files with identical rule loadouts share the ~12k-token rule-loading cost across the batch. `role` and `surface` keep batches topically coherent. `package_root` (first 3 path segments) is a tiebreaker that keeps the specialist's attention in one neighborhood per batch. Same-`package_root` files batch together; if a hard-partition bucket is small, contiguity naturally clusters by package without needing relaxation.

**Cache stays per-file.** Batches are formed from cache-miss files only. After a batch completes, the orchestrator splits findings back to per-file `findings/<content_hash>.json` and `cache/<content_hash>-<rules_hash>.json`. A future re-run that hits the cache on file X skips batching X entirely.

**Coverage preserved.** Each file's `plan.json` `status` flips to `done` only after **every lane required by its tier** has completed. Phase 5 (`verify_plan_complete.py`) is unchanged. Partial batch failures leave their files `pending`, which fails Phase 5 loudly — that's intentional.

Per-batch coverage assertion: each batched specialist returns `files_reviewed`, listing every file it scanned (including zero-finding ones). The orchestrator fails the batch on mismatch and re-dispatches the missing subset.

## Attribution gate

After dedupe, before priority assignment. For each finding, the orchestrator classifies:

- **PR-induced** — the violation was introduced or made-applicable by this PR. Includes: new code, modified code, or code moved into a location where the rule now applies and didn't before (e.g., a function with `java.util.Date` moved from `androidMain` to `commonMain`). Full severity rubric applies.
- **Pre-existing** — the violation existed in master with identical applicability. **Capped at P3**, surfaced under "P3 — Pre-existing (suggested follow-ups)" with the master file:line cited. Never blocks.

Attribution is by *rule applicability*, not by text identity. A move that text-preserves but changes which rules apply is PR-induced. This is what makes the skill safe on migration PRs: existing tech debt that travels along doesn't block the merge but is documented for a follow-up.

If attribution is unclear, default to PR-induced and let the user adjudicate.

## Priority and verdict

| P | Bar |
|---|---|
| P0 | Must fix before merge. Correctness, runtime crash, build break, security. For migration PRs: any iOS-blocking finding, auto-promoted. |
| P1 | Should fix before merge. Architectural problem, parity gap, real tech debt, missing tests for new behavior. |
| P2 | Convention or serious nit. Team-stack deviation, idiomatic Kotlin violation, hygiene issue. |
| P3 | Long-term refactor opportunity, or pre-existing issue documented as follow-up. Never blocks. |

| Verdict | Condition |
|---|---|
| `Block` | Any P0 PR-induced finding |
| `Request changes` | Any P1 PR-induced (no P0) |
| `Approve with nits` | Only P2/P3 PR-induced |
| `Approve` | Zero findings or only pre-existing P3 |

## Report format

```
# KMM PR Review — <PR title or branch>

**Verdict:** <Approve | Approve with nits | Request changes | Block>
**TL;DR:** <one-line summary>

**Surfaces touched:** SHARED_COMMON, IOS_CONSUMER, ...
**Migration detected:** yes/no
**Files reviewed:** N (NEW: x, MODIFIED: y, RELOCATION: z)
**Findings:** P0: x, P1: y, P2: z, P3: w  (pre-existing: q, all P3)

## P0
…

## P1
…

## P2
…

## P3
…

## P3 — Pre-existing (suggested follow-ups)
…

## Appendix — research notes
…
```

Each finding:

```
**[<path>:<line>]** <one-line summary>

**Why:** <1-3 sentences>

**Suggestion:** <concrete fix>

**Source:** <URL or references/rules/<file>.md#<rule-id>>

**Attribution:** PR-induced | Pre-existing  (specialists: <…>; confidence: <…>)
```

`Source:` and `Attribution:` are mandatory. Missing either → drop.

## Things this skill does not do

- Suggest Compose Multiplatform — team deferred CMP per project convention.
- Suggest Hilt — team migrated to Koin.
- Fabricate metrics ("30% slower") without a benchmark.
- Flag findings outside the diff. Unchanged-code observations go under pre-existing P3 with master file:line.
- Auto-post to GitHub via `gh pr review`. Always inline output unless the user explicitly requests file/comment posting.
- Defer with "I'm unsure" — either a rule fires or research happens.
- Skip files silently — Phase 5 fails loudly on incomplete plans.

## Scripts

- `scripts/ingest.sh` — Phase 0: detect PR source, capture title/body via `gh`, load master baselines.
- `scripts/classify.py` — Phase 1: classify, detect migration (with PR-keyword fallback), materialize sibling baselines (capped at 5), flag ambiguous migrations, write `plan.json`.
- `scripts/build_batches.py` — Phase 3 prep (only when pending files > 30): groups cache-miss files into lane-specific batches subject to per-tier file-count + token caps; writes `batches.json`; stamps `batch_id_<lane>` back into `plan.json`.
- `scripts/dedupe_findings.py` — Phase 4 dedupe step.
- `scripts/verify_finding.py` — Phase 4 verification step. Rule-keyed grep/AST/file-existence checks reject hallucinated findings before they ship. Single most important quality gate. Runs in `--batch` mode after dedupe; produces `findings.verified.json`.
- `scripts/verify_plan_complete.py` — Phase 5: assert every plan entry is `done` or `cache-hit`.

## Reference files

| File | Loaded when |
|---|---|
| `references/canonical-sources.md` | Always |
| `references/role-detection.md` | Phase 1 (consulted by `classify.py`) |
| `references/rules/_index.md` | **Always loaded by every specialist** — terse one-liner per rule across all rule files |
| `references/rules/_base.md` | Every specialist (always-loaded full body) |
| `references/rules/hygiene.md` | Every specialist (always-loaded full body) |
| `references/rules/<role>.md` | When `role` matches, always-loaded full body |
| `references/rules/ios-readiness.md` | Lazy-loaded on candidate fire; mandatory if surface ∈ {SHARED_COMMON, SHARED_PLATFORM} or migration |
| `references/rules/new-commonmain-file.md` | Lazy-loaded on candidate fire; mandatory for NEW files in commonMain |
| `references/rules/new-file-clean-code.md` | Lazy-loaded on candidate fire; mandatory for NEW files |
| `references/rules/migration-drift.md` | Always-loaded by master-grounded specialist in `drift` mode |
| `references/derivative-map.md` | Consulted by the aggregator in Phase 4 to collapse derivatives under root cause |

## Schemas

- `schemas/finding.schema.json` — every specialist output validates against this. Findings that fail validation are dropped by the aggregator with a logged warning.
- `schemas/plan.schema.json` — `plan.json` validates against this before Phase 3 dispatch.

## Prompts

Single-file prompts (used when pending files ≤ 30):

- `prompts/correctness-specialist.md` — Sonnet A: KMP correctness, type leakage, expect/actual, coroutines, iOS bridging, SKIE structure.
- `prompts/idiom-specialist.md` — Sonnet B: Kotlin idiom, hygiene, clean code on NEW files, role-specific style.
- `prompts/master-grounded-specialist.md` — Sonnet C: necessity check on NEW files in commonMain (necessity mode) or drift check on migration files (drift mode). The only specialist with master baseline + sibling baselines.

Batched prompts (used when pending files > 30):

- `prompts/correctness-specialist-batched.md` — same role, accepts a `files: [...]` envelope; loads rule bodies once, scans each file in order, emits one combined JSON with `batch_id` + `files_reviewed` + flat `findings` array.
- `prompts/idiom-specialist-batched.md` — same role plus a batch-consistency demotion rule: judgment patterns present across **all** same-package siblings in the batch are treated as team convention.
- `prompts/master-grounded-specialist-batched.md` — same role plus cross-file NC-01 duplication detection within the batch. Small batches (2-3 files) to protect the most cognitively heavy lane.

Orchestrator:

- `prompts/opus-aggregator.md` — Opus: Phase 3 dispatch (per-file or batched), ambiguity interview, dedupe, verification pass, false-positive filter, attribution gate, derivative collapse, priority assignment, cross-file aggregation, verdict, report.

## Invocation

The skill is designed for Claude Code with subagent dispatch. Inside a checked-out KMP repo branch:

```
# from a checked-out branch
skill run kmm-pr-review

# from a PR URL (gh CLI used to fetch)
skill run kmm-pr-review --pr https://github.com/<org>/<repo>/pull/<n>

# from a pasted diff
skill run kmm-pr-review --diff /path/to/patch.diff

# clear cache and rebuild plan
skill run kmm-pr-review --no-cache
```

Exact invocation syntax depends on the runner. The orchestrator (Opus by convention, per the user's global Claude Code config) reads this SKILL.md, runs the scripts, dispatches the specialists, and produces the report.
