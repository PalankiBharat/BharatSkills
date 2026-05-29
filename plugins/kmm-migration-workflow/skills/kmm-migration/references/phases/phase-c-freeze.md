# Phase C — Freeze

**Purpose.** Lock baseline tests as the immutable equivalence contract. From this point, baselines can only be edited via the migration-exception process. First Phase C in a repo bootstraps detekt enforcement; subsequent runs reuse it.

After the first-time detekt bootstrap, subsequent Phase C runs are short — verify, freeze commit, update coverage, smoke test, write transcript.

**Inputs:** `scope.md`, `plan.md`, `audit.md` (all complete), `project.md`, `coverage.md`.

---

## Sub-phases

### C.1 — Verify Phase B is complete

**Haiku** reads `audit.md` status; checks all B-tasks done; verifies baseline suite is green per B.7 recorded output.

Refuses to proceed on any gap:
- Relocation incomplete — any in-scope file still in `:app/src/main/`.
- Broken-test quarantine incomplete — any pre-existing broken test from Phase 0's list not `@Ignore`'d.
- Incomplete audit — any in-scope file without a verdict.
- Missing red-on-breakage proof — any new or rewritten test without recorded mutation + revert.
- Baseline failure — `<dest>/androidUnitTest` not green.
- Feature-surface baseline absent without opt-out rationale.

### C.2 — Enforcement bootstrap (first-time per repo only)

**Triggered if `project.md.enforcement_setup.detekt_bootstrapped` is `false` or absent.** If `true`, skipped entirely (subsequent Phase C runs reuse the bootstrap). Skill checks the structured field, not prose — see SKILL.md §project.md canonical fields.

The only mechanical enforcement is a detekt rule that catches stack-drift in `<dest>/androidUnitTest` (and later `<dest>/commonTest`). The skill's own refusal to edit frozen baselines without a migration-exception file (SKILL.md cross-cutting) is the behavioral enforcement layer; reviewer attention on PR diffs is the human layer. No CODEOWNERS dependency; no pre-commit / commit-msg hook.

#### C.2.1 — Pre-flight detekt scan (Haiku)

Before drafting anything, Haiku produces a structured 4-field report. The drafter consumes this verbatim — no rediscovery:

```
detekt_scope: project-wide | :<module>-only | <list of modules>
test_source_set_exclusions: <list of glob patterns currently excluded, or "none">
custom_rules_jar:
  present: <bool>
  path: <path-or-null>
  settings_gradle_inclusion: included | commented-out | absent
detekt_version: <version-string-or-null>
```

Plus: **scope.md's "Legacy / non-target test source sets" list** (populated at Phase 0 step 10) is read and passed forward as proposed exclude paths for the new rule.

#### C.2.2 — Draft the detekt rule extension (Sonnet subagent)

Drafts per `test-discipline/migration-baselines.md` denylist:
- Fail on imports: `io.mockk.*` (MockK — baselines use hand-rolled fakes), `org.mockito.*`, `com.google.common.truth.*`, `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`, `org.junit.After`, `androidx.test.*`, `androidx.compose.ui.test.*`, `org.robolectric.*`, `java.time.*`, `java.util.Date`.
- Fail on usage: `@get:Rule`, `@Rule`, `System.currentTimeMillis()`, `System.nanoTime()`, `Thread.sleep(`, `MainCoroutineRule`, `mockk<`, `mockk(`, `every {`, `coEvery {`, `verify {`, `coVerify {` (MockK API surface).
- Scope: applies to `<dest>/androidUnitTest` and `<dest>/commonTest` (baseline source sets). `:app/src/test/` is exempt — JVM-only stack lives there.
- Excludes: every path in scope.md's "Legacy / non-target test source sets" list is added as an exclude glob.

