# Automated Testing Reference

Two-layer testing model for KMM migrations. Each layer catches different categories of bugs:

| Layer | Tool | Backend | Catches | Token cost |
|-------|------|---------|---------|------------|
| 1. Unit/characterization tests | Gradle | N/A | Logic bugs, API parity, regressions | Zero (runs via Gradle) |
| 2. mobile-mcp automated flows | mobile-mcp | Real app + optional fake server | Runtime crashes, integration bugs, OTP/login flows | Moderate (cached screen map) |
| 3. Manual test | User | Real backend | UX issues, edge cases automation can't cover | Zero |

**Phase ordering:** Unit tests → mobile-mcp flows → Manual test

---

## During Planning: Record API Endpoints

Before writing any migration code, the planning phase captures every API endpoint the module touches:

- Source file: what URL, method, headers, and body shape
- Response shape: fields, types, error cases
- Record in migration-guide.md under the file entry and in findings.md under Research

This becomes the input for the fake server config and screen map.

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

Generate a deterministic fake server config from the recorded endpoints. mobile-mcp flows can optionally point the app at the fake server for deterministic error-path and edge-case testing.

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

**`e2e-tests/fake-server.js`:**
```javascript
const express = require('express');
const config = require('./fake-server-config.json');
const app = express();
app.use(express.json());

const requests = []; // Record all requests for assertion

config.routes.forEach(route => {
  app[route.method.toLowerCase()](route.path, (req, res) => {
    requests.push({ method: route.method, path: route.path, body: req.body });
    if (route.matchBody) {
      const matches = Object.entries(route.matchBody).every(
        ([k, v]) => req.body[k] === v
      );
      if (!matches) return; // Fall through to next matching route
    }
    res.status(route.status).json(route.response);
  });
});

app.get('/__requests', (req, res) => res.json(requests));
app.delete('/__requests', (req, res) => { requests.length = 0; res.sendStatus(204); });

const server = app.listen(process.env.FAKE_PORT || 8089, () => {
  console.log(`Fake server on port ${server.address().port}`);
});
module.exports = server;
```

Start the fake server before running mobile-mcp flows against it:
```bash
FAKE_PORT=8089 node e2e-tests/fake-server.js &
```

---

## Device & Port Isolation

When multiple gameplans run concurrently on the same machine, their test phases collide: same emulator, same ports, same app install. Each gameplan gets its own dedicated device and ports, allocated during Phase 1.

**Auto-allocation protocol (Phase 1, Task 1.7c):**

**1. Allocate fake server port:**
```bash
FAKE_PORT=$(python3 -c "
import socket
for p in range(8089, 8189):
    try:
        s = socket.socket(); s.bind(('', p)); s.close(); print(p); break
    except: pass
")
echo "Allocated: FAKE_PORT=$FAKE_PORT"
```

**2. Allocate Android emulator:**
```bash
# Create a dedicated AVD named after the gameplan
AVD_NAME="kmm-<gameplan-name>"
avdmanager create avd -n "$AVD_NAME" \
  -k "system-images;android-34;google_apis;arm64-v8a" \
  --force
# Boot in background, headless
emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim &
# Wait for boot, capture serial
adb wait-for-device
ANDROID_SERIAL=$(adb devices | grep emulator | head -1 | awk '{print $1}')
echo "Allocated Android: $ANDROID_SERIAL"
```

**3. Allocate iOS simulator:**
```bash
# Create a dedicated simulator named after the gameplan
SIM_NAME="kmm-<gameplan-name>"
IOS_UDID=$(xcrun simctl create "$SIM_NAME" "iPhone 16" "iOS-18-0")
xcrun simctl boot "$IOS_UDID"
echo "Allocated iOS: $IOS_UDID"
```

**4. Record in PLAN.md header:**
```
<!-- DEVICE: android=emulator-5558 | ios=A1B2C3D4-E5F6-... -->
<!-- PORTS: fake=8091 -->
```

**Cleanup on session completion:**
```bash
# Delete dedicated emulator
avdmanager delete avd -n "kmm-<gameplan-name>"
# Delete dedicated simulator
xcrun simctl delete <IOS_UDID>
```

The orchestrator reads device/port values from PLAN.md header and exports them as env vars before running any test command.

---

### Unit Tests — Run and Pass at Every Checkpoint

Unit tests (`./gradlew :shared:testDebugUnitTest`) must be run and pass:
- After every file migration (Phase 3, step 8)
- After Phase 3 completion (all files)
- After Phase 4 wiring (Android unit tests)
- After Phase 5 wiring (iOS unit tests where applicable)

A checkpoint with failing unit tests is invalid. If tests fail after wiring, the wiring introduced a regression — fix it before committing.

---

## Layer 2: mobile-mcp Automated Flows (real app, real device)

Drive full user journeys against the real app using mobile-mcp. This catches integration issues that unit tests miss: real backend responses, auth flows, OTP, payment gateways. Optionally point the app at the fake server for deterministic error-path coverage.

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
BLOCKER: <message from screen-map>
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

### What mobile-mcp flows catch that unit tests don't

- Real backend integration issues (actual API responses, auth token flows)
- OTP and payment gateway flows that can't be unit-tested
- Real-device behavior (biometrics, push notifications, deep links)
- Backend data format mismatches that unit tests wouldn't expose

---

## mobile-mcp: Spot Checks and Debug Loop

Beyond automated flows, mobile-mcp is also used for:

**Runtime verification (Phase 4/5):**
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
- `fake-server-config.json` — deterministic backend for error-path coverage
- `screen-map.json` — cached screen elements and flow definitions for mobile-mcp runs
- `screenshots/` — baseline screenshots for visual diff

Unit tests (`./gradlew :shared:testDebugUnitTest`) run on every PR that touches shared code. mobile-mcp flows are run on-demand or as part of release verification.

---

## Compose Screens and UiAutomator2

Compose screens without `contentDescription` or `testTag` return empty page source in UiAutomator2. PIN screens, 2FA OTP, Risk Disclosure, Dashboard — all affected.

**Workarounds:**
- `adb input text` for typing into fields
- Coordinate-based taps for buttons (use screenshot to find coordinates)
- Screenshots for verification instead of element inspection
- iOS CMP has the same issue

**Long-term fix:** Add `Modifier.testTag("...")` or `Modifier.semantics { contentDescription = "..." }` to interactive elements during migration.

---

## WDA iOS Version Mismatch

WebDriverAgent (WDA) built for one iOS version (e.g., 26.2) fails on simulators running a different version (e.g., 26.4).

**Fix:**
- Match simulator runtime to WDA build version
- Create simulators on matching iOS version
- Or rebuild WDA: `appium driver run xcuitest build-wda --sdk <version>`

Always check WDA compatibility BEFORE starting iOS E2E test runs.
