---
name: kmm-test
description: >
  Appium-based visual and functional parity testing for KMM migrations. Uses Appium for device
  interaction (parallel-safe, handles complex login flows) and Claude vision for screenshot
  comparison. Generates Appium flows from screen-map.json, captures baseline screenshots from
  master branch, compares against current branch, reports visual regressions and functional
  failures. Run at any stage — after Phase 4 (Android wiring), after Phase 5 (iOS wiring), or
  independently for debugging completed stories.
  Use when the user says "/kmm-test", "test my migration", "run visual parity", "compare with master",
  "run Appium tests", "check screenshots", or any request to verify visual/functional parity.
argument-hint: "[android|ios|both] [--screen <name>] [--skip-baseline]"
---

# KMM Test — Appium Visual & Functional Parity

## On Invocation — Parse and Discover

### 1. Parse Arguments

- **Platform:** `android`, `ios`, or `both` (default: `both`)
- **`--screen <name>`:** optional filter — test only this one screen/flow
- **`--skip-baseline`:** reuse cached baseline screenshots without rebuilding or rechecking cache

### 2. Detect Gameplan Context

Check for an active session:

```bash
ls ~/dev/gameplans/.sessions/*.active 2>/dev/null | head -1
```

If a `.active` file is found, read it to get the gameplan name, then read `~/dev/gameplans/<name>/PLAN.md` to find the worktree path.

### 3. Read Gameplan Files

Read in priority order from the worktree's `e2e-tests/` directory (or the gameplan directory if no worktree):

1. `screen-map.json` — primary source: has flows with structured steps
2. `migration-guide.md` — secondary: has screen list, navigation hints
3. `PLAN.md` — tertiary: has module context, screen references

### 4. If No Gameplan Files Found

Stop and ask the user:

> "No gameplan found. Please provide:
> (a) Screens to test with navigation instructions
> (b) App package name / bundle ID
> (c) Login credentials if needed (phone, PIN, OTP)"

Generate a temporary `e2e-tests/screen-map.json` from the user's description before continuing.

### 5. Discover App ID

- Android: `grep -r "applicationId" app/build.gradle.kts | head -1`
- iOS: `grep "PRODUCT_BUNDLE_IDENTIFIER" *.xcodeproj/project.pbxproj | head -1`
  - Fallback: `/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" <path>/Info.plist`

Export: `APP_ID`, `PHONE`, `OTP`, `PIN` (from gameplan credentials section or user input).

---

## Step 0: Appium Prerequisite Check

```bash
# Check Appium
which appium || echo "APPIUM_NOT_FOUND"
appium --version

# Check Appium drivers
appium driver list --installed 2>&1 | grep -E "uiautomator2|xcuitest"

# Check Python dependencies
python3 -c "import appium; import yaml" 2>&1 || echo "PYTHON_DEPS_MISSING"
```

If `APPIUM_NOT_FOUND` or `PYTHON_DEPS_MISSING`: output the following and STOP — do not proceed.

> "Appium is required but not installed. Install with:"
> ```bash
> npm install -g appium
> appium driver install uiautomator2
> appium driver install xcuitest
> pip3 install Appium-Python-Client PyYAML
> ```

---

## Step 1: Device Slot Allocation

Read `references/device-slot-management.md` for the full protocol before executing any step here.

1. Read `~/.claude/kmm-device-slots.json`. If the file does not exist, create it:
   ```json
   {"slots": []}
   ```

2. Scan slots for an entry matching the current worktree path. If found, reuse it — skip creation.

3. If no matching slot, create a new one:
   - **Android:**
     ```bash
     avdmanager create avd \
       -n "kmm-<name>" \
       -k "system-images;android-34;google_apis;arm64-v8a" \
       --device "pixel_6" \
       --force
     ```
     Boot the AVD, capture the serial from `adb devices`.
   - **iOS:**
     ```bash
     xcrun simctl create "kmm-<name>" "iPhone 16" "iOS-18-0"
     ```
     Boot the simulator, capture the UDID from `xcrun simctl list devices booted`.
   - Allocate a fake server port from the range `8089–8189` (pick the first unused port).
   - Read the Appium port fields from the slot config: `appium_port`, `system_port`, `mjpeg_port`.
   - Write the new slot entry to `kmm-device-slots.json`.

