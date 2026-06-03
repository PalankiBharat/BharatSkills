# Maestro for Parity — Reference

Parity reuses Maestro, but with a twist: **one flow file runs unchanged on both builds.** That
only works because a business-logic migration leaves the UI byte-identical — same composables,
same testTags, same screens. The flow is the shared probe; the two builds are what differ.

> **MANDATORY:** the probe is a **Maestro YAML flow** run with `maestro test --device <serial>`.
> Driving the UI with `adb shell input tap/swipe/text` is prohibited (see SKILL.md → "Maestro
> drives the UI — ALWAYS"). adb is only for install/launch/`screencap`/`logcat`/`maestro hierarchy`.

## Capture model: numbered segments = checkpoints

The repo's `maestro/` flows are already split into ordered segments (`kill_switch/01..06`,
`order_modify_cancel/01..07`). A **checkpoint** is "the screen state after running one segment."
The harness drives both devices through the segments in lockstep and compares at each:

```bash
A="$(cat "$RUN_DIR/locks/lock-a")"; B="$(cat "$RUN_DIR/locks/lock-b")"
for seg in $(ls maestro/<journey>/*.yaml | sort); do
  name="$(basename "$seg" .yaml)"
  maestro --device "$A" test "$seg"
  maestro --device "$B" test "$seg"
  # two samples per device ~2s apart -> lets the comparator auto-mask live fields
  bash scripts/capture-checkpoint.sh "$A" "$RUN_DIR/artifacts/<journey>/$name/a.s0"
  bash scripts/capture-checkpoint.sh "$A" "$RUN_DIR/artifacts/<journey>/$name/a.s1"
  bash scripts/capture-checkpoint.sh "$B" "$RUN_DIR/artifacts/<journey>/$name/b.s0"
  bash scripts/capture-checkpoint.sh "$B" "$RUN_DIR/artifacts/<journey>/$name/b.s1"
  python3 scripts/compare-parity.py \
    --a0 .../a.s0.hierarchy.json --a1 .../a.s1.hierarchy.json \
    --b0 .../b.s0.hierarchy.json --b1 .../b.s1.hierarchy.json \
    --checkpoint "<journey>/$name" ${PARITY_ANCHOR:+--anchor $PARITY_ANCHOR} \
    --out "$RUN_DIR/artifacts/<journey>/$name/verdict.json"
done
```
(Put the `sleep 2` between the `.s0` and `.s1` captures. If a screen has proven static — its
checkpoints report `masked_*` = 0 — you can single-sample it: capture once and reuse it as both
s0 and s1, halving capture time. Keep double-sampling anywhere live data can appear.)

## Checkpoints must follow INTERACTIONS, not just navigation

The migrated logic runs when the user acts, so segments must *do* things and capture the result:

- a segment that **changes a date-range/filter/FY** → capture the reloaded list (re-ran the `Get…` use-case);
- a segment that **scrolls to the bottom** → capture each scroll step (exercises paging `*Source`);
- a segment that **expands a row / switches a tab** → capture the new detail (mappers/view-items);
- a segment that **submits/downloads** → capture the confirmation (the `Download…`/`Submit…` use-case end-to-end).

A flow that only `launchApp` + navigates + asserts the landing screen is **not** a functional
parity test — it checks initial render only. Drive the interactions the heatmap mapped.

### Paging / scroll determinism

Both emulators share one AVD profile/resolution, so an identical `adb shell input swipe` lands at
the same offset. Use a **slow swipe** (e.g. `swipe 720 2200 720 800 700`) to suppress fling, or two
devices can drift to different offsets and read as a false divergence. Compare after each scroll
step; a paging bug shows as different rows below the fold.

**Scroll to a deterministic anchor before comparing.** Even with identical swipes, two devices can
rest a row apart, producing a FALSE presence 🔴 at the boundary. Prefer `scrollUntilVisible` a known
end marker, or scroll **both to the list bottom**, then compare — offsets converge there. On a
boundary-only presence diff mid-scroll, converge and re-compare before recording a 🔴 (observed: a
ledger scroll flagged one extra row that vanished once both devices reached the bottom).

**Every SUBJECT checkpoint must declare a required ANCHOR.** The flip side of the above: a migrated
widget that was *never scrolled-to* is below the fold on **both** devices, so the hierarchies match
and the comparator returns a false 🟢 (it compared two screens that both missed the subject). So name
the anchor that proves the migrated widget/screen was actually on screen — its tagged resource-id
(preferred) or exact visible text — and the runner forwards it via `PARITY_ANCHOR` (space-separated)
to `compare-parity.py --anchor`. Absent on both → ⚪ INDETERMINATE, not 🟢; the segment should
`scrollUntilVisible` that anchor before the capture so the subject is genuinely reached.

## Robust navigation — relaunch, never blind-Back

