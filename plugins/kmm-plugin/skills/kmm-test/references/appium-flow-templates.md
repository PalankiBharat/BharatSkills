# Appium Flow Templates

Reusable YAML flow templates for KMM migration E2E testing via Appium. Instead of Maestro YAML executed directly by the Maestro CLI, these flows use a custom YAML format read by `appium_driver.py`, which translates each step into Appium WebDriver calls. All flows assume devices are already booted and the device serial/UDID is known (see `device-slot-management.md`).

---

## Login Subflow (Fixed Credentials)

Use this when the app accepts a fixed test OTP (e.g. staging environment with OTP bypass).

```yaml
# e2e-tests/appium-flows/<platform>/subflows/login.yaml
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: launch
    clearState: true
  - action: verify
    selector: { text: "Phone Number" }
  - action: tap
    selector: { id: "phone_field" }
  - action: type
    selector: { id: "phone_field" }
    value: ${PHONE}
  - action: tap
    selector: { text: "Continue" }
  - action: verify
    selector: { text: "Enter OTP" }
  - action: type
    selector: { id: "otp_field" }
    value: ${OTP}
  - action: tap
    selector: { text: "Verify" }
  - action: verify
    selector: { text: "Enter PIN" }
  - action: type
    selector: { id: "pin_field" }
    value: ${PIN}
  - action: tap
    selector: { text: "Confirm" }
  - action: verify
    selector: { text: "Home" }
```

Run this subflow standalone to verify login works before running feature flows:

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/subflows/login.yaml \
  --device emulator-5554 \
  --appium-port 4723 \
  --system-port 8200 \
  --env PHONE=9876543210 OTP=1234 PIN=1234 APP_ID=com.example.app PLATFORM=android
```

Substitute `--device <udid> --platform ios` for iOS runs.

---

## Login Subflow (Real OTP — Segmented)

Use when the app sends a real OTP via SMS and no bypass exists. The flow is split into two segments with a manual pause between them. The bash orchestration script pauses between segments for the user to enter the OTP on the device.

### Segment 1 — Pre-OTP

```yaml
# e2e-tests/appium-flows/<platform>/subflows/login-otp-segment-1.yaml
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: launch
    clearState: true
  - action: verify
    selector: { text: "Phone Number" }
  - action: tap
    selector: { id: "phone_field" }
  - action: type
    selector: { id: "phone_field" }
    value: ${PHONE}
  - action: tap
    selector: { text: "Continue" }
  - action: verify
    selector: { text: "Enter OTP" }
  # STOP HERE — user enters OTP manually on device
```

### Segment 2 — Post-OTP

```yaml
# e2e-tests/appium-flows/<platform>/subflows/login-otp-segment-2.yaml
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: verify
    selector: { text: "Enter PIN" }
  - action: type
    selector: { id: "pin_field" }
    value: ${PIN}
  - action: tap
    selector: { text: "Confirm" }
  - action: verify
    selector: { text: "Home" }
```

### Orchestration (Claude's bash loop)

```bash
# Step 1: Navigate to OTP screen
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/subflows/login-otp-segment-1.yaml \
  --device "$DEVICE" \
  --appium-port "$APPIUM_PORT" \
  --system-port "$SYSTEM_PORT" \
  --env APP_ID="$APP_ID" PHONE="$PHONE" PLATFORM=android

# Step 2: Block and wait for user
echo "BLOCKER: The OTP screen is now visible on the device."
echo "Enter the OTP received on $PHONE, then type 'done' and press Enter:"
read -r CONFIRMATION
if [ "$CONFIRMATION" != "done" ]; then
  echo "Aborting OTP flow."
  exit 1
fi

# Step 3: Continue from PIN screen
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/subflows/login-otp-segment-2.yaml \
  --device "$DEVICE" \
  --appium-port "$APPIUM_PORT" \
  --system-port "$SYSTEM_PORT" \
  --env APP_ID="$APP_ID" PIN="$PIN" PLATFORM=android
```

Note: The BLOCKER pattern applies to any flow step that requires a real-world side effect (SMS delivery, payment confirmation, external approval). Split the flow at the blocker point and use the same orchestration pattern. Alternatively, use `action: blocker` inline in the YAML and let the driver script handle the pause — but the bash-level split gives finer control over exit codes.

---

## Per-Screen Verification Template — Baseline Mode

Use on first run to capture reference screenshots. Screenshots are saved to `e2e-tests/screenshots/<platform>/baseline/`.

```yaml
# e2e-tests/appium-flows/<platform>/home-screen.yaml  (example: home screen)
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: runFlow
    file: subflows/login.yaml

  # Navigate to target screen
  - action: tap
    selector: { id: "tab_name" }
  - action: verify
    selector: { text: "Screen Title" }

  # Verify key elements are present before capturing
  - action: verify
    selector: { id: "element_id" }

  # Capture baseline screenshot
  - action: screenshot
    name: screen-name
