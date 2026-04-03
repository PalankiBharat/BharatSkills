# Maestro Flow Templates

Reusable Maestro YAML templates for KMM migration E2E testing. Copy and adapt these to the feature under test. All flows assume devices are already booted and `ANDROID_SERIAL` / `IOS_UDID` are exported (see `device-slot-management.md`).

---

## Login Subflow (Fixed Credentials)

Use this when the app accepts a fixed test OTP (e.g. staging environment with OTP bypass).

```yaml
# e2e-tests/maestro-flows/<platform>/subflows/login.yaml
appId: ${APP_ID}
---
- launchApp:
    clearState: true
- assertVisible: "Phone Number"
- tapOn:
    id: "phone_field"
- inputText: ${PHONE}
- tapOn: "Continue"
- assertVisible: "Enter OTP"
- inputText: ${OTP}
- tapOn: "Verify"
- assertVisible: "Enter PIN"
- inputText: ${PIN}
- tapOn: "Confirm"
- assertVisible: "Home"
```

Run this subflow standalone to verify login works before running feature flows:

```bash
maestro test \
  --device "$ANDROID_SERIAL" \
  -e APP_ID=com.example.app \
  -e PHONE=9876543210 \
  -e OTP=1234 \
  -e PIN=1234 \
  e2e-tests/maestro-flows/android/subflows/login.yaml
```

Substitute `--device "$IOS_UDID" --platform ios` for iOS runs.

---

## Login Subflow (Real OTP — Segmented)

Use when the app sends a real OTP via SMS and no bypass exists. The flow is split into two segments with a manual pause between them.

### Segment 1 — Pre-OTP

```yaml
# e2e-tests/maestro-flows/<platform>/subflows/login-otp-segment-1.yaml
appId: ${APP_ID}
---
- launchApp:
    clearState: true
- assertVisible: "Phone Number"
- tapOn:
    id: "phone_field"
- inputText: ${PHONE}
- tapOn: "Continue"
- assertVisible: "Enter OTP"
# STOP HERE — user enters OTP manually on device
```

### Segment 2 — Post-OTP

```yaml
# e2e-tests/maestro-flows/<platform>/subflows/login-otp-segment-2.yaml
appId: ${APP_ID}
---
- assertVisible: "Enter PIN"
- inputText: ${PIN}
- tapOn: "Confirm"
- assertVisible: "Home"
```

### Orchestration (Claude's bash loop)

```bash
# Step 1: Navigate to OTP screen
maestro test \
  --device "$DEVICE" \
  -e APP_ID="$APP_ID" \
  -e PHONE="$PHONE" \
  e2e-tests/maestro-flows/android/subflows/login-otp-segment-1.yaml

# Step 2: Block and wait for user
echo "BLOCKER: The OTP screen is now visible on the device."
echo "Enter the OTP received on $PHONE, then type 'done' and press Enter:"
read -r CONFIRMATION
if [ "$CONFIRMATION" != "done" ]; then
  echo "Aborting OTP flow."
  exit 1
fi

# Step 3: Continue from PIN screen
maestro test \
  --device "$DEVICE" \
  -e APP_ID="$APP_ID" \
  -e PIN="$PIN" \
  e2e-tests/maestro-flows/android/subflows/login-otp-segment-2.yaml
```

Note: The BLOCKER pattern applies to any flow step that requires a real-world side effect (SMS delivery, payment confirmation, external approval). Split the flow at the blocker point and use the same orchestration pattern.

---

## Per-Screen Verification Template — Baseline Mode

Use on first run to capture reference screenshots. Screenshots are saved to `e2e-tests/screenshots/<platform>/baseline/`.

