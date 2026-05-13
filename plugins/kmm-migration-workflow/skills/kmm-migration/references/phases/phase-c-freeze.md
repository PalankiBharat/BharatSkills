# Phase C — Freeze

**Purpose.** Lock baseline tests as the immutable equivalence contract. From this point, baselines can only be edited via the migration-exception process. First Phase C in a repo bootstraps enforcement (CODEOWNERS, detekt, optional pre-commit hook); subsequent runs reuse it.

After the first-time enforcement bootstrap, subsequent Phase C runs are short — verify, freeze commit, update coverage, smoke test, write transcript.

**Inputs:** `scope.md`, `plan.md`, `audit.md` (all complete), `project.md`, `coverage.md`.

---

## Sub-phases

### C.1 — Verify Phase B is complete

**Haiku** reads `audit.md` status; checks all B-tasks done; verifies baseline suite is green per B.5 recorded output.

Refuses to proceed on any gap: incomplete audit, missing red-on-breakage proof, baseline failure, feature-surface baseline absent without opt-out rationale.

### C.2 — Enforcement bootstrap (first-time per repo only)

Triggered if `project.md` indicates enforcement isn't set up. Otherwise skipped entirely.

- **Haiku** scans the repo for existing `CODEOWNERS`, detekt config.
- **Sonnet** drafts additions:
  - **CODEOWNERS:** `app/src/baselineTest/ @<migration-tech-lead>` — user supplies the handle.
  - **Detekt rule extension** per `test-discipline §12` denylist:
    - Fail on imports: `org.mockito.*`, `com.google.common.truth.*`, `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`, `org.junit.After`, `androidx.test.*`, `androidx.compose.ui.test.*`, `org.robolectric.*`, `java.time.*`, `java.util.Date`.
    - Fail on usage: `@get:Rule`, `@Rule`, `System.currentTimeMillis()`, `System.nanoTime()`, `Thread.sleep(`, `MainCoroutineRule`.
    - Warn on `verify(` and `mockk(...)` without `relaxed = false`.
  - **Optional pre-commit hook** for baseline edits without `[migration-exception <id>]` in commit message. User opts in; not mandatory.
- **Opus** reviews the drafts — project-wide and durable. Mistakes here corrupt every future migration.
- User confirms each draft.
- On acceptance: `project.md` updated with `enforcement_setup: true` + paths to the relevant config files.

### C.3 — Freeze this session's baselines

- All baseline test files for in-scope files committed atomically.
- **Sonnet** composes the commit message — references the session, lists files frozen, aggregates trust scores from audit.md.
- User runs `git commit` (skill proposes the exact command + confirms before running).
- Resulting commit SHA = **frozen-at marker** for this session.
- Optional: tag the commit (e.g., `baseline-funds-business-logic-2026-05-13`) — user's call.

### C.4 — Update coverage.md

- **Sonnet** drafts the coverage.md diff: in-scope files flip from `audited` to `frozen` with the freeze SHA.
- Diff-confirm protocol — user accepts / edits / rejects.
- **Haiku** applies after confirmation.
- This update is committed alongside C.3 (or as an immediate follow-up commit; both belong to the freeze).

### C.5 — Enforcement smoke test

**Non-negotiable.** Verifies the freeze actually bites:

- **Sonnet** makes a trivial deliberate edit to a frozen baseline test (whitespace change, test method rename).
- Runs CODEOWNERS check + detekt locally + the pre-commit hook if installed.
- Expected: failure with migration-exception-required message.
- **Haiku** parses output, confirms the failure type matches.
- **Sonnet** reverts the deliberate edit.
- Records proof in `freeze.md`.

If the smoke test passes when it should have failed → enforcement is broken. Phase C halts; user notified.

### C.6 — Write freeze.md

- **Haiku** fills structured sections (file table, SHA, dates, trust scores from audit.md).
- **Sonnet** writes prose: decisions log, smoke test narrative.
- Living document, written progressively through C.1–C.5.

---

## Output: `freeze.md`

- Header (status, tasks)
- Frozen-at commit SHA + optional tag
- Files frozen (path, type, baseline path, trust score, SHA)
- Enforcement bootstrap status (skipped if pre-existing; logged if first-time set up)
- Smoke test results (deliberate edit attempt + caught + reverted)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase B complete (`audit.md` status = complete; baselines green).
- Enforcement mechanisms verified working via smoke test — **no exceptions**.
- `coverage.md` update diff-confirmed before write.
- Frozen-at SHA recorded in both `freeze.md` and `coverage.md` before Phase D can start.
- User confirmation on the atomic freeze commit.
