# Maestro Testing Reference

Central reference for generating Maestro YAML flows from screen-map.json and running visual/functional parity testing. Read this file to know exactly how to convert screen-map data into runnable Maestro tests.

---

## 1. Screen-Map to Maestro YAML Mapping

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

### Action-to-Maestro Mapping Table

| screen-map action | Maestro (Android) | Maestro (iOS) |
|---|---|---|
| `tap` on target with `id` | `- tapOn: { id: "<id>" }` | `- tapOn: "<visible_text>"` (prefer text, fall back to id) |
| `tap` on target with coordinates | `- tapOn: { point: "<x>,<y>" }` | Same |
| `type` on target with value | `- tapOn: { id: "<target>" }` then `- inputText: "<value>"` | Same, prefer text selector for tapOn |
| `verify` on target | `- assertVisible: { id: "<target>" }` + `- takeScreenshot: <screen>.png` | `- assertVisible: "<text>"` + screenshot |
| `blocker` | **SEGMENT SPLIT** — end current YAML, start new segment file | Same |
| `swipe` | `- swipe: { direction: UP }` | Same |
| back (navigation) | `- back` | `- tapOn: "Back"` or `- tapOn: { id: "back_button" }` |

---

## 2. iOS Selector Fallback Strategy

SwiftUI and Compose Multiplatform (CMP) accessibility hierarchies are often incomplete on iOS. Use this priority order:

1. **Text** (`- tapOn: "Button Label"`) — most reliable for SwiftUI and CMP
2. **Accessibility ID** (`- tapOn: { id: "test_tag" }`) — works if the app sets `accessibilityIdentifier` (SwiftUI) or `Modifier.testTag()` (Compose)
3. **Coordinates** (`- tapOn: { point: "x,y" }`) — last resort; fragile across device sizes
4. **If all three fail:** add `Modifier.testTag("name")` (Compose) or `.accessibilityIdentifier("name")` (SwiftUI) to the source during wiring, rebuild, then retry

For Compose Multiplatform on iOS, `Modifier.testTag("name")` automatically maps to `.accessibilityIdentifier("name")`. Android can reliably use `id` selectors from `testTag` or resource IDs without this fallback chain.

---

## 3. Blocker Segmentation Protocol

A `blocker` step signals a manual action required on-device (e.g., face ID, push notification, hardware interaction) that Maestro cannot automate.

**Segmentation rules:**

When a flow contains a `blocker` step at index N:
1. Generate `<flow-name>-segment-1.yaml` containing steps 0 through N-1
2. Generate `<flow-name>-segment-2.yaml` containing steps N+1 through end
3. If multiple blockers exist, generate more segments (segment-1, segment-2, segment-3, ...)

**Each segment is a complete Maestro flow with its own `appId` header. Segment 2 and later do NOT include `- launchApp` — they continue from current device state.**

**Wrapping bash script (Claude generates and runs this):**

```bash
#!/bin/bash
DEVICE=$1
FLOW_NAME=$2

maestro test --device "$DEVICE" "${FLOW_NAME}-segment-1.yaml"
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

maestro test --device "$DEVICE" "${FLOW_NAME}-segment-2.yaml"
```

If there are more segments, repeat the `echo "BLOCKER..."` / `read` / `maestro test` pattern for each subsequent segment.

---

## 4. assertScreenshot Configuration

### Baseline Capture Mode

Use this during Phase A (capturing from master branch):

```yaml
- takeScreenshot: <screen_name>
```

Saves the screenshot to the `--test-output-dir` path. The filename is `<screen_name>.png`.

### Comparison Mode

Use this during Phase B (comparing current branch against baseline):

```yaml
- takeScreenshot: <screen_name>
- assertScreenshot:
    path: <baseline_dir>/<screen_name>.png
    thresholdPercentage: 97
    cropOn:
      id: "content_area"
```

`cropOn` excludes volatile areas such as the status bar (time, battery indicator). If `content_area` element does not exist in the app, omit `cropOn` and lower the threshold to 95.

### Threshold Guidance

| Threshold | When to use |
|---|---|
| 97% | Default for most screens; allows minor anti-aliasing differences |
| 95% | Screens with dynamic content (timestamps, counters) or no `cropOn` available |
| 99% | Pixel-critical screens (splash, branding) where even small differences matter |

---

## 5. Two-Phase Testing Protocol

### Phase A: Baseline Capture (from master branch)

1. Create a temp worktree pointing to master:
   ```bash
   git worktree add /tmp/kmm-baseline-$(date +%s) master
   ```
2. Build the app from the temp worktree.
3. Install the build on the allocated device.
4. Run flows with `takeScreenshot` commands — this saves baseline screenshots.
5. Uninstall the app from the device.
6. Write the current master commit hash to `.cache-key`:
   ```bash
   git rev-parse master > e2e-tests/screenshots/<platform>/baseline/.cache-key
   ```
7. Clean up the temp worktree:
   ```bash
   git worktree remove /tmp/kmm-baseline-<timestamp>
   ```

### Phase B: Comparison (from current branch)

