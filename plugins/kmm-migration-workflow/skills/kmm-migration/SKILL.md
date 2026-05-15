---
name: kmm-migration
description: Orchestrates structured Android-to-KMM migration with strict behavioral-equivalence safety. Discovers scope via the user's described navigation flow, writes baseline tests proving current Android behavior, freezes them, migrates code via `git mv` + surgical edits, validates on Android and iOS, produces a clean PR. Use this skill whenever the user wants to migrate any Android feature, screen, module, or specific files (ViewModel, UseCase, Repository, Mapper, etc.) to Kotlin Multiplatform / shared module — even if they only mention 'KMM', 'shared module', 'commonMain', or name a specific file/feature to migrate. Triggers on phrases like 'migrate the funds screen to KMM', 'KMM migration plan', 'baseline tests for migration', 'move this to shared', or any preparation/execution phrase. The skill enforces a prevention-first phased workflow with user-confirmed transitions; do not bypass it for ad-hoc migration work even when individual files look simple — bypass corrupts the equivalence safety net.
---

# KMM Migration Orchestrator

A workflow for migrating Android code to Kotlin Multiplatform without behavior surprises. The skill never re-derives KMM knowledge from training — patterns come from live web search, APIs come from Context7, project conventions live in `.kmm/project.md`. The skill's job is the **workflow**.

Testing rules for the whole workflow live in `references/test-discipline.md` (loaded by Phase B; consulted by other phases when test code is touched).

---

## Principles

1. **Behavioral equivalence + API stability.** The Android app is in production. Post-migration, the app behaves identically — same observable outputs, same method/class contracts. Callers untouched. Package paths may shift; that's a mechanical import update, not an API change.

2. **Two modes.** Migrating existing code: surgical, compiler-driven edits, minimal diff, no "improvements" smuggled in. Writing new code (interfaces, `expect`/`actual`, DI module): strict clean code, KISS, DRY. No `*Holder`/`*Manager`/`*Helper` cruft. New abstractions earn ≥2 consumers or get inlined.

3. **Migration done means done.** "Migrated" means the file lives in `commonMain` and is iOS-consumable as-is via SKIE — no `TODO`s, `FIXME`s, stub `expect`/`actual` impls, or deferred work. A file relocated to `androidMain` is **not migrated**; it's a structural intermediate awaiting future migration (Phase D this session, or a future session). If full correctness in `commonMain` isn't achievable this session, the file is **held back from `commonMain`, not partially migrated**.

4. **Transparent decisions for non-trivial work.** Anything beyond mechanical substitution gets researched (web + codebase scan), planned with Opus, and discussed with the user before proceeding. Nothing surprises the PR reviewer because nothing surprised the user during the work. Existing codebase patterns are reference, not source of truth — propagate only what's clean.

---

## Cross-cutting rules

### Diff-confirm protocol

Every write to anything under `.kmm/` is a **gated operation**. Before any such write, the skill produces the following pre-write checklist as visible output:

```
Pre-write check for <path>:
- Diff for this exact path proposed in prior turn?  [y/n]
- User accepted (`a` or explicit accept) in subsequent user turn?  [y/n]
- Both yes → proceed.  Either no → abort, produce diff-confirm prompt instead.
```

If both answers are yes, the write proceeds. If either is no, the write is aborted and the diff-confirm prompt is produced instead:

```
Proposed updates to <file>:

[+] Add to <section>: <text>
[~] Update <section>:
    old: <text>
    new: <text>
[-] Remove from <section>: <text>

Apply all / edit / reject? [a/e/r]
```

User accepts, edits any line, or rejects. After acceptance, the skill re-issues the pre-write checklist (now both `[y]`) and the write happens.

**No silent writes anywhere.** The checklist ritual is not optional — skipping it is a discipline violation, recoverable only by re-running the gate. Post-hoc rationalization ("treating as draft pending accept") is not recovery; abort + diff prompt is the only recovery.

### Smart subagent routing

| Category | Model | When |
|---|---|---|
| Mechanical | Haiku | File reads, denylist scans, filetype heuristics, gradle output parsing, template fills, log parsing, git mv operations |
| Bounded judgment | Sonnet | Checklist scoring, routine test writing, breakage mutations, self-review, verdict prose, per-file analysis, routine compile-error fixes |
| High-stakes / irreversible | Opus orchestrator | Feature-surface baselines, complex-file tests (concurrency-heavy Interactors, multi-source Repos with cache, state-machine Presenters), cross-file synthesis, hold-back decisions, non-trivial decision planning |

Discipline: **Opus only when cost-of-being-wrong is high.** Default-everything-Sonnet wastes Opus depth on routine work; default-everything-Opus burns time and tokens on mechanical tasks.

