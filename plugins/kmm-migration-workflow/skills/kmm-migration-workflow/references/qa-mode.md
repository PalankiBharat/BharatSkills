# QA mode

Read by `/kmm-qa` and `agents/qa-debugger.md`. Implements **systematic on-device QA + bug-fix workflow** for migrated KMM code. Runs on any KMM project — works the same whether the migration was done with this skill or by hand.

The mode exists for one reason: **a bug found in QA is a code change like any other.** The constitution's principles (architecture before code, understand before acting, scope discipline, clean code first, tests immutable, no comments / TODOs / stubs, documents are the contract) govern the fix. **No silent patches.** A QA cycle that ends with a one-line "while I'm here" edit shipped to master is the failure this mode prevents.

## What QA mode is not

- It is **not** automated UI testing. The user drives the device. The skill orchestrates build / install / launch / log capture and applies the fix workflow when issues surface.
- It is **not** a relaxation of the constitution. Every fix runs the full mini-cycle (understand → fix-spec → failing test → apply → green). Lightweight ceremony, same protections.
- It is **not** scoped to skill-made migrations. A repo with `kmm/<scope>/` artifacts uses them as anchor; a repo without uses `kmm-qa/<session>/` as the standalone audit trail.

## Session anchor — where artifacts live

| Project state | Anchor | Artifacts |
|---|---|---|
| Migration done with this skill (`<repo>/kmm/<scope>/` exists) | The scope's worktree at `<repo>/.worktrees/kmm-<scope>/` | `<repo>/kmm/<scope>/qa-config.json`, `<repo>/kmm/<scope>/bugs.md` |
| Any other KMM project | The repo itself (no worktree) | `<repo>/kmm-qa/<session>/qa-config.json`, `<repo>/kmm-qa/<session>/bugs.md`, baseline SHA captured at session start |

`<session>` is a short user-supplied name (e.g., `auth-smoke-2026-05-10`). When omitted, the orchestrator suggests `qa-<YYYY-MM-DD>` and asks once.

## Command discovery — once per session, never repeated

The first invocation discovers the project's gradle / adb / launch / logcat commands and writes them to `qa-config.json`. Subsequent invocations read the file and skip discovery. Constitution §4 (live sources) applies: every command is **observed**, not recalled.

### Discovery ladder

1. **Read project gradle config** (`build.gradle.kts`, `settings.gradle.kts`, `app/build.gradle.kts`). Pull: application id (`namespace` / `applicationId`), default activity (manifest), `:app`-style consumer module name.
2. **Run `./gradlew tasks --all 2>&1 | grep -iE "assemble|install"`** to enumerate real build / install tasks. Don't assume `:app:assembleDebug` exists — verify.
3. **Run `adb devices`** to enumerate connected devices.
4. **For logcat filter**: pull the launched app's PID via `adb shell pidof <applicationId>` after launch. Don't pre-filter by tag — apps log under many tags.

If a step yields nothing usable, ask the user. Discovery is best-effort + confirmation, never silent assumption.

### qa-config.json schema

```json
{
  "session": "<session-name>",
  "anchor": "kmm-scope:<scope>" | "standalone",
  "baseline_sha": "<git-sha-at-session-start>",
  "application_id": "<com.example.app>",
  "consumer_module": ":app",
  "default_activity": "<com.example.app/.MainActivity>",
  "build_command": "./gradlew :app:assembleDebug",
  "build_artifact": "app/build/outputs/apk/debug/app-debug.apk",
  "install_command": "adb -s <serial> install -r <build_artifact>",
  "uninstall_command": "adb -s <serial> uninstall <application_id>",
  "launch_command": "adb -s <serial> shell am start -n <default_activity>",
  "logcat_command": "adb -s <serial> logcat -v threadtime",
  "device": {
    "serial": "<adb-serial>",
    "label": "<user-friendly name, e.g., 'Pixel 7 emulator'>",
    "api_level": "<31>"
  },
  "install_strategy_default": "ask" | "uninstall" | "update",
  "test_command": "<from spec.md if anchored to a scope, else discovered>",
  "discovered_at": "<ISO date>",
  "live_source_audit": [
    { "command": "build", "verified_via": "./gradlew tasks --all", "verified_at": "<ISO date>" }
  ]
}
```

