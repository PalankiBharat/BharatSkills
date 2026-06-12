# Verifying generated screens with Maestro

Step 9, path A: capture the generated screen running in the real app and
compare it against `figma-out/<screen>/screen-render.png`.

## Prerequisites

- `maestro` on PATH and a booted emulator or connected device (`adb devices`).
- A debug build that includes the new screen: `./gradlew :app:installDebug`
  (adjust module name).

## Reaching the screen

A freshly generated screen usually isn't wired into navigation yet. Options,
best first:

1. **Debug deep link (recommended, one-time setup).** A debug-only activity
   that renders a composable by name, reachable via
   `myapp://debug/screen?name=LoginScreen`. Maestro opens it directly with
   `openLink`. Worth proposing to the user once — it makes every future
   verification (and their parity pipeline) trivial. Adding it touches the
   manifest and a debug source set, so ask before creating it.
2. **Existing navigation.** If the screen is already reachable, drive there
   with normal Maestro taps. Brittle but zero setup.
3. **Temporary launcher swap.** Point the debug launcher activity at the new
   screen just for the capture, revert after. Last resort — easy to forget to
   revert; if used, revert in the same response.

## Flow template

```yaml
# .maestro/verify-<screen>.yaml
appId: com.example.app
---
- launchApp:
    clearState: false
- openLink: "myapp://debug/screen?name=LoginScreen"   # or taps to navigate
- assertVisible: "Welcome back"                        # any string from screen.json — proves the right screen rendered
- takeScreenshot: build/maestro/<screen>-actual
```

Run: `maestro test .maestro/verify-<screen>.yaml`. The screenshot lands at
`build/maestro/<screen>-actual.png`.

The `assertVisible` matters: without it a wrong screen (crash dialog, previous
screen) gets screenshotted and the comparison silently lies. Use an exact
string from `screen.json` so the assertion is tied to the design.

## Comparing

Open the capture and `screen-render.png` side by side and walk:

- spacing rhythm and grouping (gaps that should be equal are equal)
- alignment (edges that should line up do)
- font sizes/weights relative to each other
- icon and image sizes, corner radii
- colours (surface vs primary vs text — hue-level, not pixel-level)
- nothing cut off, overlapped, or missing

**Resolutions differ** — the device screenshot is the device's density, the
Figma render is @2x of the design frame. Compare proportions and
relationships, never absolute pixel positions. Status bars and system insets
appear on device but not in most Figma frames; ignore that band.

Fix discrepancies in the Kotlin, `installDebug`, re-run the flow, re-compare.
**Cap at two fix iterations** — a surviving mismatch goes to the user with
both images and a description of what wouldn't reconcile (it's often a design
inconsistency or a token disagreement they need to rule on).

## Batch mode

- Build and install **once** per fix-iteration, not per screen — capture all
  screens of the batch against the same install, then fix everything found,
  then rebuild once.
- One flow file per screen, named `verify-<screen>.yaml`, all runnable with
  `maestro test .maestro/`.
- The debug deep link pays for itself at batch scale: ten screens means ten
  `openLink` lines instead of ten hand-written navigation paths.

## If the user has a parity pipeline already

Prefer their harness over this template — ask where its entry point is (a
script, a CI job, a skill) and feed it the generated screen plus
`screen-render.png`. The loop is the same: capture → compare → fix → recapture.
