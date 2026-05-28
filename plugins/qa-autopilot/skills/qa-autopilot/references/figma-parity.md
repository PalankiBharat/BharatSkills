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
  {screen}-regions.json     ← element boxes you choose (view-image coords — the *-view.png)
  diff-{screen}/
    design-aligned.png      ← full-res design pixels being compared
    app-aligned.png         ← full-res app pixels being compared
    design-view.png         ← downscaled copy — OPEN THIS for the visual pass
    app-view.png            ← downscaled copy — OPEN THIS for the visual pass
    diff-overlay.png        ← red-tinted differences (HINT only)
    diff-report.json        ← blank-screen check + global hint + per-region colour
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

**Keyguard / system screens screenshot black.** Device-credential, keyguard, and full-screen system prompts return a near-black image even though the view hierarchy is intact. You cannot pixel-parity these — the script flags them (`blank_screen_check`), and you inspect the hierarchy instead (`maestro hierarchy` / inspect). See `references/maestro-android-testing.md`.

### 3. First pass — align and crop the chrome

Open `{screen}-app.png` and read off the pixel heights of the Android **status bar** (top) and **nav bar** (bottom) — they are not in the design and must be cropped, or they dominate the comparison. Then:

```bash
python3 scripts/compare-images.py \
    .maestro/figma-refs/{screen}.png \
    .maestro/figma-refs/{screen}-app.png \
    .maestro/figma-refs/diff-{screen}/ \
    --crop-top {status_bar_px} --crop-bottom {nav_bar_px}
```

This writes `design-aligned.png` / `app-aligned.png` (full-res), `design-view.png` / `app-view.png` (downscaled), and the hint overlay.

**Check `blank_screen_check` in the report first.** If `app_screenshot_blank` is true, the screen is a keyguard/system screen — STOP the pixel pass and switch to the view hierarchy.

### 4. AI comparison — look, judge, choose regions

**Open `design-view.png` AND `app-view.png`** (the downscaled copies — full-res renders blow the session image cap and get rejected). Open them as **one or two side-by-side pairs; do NOT bulk-open a dozen region crops** — you'll hit the image-count cap. This is the holistic pass only you can do:

- Layout & order: are elements in the same place and order?
- Spacing & padding: gaps, margins, alignment — anything shifted?
- Stroke thickness: borders, dividers, underlines too thick/thin?
- **Inner content, not just the container** (this is the #1 miss): for every component, check the thing *inside* it — the colour swatch's inner fill (solid vs dashed vs gradient), a preview bar's actual height, an icon's shape, a chart line's style. A container that matches tells you NOTHING about its contents.
- Presence: anything missing, extra, or cut off?
- Colour (first read): anything obviously off — confirm with numbers next.

Use `diff-overlay.png` only as a "where to look" hint.

Then **write `{screen}-regions.json`** (via the Write tool). **For every component, add TWO regions — the container AND its inner content** — so colour is checked on what's actually rendered inside, not just the frame. Coordinates are **view-image pixels** — read straight off the `*-view.png` you just opened. The script scales them to full-res internally (default `--regions-space view`), so do NOT pre-scale, and do NOT use original Figma or raw-screenshot dimensions:

```json
[
  {"name": "swatch_container",  "x": 120, "y": 1800, "w": 840, "h": 210},
  {"name": "swatch_inner_fill", "x": 150, "y": 1840, "w": 780, "h": 130},
  {"name": "preview_bar_inner", "x": 150, "y": 2000, "w": 780, "h": 40}
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
| `box_view` / `box_aligned` | the region you gave (view-image px) and where it landed after scaling (full-res px) — sanity-check it covers the element |
| `design.median_hex` / `app.median_hex` | median colour of the region (edges inset out), design vs app |
| `design.dominant_hex` / `app.dominant_hex` + `dominant_pct` | most-common colour and how much of the region it covers |
| `delta_e_2000` | perceptual colour distance between the two medians |
| `verdict_hint` | `imperceptible` / `close` / `noticeable` / `clearly-off` |
| `luminance_correlation` | structural hint (null for flat regions — expected) |

If `median` and `dominant` disagree a lot, the region is contaminated (text/icon over a fill) — trust `dominant_hex` for the fill, or pick a tighter box.

### 6. Report

Combine **your visual findings** (layout/spacing/thickness, with px estimates) and **the script's colour numbers** (exact hex pair + ΔE per region). Use this parity-specific shape (the branch-QA `references/report-template.md` is for the other mode):

```markdown
# Figma Parity — {screen}

**Verdict:** 🟡 MINOR DRIFT

## Colour (from diff-report.json)
| Region | Design | App | ΔE | |
|--------|--------|-----|----|--|
| swatch_inner_fill | #2962FF | #1E66FF | 1.5 | close |
| header_bar        | #101529 | #101529 | 0.0 | match |

## Layout / spacing / thickness (your visual read)
- Primary button ~6px taller than the design.
- Divider under the header reads 2px vs 1px in the design.

## Notes
- crop-top 96 / crop-bottom 132; blank_screen_check: false.
```

**Verdict by ΔE (numerical anchors, no hand-waving):**

| Worst region ΔE | + visual read | Verdict |
|-----------------|---------------|---------|
| < 1 | no spatial drift | 🟢 MATCHES |
| 1–3 | minor/none | 🟡 MINOR DRIFT (note the deltas) |
| 3–5 | or any clear spatial drift | 🟡 CAUTION |
| > 5 | or missing/wrong elements | 🔴 OFF-DESIGN |

## Running as a subagent

Parity runs dispatched as a subagent died in the field (login mid-step, API rate-limits mid-task, partial edits left on disk). Rules:

- **Do login/auth in the main context, never inside the subagent.** Hand the subagent an already-authenticated device on the target screen. (Maestro navigation itself is reliable once login is done up front.)
- **Checkpoint to disk as you go.** The design ref, screenshot, `regions.json`, and report are all files — a rate-limited or restarted run resumes from whatever is already on disk. Don't hold results only in memory.
- **Orchestrator must verify on-disk output, not the "done" message.** A subagent that reports success may have written only partial edits. Confirm the expected files exist and the report has the regions before trusting it.
- **Never `Read` `figma-to-compose`'s `screen.json` / `figma-out/` whole.** Parity works from the rendered PNG only. Those exports run to 1MB+ and blow the file-read cap; if you find them beside your inputs, ignore them (or `jq`/`grep`/python a slice — never a full Read).

## Red Flags — STOP if you think:

| Thought | Reality |
|---------|---------|
| "diff_pct is 14%, so it's off" | `diff_pct` and the overlay are alignment-noise HINTS, never the verdict. Judge by per-region ΔE + your eyes. |
| "I'll skip the visual pass and just read the JSON" | The script measures colour only. Layout/spacing/thickness are YOUR job — open the view images. |
| "The container matches, so the swatch matches" | Container ΔE close + no inner region sampled = sign-off INVALID. Always check the inner fill/pattern/height separately. |
| "I'll open the full-res aligned images" | They blow the image cap and get rejected. Open the downscaled `*-view.png` copies; view a couple of pairs, not many. |
| "The screenshot is black, parity fails" | A black screenshot is a keyguard/system screen (`blank_screen_check`), not a design failure. Use the view hierarchy instead. |
| "I'll eyeball the colours too" | You can't see a ΔE of 2 by eye. Put a region on it and read `delta_e_2000`. |
| "I'll put region coords from the Figma frame" | Coords are the `*-view.png` pixel space you looked at (the script scales them), or they sample the wrong pixels. |
| "The status bar is fine, I won't crop" | Uncropped chrome shifts the whole grid and poisons alignment. Always set `--crop-top`/`--crop-bottom`. |
| "I'll describe the design from memory" | Fetch or get the real reference. No memory-based parity. |
| "Close enough, ship it" | Report every mismatch with numbers. The user decides what's close enough. |

## Common Mistakes

| Mistake | Correct approach |
|---------|------------------|
| Reading `diff_pct` / the red overlay as the verdict | They are hints. The verdict is per-region ΔE + your visual read |
| Skipping the visual comparison of the view images | That pass catches layout/spacing/thickness — the script can't |
| Checking only the container, not its inner content | Sample container AND inner fill/pattern/height — the inner content is where parity actually breaks |
| Opening full-res images / bulk-opening many crops | Open the `*-view.png` copies, a couple of pairs at a time (image cap) |
| Trying to pixel-parity a keyguard/system screen | Black screenshot → use the view hierarchy (`maestro hierarchy`/inspect), not a screenshot |
| Not cropping the status/nav bars | Set `--crop-top`/`--crop-bottom` so design and app share the same frame |
| Region coords in Figma or raw-screenshot space | Use `*-view.png` pixel space (the script scales to full-res) |
| App screenshot in a different state than the design | Match data/theme/variant before `takeScreenshot` |
| "Colours slightly off" with no numbers | Quote the hex pair and `delta_e_2000` per region |
| Trusting `median_hex` on a text-over-fill region | Use `dominant_hex` for the fill, or tighten the box |