**Live-source audit** records that each command was verified by an actually-run gradle/adb invocation, not recalled. Constitution §4.

### Asking the user — device

When more than one device is connected, ask once. One question. Save to config. Never re-ask within the session.

```
Devices connected:
A) Pixel 7 emulator (api 33) — emulator-5554
B) Samsung S22 (api 31) — RFCN20<...>
[A / B / discuss]
```

If exactly one device: print the line, proceed silently.

If zero devices: stop. `qa-config: no adb devices. Plug in a device or start an emulator, then re-invoke.`

### Asking the user — install strategy

At session start, ask **once** which default to record:

```
Between iterations, reinstalling the app:
A) Update in place — `adb install -r` (default; preserves user data)
B) Uninstall first — `adb uninstall` then `install` (clears app data; matches first-run behaviour)
C) Ask each iteration — for tests where it depends
[A / B / C]
```

Per-iteration override is always available — when about to reinstall, if `install_strategy_default == "ask"`, the orchestrator asks. Otherwise it applies the default and prints one-line confirmation (`reinstall: update`).

### Re-running discovery

Run `/kmm-qa --rediscover` to force re-detection. Use when a build file changed, a new device was plugged in, or the app was renamed.

## The QA loop

```
session-start
  → discover commands (first time only) / read qa-config.json (subsequent)
  → confirm baseline SHA
  → loop:
       build latest APK
       reinstall (per install_strategy)
       launch
       start logcat in background
       wait for user input
         → user pinpoints an issue
             → diagnose-fix-verify cycle
             → resume loop
         → user says done
             → tear down, summarise
```

### 1. Build

Run `qa-config.build_command`. Always from a clean state — do not skip a build because "nothing changed". The fix loop produces real source edits between iterations and a stale APK is the most common false negative in QA.

If the build fails, surface the failure and stop. Do not auto-fix, do not retry. A broken build is an upstream issue (latest code on the branch is broken) — escalate to the user immediately, mirroring the migration mode's `*_BLOCKED` policy.

### 2. Reinstall

If `install_strategy_default == "ask"` OR the user has set per-iteration override:

```
About to reinstall <application_id> on <device.label>:
A) Update — preserves user data (default for repeat-test runs)
B) Uninstall first — clears state (default for first-run-experience tests)
[A / B]
```

Else apply the recorded default, print one-line confirmation.

### 3. Launch

Run `qa-config.launch_command`. Capture the launched app's PID:

```bash
adb -s <serial> shell pidof <application_id>
```