1. Build the app from the current working branch.
2. Install the build on the same device (master build was already uninstalled in Phase A).
3. Run flows with both `takeScreenshot` and `assertScreenshot` commands.
4. Collect pass/fail results. Any `assertScreenshot` failure is a visual regression.

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
e2e-tests/maestro-flows/android/<flow-name>.yaml
e2e-tests/maestro-flows/ios/<flow-name>.yaml
```

If a flow contains blockers, generate segmented files instead:

```
e2e-tests/maestro-flows/android/<flow-name>-segment-1.yaml
e2e-tests/maestro-flows/android/<flow-name>-segment-2.yaml
e2e-tests/maestro-flows/ios/<flow-name>-segment-1.yaml
e2e-tests/maestro-flows/ios/<flow-name>-segment-2.yaml
```

### Flow File Template

```yaml
appId: <discovered from build.gradle.kts or Info.plist>
---
# Login (include only if flow requires authentication)
- runFlow:
    file: subflows/login.yaml
    env:
      PHONE: ${PHONE}
      OTP: ${OTP}
      PIN: ${PIN}
      APP_ID: ${APP_ID}

# Step 1: <description from screen-map step>
- tapOn:
    id: "element_id"         # Android
    # text: "Element Text"   # iOS — prefer this; comment out id form
- assertVisible:
    id: "verify_target"      # Android
    # text: "Visible Text"   # iOS
- takeScreenshot: screen-name

# ... more steps ...
```

### Mandatory Generation Rules

- Every flow that requires authentication starts with `runFlow: subflows/login.yaml`.
- Insert `takeScreenshot` after every `verify` step and at every screen transition.
- Insert `assertVisible` before any interaction to confirm the target screen is loaded. Maestro auto-waits up to 7 seconds for the element.
- In comparison mode flows, add `assertScreenshot` immediately after each `takeScreenshot`.
- Flows with `blocker` steps split into segments (see §3). Each segment file is self-contained with its own `appId` header.
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

## 8. Maestro CLI Quick Reference

```bash
# Run a single flow targeting a specific Android device
maestro test --device emulator-5554 flow.yaml

# Run all flows in a directory targeting an iOS simulator
maestro test --device <UDID> --platform ios flows/ios/

# Run with environment variables (credentials for login subflow)
maestro test --device $DEVICE \
  -e PHONE=9876543210 \
  -e OTP=1234 \
  -e PIN=1234 \
  -e APP_ID=com.example.app \
  flow.yaml

# Run with JUnit output for CI parsing
maestro test --device $DEVICE \
  --format junit \
  --test-output-dir ./results \
  flow.yaml

# Run with detailed HTML report
maestro test --device $DEVICE \
  --format html-detailed \
  --test-output-dir ./results \
  flow.yaml

# Exit codes: 0 = all flows passed, 1 = one or more failures
```

**Device targeting:**
- Android emulator: `emulator-5554` (from `adb devices`)
- Android physical: serial number from `adb devices`
- iOS simulator: UDID from `xcrun simctl list devices`
- iOS physical: UDID from `instruments -s devices`

---

## 9. Known Limitations

These are Maestro behaviors to account for when generating flows.

| Limitation | Impact | Mitigation |
|---|---|---|
| iOS has no `back` command | Navigation flows break on iOS | Use `tapOn: "Back"` or `tapOn: { id: "back_button" }` |
| SwiftUI element hierarchy may be incomplete | `tapOn: { id: "..." }` fails silently | Follow iOS selector fallback strategy in §2 |
| Compose Multiplatform on iOS accessibility issues | Elements not discoverable | Add `Modifier.testTag()` in source, rebuild |
| Unicode input not supported on Android | Non-ASCII test data causes failures | Use ASCII-only characters for all test input values |
| `hideKeyboard` unreliable on iOS | Keyboard stays up, blocks next element | Tap outside the input field instead of using `hideKeyboard` |
| Dynamic content causes assertScreenshot false positives | Timestamps, counters differ between runs | Use `cropOn` to exclude the region, or lower threshold to 95% |
| `assertWithAI` requires Maestro Cloud | Cannot use AI comparison offline | Use pixel-based `assertScreenshot` for local runs; reserve `assertWithAI` for CI with Maestro Cloud |
| Segment files must not include `launchApp` | App state is lost if relaunched mid-flow | Segment 2+ must omit `- launchApp`; continue from existing app state |
| `tapOn: { point: "x,y" }` is fragile | Coordinates break across different device screen sizes | Only use as last resort; prefer `id` or text selectors |

---

## 10. What Maestro Catches vs What It Doesn't

### Catches

- **Visual regressions** — layout shifts, missing elements, wrong colors detected via `assertScreenshot`
- **Unwired buttons** — `tapOn` fails if the element does not respond to interaction
- **Navigation breaks** — `assertVisible` fails if the expected screen does not load within 7 seconds
- **Missing data elements** — `assertVisible` on content elements catches absent API responses
- **Platform parity issues** — running the same flow definitions on Android and iOS surfaces divergent behavior

### Does Not Catch

- **Performance regressions** — Maestro has no timing metrics or frame-rate measurement
- **Memory leaks** — no heap monitoring or retention tracking
- **Network error handling** — requires a fake/mock server setup outside Maestro
- **Exact data correctness** — `assertVisible` confirms an element exists, not that its displayed value is correct
- **Accessibility compliance** — does not audit contrast ratios, touch target sizes, or screen reader labels
- **Animation and transition quality** — screenshot comparison only captures static frames
