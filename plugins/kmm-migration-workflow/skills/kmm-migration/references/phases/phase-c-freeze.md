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

Triggered if `project.md` indicates enforcement isn't set up. Otherwise skipped entirely.

The only mechanical enforcement is a detekt rule that catches stack-drift in `<dest>/androidUnitTest` (and later `<dest>/commonTest`). The skill's own refusal to edit frozen baselines without a migration-exception file (SKILL.md cross-cutting) is the behavioral enforcement layer; reviewer attention on PR diffs is the human layer. No CODEOWNERS dependency; no pre-commit / commit-msg hook.

- **Haiku** scans the repo for existing detekt config.
- **Sonnet** drafts the **detekt rule extension** per `test-discipline/migration-baselines.md` denylist:
  - Fail on imports: `io.mockk.*` (MockK — baselines use hand-rolled fakes), `org.mockito.*`, `com.google.common.truth.*`, `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`, `org.junit.After`, `androidx.test.*`, `androidx.compose.ui.test.*`, `org.robolectric.*`, `java.time.*`, `java.util.Date`.
  - Fail on usage: `@get:Rule`, `@Rule`, `System.currentTimeMillis()`, `System.nanoTime()`, `Thread.sleep(`, `MainCoroutineRule`, `mockk<`, `mockk(`, `every {`, `coEvery {`, `verify {`, `coVerify {` (MockK API surface).
  - Scope: applies to `<dest>/androidUnitTest` and `<dest>/commonTest` (baseline source sets). `:app/src/test/` is exempt — JVM-only stack lives there.
- **Opus** reviews the draft — project-wide and durable. Mistakes here corrupt every future migration.
- User confirms.
- On acceptance: `project.md` updated with `enforcement_setup: true` + path to the detekt config file.

### C.3 — Freeze this session's baselines

- All baseline test files for in-scope files (in `<dest>/src/androidUnitTest/`) committed atomically.
- **Sonnet** composes the commit message — references the session, lists files frozen, aggregates trust scores from audit.md.
- User runs `git commit` (skill proposes the exact command + confirms before running).
- Resulting commit SHA = **frozen-at marker** for this session.
- Optional: tag the commit (e.g., `baseline-funds-business-logic-2026-05-13`) — user's call.

### C.4 — Update coverage.md

- **Sonnet** drafts the coverage.md diff: in-scope files flip from `audited` to `frozen` with the freeze SHA.
- Diff-confirm protocol — user accepts / edits / rejects.
- **Haiku** applies after confirmation.
- This update is committed alongside C.3 (or as an immediate follow-up commit; both belong to the freeze).

### C.5 — Detekt smoke test

**Non-negotiable.** Verifies the detekt rule actually bites:

- **Sonnet** adds a forbidden import to a frozen baseline test — e.g., `import io.mockk.mockk` (MockK is now banned in baseline source sets per the updated denylist; Mockito works too — pick either).
- Runs `./gradlew :<dest>:detekt` (or project-specific task per `project.md`).
- Expected: detekt failure citing the denylist rule for that import.
- **Haiku** parses output, confirms the failure type matches.
- **Sonnet** reverts via `git restore`. Verifies clean state.
- Records proof in `freeze.md` (forbidden import added, detekt output, revert, clean).

If the smoke test passes when it should have failed → detekt enforcement is broken. Phase C halts; user notified.

The skill's behavioral refusal to edit frozen baselines is not smoke-testable mechanically — it's a gate the skill follows at every write (see SKILL.md cross-cutting Migration-exception process).

### C.6 — Write freeze.md

- **Haiku** fills structured sections (file table, SHA, dates, trust scores from audit.md).
- **Sonnet** writes prose: decisions log, smoke test narrative.
- Living document, written progressively through C.1–C.5.

---

## Output: `freeze.md`

- Header (status, tasks)
- Frozen-at commit SHA + optional tag
- Files frozen (path, type, baseline path, trust score, SHA)
- Detekt enforcement bootstrap status (skipped if pre-existing; logged if first-time set up)
- Detekt smoke test results (forbidden import added + caught + reverted)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase B complete (`audit.md` status = complete; baselines green per B.7).
- **Detekt enforcement** verified working via smoke test — **no exceptions**.
- `coverage.md` update diff-confirmed before write.
- Frozen-at SHA recorded in both `freeze.md` and `coverage.md` before Phase D can start.
- User confirmation on the atomic freeze commit.