If the app crashes immediately at launch, that itself is the first bug — capture logcat from the last 30 seconds, hand to qa-debugger in `mode: diagnose`. Do not loop into a second launch attempt; recurring launch crashes indicate the same upstream issue (mirrors the migration mode's "do not silently refire" rule).

### 4. Logcat in background

Start logcat as a persistent background command. Filter by the app's PID once captured:

```bash
adb -s <serial> logcat --pid=<app_pid> -v threadtime > <session-dir>/logcat.txt
```

Run via `Bash` with `run_in_background: true`. Keep the bash_id; use `BashOutput` to read buffered lines when a bug is reported.

When the app's PID changes (after a relaunch or a process death), stop the previous logcat and start a fresh one with the new PID. Don't try to merge streams — the orchestrator narrows by time-window when reading.

### 5. Wait for user pinpoint

Print:

```
QA session <session-name> live on <device.label>.
App: <application_id> | PID: <pid> | logcat: <session-dir>/logcat.txt
Pinpoint an issue when you see one — describe the screen + symptom — or say "done" to finish.
```

Do not narrate. Wait for input.

### 6. User pinpoints a bug

User input arrives like: "tapping login → app crashes" or "list shows duplicate items after refresh".

Orchestrator action sequence (no labour, only state + dispatch):

1. Record approximate timestamp (now).
2. Read the last ~5 minutes of `logcat.txt` via `BashOutput` (or `tail`-equivalent), filter to severity ≥ W and to the captured PID.
3. Pull the relevant exception / error stack — usually a single FATAL or AndroidRuntime block.
4. Allocate a bug id (`B-1`, `B-2`, …).
5. Dispatch `qa-debugger` in `mode: diagnose` with: bug id, user description, logcat excerpt (raw lines), session anchor, baseline SHA, references to qa-config.

`qa-debugger mode: diagnose` is **read-only**. It uses the code graph (`semantic_search_nodes`, `query_graph`, `get_review_context`) to walk from the stack trace to the offending file:line. It returns a `QA_DIAGNOSE_COMPLETE` token with a proposed `bugs.md` entry — root cause, surgical-vs-refactor decision per §7, fix diff spec, test-to-write spec.

### 7. User approves the proposed fix

Orchestrator presents the agent's proposal in plain language (Constitution §15):

```
B-1 (proposed fix):
  Where: <file>:<line>
  Why: <one-sentence root cause from logcat + source>
  Path: surgical | refactor
  Fix: <one-line summary of the diff spec>
  Test: <test name to add — exercises the broken behaviour, currently RED>
  [y / discuss / decline]
```

- `y` → append the entry to `bugs.md` (status `OPEN`), proceed to apply-fix.
- `discuss` → orchestrator surfaces the full bug entry (raw logcat excerpt, full diff spec). User can edit or reject.
- `decline` → record as `RATIFIED` deviation in `bugs.md` with note "user declined fix in this session" and resume loop. (Used when the user wants to keep observing the same bug across iterations.)

**Refactor path approval gate** (Constitution §7): if the agent's proposed `Path: refactor`, the orchestrator additionally surfaces the clean-code violation it addresses and the file boundary. If the refactor crosses files or changes public API, the orchestrator dispatches `architecture-reviewer` for a HIGH-finding gate before proceeding. (Single-file internal refactors do not require architecture-reviewer dispatch — they're proportional to scope.)

### 8. Apply the fix

Dispatch `qa-debugger` in `mode: apply-fix` with the approved bug-id. The agent:

1. Reads the bug entry from `bugs.md` (its contract).
2. Writes the failing test exactly as specified (single test, not whole-file characterization). The test must currently be RED — runs verify-red on it.
3. Applies the diff spec verbatim (same discipline as the migrator: no inventing edits, no improvements, no `@Suppress`, no comments, no widening visibility, no new dependencies).
4. Runs the new test — must be GREEN.
5. Runs the file's existing baseline tests (if `commonTest` exists for the file) — must remain GREEN. No behaviour drift.
6. Runs per-target compile checks. Clean.
7. Returns `QA_FIX_COMPLETE` with: bug-id, file, test-name, verify-red proven, all tests green.

If anything fails: `QA_FIX_BLOCKED` with diagnostic. Orchestrator escalates. **No silent retries** — repeat failures of the same fix mean the diagnose step missed something, surface to user.

### 9. Update bugs.md

On `QA_FIX_COMPLETE`: status `OPEN` → `FIXED`. Append `Fixed-by-test:` and `Fixed-at: <ISO>`.

On `QA_FIX_BLOCKED`: status stays `OPEN`. Append `Block-reason:` and surface to user.

### 10. Resume the loop

After a fix lands, re-run from step 1 (build) automatically. Print one line: `B-1 fixed. Rebuilding.` Then proceed.

### 11. User says "done"

User input contains `done` / `finish` / `stop`:

1. Stop the background logcat process.
2. Print session summary:
   ```
   ── qa session done ──
   Session: <session-name>
   Iterations: <N builds>
   Bugs: <total> (FIXED: <a>, OPEN: <b>, RATIFIED: <c>)
   Duration: <hh:mm>
   bugs.md: <path>
   ```
3. Run constitution check (§1, §2, §6, §7, §8, §9, §12).
4. Stop. Do not auto-open a PR. The user opens a PR when ready (and re-invokes `/kmm-qa` for the next QA cycle, or `/kmm-audit <pr>` for an audit pass on the fixes).

## Bug-fix discipline (the heart of the mode)

Every entry in `bugs.md` follows the contract from `templates/bugs.md`. The fields exist so the fix is traceable end-to-end without conversation context:

| Field | Why it exists |
|---|---|
| Root cause: `<file>:<line>` | §2 — understand before acting. Generic descriptions ("somewhere in network layer") are rejected. |
| Logcat excerpt | Verifiable signal that the bug is real, not recalled. |
| Path: surgical \| refactor | §7 — explicit decision. Default surgical; refactor requires clean-code citation. |
| Fix diff spec | The migrator's contract. Verbatim application. No inventing edits at apply-fix time. |
| Test to write | §8 — failing test pins the bug. Without it, regressions are silent. |
| Baseline-test name | Pointer for future verifications + `/kmm-audit`. |
| Status: OPEN \| FIXED \| RATIFIED | Same vocabulary as `migration-report.md` deviations. |

A bug whose root cause cannot be named at `file:line` is **not eligible for a fix** in this session. The agent emits `QA_DIAGNOSE_BLOCKED` with reason `root cause not isolable from logcat + source`. The user investigates further (run with verbose logging, add breakpoints) and re-pinpoints.

## Constitutional citations — what every fix must satisfy

A QA fix is governed by the same principles as a migration. The mapping:

| Constitution | What it forbids in QA mode |
|---|---|
| §1 (architecture before code) | No fix lands without a written `bugs.md` entry. The entry IS the architecture for that fix. |
| §2 (understand before acting) | Root cause must be at file:line. "I think probably…" is drift detection (§5). |
| §6 (scope discipline) | A fix touches the file the bug is in. Pulling in adjacent files = `REQUIRES_APPROVAL`. |
| §7 (clean code first) | Surgical default. Refactor only with explicit clean-code citation in the bug entry. |
| §8 (tests immutable / baseline-first) | A failing test is written **before** the fix. Verify-red proves the test pins the bug. |
| §9 (no comments / TODOs / stubs) | A "// FIXME: revisit" smuggled in via a fix is rejected. |
| §10 (canonical patterns) | No scaffolding "to make the fix compile". Surface the boundary issue. |
| §12 (documents are the contract) | Every off-spec action becomes a deviation entry in `bugs.md`. Reading bugs.md alone recovers full context. |

## Reusing existing agents

QA mode reuses the migration mode's agents. No duplication.

| Need | Agent | Mode |
|---|---|---|
| External library / API question (e.g., "is there a multiplatform replacement for this Android API the bug needs?") | `researcher` | default |
| Single-file internal refactor that touches structure | `qa-debugger` | apply-fix (no architecture-reviewer needed, proportional) |
| Refactor that crosses files or changes public API | `architecture-reviewer` first, then `qa-debugger` | apply-fix |
| The fix itself (write 1 failing test + apply diff verbatim) | `qa-debugger` | apply-fix |

`migrator` and `test-capturer` are **not** reused for the QA fix loop. Their contracts (whole-file relocation, exhaustive characterization) are wrong-shaped for single-bug edits. `qa-debugger` is purpose-built and cites the same hard rules.

## Failure modes

- **`adb devices` returns nothing** — stop at session start. Tell user to start an emulator or plug in a device.
- **Build artifact not found at expected path** — re-discovery. The gradle config may have moved the APK output.
- **App crashes at launch every iteration** — same crash twice → orchestrator stops after 2nd iteration and dispatches `qa-debugger` in `mode: diagnose` against the launch crash. No infinite loop on launch.
- **Logcat process dies mid-session** (e.g., adb disconnect) — surface to user. Restart logcat after device reconnects; do not silently lose the gap.
- **User pinpoints a bug but logcat is empty** — possible if the bug is non-fatal (visual / logic-only). Dispatch `qa-debugger mode: diagnose` with empty logcat + user description; the agent walks the graph from the user's description (screen / action). May `QA_DIAGNOSE_BLOCKED` if not isolable.
- **Two bugs in flight** — only one fix at a time. If user reports a second bug while a fix is being applied, queue it; address after the current fix lands and rebuild succeeds.

## Why this mode is independent

QA can run on any KMM project. The mode does not require — and does not produce — `spec.md` / `architecture.md` / `migration-guide.md`. It produces `qa-config.json` + `bugs.md`, and reuses `commonTest/` (or whichever test source set the project keeps) for the failing tests.

When the project was migrated with this skill, QA mode anchors against the existing scope. When it wasn't, QA mode bootstraps a session anchor and operates standalone. **The fix discipline is identical in both cases.**
