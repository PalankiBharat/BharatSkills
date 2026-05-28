---
name: kmm-qa-autopilot
description: Use for PARITY QA of an Android-to-KMM migration PR — proving a migration changed nothing the user can see. Triggers on "parity test this PR", "qa my migration", "parity QA", "compare master vs migrated", "does this migration change behavior", "differential test the PR", "run parity on PR <url>", "kmm qa autopilot", or any request to verify a KMM/shared-module migration PR is behavior-preserving. Given a GitHub PR link, it builds the baseline master and the PR head as two ProductionRelease APKs (the shipped, R8-minified artifact — same package), boots and locks TWO visible emulators (master→A, PR→B), waits for one manual prod login on each, derives a no-exclusions heatmap from the master-vs-PR git diff, runs the SAME Maestro flows on both devices, and diffs structure + stable values (live prices/charts auto-masked) into a per-journey parity verdict. This is two builds compared head-to-head — distinct from single-build branch QA. Do NOT use for testing one branch in isolation, writing a one-off Maestro flow, or Figma parity (that's qa-autopilot); use this only when there are TWO builds to compare.
---

# KMM QA Autopilot — Parity testing for migration PRs

A KMM migration moves business logic (ViewModels, UseCases, Repositories, mappers) from `:app`
into `shared/commonMain` and leaves the UI untouched. The promise is "nothing changes for the
user." Your job is to **prove or disprove that** by running master and the PR side by side on
two devices and diffing what comes out.

You are not testing one branch. You are running a **controlled A/B**: the same probe (one
Maestro flow), the same account, two builds — and the only thing that should differ is *nothing
the user can perceive*. When something does differ, that's the finding.

## Maestro drives the UI — ALWAYS (MANDATORY, BLOCKING)

Every tap, type, scroll, and assertion MUST be performed by a **Maestro YAML flow** run with
`maestro test --device <serial>`. This is non-negotiable — Maestro is the tool of record, it's
portable and selector-based, and coordinate taps are fragile and silently wrong across states and
screen sizes. The whole "same probe on both builds" guarantee depends on the probe being one
Maestro flow, not improvised input.

- **PROHIBITED for driving the UI:** `adb shell input tap|swipe|text|keyevent`, and never resolve
  x/y coordinates from the hierarchy and tap them. If you catch yourself computing coordinates,
  STOP — you are off-pattern.
- **adb is allowed ONLY for non-UI plumbing:** build/install, app launch (`am start` / `monkey`),
  `screencap`, `pm`, `logcat`, and `maestro hierarchy` (the parity snapshot).
- **Untagged screens are not an excuse.** Use Maestro text/`id` selectors (`tapOn: "<label>"`,
  `scrollUntilVisible`, `assertVisible`, `inputText`). If a needed selector is missing, add a
  `testTag` to BOTH worktrees (see `references/maestro-parity.md`) — do not fall back to coordinates.
- **Disclose any deviation immediately.** If for some reason a step cannot be done in Maestro, say
  so explicitly and get the user's call — never silently substitute adb input and report it as a
  Maestro run.

## The single input

A **GitHub PR link** (or number). Everything else is derived. **Latest `origin/master` is always
the baseline / source of truth** — never the PR's recorded base.

## Hard prerequisites (BLOCKING — check before anything)

1. **Run from a `sniper-v2-android` checkout.** `git rev-parse --show-toplevel` must end in `sniper-v2-android`. The worktrees, diff, and flows all come from this repo.
2. **`gh` authed** (`gh auth status`) — used to resolve the PR. **`maestro` installed** (`command -v maestro` → if missing: `curl -Ls "https://get.maestro.mobile.dev" | bash`). **Android SDK** (`adb`, `emulator`) on `$ANDROID_HOME`.
3. **Two devices' worth of resources.** Two visible emulators will run at once.

All scripts below are in this skill's `scripts/`. References hold the detail — read the one named at each phase before doing that phase.

## Phase 0 — Setup & lock (the "locked at start" phase)

```bash
bash scripts/setup-worktrees.sh <pr-url-or-number>     # writes $RUN_DIR/state.env
source "$HOME/.kmm-parity/pr-<num>/state.env"          # MASTER_WT, PR_WT, PR_LOCAL_BRANCH, RUN_DIR...
bash scripts/ensure-two-emulators.sh "$RUN_DIR"        # locks A (master) + B (PR), visible
A="$(cat "$RUN_DIR/locks/lock-a")"; B="$(cat "$RUN_DIR/locks/lock-b")"
```

`setup-worktrees.sh` resolves the PR and picks the baseline (A): **if the PR is already MERGED**, it
auto-baselines against the pre-migration commit (`<mergeSha>^1`) — latest master already contains the
migration, so a normal master-vs-PR diff would be EMPTY. Override with `BASELINE_REF`. It also
**hard-stops on an empty diff** (baseline == PR head) — never run a vacuous parity pass that would
report a false 🟢.

Read `references/dual-emulator.md` for the locking policy and the **scope-every-command** rule
(two devices now — an unscoped `adb`/`maestro` call is ambiguous).

**If any flow needs a testTag that doesn't exist**, add the *identical* patch to BOTH worktrees'
UI source **now, before building** (`references/maestro-parity.md` → "Missing tag?"). The UI is
identical across the two trees, so the same edit applies to both; patching only one tree
manufactures a false divergence.

```bash
bash scripts/build-and-install.sh "$MASTER_WT" "$A" master   # ProductionRelease -> emu A
bash scripts/build-and-install.sh "$PR_WT"     "$B" pr        # ProductionRelease -> emu B
```
Builds default to **ProductionRelease** — the shipped, R8-minified artifact users actually run. Do
**NOT** use ProductionDebug: it's the canary / non-R8 build and can HIDE R8-only regressions, most
dangerously serialization (a Gson→kotlinx.serialization migration can be 🟢 on debug yet broken under
R8). Both print `APP_ID=…` (same package, different devices) and warn if `testTagsAsResourceId` is off.
ProductionRelease is slower (~5–6 min cold); the second build reuses the shared Gradle cache. Release &
debug share signing here, so the release APK installs over a prior debug one with login preserved.

## Phase 1 — Manual login (the ONLY manual step)

Launch the app on both, then hand control to the user:

```bash
APP_ID="$(python3 -c 'import json;print(json.load(open("'"$MASTER_WT"'/app/build/outputs/apk/productionDebug/output-metadata.json"))["applicationId"])')"
for S in "$A" "$B"; do adb -s "$S" logcat -c; adb -s "$S" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1; done
```
Optionally start a crash-only logcat per device in the background (`adb -s "$S" logcat --pid=<pid> -v threadtime '*:E'`, `run_in_background: true`).

Then tell the user, and **wait**:
> Both emulators are up. Please log into the **same prod account on both** (phone → OTP → PIN)
> until each is on the Dashboard, then tell me "done." This is the only manual step.

Do not proceed until the user confirms. (Prod allows concurrent sessions; if one device later
lands on a login screen mid-run, the comparator flags EVICTION — re-login, don't report a bug.)

## Phase 2 — Heatmap (no exclusions) + exception context → GATE

Read `references/heatmap-analysis.md`. Diff against the **baseline ref** chosen in Phase 0
(`$MASTER_REF` — pre-migration master for a merged PR, else latest master):

```bash
git -C "$MASTER_WT" diff "$MASTER_REF"..."$PR_LOCAL_BRANCH" --name-status
```
Categorize every changed file, trace each changed symbol up to the screens that show it, and map
to **user journeys**. Classify each journey **read-only vs state-mutating** (safety section below),
and additionally flag **stateful actions** (submit/send/download/email): on a shared prod account
the 2nd device's request hits mutated server state, so their post-action confirmation copy is NOT a
parity signal — compare the pre-submit state, not the server message (see `references/heatmap-analysis.md`).

**Read `.kmm/exceptions/*.md` in the PR tree for CONTEXT only.** These are the authors' *claims* that
the migration deliberately changes some behavior (e.g. a date-label fix). They are **not trusted
ground truth** — never let a doc downgrade a real divergence to a pass. List each as context (field /
screen, claimed old→new, and whether it's even **reachable through the UI** for this account), then
verify independently from the tool's own captured evidence in Phase 5. See `references/parity-comparison.md`.

Then **present the heatmap table and STOP for approval** — the user approves, trims, or excludes
mutating journeys before any flow runs.

## Phase 3 — Flow coverage (EXERCISE the logic, don't just open the screen)

Read `references/maestro-parity.md`. **Generating a flow per journey is the norm** — this repo
usually has no ready-made journey flows, so don't waste time hunting; reuse only if a matching
`maestro/<journey>/` already exists. Each flow is login-agnostic (`clearState: false`), prefers
`id:` selectors, and falls back to **text selectors** on untagged screens (many real screens —
reports, ledgers — carry no testTags; that's expected, not a blocker). Discover selectors from the
**master** worktree. One flow per journey — the *same file* runs on both builds.

On **untagged value-table screens** (reports/ledgers/statements) the verdict rests on the
comparator's **visible-text** signal — the on-screen amounts/dates ARE the migrated logic's output,
and static (market-closed) data makes that comparison strict. Don't try to tag every cell; at most
add a screen-level `testTag("screen_<name>")` to BOTH trees for navigation. (See `references/parity-comparison.md`.)

**Render parity ≠ functional parity — this is the #1 trap.** A migration moves *business logic*
that only runs when the user **does** something. Opening a screen and diffing its initial render
barely exercises the migrated code. Each flow MUST drive the interactions that invoke the changed
use-cases and compare the **result after each interaction**:

- **Reload-on-input** — change a date range / filter / FY, switch a tab/segment, pull-to-refresh → re-runs the migrated `Get…`/repository logic for new inputs.
- **Paging** — scroll lists to the bottom; compare at each scroll step (catches paging/`*Source` bugs that hide below the fold).
- **Expansion / drill-in** — expand a row, open a detail → exercises mappers/view-item logic.
- **Submit / download / send** — trigger the action that calls the changed use-case end-to-end; compare the resulting confirmation/state (gate real side-effects per the safety section).

The heatmap (Phase 2) already mapped each changed use-case → the interaction that invokes it; the
flow's job is to perform that interaction on both builds.

**No exclusions = investigate, never skip.** If a control/label/screen isn't found, do NOT log
"not found" and move on. Inspect the live hierarchy, try a **case-insensitive / alternate label**
(labels differ by case and wording), try the other navigation route, and only record a **genuine
gap** after a real attempt. A skipped touchpoint is a hole in "no exclusions."

## Phase 4 + 5 — Run both, compare each checkpoint

Per journey, drive both devices through the flow's ordered segments **in lockstep**. Use the helper
scripts instead of hand-issuing every maestro/capture/compare (faster, reproducible, fewer slips):

```bash
# one checkpoint (runs the SAME flow on A+B, captures, compares, writes verdict):
bash scripts/run-checkpoint.sh "$RUN_DIR" <journey> <checkpoint> <flow.yaml> [single|double]
# or every segment in a journey's flows dir, in order:
bash scripts/run-journey.sh "$RUN_DIR" <journey> <flows-dir> [single|double]
```
Reset each device to a known base by **force-stop + relaunch** (preserves login; never `clearState`)
then navigate forward — never blind Back presses (too many Backs exit the app).

**Sampling:** two samples/device auto-detect live fields. If a screen reports `masked_volatile`/
`masked_text` = 0 (proven static — common for historical/market-closed reports), switch it to
`single` to ~halve capture time. Keep `double` wherever anything live can appear (dashboards, tickers).

**Scroll/paging — confirm before 🔴:** a scrolling flow MUST scroll to a **deterministic anchor**
(list bottom / `scrollUntilVisible`) before capture — two devices at different mid-scroll offsets
produce a FALSE presence 🔴 (one extra boundary row). On a boundary-only presence diff, converge
(scroll both to the bottom) and re-run the checkpoint before trusting it.

**Stateful actions (submit/send/download/email) — confirm before 🔴:** on a shared account the 2nd
device hits mutated server state, so post-action confirmation copy differs by ORDER, not by build.
Compare the pre-submit state / that the action fired; mask the server copy with
`compare-parity.py --server-state-text "<phrase>" …`. Treat such a diff like EVICTION, not a 🔴.

Read `references/parity-comparison.md` to interpret 🟢/🟡/🔴/⚠️ and to **confirm a 🔴 before reporting
it** (re-check it isn't an unmasked live field, a scroll-offset / step desync, a stateful-action
server message, or an eviction). **The verdict is the tool's OWN, evidence-backed call** — an
exception doc claiming a change is "intentional" never auto-downgrades a confirmed 🔴.

## Phase 6 — Report

Read `references/report-template.md`. Write `$RUN_DIR/parity-report-pr<num>-<date>.md` with the
per-journey verdicts, confirmed divergences (with both values + screenshot paths), drift notes,
evictions, and **named gaps** (untested or declined journeys — "no exclusions" means gaps are
listed, never hidden). State the build variant (**ProductionRelease**) and the baseline ref used.

Make every 🟢 **auditable** — include a per-journey **confidence line**: which interactions were
actually exercised (date-range/scroll/expand/submit), how many real values were compared, how many
fields were masked, and whether the signal was tag- or text-based. A green over a shallow flow is a
false green; the report must show what each verdict actually covered. The verdict is
**evidence-backed**: report what was observed with evidence, and list anything unverified (including
documented exceptions that were not UI-reachable) as a named gap, never as a silent pass.

## Phase 7 — Cleanup

```bash
git -C "$SNIPER_ROOT" worktree remove --force "$MASTER_WT"
git -C "$SNIPER_ROOT" worktree remove --force "$PR_WT"
git -C "$SNIPER_ROOT" worktree prune
```
Leave the emulators running (never kill devices you booted unless the user asks). The report and
artifacts under `$RUN_DIR` are persistent — they are the deliverable.

## Phase 8 — Session retro (always run; the skill improves every real run)

After the report, run a retrospective of THIS session and write `$RUN_DIR/retro.md` (use
`references/retro-template.md`). Throughout the run you've been observing friction; here you record
it — **save only; do NOT edit the skill during a run.** Capture, with evidence from this run,
anything that hurt:
- **speed** — phase timings, slow or redundant steps;
- **robustness** — failures, manual re-syncs, any deviation (e.g. a non-Maestro probe);
- **confidence** — false 🔴s + their proven root cause, over-strict/over-masked cases, ambiguous or
  UI-unreachable documented changes;
- **harness** — anything you had to hand-drive that a script should do.

Each entry: observation → **evidence from this run** → proposed skill change → goal. Evidence-backed,
no guesswork. Finish by telling the user `retro.md` is saved and can be triaged into the skill **in a
separate session** (edit source in a worktree, bump versions, open a PR) — this is how the skill gets
better with every real run.

## Real-prod-state safety gate (BLOCKING for mutating journeys)

This runs on a **real prod account, on two devices**. A "cancel order" or "kill switch" flow
places/cancels **real orders / real money — doubled**. So:

- Classify every journey read-only vs state-mutating in Phase 2.
- Read-only journeys run automatically.
- **State-mutating journeys run only with explicit user confirmation at the heatmap gate**, and
  are flagged as mutating in the report. Default to declining them on a non-test account or while
  the market is open unless the user confirms.
- A declined mutating journey is reported as **untested**, not green.

## Common mistakes

| Mistake | Correct approach |
|---|---|
| Driving the UI with `adb shell input tap/swipe/text` | PROHIBITED. All taps/scrolls/typing go through Maestro YAML (`maestro test --device`). adb is only for install/launch/`screencap`/`pm`/`logcat`/`maestro hierarchy`. Untagged screen → use text selectors or add a testTag to both trees, never coordinates. |
| Silently substituting adb for Maestro and reporting it as a Maestro run | Disclose any deviation immediately and get the user's call. |
| Pixel-diffing screenshots for the verdict | Live feed → constant false positives. Verdict = hierarchy structure + stable values; screenshots are evidence only. |
| Diffing against the PR's GitHub base | Always `origin/master...PR` after `git fetch origin master` — master-latest is the source of truth. |
| `clearState: true` in a flow | Wipes the session you manually logged into and burns OTPs. Always `clearState: false`. |
| Adding a testTag to only one worktree | The same flow runs on both builds — patch BOTH trees identically, before building, or you fabricate a divergence. |
| Reporting EVICTION as a divergence | One device on a login screen = bumped session, not a migration bug. Re-login, re-run. |
| Running a mutating flow without confirmation | Real orders ×2 on prod. Gate it. |
| Unscoped `adb`/`maestro` with two devices | Always `-s "$A"` / `--device "$B"`. |
| Calling a single 🔴 "the migration is fine on average" | One confirmed structural/value divergence = 🔴 DIVERGENCE FOUND. Don't average it away. |
| Reusing single-build qa-autopilot for this | That tests one branch in isolation. Parity needs two builds compared — this skill. |
| Building **ProductionDebug** (the canary) | Use **ProductionRelease** — the shipped R8 artifact. Debug skips R8 and can hide serialization regressions (false 🟢). |
| Running when the baseline↔PR diff is empty | Vacuous parity. setup auto-baselines a merged PR to `<mergeSha>^1` and hard-stops on an empty diff — don't bypass it. |
| Trusting `.kmm/exceptions/*.md` to downgrade a 🔴 | Exceptions are authors' claims, context only. Verify independently; a confirmed 🔴 stays 🔴 until your own evidence explains it. |
| Calling a mid-scroll boundary-row diff a 🔴 | Scroll both to a deterministic anchor (list bottom) and re-compare — offset drift, not a migration bug. |
| Diffing a stateful action's server confirmation copy | Same account → 2nd request hits mutated server state. Compare pre-submit state; mask copy with `--server-state-text`. |
| Skipping the Phase 8 retro | Always write `$RUN_DIR/retro.md` — that's how the skill improves from each real run. |

## Key principles

1. **Master-latest is truth.** The PR is judged against the freshest master, always.
2. **Same probe, two builds.** One flow file on both devices; only the build differs.
3. **Mask what moves on its own.** Live fields are noise; stable structure + computed values are the signal.
4. **A wrong number is the headline.** A migrated mapper/usecase emitting a different stable value is exactly what parity exists to catch.
5. **Exercise the logic, not the screen.** Render parity ≠ functional parity. The migrated code runs on *interaction* — date-range/filter changes, paging, expansion, submit/download. Drive the interaction on both builds and compare the result; opening a screen barely tests the migration.
6. **No exclusions — investigate, don't skip.** Attempt every affected touchpoint. If a control isn't found, inspect the live UI and try alternate / case-insensitive labels and other routes before recording a *genuine* gap. A skipped touchpoint is a hole in the coverage you promised.
7. **Real prod, real money.** Mutating journeys are gated. The cost of a wrong trade dwarfs the cost of asking.
8. **Test the shipped artifact.** ProductionRelease (R8-minified), never the debug/canary build — release-only behavior (esp. serialization) is exactly what parity must catch.
9. **Your own evidence is the verdict.** Reference exception docs / PR notes for context, never to excuse a divergence; a confirmed 🔴 stays 🔴 until the tool's own evidence explains it.
10. **Improve every run.** Phase 8 writes a retro so the skill compounds with each real PR.
