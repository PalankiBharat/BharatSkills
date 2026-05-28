# Maestro for Parity — Reference

Parity reuses Maestro, but with a twist: **one flow file runs unchanged on both builds.** That
only works because a business-logic migration leaves the UI byte-identical — same composables,
same testTags, same screens. The flow is the shared probe; the two builds are what differ.

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
    --checkpoint "<journey>/$name" --out "$RUN_DIR/artifacts/<journey>/$name/verdict.json"
done
```
(Put the `sleep 2` between the `.s0` and `.s1` captures.)

## Flows must be login-agnostic

Manual login already happened (Phase 1). Every flow starts logged-in:
```yaml
- launchApp:
    clearState: false   # NEVER clearState: true — it wipes the session you just logged into
```
A flow that re-runs login would consume real OTPs and desync the two devices. Don't.

## Reuse first, generate second

For each affected journey: if a `maestro/` flow already covers it, reuse it (these are
id-based, segmented, screenshot-checkpointed — ideal). Only generate when none exists.

## Selector discipline (unchanged from good Maestro practice)

| Priority | Syntax | When |
|---|---|---|
| ✅ 1st | `id: "tag_name"` | a `testTag` (exposed via `testTagsAsResourceId=true`) |
| ⚠️ rare | `text: "..."` | system dialogs only ("Allow", "OK"), or a closed 2-value control with no tag |
| ❌ never | `point: "x%, y%"` | breaks across device sizes |

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
