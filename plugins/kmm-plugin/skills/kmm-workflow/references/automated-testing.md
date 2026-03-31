# Automated Testing Reference

Three-layer testing model for KMM migrations. Each layer catches different categories of bugs:

| Layer | Tool | Backend | Catches | Token cost |
|-------|------|---------|---------|------------|
| 1. Appium + fake server | Appium test runner | Fake (deterministic) | Mechanical bugs, error paths, edge cases | Zero (runs externally) |
| 2. mobile-mcp flows | mobile-mcp | Real app, real device | Integration bugs, real backend issues, OTP/login flows | Moderate (cached screen map) |
| 3. Manual test | User | Real backend | UX issues, edge cases automation can't cover | Zero |

**Phase ordering per platform:** Appium → mobile-mcp flows → Manual test

---

## During Planning: Record API Endpoints

Before writing any migration code, the planning phase captures every API endpoint the module touches:

- Source file: what URL, method, headers, and body shape
- Response shape: fields, types, error cases
- Record in migration-guide.md under the file entry and in findings.md under Research

This becomes the input for the fake server config, Appium test specs, and screen map.

---

## Screen Map (token optimization)

The screen map caches screen elements and navigation steps so mobile-mcp doesn't waste tokens re-discovering what's on screen every run.

**File location:** `e2e-tests/screen-map.json`

**Generated during:** Phase 1 (planning) — initial structure from reading Android screens. Updated during first runtime verification with actual element IDs and coordinates.

**Format:**
```json
{
  "screens": {
    "FundsScreen": {
      "route": "funds",
      "navigate_from": "HomeScreen → tap: funds_tab (x:90, y:680)",
      "verify_elements": [
        { "id": "balance_text", "type": "text", "description": "Shows user balance" },
        { "id": "add_funds_btn", "type": "button", "description": "Primary CTA" }
      ],
      "coordinates": {},
      "last_discovered": null
    },
    "LoginScreen": {
      "route": "login",
      "navigate_from": "launch",
      "verify_elements": [
        { "id": "email_field", "type": "input" },
        { "id": "password_field", "type": "input" },
        { "id": "login_btn", "type": "button" }
      ],
      "coordinates": {},
      "last_discovered": null,
      "blockers": ["otp_field — requires user to enter OTP after login"]
    }
  },
  "flows": {
    "add-funds-happy": {
      "description": "User adds funds successfully",
      "steps": [
        { "screen": "HomeScreen", "action": "tap", "target": "funds_tab" },
        { "screen": "FundsScreen", "action": "verify", "target": "balance_text" },
        { "screen": "FundsScreen", "action": "tap", "target": "add_funds_btn" },
        { "screen": "AddFundsScreen", "action": "type", "target": "amount_field", "value": "100" },
        { "screen": "AddFundsScreen", "action": "tap", "target": "confirm_btn" },
        { "screen": "AddFundsScreen", "action": "verify", "target": "success_message" }
      ],
      "blockers": []
    },
    "login-with-otp": {
      "description": "User logs in with OTP",
      "steps": [
        { "screen": "LoginScreen", "action": "type", "target": "email_field", "value": "test@example.com" },
        { "screen": "LoginScreen", "action": "type", "target": "password_field", "value": "password123" },
        { "screen": "LoginScreen", "action": "tap", "target": "login_btn" },
        { "screen": "OtpScreen", "action": "blocker", "message": "Enter the OTP sent to your phone" }
      ],
      "blockers": ["OTP entry required — pause for user"]
    }
  }
}
```

**Cache rules:**
- **First encounter:** call `mobile_list_elements_on_screen`, record element IDs and coordinates in `screen-map.json` under `coordinates`, set `last_discovered` to current timestamp
- **Subsequent encounters:** use cached coordinates — only call `mobile_take_screenshot` to verify, NOT `mobile_list_elements_on_screen`
- **Re-discover when:** (a) a screen's source file was modified in the current phase, (b) a cached tap fails (element moved), (c) screenshot shows unexpected layout
- **Never cache:** screenshots themselves (always take fresh ones for evidence)

This saves ~500-1000 tokens per screen per re-run by skipping element discovery on unchanged screens.

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

## Layer 1: Appium Tests (fake server, deterministic)

