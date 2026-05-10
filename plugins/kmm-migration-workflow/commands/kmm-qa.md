---
description: Systematic on-device QA + bug-fix loop for migrated KMM code. Builds the latest APK, installs on a chosen device, listens to logcat in background, and runs a test-first / no-silent-patch fix workflow when the user pinpoints a bug. Runs on any KMM project (skill-made migration or not). Distinct from /kmm-verify (completeness) and /kmm-audit (PR principle review).
argument-hint: "<session-or-scope-name?> [--rediscover]"
---

# /kmm-qa

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md`, `skills/kmm-migration-workflow/references/orchestration-protocol.md`, and `skills/kmm-migration-workflow/references/qa-mode.md` first.

QA mode runs the **same fix discipline** as the migration mode — architecture before code, understand before acting, baseline test first, verbatim diff spec, no silent patches. Lightweight per-bug ceremony (one entry in `bugs.md`), same protections.

This is **not** the verify phase (completeness) and **not** the audit (PR principle review). QA is hands-on device validation with structured fix workflow.

## When to invoke

- After `/kmm` opens a checkpoint PR and you want to validate the migrated code on a real device before merging.
- On any KMM project (with or without prior `/kmm` history) when systematic on-device debugging is needed.
- Mid-migration: pause `/kmm`, run `/kmm-qa` against the worktree, fix surfaced bugs, resume `/kmm`.

## Inputs

- `<session-or-scope-name>` — optional. If matches an existing `kmm/<scope>/` directory, anchors to that scope's worktree. Else treated as a standalone session name; bootstraps `kmm-qa/<session>/`.
- `--rediscover` — force re-detection of build / install / launch / logcat commands even if `qa-config.json` exists.
- The constitution (always loaded).
- `references/qa-mode.md` (always loaded for this command).

## Steps

### 1. Resolve the session anchor

| Argument | Resolution |
|---|---|
| `<name>` matches `<repo>/kmm/<name>/` | Anchor: `kmm-scope:<name>`. Worktree: `<repo>/.worktrees/kmm-<name>/`. Artifacts under `<repo>/kmm/<name>/`. |
| `<name>` does not match a scope | Anchor: `standalone`. Artifacts under `<repo>/kmm-qa/<name>/`. |
| No argument, exactly one in-flight `kmm/<scope>/` exists | Suggest anchoring to that scope; ask `[y / different / standalone]`. |
| No argument, no `kmm/` dir | Ask: "session name? (e.g., `qa-2026-05-10`)" |

If a session is being resumed (anchor dir already has `qa-config.json`), read it and skip step 2.

### 2. Discover commands (first invocation only, or on `--rediscover`)

Walk the discovery ladder per `references/qa-mode.md § Command discovery`:

1. Read `build.gradle.kts`, `settings.gradle.kts`, `app/build.gradle.kts` (or whichever module is the consumer). Pull `applicationId` / `namespace` and the consumer module name.
2. Read `AndroidManifest.xml` for default activity.
3. Run `./gradlew tasks --all 2>&1 | grep -iE "assemble|install"` to enumerate real gradle tasks. **Run; don't recall.** Constitution §4.
4. Run `adb devices` — enumerate connected devices.
5. Compose proposed `qa-config.json`.

Show the proposed config to the user in plain language:

```
Detected (please confirm or override):
  application id    : <com.example.app>
  consumer module   : :app
  default activity  : <com.example.app/.MainActivity>
  build command     : ./gradlew :app:assembleDebug
  build artifact    : app/build/outputs/apk/debug/app-debug.apk
  install command   : adb -s <serial> install -r <build_artifact>
  launch command    : adb -s <serial> shell am start -n <activity>
  logcat command    : adb -s <serial> logcat --pid=<runtime> -v threadtime

Devices connected:
  A) Pixel 7 emulator (api 33) — emulator-5554
  B) Samsung S22 (api 31) — RFCN20...

