# Appium Testing Reference

Central reference for generating Appium YAML flows from screen-map.json and running visual/functional parity testing. Read this file to know exactly how to convert screen-map data into runnable Appium tests driven by the Python driver script.

---

## 1. Screen-Map to Appium Flow Mapping

### Screen-Map JSON Format

```json
{
  "screens": {
    "ScreenName": {
      "route": "route_path",
      "navigate_from": "PreviousScreen → tap: element (x:X, y:Y)",
      "verify_elements": [
        { "id": "element_id", "type": "text|button|input", "description": "..." }
      ],
      "coordinates": {},
      "last_discovered": null,
      "blockers": ["description"]
    }
  },
  "flows": {
    "flow-name": {
      "steps": [
        { "screen": "ScreenName", "action": "tap|type|verify|blocker|swipe", "target": "element_id", "value": "...", "message": "..." }
      ],
      "blockers": []
    }
  }
}
```

### Action-to-Appium Flow YAML Mapping Table

| screen-map action | Appium Flow YAML (Android) | Appium Flow YAML (iOS) |
|---|---|---|
| `tap` on target with `id` | `- action: tap` / `  selector: { id: "<id>" }` | `- action: tap` / `  selector: { accessibility_id: "<id>" }` or `{ text: "<text>" }` |
| `tap` on target with coordinates | `- action: tap` / `  selector: { point: [x, y] }` | Same |
| `type` on target with value | `- action: type` / `  selector: { id: "<target>" }` / `  value: "<text>"` | Same, prefer `accessibility_id` or `text` selector |
| `verify` on target | `- action: verify` / `  selector: { id: "<target>" }` then `- action: screenshot` / `  name: <screen>` | `- action: verify` / `  selector: { text: "<text>" }` then screenshot |
| `blocker` | **SEGMENT SPLIT** — end current YAML, start new segment file | Same |
| `swipe` | `- action: swipe` / `  direction: up` | Same |
| `back` (navigation) | `- action: back` | `- action: tap` / `  selector: { accessibility_id: "back_button" }` or `{ text: "Back" }` |
| `launch` | `- action: launch` / `  clearState: true` | Same |
| `screenshot` | `- action: screenshot` / `  name: <name>` | Same |

---

## 2. iOS Selector Fallback Strategy

SwiftUI and Compose Multiplatform (CMP) accessibility hierarchies are often incomplete on iOS. Use this priority order:

1. **Text** (`selector: { text: "Button Label" }`) — most reliable for SwiftUI and CMP
2. **Accessibility ID** (`selector: { accessibility_id: "test_tag" }`) — works if the app sets `accessibilityIdentifier` (SwiftUI) or `Modifier.testTag()` (Compose)
3. **Coordinates** (`selector: { point: [x, y] }`) — last resort; fragile across device sizes
4. **If all three fail:** add `Modifier.testTag("name")` (Compose) or `.accessibilityIdentifier("name")` (SwiftUI) to the source during wiring, rebuild, then retry

For Compose Multiplatform on iOS, `Modifier.testTag("name")` automatically maps to `.accessibilityIdentifier("name")`. Android can reliably use `id` selectors from `testTag` or resource IDs without this fallback chain.

---

## 3. Blocker Segmentation Protocol

A `blocker` step signals a manual action required on-device (e.g., face ID, push notification, hardware interaction) that Appium cannot automate.

**Segmentation rules:**

When a flow contains a `blocker` step at index N:
1. Generate `<flow-name>-segment-1.yaml` containing steps 0 through N-1
2. Generate `<flow-name>-segment-2.yaml` containing steps N+1 through end
3. If multiple blockers exist, generate more segments (segment-1, segment-2, segment-3, ...)

**Each segment is a complete Appium flow YAML file with its own `appId` and `platform` headers. Segment 2 and later do NOT include `- action: launch` — they continue from current device state.**

**Wrapping bash script (Claude generates and runs this):**

