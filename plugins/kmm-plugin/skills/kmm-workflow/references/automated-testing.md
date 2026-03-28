# Automated Testing Reference

How to set up and run Appium + fake server + mobile-mcp for a KMM migration.

---

## During Planning: Record API Endpoints

Before writing any migration code, the planning phase captures every API endpoint the module touches:

- Source file: what URL, method, headers, and body shape
- Response shape: fields, types, error cases
- Record in migration-guide.md under the file entry and in findings.md under Research

This becomes the input for the fake server config and Appium test specs.

---

## Fake Server

Generate a deterministic fake server config from the recorded endpoints:

**File location:** `e2e-tests/fake-server-config.json`

**Format:**
```json
{
  "routes": [
    {
      "method": "POST",
      "path": "/api/auth/login",
      "status": 200,
      "response": { "token": "fake-token-123", "userId": "user-456" }
    },
    {
      "method": "POST",
      "path": "/api/auth/login",
      "status": 401,
      "matchBody": { "password": "wrong" },
      "response": { "error": "invalid_credentials" }
    }
  ]
}
```

A Sonnet agent writes the fake server config during planning — dispatched after migration-guide.md is written. The config is committed to `e2e-tests/` and becomes part of the regression suite.

---

## Appium Tests

One test file per critical flow. Written during planning by the same Sonnet agent.

**File location:** `e2e-tests/<flow-name>.test.js`

Each test covers:
1. Start fake server with deterministic config
2. Install app (use `mobile_install_app` or `adb install`)
3. Launch app
4. Drive the flow (tap, type, navigate)
5. Assert on screen state (element text, navigation destination)
6. Assert fake server received expected requests

Tests are committed alongside the fake server config. They run on CI as a regression suite after the migration is complete.

---

## mobile-mcp

**Primary tool** for runtime verification and quick smoke checks in the debug loop.

```
# Install and launch
mobile_install_app → mobile_launch_app

# Verify a screen
mobile_take_screenshot
mobile_list_elements_on_screen
mobile_click_on_screen_at_coordinates

# Quick smoke after a fix
mobile_uninstall_app → mobile_install_app → mobile_launch_app → mobile_take_screenshot
```

Use mobile-mcp for:
- Runtime verification: walk every screen in migration-guide.md after Android/iOS wiring
- Debug loop quick smoke: fast feedback after each fix attempt
- iOS parity check: compare screenshots against Android reference screenshots

---

## Fallback: adb / xcrun

When mobile-mcp is unavailable, fall back to direct commands.

**Android:**
```bash
adb install -r path/to/app.apk
adb shell am start -n <package>/<activity>
adb logcat -c && adb logcat -s "Debug<ScreenName>"
```

**iOS:**
```bash
xcrun simctl install booted path/to/App.app
xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | grep "Debug<ScreenName>"
```

---

## Screenshot Comparison

During iOS runtime verification, compare each screen against its Android counterpart:

1. Android runtime verify produces screenshots saved to `e2e-tests/screenshots/android/`
2. iOS runtime verify produces screenshots saved to `e2e-tests/screenshots/ios/`
3. Visual diff catches layout regressions and missing data

---

## CI Integration

After migration completes, `e2e-tests/` contains a ready CI regression suite:
- `fake-server-config.json` — deterministic backend
- `<flow>.test.js` files — Appium flow tests for Android and iOS
- `screenshots/` — baseline screenshots for visual diff

Run on every PR that touches shared code.
