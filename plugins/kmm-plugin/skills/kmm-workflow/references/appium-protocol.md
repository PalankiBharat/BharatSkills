# Appium Protocol — Verify-First Approach

This protocol replaces ad-hoc Appium testing. The key principle: NEVER guess selectors. Dump the real UI hierarchy first, extract verified element IDs, then generate flows from those IDs.

## Prerequisites

- Appium server running on allocated port: `appium --port $APPIUM_PORT --base-path /wd/hub`
- Device booted and app installed (use device serial from PLAN.md header)
- ALL device interaction goes through Appium Python driver — do NOT use mobile-mcp tools during test runs (competing sessions cause port conflicts)

---

## Step 1: UI Hierarchy Dump (MANDATORY — before generating ANY flow)

**Android:**
```bash
adb -s $ANDROID_SERIAL shell uiautomator dump /sdcard/ui_dump.xml
adb -s $ANDROID_SERIAL pull /sdcard/ui_dump.xml e2e-tests/hierarchy/android/
```
Parse XML → extract: resource-id, text, content-desc, class, bounds for every interactive element.

**iOS:**
```bash
# Via Appium session — dump page source
python3 -c "
from appium import webdriver
caps = {...}  # use allocated port, UDID
driver = webdriver.Remote(f'http://localhost:{APPIUM_PORT}/wd/hub', caps)
print(driver.page_source)
driver.quit()
" > e2e-tests/hierarchy/ios/page_source.xml
```
Parse XML → extract: name, label, type, accessible, coordinates.

**Store verified selectors in screen-map.json** — every element ID comes from the actual hierarchy dump, not from guessing.

---

## Step 2: Navigation Discovery (MANDATORY — before writing flows)

Do NOT assume navigation paths. Discover them:

1. Read the app's navigation code (Router.kt / NavHost / AppRouter) to understand the nav structure
2. OR dump the UI hierarchy at the main screen, identify actual navigation elements (bottom nav items, menu items, drawer items)
3. Verify: is the target screen in bottom nav? A menu item? Behind a drawer? Inside a sub-flow?
4. Record verified navigation paths in screen-map.json

**Common mistake:** Assuming "Funds" is in bottom nav when it's inside a "Jump To" menu. Always verify.

---

## Step 3: Generate Flows from Verified Selectors

Generate YAML flow files from the verified screen-map.json selectors:

**Rules:**
- Use ONLY selectors from the hierarchy dump — never invent IDs
- Android: resource-id primary, text secondary
- iOS: text-based primary, accessibility ID secondary (see appium-testing.md iOS Selector Fallback)
- **Interactive by default:** include typing in text fields, tapping presets/chips, expanding sections, switching tabs — not just static screenshots
- For flows with blockers (OTP, payment): split into segments with pause points

**Coverage confirmation (MANDATORY gate):**
After generating flow YAMLs, present the full numbered list of all screenshots that will be captured (including interactive states). Wait for user approval before proceeding. User may request additional interaction steps.

**Comparison flows:** Generate separate comparison YAMLs using xpath-contains selectors instead of exact text:
```yaml
# Baseline (exact): { text: "Available Balance" }
# Comparison (flexible): { xpath: "//*[contains(@text, 'Available')]" }
```
CMP migration commonly changes text casing — exact selectors from baseline will fail on feature branch.

---

## Step 4: Execute (Parallel Both Platforms)

Run Appium flows on Android and iOS SIMULTANEOUSLY using separate device slots.

**Pre-flight (before each run):**
1. Clear ADB port forwards: `adb -s $ANDROID_SERIAL forward --remove-all`
2. Verify Appium server: `curl -s http://localhost:$APPIUM_PORT/wd/hub/status | grep '"ready":true'`
3. If server down → restart, wait for ready
4. Set capabilities: `dontStopAppOnReset: true`, `shouldTerminateApp: false` (preserve login state between runs)

**Screenshot comparison:**
Dispatch sonnet subagents (batched 3-5 pairs) for comparison. Each subagent:
1. Reads baseline + comparison screenshots
2. Classifies: VISUAL_REGRESSION / EXPECTED_CHANGE / FALSE_POSITIVE
3. Returns text findings (no images in main context)

Orchestrator collects results and compiles report. Images stay OUT of main context.

**Functional check:** Any Appium flow with non-zero exit (tap failure, assertVisible failure) = functional failure.

---

## Step 5: Fix and Re-verify

On failure:
1. Fix the source code (not the test — unless the selector is genuinely wrong)
2. Rebuild and reinstall
3. Rerun ONLY the failing screen's flow (not the entire suite)
4. Max 3 iterations per screen
5. After 3 failures → escalate to user with: screenshots (baseline + comparison), error log, what was tried

**Emulator network failure:** If DNS resolution fails (`Unable to resolve host`):
1. Cold restart: `adb -s $ANDROID_SERIAL emu kill` → relaunch with `emulator -avd $AVD_NAME -no-snapshot-load`
2. Wait for boot + network connectivity
3. Reinstall app and re-verify
Never commit a checkpoint when app is stuck on splash due to network errors.

---

## What NOT to Do

- Do NOT use mobile-mcp tools during test runs (port conflicts)
- Do NOT guess selectors — always dump hierarchy first
- Do NOT hardcode back-press count — use verify-after-back pattern
- Do NOT read screenshot images in main context — use subagents
- Do NOT skip the coverage confirmation gate
- Do NOT rewrite the entire flow on failure — fix only the broken step