```bash
#!/bin/bash
DEVICE=$1
FLOW_NAME=$2
APPIUM_PORT=${3:-4723}
SYSTEM_PORT=${4:-8200}
SCREENSHOT_DIR=${5:-e2e-tests/screenshots/android/comparison/}

python3 e2e-tests/appium_driver.py \
  --flow "${FLOW_NAME}-segment-1.yaml" \
  --device "$DEVICE" \
  --appium-port "$APPIUM_PORT" \
  --system-port "$SYSTEM_PORT" \
  --screenshot-dir "$SCREENSHOT_DIR" \
  --env PHONE=$PHONE OTP=$OTP PIN=$PIN

if [ $? -ne 0 ]; then
  echo "ERROR: segment-1 failed. Aborting."
  exit 1
fi

echo "BLOCKER: <message from screen-map blocker step>. Complete the action on device, then type 'done'."
read -r confirmation
if [ "$confirmation" != "done" ]; then
  echo "Aborting at user request."
  exit 1
fi

python3 e2e-tests/appium_driver.py \
  --flow "${FLOW_NAME}-segment-2.yaml" \
  --device "$DEVICE" \
  --appium-port "$APPIUM_PORT" \
  --system-port "$SYSTEM_PORT" \
  --screenshot-dir "$SCREENSHOT_DIR" \
  --env PHONE=$PHONE OTP=$OTP PIN=$PIN
```

If there are more segments, repeat the `echo "BLOCKER..."` / `read` / `python3 e2e-tests/appium_driver.py` pattern for each subsequent segment.

---

## 4. Screenshot Comparison via Claude Vision

Instead of pixel-level threshold comparison, Claude reviews screenshots semantically after Appium captures them.

### Comparison Workflow

After running all Appium flows, Claude performs the following for each captured screenshot pair:

1. Read the baseline screenshot from `e2e-tests/screenshots/<platform>/baseline/<name>.png`
2. Read the comparison screenshot from `e2e-tests/screenshots/<platform>/comparison/<name>.png`
3. Compare and report on:
   - **Layout differences** — spacing, alignment, sizing, element position shifts
   - **Missing or extra elements** — content present in one but absent in the other
   - **Color and style changes** — backgrounds, borders, typography, icon changes
   - **Data issues** — placeholder text ("Loading...", "—"), empty fields, stale data
   - **Unwired elements** — a tap screenshot that shows no navigation or state change
4. Classify each screenshot pair as one of:
   - `VISUAL_REGRESSION` — a meaningful UI change that was not intentional
   - `EXPECTED_CHANGE` — a deliberate change consistent with the ticket scope
   - `FALSE_POSITIVE` — a difference caused by dynamic content (timestamps, counters, spinners)

No threshold configuration is needed. Claude understands layout context and does not fail on minor anti-aliasing or sub-pixel rendering differences that would trigger pixel-diff false positives.

### Screenshot Naming Convention

Baseline screenshots are captured during Phase A with the name defined in the flow YAML's `screenshot` step. Comparison screenshots are written to the same name in the comparison directory. Both directories must mirror each other in filenames for Claude's comparison to work.

---

## 5. Two-Phase Testing Protocol

### Phase A: Baseline Capture (from master branch)

1. Create a temp worktree pointing to master:
   ```bash
   git worktree add /tmp/kmm-baseline-$(date +%s) master
   ```
2. Build the app from the temp worktree.
3. Install the build on the allocated device.
4. Start the Appium server (see §9).
5. Run flows using `python3 e2e-tests/appium_driver.py` with `--screenshot-dir e2e-tests/screenshots/<platform>/baseline/` — this saves baseline screenshots.
6. Uninstall the app from the device. Stop the Appium server.
7. Write the current master commit hash to `.cache-key`:
   ```bash
   git rev-parse master > e2e-tests/screenshots/<platform>/baseline/.cache-key
   ```
8. Clean up the temp worktree:
   ```bash
   git worktree remove /tmp/kmm-baseline-<timestamp>
   ```

### Phase B: Comparison (from current branch)