**Drafter checklist — non-negotiable:**
- Every rule entry MUST carry its own `active: true`. detekt 1.23+ does NOT cascade parent `style.active: true` (or any category-level `active`) to child rules. A rule without an explicit `active: true` is silently disabled regardless of any enclosing block.
- ForbiddenImport rules use the `imports:` list correctly (one entry per pattern, with `reason:` populated — the reason string surfaces in the user's failure output and is the difference between "what just happened?" and "oh, baselines can't import MockK".)
- The forbidden-usage checks (`Thread.sleep`, `@Rule`, `mockk(`, etc.) extend the existing `customRules.jar` if present (per C.2.1's detection); otherwise propose a custom rule via the project's existing pattern — never silently introduce a new jar mechanism.

#### C.2.3 — customRules jar rebuild workflow (consult and capture)

Triggered by C.2.1's `custom_rules_jar` field. Action depends on detected state:

- **`settings_gradle_inclusion: included`** → module is permanently included; rebuilds happen as part of normal gradle invocation. Skill notes this in `project.md` as `enforcement_setup.custom_rules_rebuild: module-permanently-included`. No further work.
- **`settings_gradle_inclusion: commented-out`** → repo has a deliberate dance (temporary include → build → copy jar → re-comment) or a one-shot script. Skill asks the user explicitly which pattern this repo uses; captures the answer (and path to any script) in `project.md` as `enforcement_setup.custom_rules_rebuild: one-shot-script` with the script path or `other` with a description.
- **`absent`** → no customRules module exists. Skill proposes adding the forbidden-usage checks via the existing detekt config (YAML rules only) for this iteration; flags as a follow-up to introduce a custom-rules module if usage checks beyond YAML reach are needed.

The pattern is captured per repo; subsequent Phase C runs read it from `project.md` and skip the discussion.

#### C.2.4 — Opus review (project-wide, durable)

Opus reviews the draft — project-wide and durable. Mistakes here corrupt every future migration.

**Opus prompt MUST include the verification clause:** *"For any claim about a file, directory, gradle task, or jar path existing or not existing — verify against the filesystem with `ls` / `find` / `./gradlew tasks` before asserting. Reasoning from the gradle config alone is not sufficient; configs and disk can disagree."*

Opus also explicitly verifies the per-rule `active: true` discipline (drafter checklist above): every rule listed in the YAML carries its own `active: true`. BLOCKING on any missing entry.

#### C.2.5 — User confirms; record state

On acceptance, `project.md.enforcement_setup` is populated per the canonical schema (see SKILL.md §project.md canonical fields):
```
enforcement_setup:
  detekt_bootstrapped: true
  detekt_config_path: <path>
  custom_rules_jar_path: <path-or-null>
  scope: project-wide | :<module>-only | <list>
  custom_rules_rebuild: module-permanently-included | one-shot-script | other (describe)
```

### C.3.0 — Baseline-location vs detekt-scope check (FIRST — explicit, not model-derived)

Before the smoke test, reconcile *where this session's baselines live* (from `coverage.md`'s baseline-path column) against *what detekt actually scans* (`project.md.enforcement_setup.scope`). On the **baseline-in-place** path baselines sit in `:app/src/test/`, which is typically **outside** detekt's configured scope — so a smoke test passing "in scope" would give false assurance about *this session's* baselines.

- **If the session's baselines fall inside detekt scope** → proceed to C.3 normally.
- **If they fall outside** → choose (surfaced to the user with the recommendation): (a) **extend detekt scope** to cover the session's baseline source set, or (b) **document the residual gap** in `freeze.md` plus the compensating layers (skill-behavioral refusal + `frozen_baseline_guard` hook reading coverage.md paths + reviewer attention + Phase E relocation into a scanned set). Record the decision; don't leave it implicit.

### C.3 — Detekt smoke test (BEFORE freeze commit)

**Non-negotiable.** Verifies the detekt rule actually bites — runs while baselines are still at status `audited` so the `frozen_baseline_guard` hook does not block the deliberate mutation edit.

- **Sonnet creates a scratch file in a detekt-scoped source set** (e.g., `<dest>/src/androidUnitTest/.../scratch/DetektSmokeProbe.kt`) with a forbidden import — `import io.mockk.mockk` (MockK is banned in baseline source sets; Mockito works too). **Prefer a scratch file over mutating an existing baseline** — mutating a real (possibly already-frozen, from a prior session) baseline risks the hook blocking it and is needless. If C.3.0 chose to keep baselines outside detekt scope, the scratch file goes in a *scoped* set so the smoke still proves the rule fires.
- Runs `./gradlew :<dest>:detekt` (or project-specific task per `project.md`). Captures output via the discipline in SKILL.md Tooling discipline (`tee` or `> file; ec=$?`, never `| tail`).
- Expected: detekt failure citing the denylist rule for that import.
- **Haiku** parses output, confirms the failure type matches.
- **Sonnet** removes the scratch file (`rm` / `git restore`). Verifies clean state.
- Records proof in `freeze.md` (forbidden import added, detekt output, revert, clean) — plus, if relevant, the C.3.0 scope decision and residual-gap note.

If the smoke test passes when it should have failed → detekt enforcement is broken. Phase C halts; user notified.

The skill's behavioral refusal to edit frozen baselines is not smoke-testable mechanically — it's a gate the skill follows at every write (see SKILL.md cross-cutting Migration-exception process).

### C.4 — Freeze this session's baselines

- All baseline test files for in-scope files (in `<dest>/src/androidUnitTest/`) committed atomically.
- **Sonnet** composes the commit message — references the session, lists files frozen, aggregates trust scores from audit.md.
- **Resulting commit SHA = frozen-at marker** for this session.
- Optional: tag the commit (e.g., `baseline-funds-business-logic-2026-05-13`) — user's call, asked once.

**Commit cadence — see SKILL.md §Commit cadence for the Phase C exception.** On a repeat Phase C (no C.2 bootstrap), the standard two-commit cadence applies: this is commit 1 (code), C.5 is commit 2 (audit). On a first-time C.2 bootstrap, the cadence is three commits: bootstrap commit (detekt config + custom-rules artifact, from C.2) → freeze marker commit (this step) → audit commit (C.5). The freeze SHA cannot be self-referenced inside its own commit; that's why C.5's `freeze.md` + `coverage.md` flips must land in a separate commit AFTER the freeze marker SHA exists.

### C.5 — Update coverage.md + write freeze.md (audit commit)

- In-scope files flip from `audited` to `frozen` with the freeze SHA (sourced from C.4's commit).
- **Haiku** fills structured sections of `freeze.md` (file table, SHA, dates, trust scores from audit.md).
- **Sonnet** writes prose for `freeze.md`: decisions log, smoke test narrative, customRules rebuild workflow note (if applicable).
- Silent write (per SKILL.md Diff-confirm scope — `migrations/` writes are not gated).
- Committed as the audit half of the cadence (two-commit or three-commit per above).

### C.6 — Phase C retro
Amend `retro.md` with `## Phase C — Freeze (captured YYYY-MM-DD)`. Five-bullet structure per SKILL.md (each "What could improve the skill" bullet tagged `[skill]` / `[project.md]` / `[both]`). **Blocking, non-skippable** (per SKILL.md Retro gate).

---

## Output: `freeze.md`

- Header (status, tasks)
- Frozen-at commit SHA + optional tag
- Files frozen (path, type, baseline path, trust score, SHA)
- Detekt enforcement bootstrap status (skipped if pre-existing; logged with C.2 sub-step results if first-time set up)
- Pre-flight scan result (C.2.1's 4-field report verbatim, if C.2 ran)
- customRules rebuild workflow (captured pattern + script path, if applicable)
- Per-rule `active: true` verification (Opus result from C.2.4)
- Detekt smoke test results (forbidden import added + caught + reverted) — note: ran at C.3, BEFORE the freeze commit, so the hook doesn't block the mutation edit
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase B complete (`audit.md` status = complete; baselines green per B.7).
- **Detekt enforcement** verified working via smoke test — **no exceptions**.
- Frozen-at SHA recorded in both `freeze.md` and `coverage.md` before Phase D can start.
