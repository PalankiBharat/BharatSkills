# kmm-pipeline — Design

Date: 2026-06-13 · Repo target: `sniper-v2-android` (monorepo: `:app` Android, `:shared` KMP, `Punch/` SwiftUI iOS via CocoaPods `pod 'shared'`, `:sniper-library` KMP)

## Goal

A repo-custom plugin that takes one Android feature at a time end-to-end: scope → research → plan → TDD migration into `:shared` commonMain → iOS wiring in `Punch/` → automated parity QA → KMM-specific review → PR → merge. Post-migration invariants: **Android 100% unaffected** (rename-only diffs, unchanged callers, green pre-existing tests) and **iOS has the feature at 100% UI/functional parity** (shared logic + commonTest on iosSimulatorArm64 + mirrored Maestro flows).

## Non-goals

- No encyclopedia of KMM knowledge inside the plugin. KMM moves fast; training data and baked notes go stale. All KMP/SKIE/CMP/Xcode facts are fetched at migration time (context7 → official docs → web) by a dedicated researcher agent, cached per-migration in `research.md`, with durable repo learnings appended to the repo's committed `.kmm/project.md` profile.
- No rebuilding of existing capability. The workflow composes: **superpowers** (writing-plans, test-driven-development, systematic-debugging, verification-before-completion, requesting/receiving-code-review, using-git-worktrees, finishing-a-development-branch), **graphify** (scoping, blast radius, post-move `graphify update`), **context7/WebSearch/WebFetch** (live docs), **Maestro** (cross-platform E2E — same flow on Android emulator and iOS simulator), repo scripts (`build-production.sh`, `install-production.sh`, phone-driver CLI).

## Shape: one plugin, three lean skills, six agents, armed hooks

Considered: (a) one mega-skill — rejected: bloated context per load, no standalone review/QA reuse; (b) many micro-skills per phase — rejected: orchestration state would smear across entries. Chosen: **three user-facing skills sharing one disk state**:

| Skill | Role |
|---|---|
| `migrate` | Orchestrator state machine. Entry + resume. Dispatches agents per phase, owns human gates, advances `state.json`. Phase playbooks live in `references/phase-*.md` (progressive disclosure — only the active phase is loaded). |
| `qa` | Automated parity QA round. Standalone on any migration branch; invoked by `migrate` at phase 6. |
| `review` | KMM-migration-specific adversarial review. Standalone on any KMM PR; invoked by `migrate` at phase 6. |

Agents (`agents/`): `kmm-scout` (read-only graphify-first boundary mapping), `kmm-researcher` (live-docs only, citation-mandatory, "UNKNOWN" allowed — guessing forbidden), `kmm-migrator` (one plan step per dispatch, TDD, git mv, surgical whitelist), `kmm-ios-engineer` (Punch/ wiring + SwiftUI binding to shared via SKIE), `kmm-qa-verifier` (evidence-or-fail matrix execution), `kmm-reviewer` (lens-parameterized verdicts vs the Law).

Agent teams: the roster above IS the team. Default coordination is Agent-tool dispatch (deterministic, resumable). The experimental Agent Teams runtime (TeamCreate/SendMessage) has no session resume as of mid-2026, which conflicts with the resume requirement — `migrate` may use it for the execute phase when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, but disk state remains the source of truth either way.

## Disk state + resume

```
.kmm/migrations/ACTIVE              # slug of in-flight migration; arms the hooks
.kmm/migrations/<slug>/state.json   # machine cursor: phase, step, gates, commits, branch
.kmm/migrations/<slug>/journal.ndjson  # append-only event log (resume source of truth)
.kmm/migrations/<slug>/contract.md  # parity contract (human-approved observable behaviors)
.kmm/migrations/<slug>/plan.md      # approved step plan
.kmm/migrations/<slug>/research.md  # sourced findings (citations mandatory)
.kmm/migrations/<slug>/qa-report.md / review-report.md
```

`.kmm/migrations/` is added to `.git/info/exclude` at preflight (shared across worktrees via the common git dir) — state never leaks into PRs (a past migration leaked `.kmm/` session artifacts into #425's branch; commit f765547e96 had to remove them). `.kmm/project.md` stays committed — it is team knowledge, and the plugin appends durable learnings to it at close.

Resume: re-invoking `migrate` with state present verifies `git log` against journal SHAs, then continues from the cursor. A SessionStart hook surfaces in-flight migrations in fresh sessions.

## Hardening: deterministic guard > prose

Discipline that can be regex-checked is enforced by a PreToolUse hook (`migration_guard.py`), armed only while `ACTIVE` exists, scoped to `app/src|shared/src|Punch/` and `.kt/.swift`:

- **Copy-instead-of-move**: `Write` of a `shared/src/**.kt` whose basename exists under `app/src/**` → deny (use `git mv`). Bash `cp`/bare `mv` from `app/src` to `shared/` → deny.
- **Naming bans**: new files/declarations containing android/ios/apple/darwin affixes → deny (platform variants = same name, different source set).
- **Comment additions** in migration-scoped `.kt`/`.swift` → deny (moved code keeps its comments byte-for-byte; new code carries none).
- **Known-broken commands**: `--rerun-tasks` (fails in this repo per `.kmm/project.md`) → deny.

Everything judgment-shaped (surgical-edit whitelist, sourced-API rule, escalation) lives in `skills/migrate/references/rules.md` — the Law — loaded by every code-touching agent and cross-referenced by rule number in review.

## TDD for migrations

"Failing test first" maps to: **characterization baselines pinned on Android before any move** (they must pass identically after), promotion of tests to `commonTest` with the move (precedent: #425), and red-first TDD for genuinely new seams (expect/actual, iOS glue). commonTest on `iosSimulatorArm64` is the logic-parity gate; mirrored Maestro flows are the UX-parity gate.

## Human gates (only these)

1. Scope + parity contract approval (defines what behavior is protected).
2. Plan approval.
3. Mid-flight blocker: behavior cannot be preserved exactly / Law conflict (STOP-and-escalate, never improvise).
4. Pre-merge.

## Verification of the plugin itself

Guard script: executable test suite (`tests/test-guard.sh`, deny/allow payloads). Skills: `claude plugin validate` + word-count lean checks + a subagent pressure test that the Law text actually stops scope-creep refactoring during a simulated move step.