[A / B / discuss / edit-commands]
```

User picks device. Save to `qa-config.json`. Then ask install strategy default:

```
Between iterations, reinstalling the app:
A) Update — preserves data
B) Uninstall first — clears state
C) Ask each iteration
[A / B / C]
```

Save. Capture baseline SHA: `git rev-parse HEAD`. Initialise `bugs.md` from `templates/bugs.md`.

### 3. Run the QA loop

Per `references/qa-mode.md § The QA loop`. Numbered steps:

1. **Build.** Run `qa-config.build_command`. Failure → escalate to user; do not retry. (Build failure is upstream — the branch is broken. Mirror migration mode's `*_BLOCKED` rule.)
2. **Reinstall.** Per `install_strategy_default` or per-iteration ask.
3. **Launch.** Run `qa-config.launch_command`. Capture PID via `adb shell pidof <application_id>`. If app crashes immediately, treat as the first bug — go to step 6.
4. **Start logcat in background.** `Bash` with `run_in_background: true`. Save the bash_id. Log redirected to `<session-dir>/logcat.txt`.
5. **Wait for user pinpoint.** Print one line: `QA session live on <device>. Pinpoint an issue or say "done".`
6. **User pinpoints a bug.** Allocate `B-<n>`. Read last ~5 minutes of logcat (via `BashOutput` against the background bash_id). Filter to severity ≥ W and to the captured PID. Dispatch `qa-debugger` in `mode: diagnose` with bug-id, user description, logcat excerpt, session anchor, baseline SHA, paths to `qa-config.json` and `bugs.md`.
7. **Receive `QA_DIAGNOSE_COMPLETE`.** Read the proposed entry the agent appended to `bugs.md`. Status will be `PROPOSED`. Present to user in plain language:
   ```
   B-<n> (proposed fix):
     Where: <file>:<line>
     Why:   <root cause>
     Path:  surgical | refactor
     Fix:   <one-line summary>
     Test:  <test name — currently RED>
     [y / discuss / decline]
   ```
   - `y` → promote `PROPOSED` → `OPEN` in `bugs.md`. Continue to step 8.
   - `discuss` → unfold the full entry (raw logcat, full diff spec, full test body). Loop.
   - `decline` → mark `RATIFIED` with `note: user declined fix in this session`. Resume from step 5.

   **Refactor approval gate** (Constitution §7): if path is `refactor` and the refactor crosses files OR changes public API, dispatch `architecture-reviewer` against the proposed change before promoting `PROPOSED` → `OPEN`. Single-file internal refactors do not require this dispatch.

8. **Apply the fix.** Dispatch `qa-debugger` in `mode: apply-fix` with `bug-id`, `bugs-md-path`, `qa-config-path`, session anchor.
9. **Receive `QA_FIX_COMPLETE` or `QA_FIX_BLOCKED`.**
   - `COMPLETE` → mark entry `OPEN` → `FIXED` in `bugs.md` with `Fixed-at: <ISO>` and `Fixed-by-test: <test-fqn>`. Print one line: `B-<n> fixed.`. Resume from step 1.
   - `BLOCKED` → escalate. Do not silently retry. Append `Block-reason:` to the entry. Wait for user direction.
10. **User says "done".** Stop the background logcat process via `KillShell` on its bash_id. Print summary (iterations, bug counts by status, duration, path to `bugs.md`). Run constitution check (below). Stop.

### 4. Diagnostic-only mode (read-only QA)

If user invokes `/kmm-qa --diagnose-only`, run steps 1–7 but never apply a fix — every diagnose dispatch ends with the proposed entry written to `bugs.md` as `PROPOSED` and the orchestrator does not ask for approval. Useful for triage sessions where the user wants to enumerate bugs first and fix later.

### 5. Constitution check (at end of session)

Touched: §1, §2, §6, §7, §8, §9, §12.

Checklist:
- `[ ]` Every `FIXED` entry has both a `bugs.md` entry AND a passing test referenced by name
- `[ ]` Every `FIXED` entry has `verify-red=proven` recorded
- `[ ]` No `OPEN` entries left without `Block-reason`
- `[ ]` qa-config.json's `live_source_audit` records every command was observed (not recalled)
- `[ ]` No fix touched files outside the bug's named site without a `REQUIRES_APPROVAL` and explicit user approval recorded as a deviation
- `[ ]` No `@Suppress`, no `// TODO/FIXME`, no widened visibility introduced by any fix

### 6. Where artifacts live (final state)

