# Automated Testing Reference

Two-layer testing model for KMM migrations. Each layer catches different categories of bugs:

| Layer | Tool | Backend | Catches | Token cost |
|-------|------|---------|---------|------------|
| 1. Unit/characterization tests | Gradle | N/A | Logic bugs, API parity, regressions | Zero (runs via Gradle) |
| 2. Appium automated flows | Appium + Python driver | Real app + optional fake server | Visual regressions, runtime crashes, integration bugs, unwired buttons | Near-zero (deterministic scripts, no AI tokens for device interaction) |
| 3. Manual test | User | Real backend | UX issues, edge cases automation can't cover | Zero |

**Phase ordering:** Unit tests → Appium flows → Manual test

---

## During Planning: Record API Endpoints

Before writing any migration code, the planning phase captures every API endpoint the module touches:

- Source file: what URL, method, headers, and body shape
- Response shape: fields, types, error cases
- Record in migration-guide.md under the file entry and in findings.md under Research

This becomes the input for the fake server config and screen map.

---

## Screen Map

The screen map defines screens and navigation flows. It is consumed by the Appium flow generator to produce per-platform Appium scripts. The `coordinates` field is retained as a fallback for coordinate-based tapping, but primary selectors are `id` (Android) and `text` (iOS).

**File location:** `e2e-tests/screen-map.json`

**Generated during:** Phase 1 (planning) — initial structure from reading Android screens. Updated during first runtime verification with actual element IDs.

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

---

## Fake Server

Generate a deterministic fake server config from the recorded endpoints. Appium flows can optionally point the app at the fake server for deterministic error-path and edge-case testing.

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

Start the fake server before running Appium flows against it:
```bash
FAKE_PORT=8089 node e2e-tests/fake-server.js &
```

---

## Device & Port Isolation

When multiple gameplans run concurrently on the same machine, their test phases collide: same emulator, same ports, same app install. Each gameplan gets its own dedicated device and ports, allocated during Phase 1.

See `device-slot-management.md` for the full device slot allocation protocol.

**Allocate fake server port:**
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

**Record in PLAN.md header:**
```
<!-- DEVICE: android=emulator-5558 | ios=A1B2C3D4-E5F6-... -->
<!-- PORTS: fake=8091 -->
```

**Cleanup on session completion:** See `device-slot-management.md` for teardown commands.

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

## Layer 2: Appium Automated Flows (real app, real device)

Drive full user journeys against the real app using the Appium Python driver. This catches visual regressions, runtime crashes, integration issues, and unwired buttons that unit tests miss. Optionally point the app at the fake server for deterministic error-path coverage.

**Flow generation:** Flows are generated from `e2e-tests/screen-map.json` by reading `appium-testing.md` for mapping rules. Each flow in screen-map becomes a Python-driven Appium script per platform, written to `e2e-tests/appium-flows/`.

### Baseline capture protocol

1. Create a temp worktree for master:
   ```bash
   git worktree add /tmp/kmm-baseline-$(date +%s) master
   ```
2. Build from the temp worktree
3. Install on the allocated device
4. Run `python3 e2e-tests/appium_driver.py` with takeScreenshot mode — baseline images saved to `e2e-tests/screenshots/<platform>/baseline/`
5. Uninstall the app
6. Write the master commit hash to `e2e-tests/.cache-key`
7. Clean up the temp worktree

### Comparison protocol

1. Build from the current branch worktree
2. Install on the same allocated device
3. Run `python3 e2e-tests/appium_driver.py` in comparison mode — saves comparison screenshots
4. Collect results from Appium driver output

### Baseline caching

Skip baseline rebuild if `e2e-tests/.cache-key` matches `git rev-parse master`. This avoids rebuilding the baseline on every run when master has not changed.

### Blocker handling

Flows with `blocker` steps are split into segments. Claude's bash loop runs segments sequentially with a user pause between them. See `appium-testing.md` §3 for segmentation rules.

When a flow step has `"action": "blocker"`:

```
BLOCKER: <message from screen-map>
Screen: <current screen name>
Flow: <flow name>

Please complete this step on the device, then confirm to continue.
```

Wait for user acknowledgment before proceeding to the next segment. Common blockers:
- OTP entry (SMS/email verification)
- Personal details (KYC, identity verification)
- Payment gateway (external redirect)
- Biometric prompt (Face ID / fingerprint)

The orchestrator does NOT attempt to bypass or automate blockers. It pauses, asks, and resumes.

### Diff and report

- Screenshot comparison is done by Claude reading baseline and comparison screenshots — no pixel threshold
- Claude classifies each screen as: `VISUAL_REGRESSION` / `EXPECTED_CHANGE` / `FALSE_POSITIVE`
- Report written to `e2e-tests/test-report.md`

---

## Fallback: adb / xcrun

> **⚠️ STRICT RULE:** Every `adb` command MUST include `-s $ANDROID_SERIAL`. Every `xcrun simctl` command MUST use `$IOS_UDID` (never `booted`). Bare commands target whichever device the OS picks first, causing cross-worktree interference.

When Appium is unavailable, fall back to manual adb/xcrun commands for build verification and log capture. Screenshot comparison must be done manually.

**Android:**
```bash
adb -s $ANDROID_SERIAL install -r path/to/app.apk
adb -s $ANDROID_SERIAL shell am start -n <package>/<activity>
adb -s $ANDROID_SERIAL logcat -c && adb -s $ANDROID_SERIAL logcat -s "Debug<ScreenName>"
```

**iOS:**
```bash
xcrun simctl install $IOS_UDID path/to/App.app
xcrun simctl launch --console-pty $IOS_UDID <bundle-id> 2>&1 | grep "Debug<ScreenName>"
```

---

## Screenshot Comparison

Claude reads the baseline and comparison screenshots captured by the Appium driver and classifies each difference. There is no pixel threshold — Claude evaluates screenshots directly. Cross-platform parity: compare Android comparison screenshots against iOS comparison screenshots using Claude vision.

---

## CI Integration

`e2e-tests/` contains a CI-ready regression suite:
- `fake-server-config.json` — deterministic backend for error-path coverage
- `screen-map.json` — flow definitions consumed by Appium flow generator
- `appium-flows/` — generated Appium Python scripts per platform
- `screenshots/` — baseline screenshots for visual diff

Unit tests (`./gradlew :shared:testDebugUnitTest`) run on every PR that touches shared code. Appium flows are run on-demand or as part of release verification.

---

## Compose/SwiftUI and Appium Selectors

Compose screens need `Modifier.testTag("...")` for reliable element targeting in Appium.
SwiftUI screens need `.accessibilityIdentifier("...")`.
Compose Multiplatform maps `testTag` to `accessibilityIdentifier` automatically on iOS.

If interactive elements don't have test tags, add them during the wiring phase:
- Kotlin: `Modifier.testTag("submit_btn")`
- Swift: `.accessibilityIdentifier("submit_btn")`

Appium iOS prefers text-based selectors (most reliable). ID selectors work when accessibility identifiers are set. Coordinate-based tapping is a last resort.
