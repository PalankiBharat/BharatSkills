---
name: kmm-migration
description: Orchestrates structured Android-to-KMM migration with strict behavioral-equivalence safety. Discovers scope via the user's described navigation flow, writes baseline tests proving current Android behavior, freezes them, migrates code via `git mv` + surgical edits, validates on Android and iOS, produces a clean PR. Use this skill whenever the user wants to migrate any Android feature, screen, module, or specific files (ViewModel, UseCase, Repository, Mapper, etc.) to Kotlin Multiplatform / shared module — even if they only mention 'KMM', 'shared module', 'commonMain', or name a specific file/feature to migrate. Triggers on phrases like 'migrate the funds screen to KMM', 'KMM migration plan', 'baseline tests for migration', 'move this to shared', or any preparation/execution phrase. The skill enforces a prevention-first phased workflow with user-confirmed transitions; do not bypass it for ad-hoc migration work even when individual files look simple — bypass corrupts the equivalence safety net.
---

# KMM Migration Orchestrator

A workflow for migrating Android code to Kotlin Multiplatform without behavior surprises. The skill never re-derives KMM knowledge from training — patterns come from live web search, APIs come from Context7, project conventions live in `.kmm/project.md`. The skill's job is the **workflow**.

Testing rules for the whole workflow live in `references/test-discipline/` (split into `index.md` + per-file-type files, loaded on demand by Phase B and consulted by other phases when test code is touched — never loaded in bulk).

---

## Principles

1. **Behavioral equivalence + API stability.** The Android app is in production. Post-migration, the app behaves identically — same observable outputs, same method/class contracts. Callers untouched. Package paths may shift; that's a mechanical import update, not an API change.

2. **Two modes.** Migrating existing code: surgical, compiler-driven edits, minimal diff, no "improvements" smuggled in. Writing new code (interfaces, `expect`/`actual`, DI module): strict clean code, KISS, DRY. No `*Holder`/`*Manager`/`*Helper` cruft. New abstractions earn ≥2 consumers or get inlined.

3. **Migration done means done.** "Migrated" means the file lives in `commonMain` and is iOS-consumable as-is via SKIE — no `TODO`s, `FIXME`s, stub `expect`/`actual` impls, or deferred work. A file relocated to `androidMain` is **not migrated**; it's a structural intermediate awaiting future migration (Phase D this session, or a future session). If full correctness in `commonMain` isn't achievable this session, the file is **held back from `commonMain`, not partially migrated**.

4. **Transparent decisions for non-trivial work.** Anything beyond mechanical substitution gets researched (web + codebase scan), planned with Opus, and discussed with the user before proceeding. Nothing surprises the PR reviewer because nothing surprised the user during the work. Existing codebase patterns are reference, not source of truth — propagate only what's clean.

---

## Cross-cutting rules

### Diff-confirm protocol (scoped to `.kmm/project.md` only)

Writes to `.kmm/project.md` — the one cross-session, human-curated config file — are gated. The skill produces the diff-confirm prompt before any project.md write:

```
Proposed updates to .kmm/project.md:

[+] Add to <section>: <text>
[~] Update <section>:
    old: <text>
    new: <text>
[-] Remove from <section>: <text>

Apply all / edit / reject? [a/e/r]
```

User accepts (`a`), edits (`e`), or rejects (`r`). On accept, the write happens.

**All other `.kmm/` writes are silent** — session-local working state (`scope.md`, `plan.md`, `audit.md`, `coverage.md`, `freeze.md`, `migration.md`, `move.md`, `validation.md`, `heatmap.md`, `pr.md`, `phase-d-followups.md`, `retro.md`) and machine-managed caches (`searches/`, `exceptions/`) write without prompting. Migration speed depends on this; the gate exists only where edits ship across sessions.

