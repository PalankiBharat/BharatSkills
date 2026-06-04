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

3. **Migration done means done — and iOS readiness is designed in, not patched in.** "Migrated" means the file lives in `commonMain` and is iOS-consumable as-is via SKIE — no `TODO`s, `FIXME`s, stub `expect`/`actual` impls, or deferred work. A file relocated to `androidMain` is **not migrated**; it's a structural intermediate awaiting future migration (Phase D this session, or a future session). If full correctness in `commonMain` isn't achievable this session, the file is **held back from `commonMain`, not partially migrated**. The iOS-consumption surface is assessed at **Phase A planning**, not discovered at Phase F validation — Phase A carries the iOS-readiness lens per file (sourced from fresh searches, never training recall); Phase F only verifies what A designed. When iOS consumption demands a minimal signature change (e.g., callback param → sealed return shape), Android adapts to the new shape — but the bar is **iOS-blocker, not iOS-polish**. The skill is an orchestrator, not an encyclopedia: it cites, it doesn't know.

4. **Transparent decisions for non-trivial work.** Anything beyond mechanical substitution gets researched (web + codebase scan), planned with Opus, and discussed with the user before proceeding. Nothing surprises the PR reviewer because nothing surprised the user during the work. Existing codebase patterns are reference, not source of truth — propagate only what's clean.

---

## Cross-cutting rules

### Decision routing & question discipline — NON-NEGOTIABLE

This is the operating posture for every choice the skill makes. It governs *which* decisions reach the user and *how* they're framed.

**Goals anchor (the lens for every self-made decision).** clean migration; no KMM antipatterns; no unneeded refactoring; no unneeded improvisation over production code; post-migration code is clean and long-term maintainable. We migrate for long-term maintainability, not to tick a box. Every auto-decision is made *toward this outcome* — never toward whatever is fastest or easiest to implement.

**Self-review before asking.** Before surfacing any question, the skill asks itself: *"does the user actually need to decide this, or is it straightforward enough to decide myself?"* Route to the user **only** for high-impact calls — anything that materially affects the migration, changes observable behavior, or where a locked-in dependency/plan turns out not to work (examples, not a closed list). Everything straightforward, the skill decides itself and proceeds.

**Never auto-decide the highest-impact, hardest-to-reverse class (general rule).** Decisions in this class are *always* presented to the user, even when they look straightforward. **Dependency change / replacement / version decisions are the canonical example — never auto-answered**, regardless of how mechanical the swap appears.

**Transparent auto-decisions.** When the skill decides something itself, it **shows the decision and its one-line reasoning visibly** (not buried in a subagent dispatch or a file write), so the user can interrupt and redirect. Silent auto-decisions are not allowed — visibility is what makes smart-routing safe.

**Question framing (when the skill does ask).** Plain, scannable language for **both the problem and the options** — no jargon in chat-facing text. State: (1) the problem and its impact, (2) each option and its impact, (3) the skill's evidence-based pick and why. Technical depth lives in the phase file or an in-conversation explanation if the user asks — never in the chat-facing option labels.

> **Plain-language example.** Don't write: *"Q3: ctor param vs snapshot semantics — forced ripple to 2 VM consumers via FQN update; recommend Option B."* Write: *"The checksum class currently figures out live-vs-practice mode by itself. To share it, that decision has to move out. Option A keeps it on the class (but then iOS can't build it cleanly); Option B passes the answer in when the class is created (2 callers in the app need a one-line update). I recommend B — it's the clean long-term shape and the ripple is tiny."*

This rule changes the skill's default cadence: **fewer, higher-quality questions; more transparent auto-decisions biased toward the correct long-term outcome.** See also Principle #4 and the Non-trivial decision protocol below.

**Batch independent decisions into one turn.** When several choices are pending within a phase and they aren't interdependent, surface them **together** — don't serialize one-per-turn, each gated by its own research/recon pass. Sequential single-decision round-trips were a major wall-clock sink (base shape, strings, scope, biometric were each asked on separate turns). Bundle what can be bundled.

**When the user delegates a decision, research and RECOMMEND — never re-offer the same menu.** If the user bounces a choice back (*"you decide / what's canonical / what's more maintainable?"*), that is a request for an evidence-based recommendation, not a re-prompt. Do the research, then come back with a pick + reasoning. Re-offering the identical option list is the failure mode (it happened twice in one phase).

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

### Smart subagent routing — NON-NEGOTIABLE

The orchestrator and the subagents have **disjoint** responsibilities. The orchestrator decides, dispatches, and synthesizes; subagents read, write, and edit. **The orchestrator does not author or edit code itself**, ever — every Write / Edit / NotebookEdit / mutating Bash invocation that touches a file under version control goes through a dispatched subagent. This rule is what keeps Opus-time spent on judgment and parallelism free to compound.

**Orchestrator role (Opus, main thread).** Reads the active phase reference + active phase output file + project.md. Makes decisions. Synthesizes across files. Dispatches subagents (in parallel when work units are independent). Relays verdicts to the user. **Never** writes/edits code; **never** runs a mutating shell command when a subagent can.

