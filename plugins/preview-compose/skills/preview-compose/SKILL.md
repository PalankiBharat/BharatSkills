---
name: preview-compose
description: Use this skill whenever UI-level work is happening in Android/Compose code — editing or creating `@Preview` composables, iterating on a screen's layout/colors/spacing, or when the user says "preview", "show me this", "run the preview", "render this", "let me see it on the emulator", "does this look right", or asks to verify a UI change visually. Triggers on changes to `@Composable` functions annotated with `@Preview` in any `.kt` file under `app/src/main/` or `sniper-library/`. After a UI edit, proactively offer to run the preview; when the user explicitly asks, invoke the script immediately. Do NOT use for non-UI changes (ViewModels, repositories, tests, build scripts) or when the user hasn't indicated they want a visual check.
---

# Compose Preview Runner

Renders `@Preview` composables on a connected Android emulator without opening Android Studio. Installs the project's debug APK and launches a bundled `PreviewActivity` with the target preview's FQN as an intent extra — so the full Compose runtime (Hilt, real resources, theming) is available.

## When to invoke it (proactive)

After you edit or create a `@Preview` composable, end your response with an offer like:
> Want me to run this on the emulator? `"${CLAUDE_PLUGIN_ROOT}/scripts/preview-compose.sh" <file>`

Only offer once per UI-touching turn — don't pester.

## When to run it (explicit)

If the user says any of:
- "preview [this|that|the file]"
- "show me [this|the change|how it looks]"
- "render [it|this preview|<FileName>]"
- "run preview"
- "on the emulator" / "on the device"
- "let me see"
- "does it look right"

…run the script for the file the conversation just worked on (or the file the user named). Don't ask for confirmation on a trivial invocation.

## How to invoke

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/preview-compose.sh" app/src/main/java/com/marketpulse/sniper/vte/view/CircularLoadingScreen.kt
```

Timings:
- Cold: 2–4 min (first APK build + install).
- Warm (code edit → install): 15–25 s.

## What happens on first run

The script bootstraps three files into `app/src/debug/` if they don't already exist:
- `app/src/debug/AndroidManifest.xml` — registers `PreviewActivity`
- `app/src/debug/kotlin/com/marketpulse/sniper/preview/device/PreviewActivity.kt`
- `app/src/debug/kotlin/com/marketpulse/sniper/preview/device/DevicePreviewCallSites.kt`

Subsequent runs regenerate `DevicePreviewCallSites.kt` (the FQN → `@Composable` lambda map) for the current target file and install the APK.

## Preflight

1. `adb devices -l` — confirm an emulator is attached.
2. The script prefers the AVD named `tech-preview-compose` (override via `$PREVIEW_AVD`). Boot it first:
   `$ANDROID_HOME/emulator/emulator -avd tech-preview-compose -no-snapshot-load &`
3. To pin a specific device regardless of AVD: `ANDROID_SERIAL=emulator-NNNN`.

## When a preview crashes

The activity doesn't catch composable exceptions (Compose forbids try/catch around `@Composable` calls). A broken preview force-closes the app. Get the stack with:

```sh
adb logcat -d | grep -A 80 "FATAL EXCEPTION" | head -120
```

Most crashes are "preview isn't self-contained" — the composable reads a `CompositionLocal` or HiltViewModel that the preview function doesn't provide. Fix: wrap the preview call in `CompositionLocalProvider(... provides fake)` and pass fakes explicitly. Report the file:line of the crash and the fix pattern; don't rewrite the preview function unilaterally unless asked.

## Constraints

- **Skips `private` top-level `@Preview` functions.** File-scoped visibility prevents the script's generated call-site file from importing them. Warn the user; they need to change `private` → `internal` (or drop it) to render those.
- **No `@PreviewParameter` in v1.** Script doesn't emit provider instances yet.
- macOS + Linux (uses `adb`; no `fswatch`/`open` requirements).

## Files you may need to reference

- `"${CLAUDE_PLUGIN_ROOT}/scripts/preview-compose.sh"` — entry point
- `"${CLAUDE_PLUGIN_ROOT}/templates/debug/"` — bootstrap templates
- In the target project (auto-created on first run):
  - `app/src/debug/AndroidManifest.xml`
  - `app/src/debug/kotlin/com/marketpulse/sniper/preview/device/PreviewActivity.kt`
  - `app/src/debug/kotlin/com/marketpulse/sniper/preview/device/DevicePreviewCallSites.kt` (regenerated per run)

## Portability caveat

The script hardcodes Punch / Sniper-specific values:
- Gradle task: `:app:installProductionDebug`
- `applicationId`: `com.marketpulse.sniper.vte`
- Preview package: `com.marketpulse.sniper.preview.device`
- Preferred AVD: `tech-preview-compose` (override via `$PREVIEW_AVD`)

To reuse in another Android project these would need to be parameterized via a config file (not yet implemented). `PROJECT_ROOT` itself is auto-detected from `$PWD` walking up to the nearest `gradlew`, so the script can live anywhere on disk.
