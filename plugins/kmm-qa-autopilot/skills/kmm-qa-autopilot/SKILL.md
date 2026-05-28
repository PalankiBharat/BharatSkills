---
name: kmm-qa-autopilot
description: Use for PARITY QA of an Android-to-KMM migration PR — proving a migration changed nothing the user can see. Triggers on "parity test this PR", "qa my migration", "parity QA", "compare master vs migrated", "does this migration change behavior", "differential test the PR", "run parity on PR <url>", "kmm qa autopilot", or any request to verify a KMM/shared-module migration PR is behavior-preserving. Given a GitHub PR link, it builds LATEST master and the PR head as two ProductionDebug APKs (same package), boots and locks TWO visible emulators (master→A, PR→B), waits for one manual prod login on each, derives a no-exclusions heatmap from the master-vs-PR git diff, runs the SAME Maestro flows on both devices, and diffs structure + stable values (live prices/charts auto-masked) into a per-journey parity verdict. This is two builds compared head-to-head — distinct from single-build branch QA. Do NOT use for testing one branch in isolation, writing a one-off Maestro flow, or Figma parity (that's qa-autopilot); use this only when there are TWO builds to compare.
---

# KMM QA Autopilot — Parity testing for migration PRs

A KMM migration moves business logic (ViewModels, UseCases, Repositories, mappers) from `:app`
into `shared/commonMain` and leaves the UI untouched. The promise is "nothing changes for the
user." Your job is to **prove or disprove that** by running master and the PR side by side on
two devices and diffing what comes out.

You are not testing one branch. You are running a **controlled A/B**: the same probe (one
Maestro flow), the same account, two builds — and the only thing that should differ is *nothing
the user can perceive*. When something does differ, that's the finding.

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

Read `references/dual-emulator.md` for the locking policy and the **scope-every-command** rule
(two devices now — an unscoped `adb`/`maestro` call is ambiguous).

**If any flow needs a testTag that doesn't exist**, add the *identical* patch to BOTH worktrees'
UI source **now, before building** (`references/maestro-parity.md` → "Missing tag?"). The UI is
identical across the two trees, so the same edit applies to both; patching only one tree
manufactures a false divergence.

```bash
bash scripts/build-and-install.sh "$MASTER_WT" "$A" master   # ProductionDebug -> emu A
bash scripts/build-and-install.sh "$PR_WT"     "$B" pr        # ProductionDebug -> emu B
```
Both print `APP_ID=…` (same package, different devices) and warn if `testTagsAsResourceId` is
off. Expect the first build to take minutes; the second reuses the shared Gradle cache.

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

## Phase 2 — Heatmap (no exclusions) → GATE

Read `references/heatmap-analysis.md`. Diff against **latest master**:

```bash
git -C "$MASTER_WT" diff origin/master..."$PR_LOCAL_BRANCH" --name-status
```
Categorize every changed file, trace each changed symbol up to the screens that show it, and map
to **user journeys**. Classify each journey **read-only vs state-mutating** (see the safety
section below). Then **present the heatmap table and STOP for approval** — the user approves,
trims, or excludes mutating journeys before any flow runs.

## Phase 3 — Flow coverage

Read `references/maestro-parity.md`. For each approved journey: reuse the existing `maestro/`
flow if present; otherwise generate one (login-agnostic `clearState: false`, `id:` selectors,
discovered from the **master** worktree). One flow per journey — the *same file* runs on both
builds.

## Phase 4 + 5 — Run both, compare each checkpoint

Per journey, drive both devices through the flow's ordered segments in lockstep; at each
checkpoint capture two samples per device and compare (full loop in
`references/maestro-parity.md` → "Capture model"):

```bash
maestro --device "$A" test "$seg"; maestro --device "$B" test "$seg"
bash scripts/capture-checkpoint.sh "$A" "$RUN_DIR/artifacts/<j>/<cp>/a.s0"; sleep 2
bash scripts/capture-checkpoint.sh "$A" "$RUN_DIR/artifacts/<j>/<cp>/a.s1"
bash scripts/capture-checkpoint.sh "$B" "$RUN_DIR/artifacts/<j>/<cp>/b.s0"; sleep 2
bash scripts/capture-checkpoint.sh "$B" "$RUN_DIR/artifacts/<j>/<cp>/b.s1"
python3 scripts/compare-parity.py --a0 .../a.s0.hierarchy.json --a1 .../a.s1.hierarchy.json \
  --b0 .../b.s0.hierarchy.json --b1 .../b.s1.hierarchy.json \
  --checkpoint "<j>/<cp>" --out "$RUN_DIR/artifacts/<j>/<cp>/verdict.json"
```
Read `references/parity-comparison.md` to interpret 🟢/🟡/🔴/⚠️ and to **confirm a 🔴 before
reporting it** (re-check it isn't an unmasked live field, a step desync, or an eviction).

## Phase 6 — Report

Read `references/report-template.md`. Write
`$RUN_DIR/parity-report-pr<num>-<date>.md` with the per-journey verdicts, confirmed divergences
(with both values + screenshot paths), drift notes, evictions, and **named gaps** (untested or
declined journeys — "no exclusions" means gaps are listed, never hidden).

## Phase 7 — Cleanup

```bash
git -C "$SNIPER_ROOT" worktree remove --force "$MASTER_WT"
git -C "$SNIPER_ROOT" worktree remove --force "$PR_WT"
git -C "$SNIPER_ROOT" worktree prune
```
Leave the emulators running (never kill devices you booted unless the user asks). The report and
artifacts under `$RUN_DIR` are persistent — they are the deliverable.

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
| Pixel-diffing screenshots for the verdict | Live feed → constant false positives. Verdict = hierarchy structure + stable values; screenshots are evidence only. |
| Diffing against the PR's GitHub base | Always `origin/master...PR` after `git fetch origin master` — master-latest is the source of truth. |
| `clearState: true` in a flow | Wipes the session you manually logged into and burns OTPs. Always `clearState: false`. |
| Adding a testTag to only one worktree | The same flow runs on both builds — patch BOTH trees identically, before building, or you fabricate a divergence. |
| Reporting EVICTION as a divergence | One device on a login screen = bumped session, not a migration bug. Re-login, re-run. |
| Running a mutating flow without confirmation | Real orders ×2 on prod. Gate it. |
| Unscoped `adb`/`maestro` with two devices | Always `-s "$A"` / `--device "$B"`. |
| Calling a single 🔴 "the migration is fine on average" | One confirmed structural/value divergence = 🔴 DIVERGENCE FOUND. Don't average it away. |
| Reusing single-build qa-autopilot for this | That tests one branch in isolation. Parity needs two builds compared — this skill. |

## Key principles

1. **Master-latest is truth.** The PR is judged against the freshest master, always.
2. **Same probe, two builds.** One flow file on both devices; only the build differs.
3. **Mask what moves on its own.** Live fields are noise; stable structure + computed values are the signal.
4. **A wrong number is the headline.** A migrated mapper/usecase emitting a different stable value is exactly what parity exists to catch.
5. **No exclusions, but name the gaps.** Test every affected journey you safely can; list every one you couldn't.
6. **Real prod, real money.** Mutating journeys are gated. The cost of a wrong trade dwarfs the cost of asking.
