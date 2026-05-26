# Figma Visual Parity — Reference

Prove the built Android screen matches its Figma design **pixel-for-pixel** — not "looks roughly right." This mode catches what code review and functional tests miss: a fill that's one shade off, a border 2px too thick, a card shifted 8px right.

This is the complement to `figma-to-compose`, whose documented gap is exactly this: "render the generated code, screenshot it, and diff against the Figma render." qa-autopilot closes that loop.

## When this mode runs

- A UI story where the screen must match a design.
- The user says "does this match Figma", "compare to the design", "pixel check", "is the UI exact", or pastes a Figma link alongside a built screen.

## Prerequisites

- `python3` with `pillow` and `numpy` (`pip install pillow numpy`).
- `FIGMA_TOKEN` for auto-fetch (a Figma personal access token with `file_content:read`). Without it, the design image is supplied by the user instead.
- A reachable Android device/emulator showing the screen under test (see `references/maestro-android-testing.md` STEP 0).

## Output layout

```
.maestro/
  figma-refs/
    {screen}.png              ← design reference (fetched or user-supplied)
    {screen}-app.png          ← live app screenshot (Maestro)
    diff-{screen}/
      diff-overlay.png        ← app screenshot, differing pixels tinted red
      diff-report.json        ← metrics
```

## Workflow

### 1. Get the design reference

Auto-fetch from the Figma link:

```bash
python3 scripts/figma-screenshot.py "<figma-node-url>" .maestro/figma-refs/{screen}.png
```

The URL must point at a specific node — in Figma, right-click the frame → **Copy link to selection** (the link carries `?node-id=...`). A bare file URL has no node and will be rejected.

**If the script exits non-zero** (no `FIGMA_TOKEN`, no node id, no access — it prints the reason), do not guess. Ask the user:

> I couldn't pull the design from Figma ({reason}). Paste or drop the design screenshot for **{screen}** and I'll save it as the reference.

Save whatever they provide to `.maestro/figma-refs/{screen}.png`. The reference is always persisted so re-runs compare against the same baseline.

### 2. Capture the live screen with Maestro

Navigate to the **exact same state** as the design (same data, same theme, same variant) and screenshot it. A minimal flow:

```yaml
appId: com.marketpulse.sniper.vte
name: parity-{screen}
---
- launchApp
# ...navigate to {screen} using id: selectors (see maestro-android-testing.md)...
- takeScreenshot: .maestro/figma-refs/{screen}-app
```

`takeScreenshot: <path>` writes `<path>.png`. Run it: `maestro test .maestro/parity-{screen}.yaml`.

### 3. Diff

```bash
python3 scripts/compare-images.py \
    .maestro/figma-refs/{screen}.png \
    .maestro/figma-refs/{screen}-app.png \
    .maestro/figma-refs/diff-{screen}/
```

The script resizes the design to the app screenshot's dimensions, then measures. It **only measures** — you write the verdict.

### 4. Poke every detail, then report

Open `diff-overlay.png` AND read `diff-report.json`. Both. The overlay shows you *where* and *what shape* the mismatch is (a red outline = border thickness/position; a red fill = colour); the JSON gives you the *numbers*.

Read each field and turn it into a concrete finding:

| Field | What it tells you | Finding to write |
|-------|-------------------|------------------|
| `aspect_ratio_match: false` | Design node and screenshot framing differ | STOP — re-capture the matching region; the diff is otherwise noise |
| `top_color_mismatches` | design hex → app hex swaps, by pixel count | "Fill is `#1E66FF`, design is `#2962FF` — off by N per channel" |
| `differing_bounding_box` | overall region that differs | Where the mismatch is concentrated |
| `hotspots` | per-cell diff %, hottest first | Localise: "heaviest mismatch top-left (row2_col2)" — usually an edge/stroke |
| overlay red **outlines** | strokes/borders mismatched in width or position | "Border ~Npx thicker than design" / "card shifted ~Npx" |
| `diff_pct`, `max_distance` | overall severity | Headline number for the verdict |

Write the report (`references/report-template.md` structure) listing **every** mismatch with its hex/px numbers. Verdict: 🟢 MATCHES | 🟡 MINOR DRIFT | 🔴 OFF-DESIGN.

## Red Flags — STOP if you think:

| Thought | Reality |
|---------|---------|
| "I'll just eyeball the two images" | You will miss a one-shade colour or a 2px border. Always run `compare-images.py`. |
| "I'll describe the design from memory" | Fetch or get the real reference image. No memory-based parity. |
| "Close enough, ship it" | Report every mismatch with numbers. The user decides what's close enough, not you. |
| "I'll diff whatever screenshot I have" | The app screenshot must be the SAME screen state as the design, or the diff is noise. |
| "aspect_ratio_match is false but the diff still looks useful" | Different framing → every pixel is shifted. Re-capture the right region first. |
| "I'll fetch with a node id I guessed" | Require a Copy-link-to-selection URL; a guessed node renders the wrong frame. |

## Common Mistakes

| Mistake | Correct approach |
|---------|------------------|
| Eyeballing instead of running the diff script | Always `compare-images.py` — that's the whole point of this mode |
| Not saving the design to `figma-refs/` | Persist it; re-runs must compare against the same baseline |
| App screenshot in a different state than the design | Match data/theme/variant before `takeScreenshot` |
| Reporting "colors slightly off" with no numbers | Quote the hex pair and the per-channel delta from `top_color_mismatches` |
| Trusting the diff when `aspect_ratio_match` is false | Re-capture so design region and screenshot framing line up |