```

Run in baseline mode:

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/baseline \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

The driver writes `<name>.png` directly into `--screenshot-dir`, so no manual `mv` step is needed. After the run, write a `.cache-key` file:

```bash
echo "git-sha:$(git rev-parse HEAD)  build-date:$(date +%F)" \
  > e2e-tests/screenshots/android/baseline/.cache-key
```

---

## Per-Screen Verification Template — With Interactive Audit

Use this variant when you want to enumerate every interactive element on a screen and capture a screenshot after tapping each one. Useful for thorough regression coverage of a newly migrated screen.

```yaml
# e2e-tests/appium-flows/<platform>/home-screen-audit.yaml
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: runFlow
    file: subflows/login.yaml

  # Navigate to target screen
  - action: tap
    selector: { id: "tab_name" }
  - action: verify
    selector: { text: "Screen Title" }

  # Capture pre-audit baseline
  - action: screenshot
    name: screen-name

  # Audit: tap each interactive element and screenshot the result
  - action: tap
    selector: { id: "action_button" }
  - action: screenshot
    name: screen-name-tap-action_button
  - action: back

  - action: tap
    selector: { id: "settings_button" }
  - action: screenshot
    name: screen-name-tap-settings_button
  - action: back
```

Run with `--audit` to additionally dump the full clickable element list as JSON before executing steps:

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen-audit.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/comparison \
  --audit \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

The audit JSON is written to `<screenshot-dir>/<screen-name>-elements.json` and lists every clickable element with its resource-id, text, and bounds.

---

## Full Multi-Screen Journey Template

Use to test a complete user journey across multiple screens in a single flow. Captures screenshots at each step.

```yaml
# e2e-tests/appium-flows/<platform>/feature-flow.yaml
appId: ${APP_ID}
platform: ${PLATFORM}
---
steps:
  - action: runFlow
    file: subflows/login.yaml

  # Step 1: Verify home screen
  - action: verify
    selector: { text: "Home" }
  - action: screenshot
    name: home

  # Step 2: Navigate to feature
  - action: tap
    selector: { id: "feature_tab" }
  - action: verify
    selector: { text: "Feature Screen" }
  - action: screenshot
    name: feature-screen

  # Step 3: Perform the primary action
  - action: tap
    selector: { id: "action_button" }
  - action: verify
    selector: { text: "Success" }
  - action: screenshot
    name: feature-success
```

### Segmenting a full flow at a blocker

If any step in the journey triggers a blocker (real OTP, real payment, external confirmation), split the full flow file into two:

```
feature-flow-segment-1.yaml   # steps before the blocker
feature-flow-segment-2.yaml   # steps after the blocker
```

Use the same bash orchestration pattern described in the Login Subflow (Real OTP) section above.

---

## Python Driver Script

This is the full `appium_driver.py` that the `/kmm-test` skill generates into the project once and commits. It is the bridge between the YAML flow format and the Appium WebDriver API.

```python
#!/usr/bin/env python3
"""
Appium flow driver for KMM migration testing.
Reads YAML flow definitions and executes them via Appium.
Generated by /kmm-test skill — committed to e2e-tests/appium_driver.py
"""
import argparse
import json
import os
import re
import sys
import time
import yaml
from pathlib import Path

from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException


def parse_args():
    parser = argparse.ArgumentParser(description="Appium YAML flow driver")
    parser.add_argument("--flow", required=True, help="Path to YAML flow file")
    parser.add_argument("--device", required=True, help="Device serial (Android) or UDID (iOS)")
    parser.add_argument("--appium-port", type=int, default=4723, help="Appium server port")
    parser.add_argument("--system-port", type=int, default=8200, help="UiAutomator2 system port")
    parser.add_argument("--mjpeg-port", type=int, default=9100, help="MJPEG server port")
    parser.add_argument("--screenshot-dir", default="./screenshots", help="Screenshot output directory")
    parser.add_argument("--platform", choices=["android", "ios"], default="android")
    parser.add_argument("--app", help="Path to APK/APP file (overrides appId)")
    parser.add_argument("--env", nargs="*", help="Environment variables: KEY=VALUE pairs")
    parser.add_argument("--audit", action="store_true", help="Enable interactive element audit mode")
    return parser.parse_args()