1. Build the app from the current working branch.
2. Install the build on the same device (master build was already uninstalled in Phase A).
3. Start the Appium server.
4. Run flows using `python3 e2e-tests/appium_driver.py` with `--screenshot-dir e2e-tests/screenshots/<platform>/comparison/`.
5. Stop the Appium server.
6. Claude reads all baseline/comparison pairs and classifies each (see §4).

### Baseline Caching

Skip Phase A entirely if the `.cache-key` file matches the current master commit:

```bash
CACHED=$(cat e2e-tests/screenshots/<platform>/baseline/.cache-key 2>/dev/null)
CURRENT=$(git rev-parse master)
if [ "$CACHED" = "$CURRENT" ]; then
  echo "Baseline is current. Skipping Phase A."
fi
```

---

## 6. Flow Generation Rules

### Output File Structure

For every flow in screen-map.json, generate two files — one per platform:

```
e2e-tests/appium-flows/android/<flow-name>.yaml
e2e-tests/appium-flows/ios/<flow-name>.yaml
```

If a flow contains blockers, generate segmented files instead:

```
e2e-tests/appium-flows/android/<flow-name>-segment-1.yaml
e2e-tests/appium-flows/android/<flow-name>-segment-2.yaml
e2e-tests/appium-flows/ios/<flow-name>-segment-1.yaml
e2e-tests/appium-flows/ios/<flow-name>-segment-2.yaml
```

### Flow File Template

```yaml
appId: com.example.app
platform: android  # or ios
---
steps:
  - action: launch
    clearState: true

  # Login (include only if flow requires authentication)
  - action: runFlow
    file: subflows/login.yaml

  # Step 1: <description from screen-map step>
  - action: verify
    selector: { id: "element_id" }        # Android
    # selector: { text: "Visible Text" }  # iOS — prefer text selector

  - action: screenshot
    name: screen-name

  - action: tap
    selector: { id: "element_id" }        # Android
    # selector: { accessibility_id: "element_id" }  # iOS

  # ... more steps ...
```

### Mandatory Generation Rules

- Every flow that requires authentication starts with `action: runFlow` pointing to `subflows/login.yaml`.
- Insert `action: screenshot` after every `verify` step and at every screen transition.
- Insert `action: verify` before any interaction to confirm the target screen is loaded. The Python driver retries element discovery for up to 10 seconds.
- Flows with `blocker` steps split into segments (see §3). Each segment file is self-contained with its own `appId` and `platform` headers.
- Segment 2 and later omit `action: launch` — they resume from the existing app state left by the previous segment.
- The `appId` value is discovered at generation time by inspecting the project (see §7). Never hardcode a placeholder.

---

## 7. Discovering appId

Run these commands from the project root to find the correct app identifier before writing any flow file.

**Android:**

```bash
grep -r "applicationId" app/build.gradle.kts | head -1
# Expected output: applicationId = "com.example.app"
```

Extract the quoted string after `applicationId = `.

**iOS:**

```bash
# Option 1 — from Xcode project
grep "PRODUCT_BUNDLE_IDENTIFIER" *.xcodeproj/project.pbxproj | head -1

# Option 2 — from Info.plist directly
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" path/to/Info.plist
```

Use the extracted value as the `appId` header in every generated YAML file.

---

## 8. Python Driver CLI Reference

```bash
# Run a single flow on Android
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/funds-screen.yaml \
  --device emulator-5554 \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/comparison/ \
  --env PHONE=9876543210 OTP=1234 PIN=1234

# Run a single flow on iOS
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/ios/funds-screen.yaml \
  --device "A1B2C3D4-E5F6-..." \
  --appium-port 4724 \
  --screenshot-dir e2e-tests/screenshots/ios/comparison/ \
  --platform ios \
  --env PHONE=9876543210 OTP=1234 PIN=1234

# Run all flows in a directory
for flow in e2e-tests/appium-flows/android/*.yaml; do
  python3 e2e-tests/appium_driver.py \
    --flow "$flow" \
    --device $ANDROID_SERIAL \
    --appium-port $APPIUM_PORT \
    --system-port $SYSTEM_PORT \
    --screenshot-dir e2e-tests/screenshots/android/comparison/ \
    --env PHONE=$PHONE OTP=$OTP PIN=$PIN
done

# Exit codes: 0 = all steps pass, 1 = any failure (element not found, verify failed, crash)
```