4. Verify devices are booted:
   ```bash
   adb devices | grep $ANDROID_SERIAL
   xcrun simctl list devices booted | grep $IOS_UDID
   ```
   If not booted, boot them before continuing.

5. Export: `ANDROID_SERIAL`, `IOS_UDID`, `FAKE_PORT`, `APPIUM_PORT`, `SYSTEM_PORT`, `MJPEG_PORT`.

6. Start the Appium server on the allocated port:
   ```bash
   appium --port $APPIUM_PORT --base-path /wd/hub --allow-insecure chromedriver_autodownload &
   APPIUM_PID=$!
   sleep 3
   curl -s http://localhost:$APPIUM_PORT/wd/hub/status | grep -q '"ready":true'
   ```
   If the readiness check fails, stop and report: "Appium server did not start on port $APPIUM_PORT."

---

## Step 2: Generate Appium Flows

Read `references/appium-testing.md` for the full mapping rules and `references/appium-flow-templates.md` for YAML templates and Python driver before generating any files.

1. Read `e2e-tests/screen-map.json`.

2. If `--screen` filter is provided, only generate flows for the matching screen/flow name.

3. For each flow in `screen-map.json`, generate:
   - `e2e-tests/appium-flows/android/<flow-name>.yaml`
   - `e2e-tests/appium-flows/ios/<flow-name>.yaml`

   Apply platform-specific rules:
   - **Android:** `selector: { id: "element_id" }` uses resource-id; `action: back` works natively
   - **iOS:** `selector: { accessibility_id: "element_id" }` or `{ text: "Label" }` preferred; `action: back` taps the back button element

   After each `verify` step, insert a screenshot capture step in the YAML so the driver saves a named screenshot.

   If the flow starts with login, prepend a reference to the login subflow.

   If the flow has `blocker` steps, split into numbered segments (e.g., `<flow-name>-segment-1.yaml`, `<flow-name>-segment-2.yaml`).

4. Generate a login subflow at:
   - `e2e-tests/appium-flows/android/subflows/login.yaml`
   - `e2e-tests/appium-flows/ios/subflows/login.yaml`

   If the login requires OTP, split into:
   - `login-otp-segment-1.yaml` (enters credentials, triggers OTP send)
   - `login-otp-segment-2.yaml` (enters OTP, completes login)

5. Generate the Python driver script at `e2e-tests/appium_driver.py` if it does not already exist. Use the template from `references/appium-flow-templates.md`.

---

## Step 3: Capture Baseline Screenshots (master branch)

Only run for the platform(s) matching the invocation argument. If `--platform ios`, skip Android baselines entirely.

### Cache check

```bash
cat e2e-tests/screenshots/<platform>/baseline/.cache-key 2>/dev/null
git rev-parse master
```

- If the cache key matches `git rev-parse master` AND `--skip-baseline` was NOT passed → skip baseline capture. Report: "Using cached baselines from master@`<short-hash>`." Proceed to Step 4.
- If `--skip-baseline` was passed → skip regardless of cache state.
- If cache miss → capture fresh baselines:

### Fresh baseline capture

a. Create a temporary worktree:
```bash
git worktree add /tmp/kmm-baseline-$(date +%s) master
```

b. Build from the temp worktree:
- **Android:** `cd /tmp/kmm-baseline-... && ./gradlew :app:assembleDebug`
- **iOS:** `xcodebuild -workspace ... -scheme ... -destination 'id=<UDID>' build`

c. Install on the allocated device:
- **Android:** `adb -s $ANDROID_SERIAL install -r <apk-path>`
- **iOS:** `xcrun simctl install $IOS_UDID <app-path>`