Skill source files (the plugin's own `.md` files under `skills/kmm-migration/`) are **never edited from within a migration session**. Skill improvements happen in dedicated planning sessions that consume retro.md (see §Special actions → Per-phase retro).

### Smart subagent routing

| Category | Model | When |
|---|---|---|
| Mechanical | Haiku | File reads, denylist scans, filetype heuristics, gradle output parsing, template fills, log parsing, git mv operations |
| Bounded judgment | Sonnet | Checklist scoring, routine test writing, breakage mutations, self-review, verdict prose, per-file analysis, routine compile-error fixes |
| High-stakes / irreversible | Opus orchestrator | Feature-surface baselines, complex-file tests (concurrency-heavy Interactors, multi-source Repos with cache, state-machine Presenters), cross-file synthesis, hold-back decisions, non-trivial decision planning |

Discipline: **Opus only when cost-of-being-wrong is high.** Default-everything-Sonnet wastes Opus depth on routine work; default-everything-Opus burns time and tokens on mechanical tasks.

### Subagent-mediated exploration (read-many = subagent)

**Main context holds decisions and synthesis. Subagents hold raw inputs.** Any operation that reads more than one file — or reads a single large file purely to extract a small answer — goes through a subagent that consumes the raw content and returns a summary. The main thread receives the summary, not the files.

**Triggers (always dispatch to a subagent):**
- Codebase scans (`grep`, multi-file reads, dep-graph walks).
- Reading cached search results from `.kmm/searches/` to inform a current decision — Sonnet extracts only the bit relevant to the current question.
- Reading prior phase files during resume (see Resume protocol below).
- Reading sibling session `coverage.md` files for cross-session ripple lookups.
- Reading multiple per-type files from `references/test-discipline/` when a batch decision spans file types.
- Reading reference docs (`references/expect-actual-boundaries.md`, etc.) when only a specific sub-question is needed — Sonnet extracts the rubric's answer, not the whole rubric.

**Exceptions (main thread reads directly):**
- The single file currently being edited / migrated.
- The currently-active phase reference (one phase at a time).
- `project.md` (small, durable, repeatedly consulted — caching it in main is correct).
- The active phase's own output file (`scope.md`, `plan.md`, etc.) — the skill writes these progressively and must see their current state.

**Why this matters.** Context degrades performance. A 5–9h session that reads every phase file into main and every cached search result into main fills the window with stale or low-relevance content, crowding out the current decision. The infinite-exploration failure mode — *"investigate X"* → read 50 files → context full → quality drops — is real. Subagent-mediated reads cap each exploration at its summary cost.

### Output economy

The skill's job in the chat is to drive the workflow, not to recite artifacts.

- **File writes**: one-line acknowledgment + path (`Wrote XTest.kt — 4 cases, all red`). Never paste the contents.
- **Test bodies, code diffs, full file contents**: never reproduced in chat unless the user explicitly asks (`show me`, `paste the file`).
- **Search results / cache contents**: subagent returns a summary; main chat preserves that abstraction. Don't unfold the raw cache into chat.
- **Commits**: announce one-liner (`Committed: <subject>`), no diff dump.
- **Subagent output**: surface decisions and verdicts; don't relay the subagent's intermediate reasoning.

Brevity is the contract. If the user wants to inspect, they open the file or invoke a deliberate "show me" — the default is silent and pointer-only.

### Context budget — phase boundaries

At the end of each phase, if main context feels heavy (heavy reads this phase, several subagent dispatches with large returns, conversation already long), the skill **suggests** the user open a new session for the next phase. State is fully serialized in `.kmm/migrations/kmm/<feature>-<depth>/`; `resume_session.py` picks up at the next phase.

Suggestion, not a cutoff. Phrasing: *"This phase used a lot of context. Want to continue Phase X in a fresh session? State is saved; re-invoke the skill in a new chat."* — user can decline and continue. Skip the suggestion when the next phase is trivially small (Phase E with zero promotions, Phase G PR-only). Skill self-assesses; no token-count required.

### Tooling discipline

Reflex defaults that govern tool choice. These are not preferences — they shape the skill's output and are non-negotiable.

- **Context7 first for library/SDK/API specifics.** Library APIs, SDK signatures, framework configuration syntax — Context7 is primary. Web search is secondary, for community patterns and antipatterns. Training-data API recall is not allowed. Cache results at `.kmm/searches/<topic-hash>.md`; reuse if ≤ 30 days old; auto-invalidate past that (TTL configurable in `project.md`). **Cache reads go through a subagent** (per Subagent-mediated exploration) — the cache is for cross-session reuse, not main-context bloat.
- **Web search for patterns and approaches.** *"How do people handle X in KMM?"* — community wisdom for architectural decisions, not API specifics. Parallelize Context7 + web search when both kinds of input are needed for the same decision.
- **Regular `import` first; `import ... as Alias` only on collision.** Bring symbols in via normal import. When two imports collide on short name, alias one. Never inline the FQN at the call site — it's noisy and hides the dependency from the import list.
- **`git restore <path>` over reverse-edits.** For any tracked-file undo, use git's restore. Manually reverting via str_replace is error-prone and skips git's history checks.
- **No code comments unless WHY is non-obvious — and then, only a one-liner.** Comments explaining WHAT the code does are noise; the code is the source of truth. Comments explaining WHY (constraint, business rule, non-obvious gotcha) are allowed but must be a single line. No block comments, no multi-line explanations.
- **Gradle output via `tee` or `> file; ec=$?`, never `| tail`.** A `cmd | tail -N` invocation reports `tail`'s exit code (always 0), masking gradle failures. Use either `cmd 2>&1 | tee /tmp/gradle.log; ec=${PIPESTATUS[0]}` (preserves stream-through-tail while capturing real exit code) or `cmd > /tmp/gradle.log 2>&1; ec=$?; echo --exit:$ec--` (silent until done, then echo status). `set -o pipefail` at the top of a script also works but isn't portable to one-shot Bash tool invocations.

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

Resume is **driven by the `resume_session` SessionStart hook**, not by Claude-side logic. The hook runs once before Claude's first turn, reads phase files deterministically, and emits a structured state report (branch, per-phase status table, active phase, next pending task, recent decisions across phases, working-tree-dirty flag). The raw phase files are NOT read into main context.

What Claude does on resume:

1. Read the state report (already in context, courtesy of the hook).
2. Read `.kmm/project.md` directly (small, durable; main context).
3. Load **only the active phase's reference file** (per the report) and **only the active phase's output file** (e.g. `audit.md` if mid-Phase-B). Other phase files stay on disk; their state is already in the report.
4. Pick up at the next pending task identified by the report.

**Zero rediscovery, zero raw-file dump, no Haiku-resume subagent needed.** The hook makes the resume mechanical and deterministic.

**Off-path situations** (the hook handles these too):
- Non-`kmm/` branch → hook is silent, Claude starts fresh.
- `kmm/...` branch with no matching `.kmm/migrations/<feature>-<depth>/` folder → hook prints a "fresh session" hint pointing at Phase 0.
- No `.kmm/` initialized in the worktree → hook prints a "fresh worktree" hint pointing at Phase 0.

If the SessionStart hook didn't run for some reason (hook crashed, plugin not loaded), Claude falls back: detect branch via `git branch --show-current`; if `kmm/...` and folder exists, dispatch a **Haiku subagent** to read phase files and return the same state report (per the Subagent-mediated exploration rule — never bulk-read phase files into main).

### Rule of three (auto-promotion to project.md)

Patterns applied **≥3 times in the same session** become project.md promotion candidates. Detection: Haiku scans decisions logs for keyword + structural matches (e.g., `expect/actual + <same shape>` appearing in 3 entries). Sonnet drafts the addition. Diff-confirm to user. Single- or twice-applied patterns stay in session.

Setup facts (modules, DI framework, source-set wiring) captured on **first** occurrence via Phase 0 gap-fill — they're state, not patterns; rule of three doesn't apply.

Rule of three targets **KMM patterns specific to this repo** (project.md). General workflow rules that surfaced during a session (tool choices, edit discipline, ordering reflexes) get captured in `retro.md` per phase and reviewed in a separate skill-improvement planning session — they don't auto-promote.

### Scope-creep traceability gate

Every in-flight action must be traceable to a confirmed artifact. The skill halts when a planned action would:

- Create a new file not listed in `scope.md` and not pre-authorized by `plan.md` (foundation interface, expect/actual, fake, DI module).
- Make a structural gradle change (new module, new source set, new plugin) not specified in `plan.md`.
- Edit a file outside `scope.md` that isn't a consumer-import update of an in-scope file.

On halt, the skill presents three options:

1. **Extend scope** — invokes the existing `update scope` action; Phase 0 re-walks deps from the new file; affected later-phase files reset.
2. **Extend plan** — Phase A reopens to add the foundation/interface; logged in plan.md decisions log.
3. **Follow-up** — logged to `pr.md` "Out-of-scope follow-ups" section, not done this session.

The gate fires immediately at the point of attempted action, not at phase end. Untraceable work is treated as scope creep regardless of size — there is no numeric threshold.

### Migration-exception process

For intentional behavior changes during migration (library substitution semantics, timezone handling, JSON ordering):

- Exception file at `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` with: what changed, why, risk, user sign-off.
- Baseline edit references it: commit message contains `[migration-exception <id>]`.
- **Mechanical enforcement** via the `frozen_baseline_guard` hook (see Hooks below): writes to frozen baselines are blocked at the tool-call layer unless an exception file referencing the baseline exists. This converts the prior advisory rule into deterministic enforcement.
- **Human enforcement** via reviewer attention on the PR diff. No CI assumed; no CODEOWNERS dependency.

### Hooks (deterministic enforcement)

The skill ships two Claude Code hooks in `hooks/` at the plugin root. They convert the highest-stakes invariant (frozen-baseline edits) and the most context-expensive workflow step (resume) into mechanical operations.

| Hook | Trigger | Behavior |
|---|---|---|
| `resume_session.py` | SessionStart | If cwd is in a `kmm/<feature>-<depth>` worktree with a matching `.kmm/migrations/kmm/<feature>-<depth>/` folder, reads every phase file and emits a structured state report (per-phase status table, active phase + next pending task, recent decisions, working-tree-dirty flag) into the initial context. Raw phase files are NOT pulled into main context — the hook does the extraction. Silent on non-`kmm/` branches. |
| `frozen_baseline_guard.py` | PreToolUse on `Write\|Edit\|MultiEdit\|str_replace\|create_file` | Reads session `coverage.md` to determine baseline status. Blocks writes to any baseline in status `frozen` / `migrated` / `promoted` unless a `.kmm/exceptions/*.md` file references the baseline by name. Exit code 2 (with explanation) on block. |

Hooks are configured via `hooks/hooks.json` and reference `${CLAUDE_PLUGIN_ROOT}` so they work uniformly across worktrees.

**Why these two.** Frozen-baseline edits are the single most damaging silent-bypass mode (corrupts the equivalence safety net the entire workflow exists to maintain), so it gets full deterministic blocking. Resume context cost was the biggest single context-budget leak in a long session (8 phase files × ~100 lines × growing-as-living-documents), so it moves to deterministic extraction at session start.

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

Files are **living documents** — written progressively as work proceeds (batched per logical unit), not at phase end. Resume relies on this.

### Branch + worktree

- Branch naming: `kmm/<feature>-<depth>` (e.g., `kmm/funds-business-logic`, `kmm/funds-presentation`, `kmm/funds-full`).
- One branch = one session = one folder under `.kmm/migrations/`.
- Default worktree path: `../<repo-name>-<branch-suffix>/` — the `kmm/` prefix is dropped to avoid filesystem slashes. Configurable via `worktree_path_template` in `project.md`.
- Worktree creation does not end the invocation — skill `cd`s into the new worktree and continues Phase 0 in the same session.

### Commit cadence (autopilot)

Invoking the skill authorizes the workflow's commit cadence. Default rhythm per sub-phase: **up to two commits — code + audit**, both autopilot, both composed by Sonnet. Skill announces each as a one-liner (`Committed: <subject>`); no `[run/edit/hold]` prompt.

- **Commit 1 (code)** — test files, migrated source, `git mv` results, foundation interfaces.
- **Commit 2 (audit)** — `audit.md`, `coverage.md`, `phase-d-followups.md` updates. Conventional message: `chore(kmm): audit update — <sub-phase>`.

If a sub-phase produces only one kind of change, the cadence collapses to one commit. The rule is "up to two", not "exactly two".

**Never use `git commit -am` or `git add -A` in the two-commit cadence.** Both bypass file selection: `-am` stages every tracked change, `-A` adds all (including new) files. Use `git add <explicit paths>` between the code commit and the audit commit so commit 2 receives only `audit.md` / `coverage.md` / `phase-d-followups.md` and nothing else. The Sonnet commit-message subagent's command template uses explicit-path adds; never aggregating flags.

**Phase C exception — three commits on first-time detekt bootstrap.** The freeze SHA recorded in `freeze.md` + `coverage.md` is the SHA of the freeze commit itself; that SHA can't be self-referenced inside its own commit. When C.2 (bootstrap) runs, the cadence is three commits: (1) bootstrap commit (detekt config + custom rules) → (2) freeze marker commit (baseline tests; SHA becomes the frozen-at marker) → (3) audit commit (`freeze.md` + `coverage.md` with the SHA from commit 2 baked in). On repeat Phase C runs (no bootstrap), the standard two-commit cadence applies. See `phase-c-freeze.md`.

**Opt-out**: user passes `commit-cadence: manual` in Phase 0. Skill switches to proposing commands instead of running them. Default is autopilot.

### Universal hard gates (every phase)

- Phase predecessor must be complete (status field).
- Writes to `.kmm/project.md` go through the diff-confirm pre-write checklist.
- Scope-creep traceability gate enforced at every action.
- User confirmation gates transition to next phase (one-line acknowledgment, not a ceremony).

Phase-specific gates are listed in each phase's reference file.

---

## Directory layout

```
.kmm/
├── project.md                      # TRACKED — cross-session: reusable KMM knowledge for this repo
├── searches/                       # TRACKED — cross-session: cached live-search results (30-day TTL)
│   └── <topic-hash>.md
├── exceptions/                     # TRACKED — cross-session: migration-exception files
│   └── <YYYY-MM-DD>-<short-id>.md
└── migrations/                     # LOCAL-ONLY — gitignored, per-session working state
    └── kmm/<feature>-<depth>/      # mirrors branch path
        ├── scope.md                # Phase 0
        ├── plan.md                 # Phase A
        ├── audit.md                # Phase B
        ├── coverage.md             # session-local registry (audited → frozen → migrated → promoted)
        ├── phase-d-followups.md    # accumulator for SUTs deferred to Phase D + post-migration cleanups
        ├── freeze.md               # Phase C
        ├── migration.md            # Phase D
        ├── move.md                 # Phase E
        ├── validation.md           # Phase F
        ├── heatmap.md              # Phase F — QA checklist artifact
        ├── pr.md                   # Phase G
        └── retro.md                # Per-phase friction dump (see Special actions)
```

**Git tracking** — `project.md`, `searches/`, `exceptions/` are checked into the repo (they're reusable across sessions and across contributors). `migrations/` is gitignored via a top-level `.gitignore` entry (`.kmm/migrations/`) — session working state is local to whoever ran the migration. Phase 0 proposes this entry on first run in a repo if it's missing.

**project.md scope** — reusable KMM knowledge for this repo: modules + source-set hierarchy, DI framework + coexistence stance, persistence tech + schema locations, networking config (baseUrl, BuildKonfig), UI strategy (native vs CMP timeline), SKIE config, iOS consumption / distribution flow, manual QA workflow, test-infra wiring, conventions, hard-won gotchas. **Excludes:** migration state (lives in session folders), generic KMM how-tos (runtime lookup).

**project.md canonical fields** (populated as Phase 0 / Phase C / discovery surfaces them — schema defined by the skill, values are per-repo):

- `enforcement_setup` — Phase C detekt bootstrap state.
  - `detekt_bootstrapped`: `<bool>`
  - `detekt_config_path`: `<path>`
  - `custom_rules_jar_path`: `<path or null>`
  - `scope`: `project-wide | module-list`
  - `custom_rules_rebuild`: `<one of: module-permanently-included | one-shot-script | other; describe>` — how this repo produces the custom-rule jar (note: detekt 1.23+ does not cascade parent `active: true` to child rules; every rule entry must carry its own `active: true`).
- `networking.build_config_scope` — for each generated build-time config object (BuildKonfig / BuildConfig / equivalent):
  - `object_name`: `<name>`
  - `access`: `internal | module-private | public`
  - `app_layer_aliases`: `<list of public constant names + paths to consult when wiring DI providers in the app layer>`
- `networking.shared_client_config` — shared HTTP client config:
  - `object_name`: `<name of the shared client/config factory>`
  - `host_constant_convention`: `<e.g., per-flavor BuildKonfig fields named *_API / *_DNS / *_BASE_PATH>`
- `git.base_branch` (optional) — the repo's PR base branch (`master` / `main` / `develop`). Detected at runtime if absent via `git symbolic-ref refs/remotes/origin/HEAD`.

The skill defines what slots exist; each repo's `project.md` fills them in. The skill itself contains no per-repo identifiers.

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

- `references/test-discipline/` — authoritative testing rules. **`index.md`** (Toolbox, decision matrices, cross-cutting rules, file-level skeletons, Verification gates) is loaded whenever test code is touched. **Per-type files** (`viewmodels.md`, `usecases.md`, `repositories.md`, `remote-stores.md`, `local-stores.md`, `mappers.md`, `models.md`, `interactors.md`, `presenters.md`, `composables-pages.md`, `workers-receivers-services.md`) are loaded **only when a SUT of that type is in scope this session** — per Subagent-mediated exploration, never bulk-load. **`migration-baselines.md`** (the former §12 — denylist, KMM-portable stack rules, feature-surface pattern, quarantine, migration-exception process) is always loaded in Phase B alongside `index.md`. Used by Phase B (mandatory) and consulted by phases that touch test code (D foundation, E commonTest promotion, F regression checks).
- `references/expect-actual-boundaries.md` — design-vocabulary for choosing the right common/platform seam (`expect`/`actual` vs interface, semantic common APIs, thin actuals, Compose interop guidance, red flags). Loaded by Phase A (per-file seam strategy) and Phase D (D.0 foundation setup).

**Phase E is conditional.** If no in-scope file reached `commonMain` by end of Phase D (intentional `androidMain` landings throughout), Phase E is skipped — baselines stay in `androidUnitTest` as their final destination this session. A future session can promote when code ripens.

---

## Special actions (anytime, user-invoked)

- **Abandon session.** User invokes `abandon session`. Skill prompts for retro on the current in-flight phase first — friction signal matters most from abandoned sessions. Then asks: revert changes / keep but archive? Confirms. Removes session folder, optionally `git worktree remove`. Branch left for user to handle.
- **Update scope.** Post-Phase-0, user wants to add/remove files. Phase 0 re-runs in update-mode: re-walks deps from new files, re-classifies, re-confirms. Affected later-phase files reset (audit/freeze/migration entries removed for newly out-of-scope files; new entries added for newly in-scope).
- **Update project.md manually.** User invokes; skill shows current contents; user proposes change; diff-confirm; write.
- **Resume.** Implicit on every invocation in an in-flight session. Self-audit on resume catches drift before continuing.

### Per-phase retro

Retro fires at the **end of each phase** (Phase 0 through Phase G). It is **purely reflective** — concise dump of friction signal. No skill/drop verdicts, no promotion candidates, no in-session decisions. Decisions about what to promote into the skill happen in a **separate planning session** that consumes retro.md (user opens a fresh session in the skill repo, enters plan mode, drops retro.md content into context, walks through improvements collaboratively, edits skill files there). Migration sessions stay focused on migration.

**File:** `.kmm/migrations/kmm/<feature>-<depth>/retro.md`, **amended** with a new section per phase. Header format: `## Phase X — <name> (captured YYYY-MM-DD)`.

**Per-phase contents** — five short bullet sections, scannable:

1. **Phase recap** (1–2 lines) — what was accomplished this phase (e.g., scope count, key library substitutions chosen, baselines green, files migrated). Lets a future skill-improvement session understand context without re-reading the migration session.
2. **What went smoothly** — workflow steps that landed cleanly, subagent dispatches that paid off, decisions that compounded.
3. **What got stuck** — gates that didn't fit, repeated clarifications, deps surfaced late, classpath gaps, subagent context drops.
4. **What could improve the skill** — concrete refinements (e.g., "auto-inject resolved decisions into per-file subagent prompts", "Phase 0 should scan SUT classpaths upfront"). One line per item. **Each bullet is prefixed with a destination tag:** `[skill]` (general workflow lesson, promotes to the skill in a later iteration session), `[project.md]` (per-repo fact specific to this codebase; e.g., a module name, host constant, build-config access scope), `[both]` (pattern that needs a per-repo slot — skill gets the pattern, project.md gets the value). Model proposes the tag at write-time; user overrides at retro accept. Litmus test: if the bullet contains proper nouns specific to this repo → at minimum `[both]`, more often `[project.md]`; if pure pattern with no proper nouns → `[skill]`.
5. **User steering log** — every moment in the phase where the user manually corrected, redirected, or guided the model. Highest-signal section — these are exactly where the skill failed to anticipate. One line per entry: `<verbatim or close paraphrase of user steering> — context: <what model was doing>`. The skill self-tags these during the phase (mental note: "user just steered me here, log at retro") so retro-time scan doesn't have to recover them from full context. Examples to capture: "no", "don't", "stop", "actually", "wait", "do X instead", or any non-trivial direction change the user introduced.

**Format discipline:** Bullets, not essays. Concise but self-contained — a separate session reading retro.md (without the original migration conversation) should understand what happened and what could improve. No drama. Pure signal.

User can skip with `skip retro` — skill writes one "skipped" line for that phase and moves on.

### Session close-out (after Phase G retro)

Once the final phase retro is captured, the skill runs a one-shot consolidation step that prevents the skill from accumulating per-repo facts:

1. **Scan `retro.md`** for every `[project.md]` and `[both]`-tagged bullet under "What could improve the skill" across all phases.
2. **Draft proposed `project.md` additions** — one block per bullet, slotting into the appropriate canonical field (see §project.md canonical fields). For `[both]` bullets, draft only the per-repo value portion (the pattern side belongs in a separate skill-iteration session, not here).
3. **Diff-confirm gate** — present the proposed additions via the standard `.kmm/project.md` diff-confirm prompt (apply / edit / reject). User decides per block.
4. On accept, write to `project.md` and commit as a final two-commit cadence (`project.md` update + retro consolidation marker in `retro.md`).
5. `[skill]` and `[both]` bullets remain in `retro.md` for the separate skill-iteration planning session to consume — they are NOT extracted into the skill from inside a migration session.

This step is **silent for sessions that produced no `[project.md]` or `[both]` bullets** (the common case after the skill stabilizes). It runs automatically; user can skip with `skip consolidate`.

---

## When in doubt

The skill enforces workflow. Project facts are asked, never assumed. Decisions trigger transparency. Migrations preserve behavior. Tests are the contract. Phases proceed in order. **If a path forward isn't obvious, surface to the user — never improvise around a gate.**