### Tooling discipline

Reflex defaults that govern tool choice. These are not preferences — they shape the skill's output and are non-negotiable.

- **Context7 first for library/SDK/API specifics.** Library APIs, SDK signatures, framework configuration syntax — Context7 is primary. Web search is secondary, for community patterns and antipatterns. Training-data API recall is not allowed. Cache results at `.kmm/searches/<topic-hash>.md`; reuse if ≤ 30 days old; auto-invalidate past that (TTL configurable in `project.md`).
- **Web search for patterns and approaches.** *"How do people handle X in KMM?"* — community wisdom for architectural decisions, not API specifics. Parallelize Context7 + web search when both kinds of input are needed for the same decision.
- **Regular `import` first; `import ... as Alias` only on collision.** Bring symbols in via normal import. When two imports collide on short name, alias one. Never inline the FQN at the call site — it's noisy and hides the dependency from the import list.
- **`git restore <path>` over reverse-edits.** For any tracked-file undo, use git's restore. Manually reverting via str_replace is error-prone and skips git's history checks.
- **No code comments unless WHY is non-obvious — and then, only a one-liner.** Comments explaining WHAT the code does are noise; the code is the source of truth. Comments explaining WHY (constraint, business rule, non-obvious gotcha) are allowed but must be a single line. No block comments, no multi-line explanations.

### Non-trivial decision protocol (principle #4)

**Triggers:**
- Adding new files to commonMain (interfaces, helpers, abstractions).
- Library substitutions with semantic differences.
- Concurrency / threading model decisions.
- Multiple plausible `expect`/`actual` shapes.
- ≥2 reasonable approaches exist with downstream impact.