Reset to a known screen by **relaunching the app** (`monkey -p <pkg> LAUNCHER 1`) then navigating
*forward*, using bounded Back presses that stop the moment the app's home/dashboard screen-tag is
visible. Blindly pressing Back N times overshoots and **exits the app to the launcher**, derailing
the next checkpoint.

## Selectors: match case-insensitively, and investigate misses

Labels in the wild differ by case and exact wording. Match exact first, then fall back to
case-insensitive. If a control still isn't found, **inspect the live hierarchy and try alternate
labels/routes before declaring a gap** — never silently skip a touchpoint in a "no-exclusions" run.

Inspect with the committed helper, not a hand-rolled one-liner:
```bash
python3 scripts/dump-hierarchy.py "$A" --filter id            # what's tagged (id: selectors)
python3 scripts/dump-hierarchy.py "$A" --filter text --grep ledger   # text on untagged screens
python3 scripts/dump-hierarchy.py "$A" --filter clickable      # the tappable target
```
(Use this over inline `python3 -c '…'` — those break on backslashes/quoting under zsh, which cost
real time on the PR #420 run.)

## Stateful actions (submit / send / download / email) — don't diff the server's reply

A flow that fires a stateful action changes server state. Because both devices use the **same
account**, the 2nd device's identical request sees the mutated state and gets different confirmation
copy — a false 🔴 by ORDER, not by build. So assert the action **fired** and compare the **pre-submit**
state; do not compare the post-action server message. If the comparator still flags the copy, it's
server-returned (not in either build's source) — mask it with `compare-parity.py --server-state-text`.
(Observed: Contract-notes "EMAIL THE REPORT" showed "You will receive…" on the 1st device and "We have
sent…" on the 2nd — purely request order; an order-swap proved it.)

## Flows must be login-agnostic

Manual login already happened (Phase 1). Every flow starts logged-in:
```yaml
- launchApp:
    clearState: false   # NEVER clearState: true — it wipes the session you just logged into
```
A flow that re-runs login would consume real OTPs and desync the two devices. Don't.

## Generate is the norm; reuse only if a flow already exists

Most repos (this one included) have **no ready-made journey flows** — generating one per journey is
the default; don't waste time hunting for flows that aren't there. Reuse only if a matching
`maestro/<journey>/` already exists (id-based, segmented, screenshot-checkpointed — ideal when present).

## Selector discipline (unchanged from good Maestro practice)

| Priority | Syntax | When |
|---|---|---|
| ✅ 1st | `id: "tag_name"` | a `testTag` (exposed via `testTagsAsResourceId=true`) |
| ⚠️ rare | `text: "..."` | system dialogs only ("Allow", "OK"), or a closed 2-value control with no tag |
| ❌ never | `point: "x%, y%"` | breaks across device sizes |

**Untagged screens (reports/ledgers):** `id:` won't resolve, so use `text:` selectors for stable
navigation controls (tab labels, buttons, labeled FY chips, list-row titles) — expected here, not a
fallback to avoid. The parity VALUE signal comes from the comparator's text-multiset of the whole
screen, not from selectors, so untagged value tables still get a strict verdict. Reserve `point:` for never.

Stock symbols, prices, and percentages appear many times per screen — `text:` selectors match
the wrong node. Always `id:`. Before writing a flow, discover tags in the **master** worktree
(source of truth):
```bash
grep -rh "\.testTag\|\.semanticsTag" "$MASTER_WT/app/src/main" --include="*.kt" \
  | grep -o '"[^"]*"' | sort -u
```

## Missing tag? Patch BOTH trees identically, before building

If a needed `testTag` doesn't exist, add it to the Compose source — but the flow runs on *both*
builds, so the tag must exist in *both*. Because the migration doesn't touch UI, the UI source
is identical in both worktrees, so the **same edit applies cleanly to both**:

```bash
# apply the identical testTag patch to master and pr worktrees, THEN build both
$EDITOR "$MASTER_WT/app/src/main/.../FooScreen.kt"   # add Modifier.testTag("screen_foo")
$EDITOR "$PR_WT/app/src/main/.../FooScreen.kt"        # identical edit
```
Do this in Phase 0 **before** `build-and-install.sh` — the tag must be compiled into both APKs.
If you add the tag to only one tree, the comparator will (correctly) report a presence
divergence that is really just your asymmetric patch.

## What a checkpoint screen needs to be comparable

The comparator keys off `resource-id` (= testTag). The more tagged the screen, the sharper the
parity signal. Untagged regions fall back to a soft class-structure hint only. So a screen with
good screen-level + element-level testTags gives a 🔴/🟢 you can trust; a sparsely-tagged screen
gives mostly 🟡 hints. Prefer adding a screen-level `testTag("screen_<name>")` (to both trees)
over living with weak signal.