def resolve_env(value, env_vars):
    """Replace ${VAR} placeholders with env var values."""
    if not isinstance(value, str):
        return value
    def replacer(match):
        key = match.group(1)
        return env_vars.get(key, match.group(0))
    return re.sub(r'\$\{(\w+)\}', replacer, value)


def resolve_selector(selector, env_vars, platform):
    """Convert YAML selector to Appium (by, value) tuple."""
    selector = {k: resolve_env(v, env_vars) for k, v in selector.items()}

    if "id" in selector:
        if platform == "ios":
            return AppiumBy.ACCESSIBILITY_ID, selector["id"]
        return AppiumBy.ID, selector["id"]
    elif "accessibility_id" in selector:
        return AppiumBy.ACCESSIBILITY_ID, selector["accessibility_id"]
    elif "text" in selector:
        if platform == "android":
            return AppiumBy.XPATH, f'//*[@text="{selector["text"]}"]'
        return AppiumBy.ACCESSIBILITY_ID, selector["text"]  # iOS: try accessibility first
    elif "xpath" in selector:
        return AppiumBy.XPATH, selector["xpath"]
    elif "point" in selector:
        return "point", selector["point"]
    else:
        raise ValueError(f"Unknown selector: {selector}")


def load_flow(flow_path, env_vars):
    """Load and parse a YAML flow file."""
    with open(flow_path) as f:
        content = f.read()

    # Split header and steps on the --- separator
    parts = content.split("---", 1)
    header = yaml.safe_load(parts[0]) if len(parts) > 1 else {}
    body = yaml.safe_load(parts[1] if len(parts) > 1 else parts[0])

    return header, body


def create_driver(args, header, env_vars):
    """Create Appium WebDriver with appropriate capabilities."""
    app_id = resolve_env(header.get("appId", ""), env_vars)
    platform = args.platform or header.get("platform", "android")

    if platform == "android":
        options = UiAutomator2Options()
        options.device_name = args.device
        options.udid = args.device
        options.system_port = args.system_port
        options.mjpeg_server_port = args.mjpeg_port
        options.auto_grant_permissions = True
        options.new_command_timeout = 120
        if args.app:
            options.app = args.app
        else:
            options.app_package = app_id
            options.app_activity = ""  # Let Appium find the launcher activity
            options.no_reset = True
    else:  # ios
        options = XCUITestOptions()
        options.device_name = args.device
        options.udid = args.device
        options.auto_accept_alerts = True
        options.new_command_timeout = 120
        if args.app:
            options.app = args.app
        else:
            options.bundle_id = app_id
            options.no_reset = True

    url = f"http://localhost:{args.appium_port}/wd/hub"
    return webdriver.Remote(url, options=options)