**Device targeting:**
- Android emulator: `emulator-5554` (from `adb devices`)
- Android physical: serial number from `adb devices`
- iOS simulator: UDID from `xcrun simctl list devices`
- iOS physical: UDID from `instruments -s devices`

---

## 9. Appium Server Management

```bash
# Start Appium server (one per worktree, use a unique port to avoid collisions)
appium --port $APPIUM_PORT --base-path /wd/hub \
  --allow-insecure chromedriver_autodownload &
APPIUM_PID=$!

# Wait for server to be ready (takes 2-3 seconds)
sleep 3
curl -s http://localhost:$APPIUM_PORT/wd/hub/status | grep -q '"ready":true'

# Stop after testing
kill $APPIUM_PID
```

**Prerequisites (one-time install):**

```bash
npm install -g appium
appium driver install uiautomator2  # Android
appium driver install xcuitest       # iOS
pip3 install Appium-Python-Client PyYAML
```

**Port assignment across worktrees:**

When running tests in multiple worktrees concurrently, assign unique port pairs to avoid collisions:

| Worktree slot | APPIUM_PORT | SYSTEM_PORT | MJPEG_PORT |
|---|---|---|---|
| slot-1 | 4723 | 8200 | 7100 |
| slot-2 | 4724 | 8201 | 7101 |
| slot-3 | 4725 | 8202 | 7102 |

The device serial (ANDROID_SERIAL or iOS UDID) is always passed explicitly so Appium never defaults to the wrong connected device.

---

## 10. Appium Capabilities Reference

### Android (UiAutomator2)

```python
{
    "platformName": "Android",
    "appium:automationName": "UiAutomator2",
    "appium:deviceName": serial,
    "appium:udid": serial,
    "appium:systemPort": system_port,
    "appium:mjpegServerPort": mjpeg_port,
    "appium:app": apk_path,        # absolute path to .apk
    # Alternatively, for already-installed apps:
    # "appium:appPackage": "com.example.app",
    # "appium:appActivity": ".MainActivity",
    "appium:autoGrantPermissions": True,
    "appium:noReset": False,       # set True to preserve app state across sessions
    "appium:newCommandTimeout": 120,
}
```

### iOS (XCUITest)

```python
{
    "platformName": "iOS",
    "appium:automationName": "XCUITest",
    "appium:deviceName": sim_name,
    "appium:udid": udid,
    "appium:app": app_path,        # absolute path to .app (simulator) or .ipa (device)
    "appium:autoAcceptAlerts": True,
    "appium:newCommandTimeout": 120,
}
```

---

## 11. Known Limitations

| Limitation | Impact | Mitigation |
|---|---|---|
| Compose elements need `testTagsAsResourceId` | `testTag` values not discoverable as resource IDs | Add `Modifier.semantics { testTagsAsResourceId = true }` at the top-level composable |
| iOS has no system `back` command | Navigation flows break on iOS | Tap the back button element explicitly: `selector: { accessibility_id: "back_button" }` or `{ text: "Back" }` |
| Appium server startup latency | First test fails if driver connects before server is ready | Wait 3 seconds and confirm `/wd/hub/status` returns `"ready":true` before running flows |
| UiAutomator2 element dump is slow | Element discovery takes ~500ms vs Maestro's ~10ms | This is a one-time cost per screen; driver caches the hierarchy within a step sequence |
| SwiftUI element hierarchy may be incomplete | `accessibility_id` selectors fail silently | Follow the iOS selector fallback strategy in §2 |
| System dialogs (permissions, pickers) | Test flow interrupted by unexpected dialogs | `autoGrantPermissions: True` (Android) and `autoAcceptAlerts: True` (iOS) handle the common cases automatically |
| Activity recreation (Android) | UI state lost when activity is recreated by OS | UiAutomator2 operates at OS level and is unaffected by activity lifecycle changes |
| `point` selector is fragile | Coordinates break across different device screen sizes | Only use as last resort; prefer `id`, `accessibility_id`, or `text` selectors |
| Unicode input on Android | Non-ASCII characters may not type correctly via UiAutomator2 | Use ASCII-only test values; for Unicode test cases, use `adb shell input text` separately |