One test file per critical flow. Written during planning by the same Sonnet agent.

**File location:** `e2e-tests/<flow-name>.test.js`

Each test covers:
1. Start fake server with deterministic config
2. Install app (use `mobile_install_app` or `adb install`)
3. Launch app
4. Drive the flow (tap, type, navigate)
5. Assert on screen state (element text, navigation destination)
6. Assert fake server received expected requests

**What Appium catches that mobile-mcp doesn't:**
- Error path responses (404, 500, timeout) via fake server routing
- Edge case data shapes (empty lists, large payloads, special characters)
- Deterministic reproduction — same test, same result, every time
- CI-ready — runs without agent tokens

Tests are committed alongside the fake server config. They run on CI as a regression suite after the migration is complete.

**Checkpoint commit requirements:** The Appium phase checkpoint MUST include:
1. Any test file fixes from debugging
2. `e2e-tests/` directory if not yet committed (test files created during Phase 1 may still be uncommitted)
3. Test results and screenshots in `e2e-tests/screenshots/`

Before marking an Appium phase complete, verify `e2e-tests/` is committed — `git status e2e-tests/` should show no untracked files.

---

## Layer 2: mobile-mcp Automated Flows (real app, real device)

After Appium passes, drive full user journeys against the real app using mobile-mcp. This catches integration issues that fake server tests miss: real backend responses, auth flows, OTP, payment gateways.

**Uses `e2e-tests/screen-map.json`** for cached element coordinates. Does NOT re-discover screen elements unless the screen changed.

### Flow execution protocol

For each flow defined in `screen-map.json`:

1. **Install and launch:** `mobile_install_app` → `mobile_launch_app`
2. **Execute steps sequentially** from the flow definition:
   - `tap` → use cached coordinates from screen-map; if tap fails → re-discover with `mobile_list_elements_on_screen`, update cache, retry
   - `type` → `mobile_type_keys` with the specified value
   - `verify` → `mobile_take_screenshot`, visually confirm the expected element is present
   - `blocker` → **STOP and ask user.** Present the blocker message. Wait for user to complete the action on the device (e.g., enter OTP, complete payment). User confirms done → resume automation.
3. **After each screen transition:** `mobile_take_screenshot` → save to `e2e-tests/screenshots/<platform>/`
4. **On failure:** screenshot + `mobile_list_elements_on_screen` (re-discover) → diagnose → DEBUG LOOP

### Blocker handling

When a flow step has `"action": "blocker"`:

```
⏸️ BLOCKER: <message from screen-map>
Screen: <current screen name>
Flow: <flow name>

Please complete this step on the device, then confirm to continue.
```

Wait for user acknowledgment before proceeding to the next step. Common blockers:
- OTP entry (SMS/email verification)
- Personal details (KYC, identity verification)
- Payment gateway (external redirect)
- Biometric prompt (Face ID / fingerprint)

The orchestrator does NOT attempt to bypass or automate blockers. It pauses, asks, and resumes.

### What mobile-mcp flows catch that Appium doesn't

- Real backend integration issues (actual API responses, auth token flows)
- OTP and payment gateway flows that can't be faked
- Real-device behavior (biometrics, push notifications, deep links)
- Backend data format mismatches that the fake server wouldn't expose

---

## mobile-mcp: Spot Checks and Debug Loop

Beyond automated flows, mobile-mcp is also used for:

**Runtime verification (Phase 4/6):**
```
# Install and launch
mobile_install_app → mobile_launch_app

# Per-screen verification using cached screen-map
# First time: discover elements, populate cache
mobile_list_elements_on_screen → update screen-map.json
# Subsequent times: use cached coordinates
mobile_take_screenshot → verify visually
mobile_click_on_screen_at_coordinates → navigate (from cache)
```

**Debug loop quick smoke:**
```
# Quick smoke after a fix
mobile_uninstall_app → mobile_install_app → mobile_launch_app → mobile_take_screenshot
```

**iOS parity check:**
- Compare screenshots against Android reference screenshots in `e2e-tests/screenshots/`

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
- `screen-map.json` — cached screen elements and flow definitions
- `<flow>.test.js` files — Appium flow tests for Android and iOS
- `screenshots/` — baseline screenshots for visual diff

Run on every PR that touches shared code.
