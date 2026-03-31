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

### Device & Port Isolation

When multiple gameplans run concurrently on the same machine, their test phases collide: same emulator, same ports, same app install. Each gameplan gets its own dedicated device and ports, allocated during Phase 1.

**Auto-allocation protocol (Phase 1, Task 1.7c):**

**1. Allocate ports:**
```bash
# Find free ports for fake server and Appium
# Start from base ports, increment until free
FAKE_PORT=$(python3 -c "
import socket
for p in range(8089, 8189):
    try:
        s = socket.socket(); s.bind(('', p)); s.close(); print(p); break
    except: pass
")
APPIUM_PORT=$(python3 -c "
import socket
for p in range(4723, 4823):
    try:
        s = socket.socket(); s.bind(('', p)); s.close(); print(p); break
    except: pass
")
echo "Allocated: FAKE_PORT=$FAKE_PORT APPIUM_PORT=$APPIUM_PORT"
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
<!-- PORTS: fake=8091 | appium=4725 -->
```

**5. Wire into test infrastructure** — `run-tests.sh` reads these from env vars (`FAKE_PORT`, `APPIUM_PORT`, `ANDROID_SERIAL`, `IOS_UDID`). `wdio.conf.js` uses them for device capabilities and Appium connection.

**Cleanup on session completion:**
```bash
# Delete dedicated emulator
avdmanager delete avd -n "kmm-<gameplan-name>"
# Delete dedicated simulator
xcrun simctl delete <IOS_UDID>
```

The orchestrator reads device/port values from PLAN.md header and exports them as env vars before running any test command.

---

### Appium Infrastructure (generated during Phase 1)

Phase 1 generates the full test infrastructure so Appium tests run automatically — no manual setup needed.

**`e2e-tests/package.json`:**
```json
{
  "name": "e2e-tests",
  "private": true,
  "scripts": {
    "test:android": "./run-tests.sh android",
    "test:ios": "./run-tests.sh ios",
    "fake-server": "node fake-server.js"
  },
  "devDependencies": {
    "@wdio/cli": "^9.0.0",
    "@wdio/local-runner": "^9.0.0",
    "@wdio/mocha-framework": "^9.0.0",
    "@wdio/spec-reporter": "^9.0.0",
    "@wdio/appium-service": "^9.0.0",
    "appium": "^2.0.0",
    "appium-uiautomator2-driver": "^3.0.0",
    "appium-xcuitest-driver": "^7.0.0",
    "express": "^4.18.0"
  }
}
```

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

**`e2e-tests/wdio.conf.js`** (template — adapt capabilities to project):
```javascript
const path = require('path');
const platform = process.env.TEST_PLATFORM || 'android';
const appiumPort = parseInt(process.env.APPIUM_PORT || '4723', 10);

const androidCaps = {
  platformName: 'Android',
  'appium:automationName': 'UiAutomator2',
  'appium:app': process.env.ANDROID_APK || path.resolve(__dirname, '../app/build/outputs/apk/debug/app-debug.apk'),
  'appium:udid': process.env.ANDROID_SERIAL || undefined, // targets dedicated emulator
  'appium:noReset': false,
};

const iosCaps = {
  platformName: 'iOS',
  'appium:automationName': 'XCUITest',
  'appium:app': process.env.IOS_APP || path.resolve(__dirname, '../iosApp/build/Build/Products/Debug-iphonesimulator/iosApp.app'),
  'appium:udid': process.env.IOS_UDID || undefined, // targets dedicated simulator
  'appium:deviceName': 'iPhone 16',
  'appium:platformVersion': '18.0',
  'appium:noReset': false,
};

exports.config = {
  runner: 'local',
  port: appiumPort,
  specs: ['./*.test.js'],
  capabilities: [platform === 'ios' ? iosCaps : androidCaps],
  services: [['appium', { args: { port: appiumPort } }]],
  framework: 'mocha',
  reporters: ['spec'],
  mochaOpts: { timeout: 120000 },
};
```