def execute_step(driver, step, env_vars, platform, screenshot_dir, flow_dir):
    """Execute a single flow step. Returns False on failure, True otherwise."""
    action = step["action"]

    if action == "launch":
        if step.get("clearState"):
            driver.reset()
        else:
            app_id = driver.capabilities.get("appPackage") or driver.capabilities.get("bundleId")
            driver.activate_app(app_id)

    elif action == "tap":
        by, value = resolve_selector(step["selector"], env_vars, platform)
        if by == "point":
            from selenium.webdriver.common.action_chains import ActionChains
            from selenium.webdriver.common.actions.pointer_input import PointerInput
            from selenium.webdriver.common.actions import interaction
            x, y = value
            actions = ActionChains(driver)
            actions.w3c_actions.devices = []
            finger = PointerInput(interaction.POINTER_TOUCH, "finger")
            actions.w3c_actions.add_pointer_input("touch", "finger", finger)
            actions.w3c_actions.pointer_action.move_to_location(x, y)
            actions.w3c_actions.pointer_action.pointer_down()
            actions.w3c_actions.pointer_action.pause(0.1)
            actions.w3c_actions.pointer_action.pointer_up()
            actions.perform()
        else:
            el = WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((by, value))
            )
            el.click()

    elif action == "type":
        by, value = resolve_selector(step["selector"], env_vars, platform)
        el = WebDriverWait(driver, 10).until(
            EC.presence_of_element_located((by, value))
        )
        text = resolve_env(step["value"], env_vars)
        el.clear()
        el.send_keys(text)

    elif action == "verify":
        by, value = resolve_selector(step["selector"], env_vars, platform)
        try:
            WebDriverWait(driver, 15).until(
                EC.presence_of_element_located((by, value))
            )
        except TimeoutException:
            print(f"VERIFY_FAIL: Element not found: {step['selector']}")
            return False

    elif action == "screenshot":
        name = resolve_env(step.get("name", "screenshot"), env_vars)
        path = os.path.join(screenshot_dir, f"{name}.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        driver.save_screenshot(path)
        print(f"Screenshot saved: {path}")

    elif action == "back":
        if platform == "android":
            driver.back()
        else:
            # iOS: try tapping back button by accessibility ID, then XPath
            try:
                el = driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Back")
                el.click()
            except NoSuchElementException:
                try:
                    el = driver.find_element(AppiumBy.XPATH, '//XCUIElementTypeButton[@name="Back"]')
                    el.click()
                except NoSuchElementException:
                    print("WARNING: Could not find back button on iOS")

    elif action == "swipe":
        direction = step.get("direction", "up")
        size = driver.get_window_size()
        cx, cy = size["width"] // 2, size["height"] // 2
        offsets = {
            "up":    (cx, cy + 300, cx, cy - 300),
            "down":  (cx, cy - 300, cx, cy + 300),
            "left":  (cx + 300, cy, cx - 300, cy),
            "right": (cx - 300, cy, cx + 300, cy),
        }
        sx, sy, ex, ey = offsets[direction]
        driver.swipe(sx, sy, ex, ey, 500)

    elif action == "runFlow":
        subflow_path = os.path.join(flow_dir, resolve_env(step["file"], env_vars))
        sub_header, sub_body = load_flow(subflow_path, env_vars)
        sub_dir = os.path.dirname(os.path.abspath(subflow_path))
        for sub_step in sub_body.get("steps", []):
            result = execute_step(driver, sub_step, env_vars, platform, screenshot_dir, sub_dir)
            if result is False:
                return False

    elif action == "blocker":
        msg = resolve_env(step.get("message", "Complete action on device"), env_vars)
        print(f"\nBLOCKER: {msg}")
        print("Complete the action on the device, then type 'done' and press Enter:")
        response = input().strip().lower()
        if response != "done":
            print("Aborting flow.")
            return False

    elif action == "wait":
        time.sleep(step.get("seconds", 2))

    else:
        print(f"WARNING: Unknown action '{action}', skipping")

    return True


def run_audit(driver, screenshot_dir, screen_name):
    """Discover all clickable elements and write them to JSON."""
    elements = driver.find_elements(AppiumBy.XPATH, '//*[@clickable="true"]')
    audit_results = []

    for i, el in enumerate(elements):
        try:
            el_id = el.get_attribute("resource-id") or el.get_attribute("name") or f"element_{i}"
            el_text = el.text or ""
            el_bounds = el.rect
            audit_results.append({
                "index": i,
                "id": el_id,
                "text": el_text,
                "bounds": el_bounds,
                "clickable": True,
            })
        except Exception:
            pass

    audit_path = os.path.join(screenshot_dir, f"{screen_name}-elements.json")
    os.makedirs(screenshot_dir, exist_ok=True)
    with open(audit_path, "w") as f:
        json.dump(audit_results, f, indent=2)
    print(f"Audit: found {len(audit_results)} clickable elements -> {audit_path}")
    return audit_results


def main():
    args = parse_args()

    # Parse env vars from KEY=VALUE pairs
    env_vars = {}
    if args.env:
        for item in args.env:
            key, _, val = item.partition("=")
            env_vars[key] = val
    env_vars["PLATFORM"] = args.platform

    # Load flow
    header, body = load_flow(args.flow, env_vars)
    flow_dir = os.path.dirname(os.path.abspath(args.flow))
    platform = args.platform or header.get("platform", "android")

    # Ensure screenshot directory exists
    os.makedirs(args.screenshot_dir, exist_ok=True)

    # Run pre-flight audit if requested (before creating a session)
    driver = create_driver(args, header, env_vars)

    try:
        if args.audit:
            run_audit(driver, args.screenshot_dir, "pre-run")

        success = True
        for step in body.get("steps", []):
            result = execute_step(driver, step, env_vars, platform, args.screenshot_dir, flow_dir)
            if result is False:
                success = False
                # Capture failure screenshot for diagnosis
                fail_path = os.path.join(args.screenshot_dir, "FAILURE.png")
                driver.save_screenshot(fail_path)
                print(f"Failure screenshot: {fail_path}")
                break

        if success:
            print("FLOW_PASS: All steps completed successfully")
        else:
            print("FLOW_FAIL: One or more steps failed")

        sys.exit(0 if success else 1)

    finally:
        driver.quit()


if __name__ == "__main__":
    main()
```

---

## CLI Reference

### Run a single flow on Android

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

### Run a single flow on iOS

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/ios/home-screen.yaml \
  --device "$IOS_UDID" \
  --platform ios \
  --appium-port 4724 \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=ios
```

### Run in baseline mode (write screenshots to baseline dir)

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/baseline \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

### Run in comparison mode (write screenshots to comparison dir)

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/comparison \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

After running comparison mode, diff screenshots manually or with ImageMagick:

```bash
compare -metric RMSE \
  e2e-tests/screenshots/android/baseline/home.png \
  e2e-tests/screenshots/android/comparison/home.png \
  /dev/null 2>&1
```

### Run with audit mode (dump clickable elements to JSON)

```bash
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/comparison \
  --audit \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android
```

### Run Android and iOS flows concurrently (different devices)

```bash
# Launch Android and iOS in parallel — each targets its own device and Appium port
python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/android/home-screen.yaml \
  --device "$ANDROID_SERIAL" \
  --appium-port 4723 \
  --system-port 8200 \
  --screenshot-dir e2e-tests/screenshots/android/comparison \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=android &

python3 e2e-tests/appium_driver.py \
  --flow e2e-tests/appium-flows/ios/home-screen.yaml \
  --device "$IOS_UDID" \
  --platform ios \
  --appium-port 4724 \
  --screenshot-dir e2e-tests/screenshots/ios/comparison \
  --env APP_ID=com.example.app PHONE=9876543210 OTP=1234 PIN=1234 PLATFORM=ios &

wait
```

### Install Python dependencies

```bash
pip install Appium-Python-Client selenium PyYAML
```

Appium server must be running before invoking the driver. Start it with a pinned port to match the `--appium-port` argument:

```bash
appium --port 4723 --address 127.0.0.1 &
```

---

## File Structure

All Appium-related files live under `e2e-tests/` at the root of the worktree:

```
e2e-tests/
  appium_driver.py              # Python driver (generated once, committed)
  appium-flows/
    android/
      subflows/
        login.yaml                    # fixed-credential login
        login-otp-segment-1.yaml      # real-OTP pre-pause
        login-otp-segment-2.yaml      # real-OTP post-pause
      home-screen.yaml
      funds-flow.yaml
      funds-flow-segment-1.yaml       # only if the flow has a blocker
      funds-flow-segment-2.yaml       # only if the flow has a blocker
    ios/
      subflows/
        login.yaml
        login-otp-segment-1.yaml
        login-otp-segment-2.yaml
      home-screen.yaml
      funds-flow.yaml
  screenshots/
    android/
      baseline/
        .cache-key                    # checksum/tag of the build that produced baselines
        home.png
        funds-screen.png
      comparison/
        home.png
        funds-screen.png
    ios/
      baseline/
        .cache-key
        home.png
        funds-screen.png
      comparison/
        home.png
        funds-screen.png
  results/
    test-report.md                    # human-readable summary generated post-run
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
| No baseline screenshots exist for this platform | Run in baseline mode first (`--screenshot-dir .../baseline`), then comparison mode |
| `.cache-key` SHA does not match current base branch HEAD | Warn user, ask whether to regenerate baselines |
| Any flow step triggers a real-world side effect | Split at that step, use BLOCKER bash orchestration (or inline `action: blocker`) |
| Android and iOS flows are independent | Run both concurrently via background processes (`&` + `wait`) with separate `--appium-port` values |
| `appium_driver.py` exits non-zero | Capture stdout+stderr, check `FAILURE.png`, attach findings to test-report.md, fail the stage |
| `VERIFY_FAIL` appears in driver output | The element was not found within 15 s — report the selector that failed, do not retry automatically |
| Screenshot diff exceeds acceptable threshold | Do not auto-adjust threshold — report the diff metric and let the user decide |
| `id` selector works on Android but not iOS | Use `accessibility_id` selector instead; on iOS `id` maps to `ACCESSIBILITY_ID` automatically via the driver |
| Appium server is not running | Start it with `appium --port <port> --address 127.0.0.1` before invoking the driver |