d. Run baseline flows:
```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/<platform>/<flow>.yaml \
  --device $ANDROID_SERIAL \
  --appium-port $APPIUM_PORT \
  --system-port $SYSTEM_PORT \
  --screenshot-dir e2e-tests/screenshots/<platform>/baseline/ \
  --env PHONE=$PHONE OTP=$OTP PIN=$PIN APP_ID=$APP_ID PLATFORM=android
```

e. For flows with blocker segments: run segment 1 → pause and prompt:
> "BLOCKER: `<message>`. Complete this step on the device, then type 'done' to continue."
Wait for user confirmation, then run segment 2.

f. Uninstall:
- **Android:** `adb -s $ANDROID_SERIAL uninstall $APP_ID`
- **iOS:** `xcrun simctl uninstall $IOS_UDID $APP_ID`

g. Write cache key:
```bash
git rev-parse master > e2e-tests/screenshots/<platform>/baseline/.cache-key
```

h. Clean up:
```bash
git worktree remove /tmp/kmm-baseline-...
```

---

## Step 4: Capture Comparison Screenshots (current branch)

1. Build from the current worktree:
   - **Android:** `./gradlew :app:assembleDebug`
   - **iOS:** `xcodebuild -workspace ... -scheme ... -destination 'id=<UDID>' build`

2. Install on the allocated device (master build was already uninstalled in Step 3):
   - **Android:** `adb -s $ANDROID_SERIAL install -r <apk-path>`
   - **iOS:** `xcrun simctl install $IOS_UDID <app-path>`

3. Run comparison flows:
   ```bash
   python3 e2e-tests/appium_driver.py \
     --flow e2e-tests/appium-flows/<platform>/<flow>.yaml \
     --device $ANDROID_SERIAL \
     --appium-port $APPIUM_PORT \
     --system-port $SYSTEM_PORT \
     --screenshot-dir e2e-tests/screenshots/<platform>/comparison/ \
     --env PHONE=$PHONE OTP=$OTP PIN=$PIN APP_ID=$APP_ID PLATFORM=android
   ```

4. For flows with blocker segments: same pause-and-resume protocol as Step 3e.

5. Screenshots are saved to `e2e-tests/screenshots/<platform>/comparison/`.

---

## Step 5: Diff and Report

Claude vision reviews ALL screenshots — no pixel threshold, no assertScreenshot. Claude understands what it's looking at.

### 1. Per-screen vision review

For each screen that was captured, read both screenshots:
- Baseline: `e2e-tests/screenshots/<platform>/baseline/<screen-name>.png`
- Comparison: `e2e-tests/screenshots/<platform>/comparison/<screen-name>.png`

Claude compares and reports on:
- **Layout:** spacing, alignment, sizing differences
- **Elements:** missing, extra, or changed elements
- **Colors/styles:** wrong colors, font changes
- **Data:** placeholder text, "loading...", empty fields, stale data
- **Tap audit:** "Did the button tap produce a visible change?"

Classify each finding as one of:
- `VISUAL_REGRESSION` — layout shift, missing element, wrong color, dead/missing button → needs a fix
- `EXPECTED_CHANGE` — intentional platform-native rendering difference from the migration
- `FALSE_POSITIVE` — status bar change, animation frame, dynamic content (timestamp, avatar, etc.)

### 2. Classify functional failures

Functional failures (action steps that errored in the driver) are definitive — the button does not exist or the screen did not load. Always mark `VISUAL_REGRESSION`.

### 3. Cross-platform parity (after both platforms tested)

For each screen, read both platform comparison screenshots:
- Android: `e2e-tests/screenshots/android/comparison/<screen-name>.png`
- iOS: `e2e-tests/screenshots/ios/comparison/<screen-name>.png`

Claude checks structural equivalence — not pixel-identical (different renderers), but functionally equivalent layout and content.

### 4. Generate report

Write `e2e-tests/results/test-report.md`:

```markdown
# KMM Test Report — <date>

Platform: <android|ios|both>
Baseline: master@<short-hash>
Branch: <current-branch>

| Screen | Platform | Status | Notes |
|--------|----------|--------|-------|
| Home | Android | PASS | |
| Settings | Android | VISUAL_REGRESSION | Missing bottom bar |
| Home | iOS | PASS | |
| Settings | iOS | VISUAL_REGRESSION | Layout shift in header |
```