**`e2e-tests/run-tests.sh`:**
```bash
#!/usr/bin/env bash
# run-tests.sh — Runs Appium tests with fake server, zero manual setup
# Usage: ./run-tests.sh <android|ios> [--apk path] [--app path] [--plan path/to/PLAN.md]
# Device and port isolation: reads DEVICE/PORTS from PLAN.md header or env vars.
# Env vars: FAKE_PORT, APPIUM_PORT, ANDROID_SERIAL, IOS_UDID
set -euo pipefail

PLATFORM="${1:?Usage: ./run-tests.sh <android|ios>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Parse optional args
APK_PATH="" ; APP_PATH="" ; PLAN_PATH=""
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK_PATH="$2"; shift 2 ;;
    --app) APP_PATH="$2"; shift 2 ;;
    --plan) PLAN_PATH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Auto-read device/port allocation from PLAN.md if not set via env
if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
  if [ -z "${FAKE_PORT:-}" ]; then
    FAKE_PORT=$(grep -oP '(?<=fake=)\d+' "$PLAN_PATH" | head -1) || true
  fi
  if [ -z "${APPIUM_PORT:-}" ]; then
    APPIUM_PORT=$(grep -oP '(?<=appium=)\d+' "$PLAN_PATH" | head -1) || true
  fi
  if [ -z "${ANDROID_SERIAL:-}" ]; then
    ANDROID_SERIAL=$(grep -oP '(?<=android=)[^\s|]+' "$PLAN_PATH" | head -1) || true
  fi
  if [ -z "${IOS_UDID:-}" ]; then
    IOS_UDID=$(grep -oP '(?<=ios=)[^\s|]+' "$PLAN_PATH" | head -1) || true
  fi
fi

# Defaults if nothing allocated (single-gameplan scenario)
export FAKE_PORT="${FAKE_PORT:-8089}"
export APPIUM_PORT="${APPIUM_PORT:-4723}"
[ -n "${ANDROID_SERIAL:-}" ] && export ANDROID_SERIAL
[ -n "${IOS_UDID:-}" ] && export IOS_UDID

echo "--- Config: FAKE_PORT=$FAKE_PORT APPIUM_PORT=$APPIUM_PORT"
[ -n "${ANDROID_SERIAL:-}" ] && echo "    ANDROID_SERIAL=$ANDROID_SERIAL"
[ -n "${IOS_UDID:-}" ] && echo "    IOS_UDID=$IOS_UDID"

cleanup() {
  echo "--- Cleaning up..."
  [ -n "${FAKE_PID:-}" ] && kill "$FAKE_PID" 2>/dev/null || true
  wait "$FAKE_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Install deps if needed
[ -d node_modules ] || npm install || { echo "FAIL: npm install failed"; exit 1; }

# Start fake server on allocated port
echo "--- Starting fake server on port $FAKE_PORT..."
node fake-server.js &
FAKE_PID=$!
sleep 2

# Verify fake server is running
curl -sf "http://localhost:${FAKE_PORT}/__requests" > /dev/null || { echo "FAIL: Fake server not responding on port $FAKE_PORT"; exit 1; }

# Set platform and optional paths
export TEST_PLATFORM="$PLATFORM"
[ -n "$APK_PATH" ] && export ANDROID_APK="$APK_PATH"
[ -n "$APP_PATH" ] && export IOS_APP="$APP_PATH"

# Run tests (wdio.conf.js reads APPIUM_PORT, ANDROID_SERIAL, IOS_UDID from env)
echo "--- Running Appium tests ($PLATFORM)..."
npx wdio run wdio.conf.js 2>&1 | tee test-results-${PLATFORM}.log
RESULT=${PIPESTATUS[0]}

echo ""
if [ "$RESULT" -eq 0 ]; then
  echo "=== ALL TESTS PASSED ($PLATFORM) ==="
else
  echo "=== TESTS FAILED ($PLATFORM) — see test-results-${PLATFORM}.log ==="
  exit 1
fi
```

### Running Appium Tests

The agent runs Appium tests via Bash — zero LLM tokens on execution, only on failure diagnosis. Pass `--plan` to auto-read allocated device/ports from PLAN.md:

**Phase 5 (Android):**
```bash
e2e-tests/run-tests.sh android --plan ~/dev/gameplans/<name>/PLAN.md
```

**Phase 7 (iOS):**
```bash
e2e-tests/run-tests.sh ios --plan ~/dev/gameplans/<name>/PLAN.md
```

**On failure:**
1. Read `e2e-tests/test-results-<platform>.log`
2. Identify which test failed and what assertion broke
3. Fix the migration code (NOT the test) — the test describes expected behavior
4. Re-run `run-tests.sh` — max 3 attempts (3-strike), then escalate

**ALL tests must pass.** No skipping (`xit`), no commenting out, no `.skip()`. Failing tests mean the migration has bugs — fix the migration, not the tests.

### Unit Tests — Run and Pass at Every Checkpoint

Unit tests (`./gradlew :shared:testDebugUnitTest`) must be run and pass:
- After every file migration (Phase 3, step 8)
- After Phase 3 completion (all files)
- After Phase 4 wiring (Android unit tests)
- After Phase 6 wiring (iOS unit tests where applicable)

A checkpoint with failing unit tests is invalid. If tests fail after wiring, the wiring introduced a regression — fix it before committing.

**Checkpoint commit requirements:** The Appium phase checkpoint MUST include:
1. Any test file fixes from debugging
2. `e2e-tests/` directory if not yet committed (test files created during Phase 1 may still be uncommitted)
3. Test results log (`test-results-<platform>.log`) and screenshots in `e2e-tests/screenshots/`

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