```yaml
# e2e-tests/maestro-flows/<platform>/home-screen.yaml  (example: home screen)
appId: ${APP_ID}
---
- runFlow:
    file: subflows/login.yaml
    env:
      PHONE: ${PHONE}
      OTP: ${OTP}
      PIN: ${PIN}
      APP_ID: ${APP_ID}

# Navigate to target screen
- tapOn: "Tab Name"
- assertVisible: "Screen Title"

# Verify key elements are present before capturing
- assertVisible:
    id: "element_id"
- assertVisible: "Expected Text"

# Capture baseline screenshot
- takeScreenshot: ${SCREEN_NAME}
```

Run in baseline mode:

```bash
maestro test \
  --device "$ANDROID_SERIAL" \
  -e APP_ID=com.example.app \
  -e PHONE=9876543210 \
  -e OTP=1234 \
  -e PIN=1234 \
  -e SCREEN_NAME=home \
  e2e-tests/maestro-flows/android/home-screen.yaml

# Move the captured screenshot to the baseline directory
mkdir -p e2e-tests/screenshots/android/baseline
mv home.png e2e-tests/screenshots/android/baseline/home.png
```

---

## Per-Screen Verification Template — Comparison Mode

Use on subsequent runs after the migration to detect visual regressions. Adds `assertScreenshot` after `takeScreenshot`.

```yaml
# e2e-tests/maestro-flows/<platform>/home-screen.yaml  (comparison variant)
appId: ${APP_ID}
---
- runFlow:
    file: subflows/login.yaml
    env:
      PHONE: ${PHONE}
      OTP: ${OTP}
      PIN: ${PIN}
      APP_ID: ${APP_ID}

# Navigate to target screen
- tapOn: "Tab Name"
- assertVisible: "Screen Title"

# Verify key elements
- assertVisible:
    id: "element_id"
- assertVisible: "Expected Text"

# Capture comparison screenshot
- takeScreenshot: ${SCREEN_NAME}

# Compare against baseline
- assertScreenshot:
    path: ${BASELINE_DIR}/${SCREEN_NAME}.png
    thresholdPercentage: 97
    cropOn:
      id: "content_area"
```

### Fallback: content area element not found

If the `cropOn` element does not exist on the current screen (e.g. dynamic content, missing ID), fall back to full-screen comparison with a more lenient threshold to account for status bar differences:

```yaml
- assertScreenshot:
    path: ${BASELINE_DIR}/${SCREEN_NAME}.png
    thresholdPercentage: 95
```

The agent must check for the presence of `content_area` before deciding which variant to use. If `assertVisible: {id: "content_area"}` would fail, use the full-screen fallback.

Run in comparison mode:

```bash
maestro test \
  --device "$ANDROID_SERIAL" \
  -e APP_ID=com.example.app \
  -e PHONE=9876543210 \
  -e OTP=1234 \
  -e PIN=1234 \
  -e SCREEN_NAME=home \
  -e BASELINE_DIR=e2e-tests/screenshots/android/baseline \
  e2e-tests/maestro-flows/android/home-screen.yaml
```

---

## Full Flow Template (Multi-Screen Journey)

Use to test a complete user journey across multiple screens in a single flow. Captures screenshots at each step.

```yaml
# e2e-tests/maestro-flows/<platform>/feature-flow.yaml
appId: ${APP_ID}
---
- runFlow:
    file: subflows/login.yaml
    env:
      PHONE: ${PHONE}
      OTP: ${OTP}
      PIN: ${PIN}
      APP_ID: ${APP_ID}

# Step 1: Verify home screen
- assertVisible: "Home"
- takeScreenshot: home

# Step 2: Navigate to feature
- tapOn: "Feature Tab"
- assertVisible: "Feature Screen"
- takeScreenshot: feature-screen

# Step 3: Perform the primary action
- tapOn:
    id: "action_button"
- assertVisible: "Success"
- takeScreenshot: feature-success
```

### Segmenting a full flow at a blocker

If any step in the journey triggers a blocker (real OTP, real payment, external confirmation), split the full flow file into two:

```
feature-flow-segment-1.yaml   # steps before the blocker
feature-flow-segment-2.yaml   # steps after the blocker
```