| Anchor | Files |
|---|---|
| `kmm-scope:<scope>` | `<repo>/kmm/<scope>/qa-config.json`, `<repo>/kmm/<scope>/bugs.md`, `<repo>/kmm/<scope>/logcat.txt` |
| `standalone` | `<repo>/kmm-qa/<session>/qa-config.json`, `<repo>/kmm-qa/<session>/bugs.md`, `<repo>/kmm-qa/<session>/logcat.txt` |

`logcat.txt` is preserved for forensic reference. The orchestrator does not auto-commit any QA artifacts. The user decides whether QA artifacts go into the migration PR or stay local — typically `qa-config.json` and `bugs.md` are useful in the PR's audit trail; `logcat.txt` is local-only.

## What auto-routing DOES NOT skip

QA mode always pauses for:

- **Device choice** when multiple devices are connected.
- **Install strategy default** at session start.
- **Per-iteration install strategy** when default is `ask`.
- **Bug fix approval** at each `QA_DIAGNOSE_COMPLETE` (the `[y / discuss / decline]` gate).
- **Refactor approval gate** when a proposed fix is `Path: refactor` and crosses files or changes public API.
- **`REQUIRES_APPROVAL`** from `qa-debugger` (any interpretive escalation).

## Failure modes

- **`adb devices` returns nothing** — stop at session start. Tell user to start an emulator or plug in a device.
- **Build fails on first iteration** — the branch is broken upstream. Surface the gradle error. Do not auto-fix. The user decides whether to fix the upstream break first or scope QA to a different branch.
- **Build fails after a fix lands** — the fix introduced a compile error the test runner missed (rare, since `qa-debugger mode: apply-fix` runs per-target compile checks). Surface the error; the fix needs revisiting. Do not auto-revert; let the user decide.
- **App crashes on launch every iteration with the same crash** — same bug surface twice → after the 2nd identical crash, dispatch `qa-debugger mode: diagnose` against it instead of looping. Mirrors migration mode's "do not silently refire".
- **Logcat process dies mid-session** — reconnect device, restart logcat, log the gap. Don't silently lose it.
- **User pinpoints a bug while a fix is being applied** — queue. Address after the current fix lands and rebuild succeeds. Print: `noted — addressing after current fix lands`.
- **`qa-debugger` returns `QA_DIAGNOSE_BLOCKED`** — surface to user with the agent's reason. User collects more signal (verbose logging, breakpoint, narrower steps) and re-pinpoints. Do not retry the same dispatch with the same inputs.
- **`qa-debugger` returns malformed completion line** — treat as `*_BLOCKED` reason `malformed-completion-promise`. Escalate.

## What you MUST NOT do

- **Do not patch a bug yourself.** Even a one-character fix runs through `qa-debugger`. The orchestrator never writes code into the worktree (Constitution + orchestration-protocol).
- **Do not retry a fix silently** when `QA_FIX_BLOCKED` returns. Surface to user. Recurring failure means the diagnose step missed something.
- **Do not skip the failing-test step** because "the fix is obvious". Constitution §8.
- **Do not commit fixes mid-session** unless the user explicitly asks. QA fixes accumulate on the branch; the user decides commit/PR boundaries.
- **Do not auto-open a PR** at session end. PR opening is `/kmm`'s job (or manual). QA mode validates and fixes; it does not publish.
- **Do not amend the migration's `tasks.md` / `migration-report.md`** as part of a QA fix. Bugs surfaced post-migration are recorded in `bugs.md`. If a QA-found bug reveals a planning gap that should retroactively be a deviation, surface to the user — they decide whether to amend.

## Why this command exists

The migration pipeline is rigorous up to PR-open. After PR-open, on-device validation is where teams traditionally relax discipline — "just patch it, ship it". This is the failure mode Constitution §1 + §10 was written against: the **migration is the cheapest moment to fix tech debt, but the cycle right after migration is the most expensive moment to introduce it**. A patch shipped during QA is harder to retire than tech debt that pre-existed.

`/kmm-qa` makes the rigorous path the path of least resistance: build is automated, install is automated, the fix workflow is templated. The user's only decision is "does this proposed fix look right?" — same gate as the architecture / plan approvals in migration mode.
