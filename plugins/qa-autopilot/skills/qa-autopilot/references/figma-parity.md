# Figma Visual Parity — Reference

Prove the built Android screen matches its Figma design — not "looks roughly right." Catch what code review and functional tests miss: a fill one shade off, a border 2px too thick, a card shifted 8px.

This is the complement to `figma-to-compose`, whose documented gap is exactly this: render the code, screenshot it, diff against the design. qa-autopilot closes that loop.

## The division of labour (read this first)

Naive whole-image pixel diffing of a design against a device screenshot does **not** work — system chrome, framing/aspect differences, sub-pixel shifts, anti-aliasing, and mock-vs-real data all light up red and bury the real signal. So this mode splits the work:

- **`compare-images.py` (the script) = deterministic colour.** It aligns the two images to one pixel grid and reports exact per-region hex + **CIEDE2000 ΔE** (perceptual colour distance). Numbers you can trust and cite.
- **You (the model) = spatial judgement.** You *look* at the aligned images and judge layout, spacing, stroke thickness, alignment, and missing/extra elements — the things a script can't quantify reliably.

The red overlay and `diff_pct` are **hints for where to look, never the verdict.** The verdict is per-region ΔE + your visual read.

## When this mode runs

- A UI story where the screen must match a design.
- "does this match Figma", "compare to the design", "pixel check", "is the UI exact", or a Figma link beside a built screen.

## Prerequisites

- `python3` with `pillow` and `numpy` (`pip install pillow numpy`).
- `FIGMA_TOKEN` for auto-fetch (Figma personal access token, `file_content:read`). Without it, the user supplies the design image.
- A reachable device/emulator on the screen under test (`references/maestro-android-testing.md` STEP 0).

## Output layout

```
.maestro/figma-refs/
  {screen}.png              ← design reference (fetched or user-supplied)
  {screen}-app.png          ← live app screenshot (Maestro)
  {screen}-regions.json     ← element boxes you choose (aligned-image coords)
  diff-{screen}/
    design-aligned.png      ← the exact design pixels being compared
    app-aligned.png         ← the exact app pixels being compared
    diff-overlay.png        ← red-tinted differences (HINT only)
    diff-report.json        ← global hint + per-region colour numbers
```

## Workflow

### 1. Get the design reference

```bash
python3 scripts/figma-screenshot.py "<figma-node-url>" .maestro/figma-refs/{screen}.png
```

The URL must point at a node — in Figma, right-click the frame → **Copy link to selection** (carries `?node-id=...`). A bare file URL is rejected.

**If it exits non-zero** (no `FIGMA_TOKEN`, no node id, no access — it prints why), do not guess. Ask:

> I couldn't pull the design from Figma ({reason}). Paste or drop the design screenshot for **{screen}** and I'll save it.

Save it to `.maestro/figma-refs/{screen}.png`. Always persist the reference so re-runs share one baseline.

### 2. Screenshot the live screen with Maestro

Drive the app to the **same state** as the design (same data, theme, variant) and capture it:

```yaml
appId: com.marketpulse.sniper.vte
name: parity-{screen}
---
- launchApp
# ...navigate to {screen} using id: selectors (see maestro-android-testing.md)...
- takeScreenshot: .maestro/figma-refs/{screen}-app
```

`takeScreenshot: <path>` writes `<path>.png`. Run: `maestro test .maestro/parity-{screen}.yaml`.

### 3. First pass — align and crop the chrome

Open `{screen}-app.png` and read off the pixel heights of the Android **status bar** (top) and **nav bar** (bottom) — they are not in the design and must be cropped, or they dominate the comparison. Then:

```bash
python3 scripts/compare-images.py \
    .maestro/figma-refs/{screen}.png \
    .maestro/figma-refs/{screen}-app.png \
    .maestro/figma-refs/diff-{screen}/ \
    --crop-top {status_bar_px} --crop-bottom {nav_bar_px}
```

This writes `design-aligned.png` and `app-aligned.png` at the same dimensions, plus the hint overlay.

### 4. AI comparison — look, judge, choose regions

**Open `design-aligned.png` AND `app-aligned.png` and compare them visually.** This is the holistic pass only you can do:

- Layout & order: are elements in the same place and order?
- Spacing & padding: gaps, margins, alignment — anything shifted?
- Stroke thickness: borders, dividers, underlines too thick/thin?
- Presence: anything missing, extra, or cut off?
- Colour (first read): anything obviously off — to confirm with numbers next.

Use `diff-overlay.png` only as a "where to look" hint.

Then **write `{screen}-regions.json`** (via the Write tool) listing the element rectangles you want exact colour numbers for. Coordinates are **aligned-image pixels** (the post-crop, post-resize space you're viewing — NOT original Figma or original screenshot dimensions):

```json
[
  {"name": "primary_button", "x": 120, "y": 1800, "w": 840, "h": 210},
  {"name": "header_bar",     "x": 0,   "y": 0,    "w": 1080, "h": 240}
]
```

### 5. Second pass — exact colour per region

```bash
python3 scripts/compare-images.py \
    .maestro/figma-refs/{screen}.png \
    .maestro/figma-refs/{screen}-app.png \
    .maestro/figma-refs/diff-{screen}/ \
    --crop-top {status_bar_px} --crop-bottom {nav_bar_px} \
    --regions .maestro/figma-refs/{screen}-regions.json
```

Read `diff-report.json`. Per region you get:

| Field | Meaning |
|-------|---------|
| `design.median_hex` / `app.median_hex` | median colour of the region (edges inset out), design vs app |
| `design.dominant_hex` / `app.dominant_hex` + `dominant_pct` | most-common colour and how much of the region it covers |
| `delta_e_2000` | perceptual colour distance between the two medians |
| `verdict_hint` | `imperceptible` / `close` / `noticeable` / `clearly-off` |
| `luminance_correlation` | structural hint (null for flat regions — expected) |

If `median` and `dominant` disagree a lot, the region is contaminated (text/icon over a fill) — trust `dominant_hex` for the fill, or pick a tighter box.

### 6. Report

Write the report (`references/report-template.md` structure), combining **your visual findings** (layout/spacing/thickness, with px estimates) and **the script's colour numbers** (exact hex pair + ΔE per region).

**Verdict by ΔE (numerical anchors, no hand-waving):**

| Worst region ΔE | + visual read | Verdict |
|-----------------|---------------|---------|
| < 1 | no spatial drift | 🟢 MATCHES |
| 1–3 | minor/none | 🟡 MINOR DRIFT (note the deltas) |
| 3–5 | or any clear spatial drift | 🟡 CAUTION |
| > 5 | or missing/wrong elements | 🔴 OFF-DESIGN |

## Red Flags — STOP if you think:

| Thought | Reality |
|---------|---------|
| "diff_pct is 14%, so it's off" | `diff_pct` and the overlay are alignment-noise HINTS, never the verdict. Judge by per-region ΔE + your eyes. |
| "I'll skip the visual pass and just read the JSON" | The script measures colour only. Layout/spacing/thickness are YOUR job — open the aligned images. |
| "I'll eyeball the colours too" | You can't see a ΔE of 2 by eye. Put a region on it and read `delta_e_2000`. |
| "I'll put region coords from the Figma frame" | Coords are ALIGNED-image space (post-crop, post-resize), or they sample the wrong pixels. |
| "The status bar is fine, I won't crop" | Uncropped chrome shifts the whole grid and poisons alignment. Always set `--crop-top`/`--crop-bottom`. |
| "I'll describe the design from memory" | Fetch or get the real reference. No memory-based parity. |
| "Close enough, ship it" | Report every mismatch with numbers. The user decides what's close enough. |

## Common Mistakes

| Mistake | Correct approach |
|---------|------------------|
| Reading `diff_pct` / the red overlay as the verdict | They are hints. The verdict is per-region ΔE + your visual read |
| Skipping the visual comparison of the aligned images | That pass catches layout/spacing/thickness — the script can't |
| Not cropping the status/nav bars | Set `--crop-top`/`--crop-bottom` so design and app share the same frame |
| Region coords in Figma or raw-screenshot space | Use aligned-image pixels (post-crop, post-resize) |
| App screenshot in a different state than the design | Match data/theme/variant before `takeScreenshot` |
| "Colours slightly off" with no numbers | Quote the hex pair and `delta_e_2000` per region |
| Trusting `median_hex` on a text-over-fill region | Use `dominant_hex` for the fill, or tighten the box |