Use the same bash orchestration pattern described in the Login Subflow (Real OTP) section above.

---

## CLI Reference

### Run a single flow on Android

```bash
maestro test \
  --device "$ANDROID_SERIAL" \
  -e APP_ID=com.example.app \
  flow.yaml
```

### Run all flows in a directory on iOS

```bash
maestro test \
  --device "$IOS_UDID" \
  --platform ios \
  -e APP_ID=com.example.app \
  e2e-tests/maestro-flows/ios/
```

### Run with JUnit output (for CI)

```bash
maestro test \
  --device "$DEVICE" \
  --format junit \
  --test-output-dir ./e2e-tests/results/comparison/android \
  flow.yaml
```

### Run with all common environment variables

```bash
maestro test \
  --device "$ANDROID_SERIAL" \
  -e APP_ID=com.example.app \
  -e PHONE=9876543210 \
  -e OTP=1234 \
  -e PIN=1234 \
  -e SCREEN_NAME=home \
  -e BASELINE_DIR=e2e-tests/screenshots/android/baseline \
  flow.yaml
```

### Run multiple flows concurrently (different devices)

```bash
# Launch Android and iOS in parallel — each targets its own device
maestro test --device "$ANDROID_SERIAL" -e APP_ID=com.example.app \
  e2e-tests/maestro-flows/android/ &

maestro test --device "$IOS_UDID" --platform ios -e APP_ID=com.example.app \
  e2e-tests/maestro-flows/ios/ &

wait
```

---

## File Structure

All Maestro-related files live under `e2e-tests/` at the root of the worktree:

```
e2e-tests/
  maestro-flows/
    android/
      subflows/
        login.yaml                    # fixed-credential login
        login-otp-segment-1.yaml      # real-OTP pre-pause
        login-otp-segment-2.yaml      # real-OTP post-pause
      home-screen.yaml
      feature-flow.yaml
      feature-flow-segment-1.yaml     # only if the flow has a blocker
      feature-flow-segment-2.yaml     # only if the flow has a blocker
    ios/
      subflows/
        login.yaml
        login-otp-segment-1.yaml
        login-otp-segment-2.yaml
      home-screen.yaml
      feature-flow.yaml
  screenshots/
    android/
      baseline/
        .cache-key                    # checksum/tag of the build that produced baselines
        home.png
        feature-screen.png
        feature-success.png
      comparison/
        home.png
        feature-screen.png
        feature-success.png
    ios/
      baseline/
        .cache-key
        home.png
        feature-screen.png
        feature-success.png
      comparison/
        home.png
        feature-screen.png
        feature-success.png
  results/
    baseline/
      android/                        # JUnit XML from baseline runs
      ios/
    comparison/
      android/                        # JUnit XML from comparison runs
      ios/
  test-report.md                      # human-readable summary generated post-run
```

### `.cache-key` format

The `.cache-key` file contains a single line identifying the build that captured the baseline screenshots. Use the git commit SHA of the pre-migration build:

```
git-sha:<commit-sha>  build-date:<YYYY-MM-DD>
```

Agents compare the current git SHA against this file to detect stale baselines. If the baseline is stale (e.g. unrelated UI changes landed), regenerate baselines before running comparison mode.

---

## Agent Decision Rules

Follow these rules mechanically when choosing templates and modes.

| Condition | Action |
|---|---|
| No baseline screenshots exist for this platform | Run in baseline mode first, then comparison mode |
| `.cache-key` SHA does not match current base branch HEAD | Warn user, ask whether to regenerate baselines |
| `cropOn` element ID is not guaranteed stable | Use full-screen fallback with threshold 95 |
| Any flow step triggers a real-world side effect | Split at that step, use BLOCKER orchestration |
| Android and iOS flows are independent | Run both concurrently via background processes |
| `maestro test` exits non-zero | Capture stdout+stderr, attach to test-report.md, fail the stage |
| Comparison threshold fails | Do not auto-adjust threshold — report the diff percentage and let the user decide |