---

## 12. What Appium Catches vs What It Doesn't

### Catches

- **Visual regressions** — layout shifts, missing elements, wrong colors detected via Claude Vision screenshot comparison
- **Unwired buttons** — `action: tap` followed by `action: verify` will fail if the button does not produce the expected navigation or state change
- **Navigation breaks** — `action: verify` fails if the expected screen does not load within the driver's retry window
- **Missing data elements** — `action: verify` on content elements catches absent API responses
- **Platform parity issues** — running the same flow definitions on Android and iOS surfaces divergent behavior

### Does Not Catch

- **Performance regressions** — Appium has no timing metrics or frame-rate measurement
- **Memory leaks** — no heap monitoring or retention tracking
- **Network error handling** — requires a mock server or traffic interception setup outside Appium
- **Exact data correctness** — `action: verify` confirms an element exists, not that its displayed value is correct
- **Accessibility compliance** — does not audit contrast ratios, touch target sizes, or screen reader labels
- **Animation and transition quality** — screenshot comparison only captures static frames

---

## 13. Structured Per-Screen Audit

For maximum bug detection beyond the standard flow, the Python driver supports a `--audit` mode that systematically exercises every interactive element on each screen.

### Audit Execution Steps

When `--audit` is passed to the driver:

1. Navigate to the target screen using the flow's pre-audit steps.
2. Take an initial screenshot — saved as `<screen>-initial.png`.
3. Call `driver.find_elements()` to enumerate all interactive (clickable/focusable) elements currently visible.
4. For each element listed in the screen-map's `verify_elements` array that has `"type": "button"`:
   a. Tap the element.
   b. Take a screenshot — saved as `<screen>-tap-<element_id>.png`.
   c. Press back (Android) or tap the back button (iOS) to return to the screen.
5. Save the complete element discovery list to `e2e-tests/screenshots/<platform>/<mode>/<screen>-elements.json`.

### Audit CLI Invocation

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/funds-screen.yaml \
  --device $ANDROID_SERIAL \
  --appium-port $APPIUM_PORT \
  --system-port $SYSTEM_PORT \
  --screenshot-dir e2e-tests/screenshots/android/comparison/ \
  --audit \
  --env PHONE=$PHONE OTP=$OTP PIN=$PIN
```

### Claude Review After Audit

After the audit run completes, Claude reviews:

1. **Initial screenshot vs baseline** — visual parity check as in the standard flow (see §4).
2. **Each tap screenshot** — did the button produce a visible navigation, modal, or state change? If the before and after screenshots are identical, the button is unwired.
3. **Element list JSON** — are all elements declared in `verify_elements` present in the discovered list? Any missing element is flagged as `MISSING_ELEMENT`.

### Audit Output Structure

```
e2e-tests/screenshots/<platform>/comparison/
  <screen>-initial.png
  <screen>-tap-<element_id>.png     # one per button in verify_elements
  <screen>-elements.json            # full element discovery dump
```

Claude reads all files in this directory after an audit run and produces a per-element report:

| Element | Present | Tap Response | Classification |
|---|---|---|---|
| `btn_transfer` | yes | navigated to TransferScreen | OK |
| `btn_history` | yes | no change after tap | UNWIRED |
| `lbl_balance` | yes | N/A (text, not button) | OK |
| `btn_support` | no | N/A | MISSING_ELEMENT |