### 5. Present summary to user

Report:

> "X of Y screens passed visual parity. Z visual regressions found. N functional failures."

List each `VISUAL_REGRESSION` with the specific issue identified.

Then ask:

> "Fix these issues now, or review the screenshots first?"

Wait for the user's answer before proceeding to Step 6.

---

## Step 6: Debug Loop (on failures)

For each screen marked `VISUAL_REGRESSION` or functional failure:

1. Read the comparison screenshot.
2. Read the relevant source files:
   - Android: the Composable for this screen
   - iOS: the SwiftUI view for this screen
3. Identify the likely cause of the visual difference from the two screenshots.
4. Fix the source code.
5. Rebuild → reinstall → rerun ONLY the failing screen's flow (not all flows):
   ```bash
   python3 e2e-tests/appium_driver.py \
     --flow e2e-tests/appium-flows/<platform>/<flow-name>.yaml \
     --device $ANDROID_SERIAL \
     --appium-port $APPIUM_PORT \
     --system-port $SYSTEM_PORT \
     --screenshot-dir e2e-tests/screenshots/<platform>/comparison/ \
     --env PHONE=$PHONE OTP=$OTP PIN=$PIN APP_ID=$APP_ID PLATFORM=android
   ```
6. Re-compare using Claude vision: if PASS → move to next failure. If still failing → iterate.
7. **Max 3 iterations per screen.** After 3 failures on the same screen, stop and escalate to the user with:
   - Both screenshots (paths)
   - The source file(s) modified
   - What was tried in each iteration and what the result was

---

## Step 7: Cleanup

After testing completes (whether passing, failing, or escalating), stop the Appium server:

```bash
kill $APPIUM_PID  # Stop Appium server
```

This frees the port for other worktrees.

---

## Rules

- **Never skip Appium testing.** If invoked during Phase 4 or Phase 5 of the KMM workflow, Appium automated flows are MANDATORY — the orchestrator cannot mark the phase complete without them passing.
- **Baseline caching is the default.** Only rebuild baselines when master HEAD has changed. The `--skip-baseline` flag skips comparison-mode flows without rebuilding baselines — it does not affect cache validation logic.
- **Token efficiency.** Claude does NOT interact with devices. Appium handles all device interaction. Claude reads saved screenshot files for every screen to review them — this is intentional and required.
- **OTP rate limits.** Default test credentials use a fixed OTP (no rate limit). For real OTP flows, warn the user before running: "Login OTP has rate limits (max 2–3 resends → 10-min block). Each baseline + comparison run = 2 logins."
- **One device per worktree.** Never share an emulator or simulator between worktrees. The slot system in `references/device-slot-management.md` guarantees isolation — always follow it.
- **Clean installs.** Always uninstall before installing a new build. Never install over an existing build — leftover state from the previous build can mask bugs.
- **Login is required for all flows** unless a flow is explicitly marked `requiresLogin: false` in `screen-map.json`. Generate the login subflow and prepend it to every flow by default.
- **Device isolation is absolute.** Every `adb` command MUST include `-s $ANDROID_SERIAL` and every `xcrun simctl` command MUST use `$IOS_UDID` (never `booted`). Bare `adb install`, `adb shell`, `adb logcat`, `xcrun simctl install booted`, etc. will target whichever device the OS picks first — which may be another worktree's emulator/simulator. Read the device serial from the PLAN.md header (`<!-- DEVICE: android=... | ios=... -->`) and use it in EVERY command. No exceptions.
- **Always stop the Appium server after testing completes** to free the port for other worktrees.

---

## References

- `references/appium-testing.md` — screen-map→YAML mapping rules, iOS selector fallback chain, blocker segmentation, screenshot capture configuration
- `references/device-slot-management.md` — device slot allocation, creation commands, cleanup protocol
- `references/appium-flow-templates.md` — reusable YAML templates for login, per-screen, and multi-screen flows; Python driver script template
