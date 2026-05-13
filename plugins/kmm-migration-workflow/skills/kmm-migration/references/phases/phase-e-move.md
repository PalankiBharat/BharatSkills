# Phase E — Move

**Purpose.** Relocate baseline tests from `app/src/baselineTest/` to `<destination>/src/commonTest/`. Tests were written in the KMM-portable stack (per `test-discipline §12`), so this is mechanical. Final integrity check: same tests green in the final architecture, against the migrated production code.

Phase E is mechanically simple — that's the prevention model paying off. Baselines were KMM-portable from the start, so moving them is `git mv` + verify, not rewrite.

**Inputs:** all prior session files (`scope.md` through `migration.md`, status complete), `project.md`, `coverage.md`.

---

## Sub-phases

### E.1 — Move via `git mv` (Haiku, parallel)

For each frozen baseline test file:
- `git mv app/src/baselineTest/.../X.kt <destination>/src/commonTest/.../X.kt`
- Content preserved bit-for-bit. History tracked.

### E.2 — Update package declarations (Haiku, parallel)

Match new source-set conventions per `project.md`.

### E.3 — Run tests in commonTest (Haiku)

`./gradlew :<destination>:commonTestKotlinJvm` (or project-equivalent task per profile). All tests must be green.

If anything fails: **Sonnet** investigates. Common causes:
- Stack edge case slipped past audit (Truth import, JUnit rule that wasn't caught).
- commonTest source-set dep missing.
- Migration mechanic side-effect — test references something that didn't migrate.

Fix via surgical edit (same `git mv`-then-fix discipline as Phase D — never read and rewrite). If unfixable cleanly → hold-back, test stays in `baselineTest`, flagged for next session.

### E.4 — Run tests in iosTest if host supports (Haiku)

`./gradlew :<destination>:iosSimulatorArm64Test` or equivalent target per profile. All green required.

**Strongest equivalence verification** — same baseline tests now running on the iOS runtime, against the migrated code.

If host doesn't support iOS testing (non-macOS dev machine): skill flags this clearly — full local verification is incomplete. **User decides handling** — test on a Mac, defer until team has access. Skill does not auto-defer to CI.

### E.5 — Update coverage.md (Sonnet drafts, Haiku applies)

For each moved file: status flips `frozen` → `migrated`; `migrated_to` field filled with the commonTest path. Diff-confirmed.

### E.6 — Write move.md

- **Haiku** fills structured sections (file moves table, test counts, commit SHA).
- **Sonnet** writes prose: any commonTest issues encountered, iOS test results.
- Living document, finalized at E.6 with status complete.

---

## Output: `move.md`

- Header (status, tasks)
- File moves table (old path → new path)
- commonTest run result (test count, all green)
- iosTest run result — or "deferred, host doesn't support iOS testing" with explicit user acknowledgment
- coverage.md updates summary
- Commit SHA
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase D complete (`migration.md` status = complete, integration verified).
- All baselines green in commonTest.
- All baselines green in iosTest (or explicit user acknowledgment of host limitation).
- `coverage.md` updated with `migrated` status per file.
- User confirms before commit.

---

## Post-session (outside Phase E, after PR merge)

After the PR merges to main:
- Skill offers `git worktree remove <path>` for cleanup.
- User confirms; skill runs.
- Branch `kmm/<feature>-<depth>` can be deleted (or kept as audit-trail tag).
