# Automated Testing Reference

Testing model for KMM migrations. Each layer catches different categories of bugs:

| Layer | Tool | Catches | Token cost |
|-------|------|---------|------------|
| 1. Unit/characterization tests | Gradle (`commonTest`) | Logic bugs, API parity, regressions | Zero |
| 2. appium-mcp E2E | appium-mcp + Claude Vision | Visual regressions, runtime crashes, unwired buttons, cross-platform parity | Low (appium-mcp NO_UI mode) |
| 3. Manual test | User on device | UX issues, edge cases automation can't cover | Zero |

**Phase ordering:** Unit tests → appium-mcp E2E → Manual test

---

## Unit Tests — Run and Pass at Every Checkpoint

Unit tests (`./gradlew :shared:testDebugUnitTest`) must run and pass:
- After every file migration (Phase 3)
- After Phase 3 completion (all files)
- After Phase 4 wiring (Android unit tests)
- After Phase 5 wiring (iOS unit tests where applicable)

A checkpoint with failing unit tests is invalid. If tests fail after wiring, the wiring introduced a regression — fix before committing.

---

## appium-mcp E2E (real app, real device)

Drive testing against real apps using the official Appium MCP server. Claude reads migration-guide.md and drives appium-mcp tools directly — no YAML flows, no Python scripts, no intermediate test definitions.

See `references/appium-mcp-testing.md` for the complete protocol including:
- 3-build comparison (master Android vs migrated Android vs iOS)
- Vision-based element finding (no brittle selectors)
- Blocker handling (Claude pauses, asks user, resumes)
- Functional verification per migration-guide.md fields

---

## Deterministic Verification Scripts

These run before appium-mcp E2E (fast, zero tokens):

| Script | What it checks |
|--------|---------------|
| `build-verify.sh` | Build compilation + unit tests across all platforms |
| `parity-check.sh` | Static analysis: imports, route mapping, string literals, empty lambdas, stubs |
| `flow-collector-check.sh` | Every ViewModel StateFlow/SharedFlow has a corresponding iOS `.task {}` collector |
| `koin-binding-check.py` | Every constructor-injected dependency has a Koin binding on both platforms |

Generated during Phase 1 planning with project-specific paths. Run at every Phase 4/5 checkpoint BEFORE appium-mcp E2E.

---

## Fallback: adb / xcrun

> **STRICT RULE:** Every `adb` command MUST include `-s $ANDROID_SERIAL`. Every `xcrun simctl` command MUST use `$IOS_UDID` (never `booted`).

When appium-mcp is unavailable, use adb/xcrun for build verification and log capture only:

**Android:**
```bash
adb -s $ANDROID_SERIAL install -r path/to/app.apk
adb -s $ANDROID_SERIAL shell am start -n <package>/<activity>
adb -s $ANDROID_SERIAL logcat -c && adb -s $ANDROID_SERIAL logcat -d *:E
```

**iOS:**
```bash
xcrun simctl install $IOS_UDID path/to/App.app
xcrun simctl launch --console-pty $IOS_UDID <bundle-id>
```