**Protocol:**
1. **Live research (parallel Sonnet)** — Context7 for API specifics, web search for patterns + antipatterns; codebase scan for prior similar solutions (reference, not gospel — propagate only what's clean).
2. **Opus planning** — generates 2–3 plausible approaches; pros/cons; fit with project conventions (per project.md); risk to equivalence; states its lean and why.
3. **Present to user** — problem, options with rationale, skill's lean, asks for thoughts.
4. **Discuss** — substantively engage; don't just defer.
5. **Log** — in active phase's decisions log: problem, options considered, choice, rationale. Audit trail for PR reviewers.
6. **Proceed.**

Trivial decisions (apply plan.md substitution; single obvious compile fix) — skill self-decides and logs to decisions log. User can review later, isn't blocked.

### Resume protocol (every invocation)

1. Read `.kmm/project.md` and (if topic-relevant) `.kmm/searches/`.
2. Detect current git branch (`git branch --show-current`).
3. Branch on situation:
   - On `kmm/...` branch with matching session folder → **resume**: read ALL phase files in that session folder in order, reconstruct full context (scope, decisions, evidence, tasks done, tasks pending), self-audit (baselines still green? uncommitted state? branch matches folder?), report state, pick up at next pending task. **Zero rediscovery.**
   - On `kmm/...` branch without session folder → start fresh session here.
   - On `main`/`master`/non-`kmm/` → branch + worktree setup (see Phase 0), then end invocation. Phase 0 runs in the new worktree.

### Rule of three (auto-promotion to project.md)

Patterns applied **≥3 times in the same session** become project.md promotion candidates. Detection: Haiku scans decisions logs for keyword + structural matches (e.g., `expect/actual + <same shape>` appearing in 3 entries). Sonnet drafts the addition. Diff-confirm to user. Single- or twice-applied patterns stay in session.

Setup facts (modules, DI framework, source-set wiring) captured on **first** occurrence via Phase 0 gap-fill — they're state, not patterns; rule of three doesn't apply.

Rule of three targets **KMM patterns specific to this repo** (project.md). General workflow rules that surfaced during a session (tool choices, edit discipline, ordering reflexes) are handled by the **session-retro skill-improvement step** — see Special actions below.

### Scope-creep traceability gate

Every in-flight action must be traceable to a confirmed artifact. The skill halts when a planned action would:

- Create a new file not listed in `scope.md` and not pre-authorized by `plan.md` (foundation interface, expect/actual, fake, DI module).
- Make a structural gradle change (new module, new source set, new plugin) not specified in `plan.md`.
- Edit a file outside `scope.md` that isn't a consumer-import update of an in-scope file.

On halt, the skill presents three options:

1. **Extend scope** — invokes the existing `update scope` action; Phase 0 re-walks deps from the new file; affected later-phase files reset.
2. **Extend plan** — Phase A reopens to add the foundation/interface; logged in plan.md decisions log via diff-confirm.
3. **Follow-up** — logged to `pr.md` "Out-of-scope follow-ups" section, not done this session.

The gate fires immediately at the point of attempted action, not at phase end. Untraceable work is treated as scope creep regardless of size — there is no numeric threshold.

### Migration-exception process

For intentional behavior changes during migration (library substitution semantics, timezone handling, JSON ordering):

- Exception file at `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` with: what changed, why, risk, user sign-off.
- Baseline edit references it: commit message contains `[migration-exception <id>]`.
- Enforcement is **human-gated** via reviewer attention on the PR diff. No CI assumed; no CODEOWNERS dependency.
- **Skill itself refuses to edit frozen baselines without a corresponding exception file present** — this is the primary enforcement layer.

### Phase file format

All phase files follow:

```markdown
# Phase <X> — <Name>
Session: <branch-name>
Status: not-started | in-progress | complete
Last updated: <ISO timestamp>

## Tasks
- [x] <completed task>
- [ ] <pending task>  ← next

## <Phase-specific sections>
[per-file entries, verdicts, evidence, etc.]

## Decisions log (chronological)
- <timestamp> — <decision + rationale>

## Self-review notes (where applicable)
- <considered X, chose Y because Z>
```

Files are **living documents** — written progressively as work proceeds (batched per logical unit, diff-confirmed), not at phase end. Resume relies on this.

### Branch + worktree

- Branch naming: `kmm/<feature>-<depth>` (e.g., `kmm/funds-business-logic`, `kmm/funds-presentation`, `kmm/funds-full`).
- One branch = one session = one folder under `.kmm/migrations/`.
- Default worktree path: `../<repo-name>-<branch-suffix>/` — the `kmm/` prefix is dropped to avoid filesystem slashes. Configurable via `worktree_path_template` in `project.md`.
- Skill never creates branches or commits silently — proposes commands, user confirms.

### Universal hard gates (every phase)

- Phase predecessor must be complete (status field).
- All `.kmm/` writes go through the diff-confirm pre-write checklist.
- No silent updates.
- Scope-creep traceability gate enforced at every action.
- User confirmation gates transition to next phase.

Phase-specific gates are listed in each phase's reference file.

---

## Directory layout

```
.kmm/
├── project.md                      # cross-session: reusable KMM knowledge for this repo
├── searches/                       # cross-session: cached live-search results (30-day TTL)
│   └── <topic-hash>.md
├── exceptions/                     # cross-session: migration-exception files
│   └── <YYYY-MM-DD>-<short-id>.md
└── migrations/
    └── kmm/<feature>-<depth>/      # per-session, mirrors branch path
        ├── scope.md                # Phase 0
        ├── plan.md                 # Phase A
        ├── audit.md                # Phase B
        ├── coverage.md             # session-local registry (audited → frozen → migrated → promoted)
        ├── freeze.md               # Phase C
        ├── migration.md            # Phase D
        ├── move.md                 # Phase E
        ├── validation.md           # Phase F
        ├── heatmap.md              # Phase F — QA checklist artifact
        ├── pr.md                   # Phase G
        └── retro.md                # Session-end friction signal (see Special actions)
```

**project.md scope** — reusable KMM knowledge for this repo: modules + source-set hierarchy, DI framework + coexistence stance, persistence tech + schema locations, networking config (baseUrl, BuildKonfig), UI strategy (native vs CMP timeline), SKIE config, iOS consumption / distribution flow, manual QA workflow, test-infra wiring, conventions, hard-won gotchas. **Excludes:** migration state (lives in session folders), generic KMM how-tos (runtime lookup).

**coverage.md (per session) columns:** File, Type, Phase D plan (`migrate` / `hold`, decided Phase A), Baseline path (initial — always `<dest>/androidUnitTest/...`), Trust score, Status (`relocated` → `audited` → `frozen` → `migrated` → `promoted`), Frozen-at SHA, Final code path (`<dest>/commonMain/...` if migrated, `<dest>/androidMain/...` if held), Final baseline path (`<dest>/commonTest/...` if promoted, else initial).

---

## Preconditions

- JVM + gradle.
- Git ≥ 2.5 (worktree support).
- Android SDK configured.
- macOS + Xcode toolchain for full iOS verification (non-macOS hosts get limited iOS checks; flagged in D / E / F).

## Realistic expectations

A non-trivial migration session takes **5–9 hours end-to-end**, distributed across phases (mostly waiting on gradle and manual QA). Fully resumable — start one day, continue the next. Manual QA in Phase F requires real human time at an emulator/device (typically 30+ minutes for a non-trivial scope).

---

## Phases — overview

The migration runs through 8 phases. **Load the relevant phase reference file when entering or resuming a phase**, not all upfront.

| Phase | Purpose | Output | Reference |
|---|---|---|---|
| **0** | Discovery & Scoping | `scope.md` | `references/phases/phase-0-discovery.md` |
| **A** | Diagnostic — architectural plan (incl. per-file Phase D plan: migrate to `commonMain` this session, or hold at `androidMain`) | `plan.md` | `references/phases/phase-a-diagnostic.md` |
| **B** | Structural relocation (`git mv` every in-scope file uniformly to `<dest>/androidMain`) + Baseline Coverage Audit & Write (in `<dest>/androidUnitTest`) | `audit.md` | `references/phases/phase-b-baseline.md` |
| **C** | Freeze | `freeze.md` | `references/phases/phase-c-freeze.md` |
| **D** | KMM-ification (abstract Android deps + `git mv` `androidMain` → `commonMain` for files that ripen this session) | `migration.md` | `references/phases/phase-d-migration.md` |
| **E** | Baseline promotion (`git mv` baseline `androidUnitTest` → `commonTest` for files whose code reached `commonMain`) | `move.md` | `references/phases/phase-e-move.md` |
| **F** | Validation (build, tests, smoke, manual QA) | `validation.md` + `heatmap.md` | `references/phases/phase-f-validation.md` |
| **G** | PR Creation | `pr.md` | `references/phases/phase-g-pr.md` |

Read phase references **on demand** — when the workflow enters or resumes a phase, before executing its sub-phases. This keeps context focused on the current work.

**Cross-phase references:**

- `references/test-discipline.md` — authoritative testing rules (per-file-type checklists, denylist, MockK templates, kotlin.test patterns, broken-test quarantine). Loaded by Phase B (mandatory) and consulted by any phase that touches test code (D foundation, E commonTest promotion, F regression checks).
- `references/expect-actual-boundaries.md` — design-vocabulary for choosing the right common/platform seam (`expect`/`actual` vs interface, semantic common APIs, thin actuals, Compose interop guidance, red flags). Loaded by Phase A (per-file seam strategy) and Phase D (D.0 foundation setup).

**Phase E is conditional.** If no in-scope file reached `commonMain` by end of Phase D (intentional `androidMain` landings throughout), Phase E is skipped — baselines stay in `androidUnitTest` as their final destination this session. A future session can promote when code ripens.

---

## Special actions (anytime, user-invoked)

- **Abandon session.** User invokes `abandon session`. Skill prompts for **session retro first** (see below) — friction signal matters most from abandoned sessions. Then asks: revert changes / keep but archive? Confirms. Removes session folder, optionally `git worktree remove`. Branch left for user to handle.
- **Update scope.** Post-Phase-0, user wants to add/remove files. Phase 0 re-runs in update-mode: re-walks deps from new files, re-classifies, re-confirms. Affected later-phase files reset (audit/freeze/migration entries removed for newly out-of-scope files; new entries added for newly in-scope).
- **Update project.md manually.** User invokes; skill shows current contents; user proposes change; diff-confirm; write.
- **Resume.** Implicit on every invocation in an in-flight session. Self-audit on resume catches drift before continuing.
- **Session retro.** Fires automatically after Phase G PR opens, or as the first step of `abandon session`. Skill asks the user four short questions and writes responses to `.kmm/migrations/kmm/<feature>-<depth>/retro.md`:
    1. **What went smoothly?** (workflow steps, automation, decisions that landed cleanly)
    2. **What got stuck?** (skill or reference fell short, repeated clarifications, gates that didn't fit)
    3. **What would have helped?** (missing example, tighter rule, new gate, clearer phrasing, new reference section)
    4. **Workflow rules to promote.** Haiku scans the session's decision logs and self-review notes for general workflow rules (tool choices, edit discipline, ordering reflexes) that recurred as user-feedback or course-correction. Sonnet drafts each as a candidate skill-file edit. User marks each `skill` / `drop`. `skill` candidates are routed to the relevant file (cross-cutting in SKILL.md if global to the skill, the relevant phase reference if phase-specific), diff-confirmed, written. This is the skill's own learning loop — distinct from Rule of three (which targets project.md for KMM patterns specific to the repo).
  
  Bullet points, not essays. Diff-confirm before writing. Purpose is structured friction signal for the next skill iteration — not a postmortem. The user can skip with `skip retro`, but the default is to capture. Across sessions, `retro.md` files accumulate as the maintenance backlog for the skill itself.

---

## When in doubt

The skill enforces workflow. Project facts are asked, never assumed. Decisions trigger transparency. Migrations preserve behavior. Tests are the contract. Phases proceed in order. **If a path forward isn't obvious, surface to the user — never improvise around a gate.**
