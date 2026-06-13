# Figma parity — prove the UI matches, don't claim it

The moment a phase carries a Figma link, parity becomes a **generated artifact** (a parity sheet + a number), not an opinion. Dev produces it before QA ever sees the phase; once approved it is locked as a regression gate.

## Render source — use the project's own screenshot tool first

**Detect before adding anything**: grep the module build files **and** the version catalog for the plugin ids below, and **use the first headless tool you find in its own idiom** — never install a second screenshot stack beside an existing one.

| Plugin id | Tool | Record (render) | Verify (drift lock) | Render PNGs land in |
|---|---|---|---|---|
| `com.android.compose.screenshot` | Google CPST | `:m:update<Variant>ScreenshotTest` | `:m:validate<Variant>ScreenshotTest` | `src/screenshotTest/<variant>/reference/` |
| `io.github.takahirom.roborazzi` | Roborazzi | `:m:recordRoborazzi<Variant>` | `:m:verifyRoborazzi<Variant>` | `build/outputs/roborazzi/` |
| `app.cash.paparazzi` | Paparazzi | `:m:recordPaparazzi<Variant>` | `:m:verifyPaparazzi<Variant>` | `src/test/snapshots/images/` |
| `shot` · `dropshots` · `dev.testify` | instrumentation | runs on the locked emulator — slow; don't extend it for parity, add CPST below instead | | |

Whatever the tool: write the **frame-sized composable test/preview in that tool's idiom**, run its record task, take the PNG from its output dir, and feed `bash .harness/figma-parity diff` — the diff, sheet, DIFF_PCT and gate are tool-agnostic. After approval, the **drift lock is that tool's verify task** (same role as `validateScreenshotTest` everywhere this doc or a dispatch mentions it).

Tool quirks worth knowing:
- **Paparazzi runs only in library modules** — if the screen lives in `:app`, put the test in the UI library module that owns the composable, or fall back to CPST.
- **Roborazzi can auto-generate tests from `@Preview`**: `roborazzi { generateComposePreviewRobolectricTests { enable = true } }`.

## No headless tool in the project? Add Google's CPST (the default)

Only when the table above found nothing headless, add (test-only — zero effect on production code, the APK, or iOS builds; note the build change in `dev-handoff.md`):

```properties
# gradle.properties
android.experimental.enableScreenshotTest=true
```

```toml
# libs.versions.toml            (AGP >= 8.5, Kotlin >= 1.9.20, JDK 17 required)
[versions]
screenshot = "0.0.1-alpha15"
[plugins]
screenshot = { id = "com.android.compose.screenshot", version.ref = "screenshot" }
[libraries]
screenshot-validation-api = { group = "com.android.tools.screenshot", name = "screenshot-validation-api", version.ref = "screenshot" }
```

```kotlin
// <module>/build.gradle.kts
plugins { alias(libs.plugins.screenshot) }
android { experimentalProperties["android.experimental.enableScreenshotTest"] = true }
dependencies {
    screenshotTestImplementation(libs.screenshot.validation.api)
    screenshotTestImplementation("androidx.compose.ui:ui-tooling")
}
```

**KMP module** (Compose Multiplatform, e.g. a `composeApp` with `androidTarget`): apply the plugin to that module — previews live in the **Android** `screenshotTest` source set and can call any `commonMain` composable directly. Non-Android targets can't be rendered (acceptable: same composable, one render proves the layout).

## Per Figma frame — the parity loop

1. **Preview sized to the frame.** In `src/screenshotTest/kotlin/…`, a `@PreviewTest @Preview(widthDp = <frame w>, heightDp = <frame h>)` composable rendering the screen with fixed fake data.
2. **Render headless** (seconds, no emulator): `bash .harness/run dev -- ./gradlew :<module>:updateDebugScreenshotTest` → PNG in `<module>/src/screenshotTest/<variant>/reference/`.
3. **Export the frame**: `bash .harness/figma-parity export <file-key> <node-id> design.png` (no `FIGMA_TOKEN` → ask the user; never hand-build from imagination).
4. **Diff**: `bash .harness/figma-parity diff design.png <render>.png .harness/artifacts/parity/<screen>/` → prints `DIFF_PCT=` and writes `parity-sheet.png` (design | render | heatmap).
5. **Iterate** until the sheet is quiet, then list every sheet path + DIFF_PCT in `dev-handoff.md`.

## Judging the number

Renders never byte-match a Figma export (font anti-aliasing, shadows). A low single-digit `DIFF_PCT` with a **quiet heatmap** is parity; localized hot spots are real mistakes (wrong color, spacing, missing element) regardless of the total. The sheet is the evidence a human approves in seconds.

## The PARITY GATE — a human approves every screen

When Dev signals done on a Figma phase, the Orchestrator (1) **file-checks** every screen (`bash .harness/require …/parity-sheet.png …/diff-pct.txt` — a claim without script-generated files is not done), then (2) renders the gate: `bash .harness/parity-review .harness/artifacts/parity` — a page with **design left, render right**, the heatmap, and an `approve | needs changes` verdict + comment box **per screen**. The user clicks Copy reply and pastes back:

```
PARITY REVIEW
[chart-screen] approve
[watchlist] needs-changes: header spacing too tight; CTA color wrong
```

All approve → QA dispatch. Any needs-changes → the verbatim block goes to Dev (`.harness/answer dev`), Dev fixes those screens, regenerates their sheets, gate repeats. Under `--auto` the page is skipped; the file check never is.

## After approval — parity is locked

The approved renders ARE the goldens. Every later chunk/phase/fix keeps
`./gradlew :<module>:validateDebugScreenshotTest` green (report: `<module>/build/reports/screenshotTest/preview/`, threshold via `testOptions { screenshotTests { imageDifferenceThreshold = 0.01f } }`). Drift fails the phase — UI can never silently degrade after sign-off.

## Gotchas

- Google's CPST plugin is **alpha**: pin the version; a rendering crash is a tooling `blocked`, not an app bug. (If it misbehaves, Roborazzi is the drop-in fallback — same workflow shape.)
- CPST is memory-hungry on big modules: `android.compose.screenshot.maxHeapSize=4g` in `gradle.properties`.
- Renaming a preview function orphans its golden — regenerate via `updateScreenshotTest` in the same commit.
- The Figma export must be the **frame node**, not a group inside it, or dimensions won't correspond.