**Subagent role (dispatched, never the main thread).** Every Write / Edit / multi-file scan / test authoring / migration step / `git mv` / package update / commit-message draft / compile-fix iteration / mutation + revert / structured-field fill.

| Category | Subagent model | When |
|---|---|---|
| Mechanical | Haiku subagent | File reads, denylist scans, filetype heuristics, gradle output parsing, template fills, log parsing, `git mv` operations, structured-field fills, single-line edits the orchestrator could "obviously" do itself but must not |
| Bounded judgment | **Sonnet subagent — default for all code writes/edits** | Checklist scoring, baseline test writing, breakage mutations, self-review, verdict prose, per-file analysis, routine compile-error fixes, commit-message composition, package updates, foundation actual impls per platform |
| High-stakes code authoring | Opus subagent (escalation) | Feature-surface baselines, concurrency-heavy Interactor tests, multi-source-cache Repository tests, state-machine Presenter tests, consolidated `expect`/`actual` interface declarations, drafter for first-time detekt bootstrap, complex Phase D substitutions where live-search is needed |
| Cross-file synthesis + final decisions | Opus orchestrator (main thread) | Phase A cross-file synthesis, Phase D migration ordering, DI plan synthesis, risk-register dedup, Phase D plan flips (`migrate` → `hold`), `expect`/`actual` ≥2-consumer enforcement, blocker-loop categorisation, Opus review of detekt-rule draft. **Decision output only — any resulting code lands via a subagent.** |

**The four non-negotiables:**

1. **No code from the orchestrator.** Every Write / Edit / NotebookEdit lands via a subagent. If the orchestrator needs a one-line edit, it still dispatches a Haiku subagent. The orchestrator's tool budget on the main thread is read-only + dispatch + decision-recording into the active phase's own output file (which is allowed to be edited directly per the read-many exceptions).
2. **Parallel by default.** Independent units of work — per-file baselines in a batch, per-platform `actual` impls, per-host parity audits, per-file consumer-import updates — are dispatched in a **single message with multiple subagent tool calls**. Sequential dispatch is reserved for work that genuinely depends on prior subagent output (compile-fix loops where iteration N+1 needs iteration N's build state, dep-graph walks where layer N+1 depends on layer N).
3. **Subagent failure ⇒ another subagent.** When a dispatched subagent dies, times out, returns garbled output, hits a permission denial, or refuses, the orchestrator **dispatches another subagent** (same model retry, or escalate the model). The orchestrator NEVER continues the failed subagent's work in the main thread. This is the silent-degradation mode that has historically turned a Sonnet-grade parallel batch into Opus-doing-labor-sequentially.
4. **Parallel-not-worth-it is still subagent-mediated.** When parallelism wouldn't pay back the dispatch cost (single-file fix, sequential dependency, a unit too small), the orchestrator still dispatches **one** subagent — it does not pick up the work itself. The choice is "parallel subagents vs one subagent", never "subagent vs orchestrator."

Discipline anchor: **Opus only when cost-of-being-wrong is high, AND only as a subagent for code authoring.** Default-everything-Sonnet wastes Opus depth on routine work; default-everything-Opus burns time and tokens on mechanical tasks; Opus-orchestrator-doing-code-itself burns BOTH while serializing what should have been parallel.

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

**Path precision.** When a file's exact path is already known, give the subagent that path **verbatim** — never dispatch a *searching* subagent to re-find it (false-negative risk: a search subagent once reported "not found" for a file that existed, derailing the conclusion). A small, known file may be read directly on the main thread per the single-file exception above — a searching subagent is for *discovery*, not for re-locating something whose path you hold.

**Why this matters.** Context degrades performance. A 5–9h session that reads every phase file into main and every cached search result into main fills the window with stale or low-relevance content, crowding out the current decision. The infinite-exploration failure mode — *"investigate X"* → read 50 files → context full → quality drops — is real. Subagent-mediated reads cap each exploration at its summary cost.

### Subagent-mediated execution (write-many = subagent, parallel by default) — NON-NEGOTIABLE

Symmetric to the read-many rule: **the main thread does not write code.** Every Write / Edit / NotebookEdit that touches a version-controlled file under the migration's scope goes through a dispatched subagent (per the Smart subagent routing table). Independent writes go out in a **single message with multiple subagent dispatches** — parallel is the default, sequential is the exception that must be justified by a dependency.

**Triggers (always dispatch — never main thread):**
- Batch of file writes (per-file baselines, foundation interfaces, per-platform `actual` impls, package-rename across consumers).
- Each iteration of a compile-fix loop (one fix = one subagent dispatch; the loop is sequential by build dependency but the work inside each iteration is not orchestrator work).
- Commit-message composition (Sonnet subagent per commit; the orchestrator decides *when* to commit, the subagent composes *what* the message says).
- Mutation + revert proofs (Phase B.5 red-on-breakage): one subagent per file, parallel across files.
- `git mv` runs (Haiku subagent, parallel per file).
- Detekt-rule drafting (Sonnet subagent), detekt-config edits, build.gradle source-set tweaks (Haiku/Sonnet subagent depending on judgment surface).
- Any prose write that's longer than a paragraph and lands in a phase file's per-file entry (audit verdicts, migration log entries, decision-log rationales). Short timestamped one-liners into the active phase's *own* output file are exempt (see below).

**Exceptions (orchestrator may write directly):**
- The active phase's own output file (`scope.md`, `plan.md`, `audit.md`, `migration.md`, etc.) for **short structured updates** — status flips, task-checkbox ticks, one-line decision-log entries. Long per-file entries and audit-prose blocks still go to a subagent.
- `.kmm/project.md` is governed by its diff-confirm protocol — orchestrator drafts the diff, user accepts, write happens. No subagent needed (the gate is the user).

**No concurrent co-editing of a living phase file.** Never have a writer-subagent and the orchestrator (or two writer-subagents) editing the **same** living phase file in one window — concurrent appends stale the on-disk content and fail subsequent Edits (a prior session burned a sub-loop on this). Serialize writes to a given phase file, and **re-read it immediately before each Edit**. Use **ASCII-only `old_string` anchors** — em-dash / ellipsis / arrow / emoji in the anchor break exact-match and silently fail the edit.

**Failure → another subagent.** Same rule as the routing non-negotiables. If a write-subagent dies / refuses / returns broken output, the orchestrator dispatches another (same or escalated model). It does NOT pick up the half-finished write itself — that silent degradation is the failure mode this rule exists to prevent.

**Why this matters.** Parallel subagent dispatch is what lets a multi-file batch land in one orchestrator turn instead of N. Orchestrator-does-it-itself collapses the batch into sequential work AND burns the most expensive model on Sonnet-grade labor. The routing table tells you *which* subagent; this rule tells you that *some* subagent always handles the write.

### Output economy

The skill's job in the chat is to drive the workflow, not to recite artifacts.

- **File writes**: one-line acknowledgment + path (`Wrote XTest.kt — 4 cases, all red`). Never paste the contents.
- **Test bodies, code diffs, full file contents**: never reproduced in chat unless the user explicitly asks (`show me`, `paste the file`).
- **Search results / cache contents**: subagent returns a summary; main chat preserves that abstraction. Don't unfold the raw cache into chat.
- **Commits**: announce one-liner (`Committed: <subject>`), no diff dump.
- **Subagent output**: surface decisions and verdicts; don't relay the subagent's intermediate reasoning.

Brevity is the contract. If the user wants to inspect, they open the file or invoke a deliberate "show me" — the default is silent and pointer-only.

**Value-driven, abstract presentation (as the migration runs).** Keep the main-context screen as clean as possible — the user must not be bombarded with text across a multi-hour session. Every chat turn leads with **signal**: what happened, what it means, what's next — abstracted over detail. Don't narrate steps, don't pad with reassurance, don't restate the plan. A sub-phase that completed cleanly is one line. The user can ask for any detail on demand; the default is the short, value-first version. Optimize for signal, not word count or polish.

### Context budget — phase boundaries

At the end of each phase, the skill **may suggest** the user open a new session for the next phase — but **only when ACTUAL context usage is high (~>60%)**. State is fully serialized in `.kmm/migrations/kmm/<feature>-<depth>/`; `resume_session.py` picks up at the next phase.

**Gate on actual usage only — never on a subjective sense of "heaviness."** Do NOT trigger the suggestion from a feeling that the conversation is long, nor from subagent-dispatch volume — both mis-fired repeatedly (a single session suggested breaks at 27% / 37% / 45%, each corrected by the user via `/context`). If actual usage is below the threshold, continue; say nothing about a break. Suggestion, not a cutoff. Phrasing: *"Context is at ~X%. Want to continue Phase X in a fresh session? State is saved; re-invoke the skill in a new chat."* — user can decline and continue. Skip the suggestion entirely when the next phase is trivially small (Phase E with zero promotions, Phase G PR-only).

### Tooling discipline

Reflex defaults that govern tool choice. These are not preferences — they shape the skill's output and are non-negotiable.

- **Context7 first for library/SDK/API specifics.** Library APIs, SDK signatures, framework configuration syntax — Context7 is primary. Web search is secondary, for community patterns and antipatterns. Training-data API recall is not allowed. Cache results at `.kmm/searches/<topic-hash>.md`; reuse if ≤ 30 days old; auto-invalidate past that (TTL configurable in `project.md`). **Cache reads go through a subagent** (per Subagent-mediated exploration) — the cache is for cross-session reuse, not main-context bloat.
- **Web search for patterns and approaches.** *"How do people handle X in KMM?"* — community wisdom for architectural decisions, not API specifics. Parallelize Context7 + web search when both kinds of input are needed for the same decision.
- **iOS Swift interop is a first-class search axis at Phase A — equal footing with KMM-pattern search.** Per file-type in scope, fetch fresh (Context7 + web) and cache: SKIE consumption examples, Swift-side call-site shapes, iOS pitfalls for the dominant idiom (suspend, Flow, sealed return, callback param, etc.). Same 30-day cache, same subagent-mediated reads. **The skill never bakes SKIE patterns into its references** — interop knowledge moves too fast; it's cited per session, not enshrined.
- **Regular `import` first; `import ... as Alias` only on collision.** Bring symbols in via normal import. When two imports collide on short name, alias one. Never inline the FQN at the call site — it's noisy and hides the dependency from the import list.
- **`git restore <path>` over reverse-edits.** For any tracked-file undo, use git's restore. Manually reverting via str_replace is error-prone and skips git's history checks. **Caveat — staged-rename SUTs (Phase D/E git-mv'd files):** on a staged-rename-with-unstaged-edits, `git restore`/`git checkout <path>` brings back the **old pre-move blob**, not the working-tree content — silently corrupting a migrated file. Before mutating such a file (e.g. a B.5 red-on-breakage proof on a relocated SUT), snapshot the working-tree content first (`cp` or `git stash`) and restore **that** — never `git checkout` a migrated file.
- **A failed read is a hard red flag — never fabricate from it.** A Read/Grep returning "file does not exist", or a subagent reporting "not found", means **re-verify the path** (`git ls-files` / `grep`) before *any* conclusion. NEVER infer, scaffold, or fabricate file contents from a missing read — surface the miss instead. (A wrong-path read once produced a fabricated scaffold written into plan.md, costing two corrections.)
- **No code comments unless WHY is non-obvious — and then, only a one-liner.** Comments explaining WHAT the code does are noise; the code is the source of truth. Comments explaining WHY (constraint, business rule, non-obvious gotcha) are allowed but must be a single line. No block comments, no multi-line explanations.
- **Gradle output via `tee` or `> file; ec=$?`, never `| tail`.** A `cmd | tail -N` invocation reports `tail`'s exit code (always 0), masking gradle failures. Use either `cmd 2>&1 | tee /tmp/gradle.log; ec=${PIPESTATUS[0]}` (preserves stream-through-tail while capturing real exit code) or `cmd > /tmp/gradle.log 2>&1; ec=$?; echo --exit:$ec--` (silent until done, then echo status). `set -o pipefail` at the top of a script also works but isn't portable to one-shot Bash tool invocations. **This also covers background-task / wrapper exit codes:** a trailing `echo` (or any command) placed *after* gradle resets `$?` to that command's status, masking a failed build as exit 0. Capture `ec` immediately after gradle, then `echo` — never the reverse.
- **Gradle execution discipline (timeout, serialization, KSP).**
  - **Hard timeout-with-grace on every phase gradle call.** Wrap each invocation so it can't hang for hours on a pathological test: `timeout --kill-after=<grace> <cap> ./gradlew …` (SIGTERM at the cap, SIGKILL after the grace), then `./gradlew --stop` to clear daemons. Per-task ceilings: `assemble` ~30m, unit-test ~20m, compile-only ~10m. Directly closes the hours-long-hang failure mode.
  - **Serialize heavy gradle.** Never launch a 2nd gradle build while one is running in the same or a sibling worktree — they share the daemon + build-dir and contention produces stuck workers + missing JUnit XML + unrecorded exit codes. One build at a time.
  - **Room/KSP modules.** Default `-Pksp.incremental=false`, or auto-retry once on `Number of loaded files in snapshots differs` — that's a known KSP incremental-cache bug (exposed by `clean`), not a code failure; don't diagnose it as one.
- **"BUILD SUCCESSFUL" is not proof tests ran — verify execution + counts via JUnit XML.** Gradle suppresses test counts in console output, and a cached / `UP-TO-DATE` task prints `BUILD SUCCESSFUL` *without running anything*. After any test task, confirm the tests actually executed and read their counts from `build/test-results/<task>/*.xml` (testsuite `tests`/`failures`/`skipped` attributes). This is the companion to the `--rerun-tasks` false-green rule (Phase D D.1 step 6): `--rerun-tasks` forces execution, JUnit-XML parsing *confirms* it happened.
- **Verify a library/SDK's KMM availability from its published Gradle module metadata — never infer from the `:app` consumption site.** Whether a dependency can move to `commonMain` is determined by its published artifacts: the `.module` metadata / an `iosSimulatorArm64` (or `iosArm64`/`iosX64`) klib in `~/.gradle/caches`, or `./gradlew :<dest>:dependencyInsight --dependency <lib>`. How the Android app currently consumes it tells you nothing about iOS availability. (Repeated failure mode: `mobilenetworkingsdk` was misclassified Android-only three times across two sessions; the gradle-cache klib proved it KMM-published each time.) See Phase A sub-phase 3 for the hard gate that enforces this.

### Non-trivial decision protocol (principle #4)

**Triggers:**
- Adding new files to commonMain (interfaces, helpers, abstractions).
- Library substitutions with semantic differences.
- Concurrency / threading model decisions.
- Multiple plausible `expect`/`actual` shapes.
- ≥2 reasonable approaches exist with downstream impact.
- Migrated-file public surface that Swift will consume — proposed shape lacks a cited interop precedent, or an iOS-blocker requires a signature change that ripples to out-of-scope callers.

**Protocol:**
0. **Ask first — does the user already have a known-good approach?** Before launching any deep research on a sub-problem, ask: *"Do you already have a proven / known-good approach for this?"* A single cheap question can short-circuit a whole research branch — a prior session ran full Context7 + web + a 2-subagent investigation on a biometric crypto question the user then made moot by handing over the proven solution.
1. **Live research (parallel Sonnet)** — Context7 for API specifics, web search for patterns + antipatterns; codebase scan for prior similar solutions (reference, not gospel — propagate only what's clean).
2. **Opus planning** — generates 2–3 plausible approaches; pros/cons; fit with project conventions (per project.md); risk to equivalence; states its lean and why.
3. **Verify-before-offering (NON-NEGOTIABLE).** Before any option reaches the user, the orchestrator **self-verifies every subagent-reported API/library/module fact the options rest on** — read the actual signature from source, confirm the module boundary (a cross-module `internal` is useless to a `commonTest` in another module), confirm the library version exists and fits the repo's Kotlin version. An option built on an unverified claim is not presented. *Why: across two sessions, users wasted whole decision rounds choosing options that turned out impossible — a Hilt approach that failed at compile on an untested KSP edge case, and the N1 fix that needed three rounds because each option's infeasibility surfaced only after a subagent tried it. The cost of a quick self-verify (read one file, check one boundary) is tiny next to a wasted round-trip.*
4. **Present to user** — plain-language problem + options + impacts + the skill's evidence-based pick and why (per Decision routing & question discipline above). Asks for thoughts.
5. **Discuss** — substantively engage; don't just defer.
6. **Log** — in active phase's decisions log: problem, options considered, choice, rationale. Audit trail for PR reviewers.
7. **Proceed.**

Trivial decisions (apply plan.md substitution; single obvious compile fix) — skill self-decides, **shows the call + one-line reasoning per the transparent-auto-decision rule**, and logs to the decisions log. User can interrupt; isn't blocked. (Dependency change/replacement/version decisions are **never** trivial — always routed to the user per the general rule above.)

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

**Pure per-repo facts are captured INLINE at discovery — never deferred to retro/session-end.** The moment the skill recognizes a fact that belongs *purely* in `project.md` (a module name, host constant, build-config access scope, the canonical flavored gradle task, an iOS-sim name, "SDK X is KMM-published", a final-class testability gap, the squash-merge policy, etc.), it **drafts the `project.md` addition via the diff-confirm gate right then** — shows the user exactly what's being added (apply / edit / reject) and writes it on accept. Capturing at discovery time means later phases in the same session benefit immediately, instead of rediscovering the same fact. **It is also logged in `retro.md` tagged `[project.md]`** — the inline write handles the value now; the retro note lets the separate skill-improvement session decide whether the fact also implies a `[skill]` pattern. For `[both]`-type findings, write the per-repo *value* inline; the *pattern* side stays in retro for the skill session. This does not need the rule of three — a per-repo fact is worth recording on first sighting.

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
- **Orchestrator mediation (the hook does NOT fire on subagent tool calls).** PreToolUse hooks cover the main thread, but **subagents do all editing in this workflow** — so a subagent's edit to a frozen/`migrated`/`promoted` baseline lands *without* the guard firing (observed in a prior session). The orchestrator therefore mediates: **before dispatching any subagent to touch a frozen-status baseline, it first creates or confirms the `.kmm/exceptions/*.md` file listing that baseline under `Authorizes.baseline-edit`.** No frozen-baseline edit is dispatched without the exception already in place. The hook remains the main-thread backstop; the orchestrator's pre-dispatch check is the real gate.
- **Human enforcement** via reviewer attention on the PR diff. No CI assumed; no CODEOWNERS dependency.

### Late-change discipline (post-completion) — NON-NEGOTIABLE

**Any change that arrives after a phase is "done" routes through the workflow — it is never live-patched.** Code-review feedback (Phase H), parity-QA bugs (Phase I), and any late tweak the user requests after the migration looks finished all follow the same discipline as the migration itself: **failing test first** (proving the bug/gap), **fix**, green, **migration-exception file if observable behavior shifts**, **proper commit**, and a **retro entry**. No ad-hoc edits, no fix-looping through variants until something sticks, no undocumented "while we're here" changes.

The failure mode this closes: in a prior session, changes made *after* the migration was declared complete were neither documented nor covered by a test — they bypassed every safety the workflow exists to provide. The fix is structural: **Phases H and I are the structured intake** for late changes, and because every such change carries a retro entry, the skill keeps learning from review/QA findings instead of silently absorbing them.

This applies whenever the skill is active — *it does not matter when the change arrives*. If a change surfaces mid-phase that belongs to an earlier gate (a baseline edit, a new file, a behavior shift), it goes through that gate's process, not around it. When the right process isn't obvious, surface to the user (per §When in doubt) — never improvise around a gate.

### Hooks (deterministic enforcement)

The skill ships two Claude Code hooks in `hooks/` at the plugin root. They convert the highest-stakes invariant (frozen-baseline edits) and the most context-expensive workflow step (resume) into mechanical operations.

| Hook | Trigger | Behavior |
|---|---|---|
| `resume_session.py` | SessionStart | If cwd is in a `kmm/<feature>-<depth>` worktree with a matching `.kmm/migrations/kmm/<feature>-<depth>/` folder, reads every phase file and emits a structured state report (per-phase status table, active phase + next pending task, recent decisions, working-tree-dirty flag) into the initial context. Raw phase files are NOT pulled into main context — the hook does the extraction. Silent on non-`kmm/` branches. |
| `frozen_baseline_guard.py` | PreToolUse on `Write\|Edit\|MultiEdit\|str_replace\|create_file` | Reads session `coverage.md` to determine baseline status **and to resolve where this session's baselines actually live** — it keys off the baseline-path column rather than a hardcoded `androidUnitTest`/`commonTest` regex, so it protects baselines in the **baseline-in-place** layout (`:app/src/test/…`, Phase B variant) too. Blocks writes to any baseline in status `frozen` / `migrated` / `promoted` unless a `.kmm/exceptions/*.md` file lists it under `Authorizes.baseline-edit`. Exit code 2 (with explanation) on block. |

Hooks are configured via `hooks/hooks.json` and reference `${CLAUDE_PLUGIN_ROOT}` so they work uniformly across worktrees.

**Why these two.** Frozen-baseline edits are the single most damaging silent-bypass mode (corrupts the equivalence safety net the entire workflow exists to maintain), so it gets full deterministic blocking. Resume context cost was the biggest single context-budget leak in a long session (10 phase files × ~100 lines × growing-as-living-documents), so it moves to deterministic extraction at session start.

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

**Gitignore-collapse case (now the canonical setup).** When `.kmm/migrations/` is gitignored (the default — session working state is local-only) AND the code was already committed progressively, **there is no audit commit at all** — `audit.md` / `coverage.md` / `freeze.md` live only in the working tree and never enter git. The cadence collapses to one (code) commit, or to a single empty marker commit where one is structurally required (the Phase C freeze SHA — see below). **Do not manufacture an empty commit just to satisfy "commit 2"**, and do not try to `git add` a gitignored audit file (it will silently no-op or error). Both prior sessions re-derived this each time; it is expected, not an anomaly.

**Never use `git commit -am` or `git add -A` in the two-commit cadence.** Both bypass file selection: `-am` stages every tracked change, `-A` adds all (including new) files. Use `git add <explicit paths>` between the code commit and the audit commit so commit 2 receives only `audit.md` / `coverage.md` / `phase-d-followups.md` and nothing else. The Sonnet commit-message subagent's command template uses explicit-path adds; never aggregating flags.

**Phase C exception — three commits on first-time detekt bootstrap.** The freeze SHA recorded in `freeze.md` + `coverage.md` is the SHA of the freeze commit itself; that SHA can't be self-referenced inside its own commit. When C.2 (bootstrap) runs, the cadence is three commits: (1) bootstrap commit (detekt config + custom rules) → (2) freeze marker commit (baseline tests; SHA becomes the frozen-at marker) → (3) audit commit (`freeze.md` + `coverage.md` with the SHA from commit 2 baked in). On repeat Phase C runs (no bootstrap), the standard two-commit cadence applies. See `phase-c-freeze.md`.

**Opt-out**: user passes `commit-cadence: manual` in Phase 0. Skill switches to proposing commands instead of running them. Default is autopilot.

### Universal hard gates (every phase)

- Phase predecessor must be complete (status field).
- Writes to `.kmm/project.md` go through the diff-confirm pre-write checklist.
- Scope-creep traceability gate enforced at every action.
- **State-serialization gate (BLOCKING, non-negotiable).** A phase cannot transition to the next until its `.kmm/` state is fully current. This is enforced at the *source*, not reconciled afterward: task checkboxes are ticked **as each unit commits** (a phase file showing `complete` with unchecked boxes is a defect), `coverage.md` reflects each file's real status and paths (e.g., Phase D flips `frozen → migrated` the moment code lands in `commonMain` — see phase-d), and every living-document section is written. Nothing advances on a stale ledger. The `resume_session` hook's status/checkbox-mismatch warning is a *backstop only*; the drift must not occur in the first place.
- **Retro gate (BLOCKING, non-negotiable).** The per-phase retro runs before the phase closes. There is **no `skip retro` affordance**, and the skill does **not** ask "should I do the retro?" — it just captures it (see Special actions → Per-phase retro). Same for the session-end consolidation step: it runs (its *writes* to `.kmm/project.md` remain diff-confirmed, but the step itself is not skippable). **`Status: complete` MUST NOT be written while the phase's retro checkbox is still unchecked** — the retro is part of closing the phase, not an afterthought. A `complete` status with an uncaptured retro is a defect (it recurred twice across sessions); the `resume_session` status/checkbox-mismatch warning is only a backstop.
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
        ├── validation.md           # Phase F (automated checks + smoke; no manual-QA gate)
        ├── heatmap.md              # Phase F — QA checklist artifact (embedded into the PR body at Phase G)
        ├── pr.md                   # Phase G — phase artifact (audit wrapper; never the --body-file source)
        ├── pr-body.md              # Phase G — the raw PR body shipped via --body-file
        ├── review.md               # Phase H — code-review intake + per-finding resolution log
        ├── qa.md                   # Phase I — parity-QA hand-off + bug-fixing log (kmm-qa-autopilot invocation + PR link)
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
- `networking.json_config` — the single shared `kotlinx.serialization` `Json` instance every server decode goes through (Gson→kotlinx migrations must route through this one, never ad-hoc `Json {}`; see migration-baselines.md §"Gson → kotlinx.serialization"):
  - `object_name`: `<name of the shared Json instance / factory + its path>`
  - `lenient_flags_confirmed`: `<bool — isLenient + coerceInputValues + ignoreUnknownKeys + explicitNulls=false all set, reproducing Gson's leniency>`
- `git.base_branch` (optional) — the repo's PR base branch (`master` / `main` / `develop`). Detected at runtime if absent via `git symbolic-ref refs/remotes/origin/HEAD`.
- `git.pr_merge_policy` — `squash | merge | rebase`. Drives Phase F.4's pre-merge integration simulation: a squash-merge repo is validated with `git merge origin/<base>` (the true PR simulation), NOT a rebase — a rebase replays intermediate commits and produces spurious conflicts on files the branch relocated that the base also touched at the old path. Conflict detection must use the same operation that will integrate.

The skill defines what slots exist; each repo's `project.md` fills them in. The skill itself contains no per-repo identifiers.

**coverage.md (per session) columns:** File, Type, Phase D plan (`migrate` / `hold`, decided Phase A), Baseline path (initial — always `<dest>/androidUnitTest/...`), Trust score, Status (`relocated` → `audited` → `frozen` → `migrated` → `promoted`), Frozen-at SHA, Final code path (`<dest>/commonMain/...` if migrated, `<dest>/androidMain/...` if held), Final baseline path (`<dest>/commonTest/...` if promoted, else initial).

---

## Preconditions

- JVM + gradle.
- Git ≥ 2.5 (worktree support).
- Android SDK configured.
- macOS + Xcode toolchain for full iOS verification (non-macOS hosts get limited iOS checks; flagged in D / E / F).

## Realistic expectations

A non-trivial migration session takes **5–9 hours end-to-end**, distributed across phases (mostly waiting on gradle). Fully resumable — start one day, continue the next. **Parity QA is no longer inside this skill** — Phase F runs automated checks plus a runtime-crash smoke and the PR opens at Phase G. After the PR, **Phase H ingests external code-review feedback** and resolves blockers through the workflow, then **Phase I hands off to the `kmm-qa-autopilot` skill** (run separately with the PR link) for behavioral parity QA and fixes any QA bug through the workflow. Review feedback and QA bugs are never live-patched (see §Late-change discipline); both are structured intakes that carry their own retro.

---

## Phases — overview

The migration runs through 10 phases. **Load the relevant phase reference file when entering or resuming a phase**, not all upfront.

| Phase | Purpose | Output | Reference |
|---|---|---|---|
| **0** | Discovery & Scoping | `scope.md` | `references/phases/phase-0-discovery.md` |
| **A** | Diagnostic — architectural plan (incl. per-file Phase D plan: migrate to `commonMain` this session, or hold at `androidMain`) | `plan.md` | `references/phases/phase-a-diagnostic.md` |
| **B** | Structural relocation + Baseline Coverage Audit & Write (relocate-first **or** baseline-in-place — Phase B chooses) | `audit.md` | `references/phases/phase-b-baseline.md` |
| **C** | Freeze | `freeze.md` | `references/phases/phase-c-freeze.md` |
| **D** | KMM-ification (abstract Android deps + `git mv` `androidMain` → `commonMain` for files that ripen this session) | `migration.md` | `references/phases/phase-d-migration.md` |
| **E** | Baseline promotion (`git mv` baseline `androidUnitTest` → `commonTest` for files whose code reached `commonMain`) | `move.md` | `references/phases/phase-e-move.md` |
| **F** | Validation — automated checks (build, baseline tests JVM+iOS, pre-merge integration, code-quality/iOS-surface) + runtime-crash smoke + heatmap draft. **No manual-QA gate.** | `validation.md` + `heatmap.md` | `references/phases/phase-f-validation.md` |
| **G** | PR Creation (heatmap embedded as a checklist in the PR body's QA section; concise, value-driven body) | `pr.md` + `pr-body.md` | `references/phases/phase-g-pr.md` |
| **H** | Receive & Resolve Review — ingest external code-review feedback on the PR, resolve blockers *through the workflow* (test + exception + commit + retro), user-approval gate to proceed | `review.md` | `references/phases/phase-h-review.md` |
| **I** | Parity-QA + Bug-fixing — hand off to `kmm-qa-autopilot` (works off the PR git diff + heatmap); fix any QA bug through the workflow. Final phase. | `qa.md` | `references/phases/phase-i-qa.md` |

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

Retro fires at the **end of each phase** (Phase 0 through Phase I) and is a **BLOCKING, non-negotiable gate** — the phase does not close without it. There is **no skip affordance**, and the skill does **not** ask "should I do the retro?"; it just captures it and moves on. It is **purely reflective** — concise dump of friction signal. No skill/drop verdicts, no promotion candidates, no in-session decisions. Decisions about what to promote into the skill happen in a **separate planning session** that consumes retro.md (user opens a fresh session in the skill repo, enters plan mode, drops retro.md content into context, walks through improvements collaboratively, edits skill files there). Migration sessions stay focused on migration.

**File:** `.kmm/migrations/kmm/<feature>-<depth>/retro.md`, **amended** with a new section per phase. Header format: `## Phase X — <name> (captured YYYY-MM-DD)`.

**Per-phase contents** — five short bullet sections, scannable:

1. **Phase recap** (1–2 lines) — what was accomplished this phase (e.g., scope count, key library substitutions chosen, baselines green, files migrated). Lets a future skill-improvement session understand context without re-reading the migration session.
2. **What went smoothly** — workflow steps that landed cleanly, subagent dispatches that paid off, decisions that compounded.
3. **What got stuck** — gates that didn't fit, repeated clarifications, deps surfaced late, classpath gaps, subagent context drops.
4. **What could improve the skill** — concrete refinements (e.g., "auto-inject resolved decisions into per-file subagent prompts", "Phase 0 should scan SUT classpaths upfront"). One line per item. **Each bullet is prefixed with a destination tag:** `[skill]` (general workflow lesson, promotes to the skill in a later iteration session), `[project.md]` (per-repo fact specific to this codebase; e.g., a module name, host constant, build-config access scope), `[both]` (pattern that needs a per-repo slot — skill gets the pattern, project.md gets the value). Model proposes the tag at write-time; user overrides at retro accept. Litmus test: if the bullet contains proper nouns specific to this repo → at minimum `[both]`, more often `[project.md]`; if pure pattern with no proper nouns → `[skill]`.
5. **User steering log** — every moment in the phase where the user manually corrected, redirected, or guided the model. Highest-signal section — these are exactly where the skill failed to anticipate. One line per entry: `<verbatim or close paraphrase of user steering> — context: <what model was doing>`. The skill self-tags these during the phase (mental note: "user just steered me here, log at retro") so retro-time scan doesn't have to recover them from full context. Examples to capture: "no", "don't", "stop", "actually", "wait", "do X instead", or any non-trivial direction change the user introduced.

**Format discipline:** Bullets, not essays. Concise but self-contained — a separate session reading retro.md (without the original migration conversation) should understand what happened and what could improve. No drama. Pure signal.

The retro is captured automatically as part of closing the phase — it is not optional and is not gated behind a user prompt (per the Retro gate in §Universal hard gates).

### Session close-out (after Phase I retro) — safety-net sweep

Per-repo facts are written to `project.md` **inline at discovery** throughout the session (see Rule of three → "Pure per-repo facts are captured INLINE"). So by close-out, most `[project.md]` values are already in `project.md`. This step is therefore a **safety-net sweep**, not the primary extraction path:

1. **Scan `retro.md`** for every `[project.md]` and `[both]`-tagged bullet across all phases.
2. **Diff each against current `project.md`** — for any value that was NOT already written inline (missed at discovery), draft the addition into the appropriate canonical field (see §project.md canonical fields). For `[both]` bullets, draft only the per-repo value portion (the pattern side belongs in a separate skill-iteration session).
3. **Diff-confirm gate** — present any remaining additions via the standard `.kmm/project.md` diff-confirm prompt (apply / edit / reject). User decides per block. (Usually empty, because inline capture already handled them.)
4. On accept, write to `project.md` and commit (`project.md` update + retro consolidation marker in `retro.md`).
5. `[skill]` and `[both]` bullets remain in `retro.md` for the separate skill-iteration planning session to consume — they are NOT extracted into the skill from inside a migration session.

This step runs automatically and is **not skippable** — only its *writes* to `.kmm/project.md` remain gated behind the diff-confirm prompt. It's **silent when the inline captures already covered everything** (the common case).

---

## When in doubt

The skill enforces workflow. Project facts are asked, never assumed. Decisions trigger transparency. Migrations preserve behavior. Tests are the contract. Phases proceed in order. **If a path forward isn't obvious, surface to the user — never improvise around a gate.**
