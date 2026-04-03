---
name: kmm-test
description: >
  Maestro-based visual and functional parity testing for KMM migrations. Generates Maestro flows
  from screen-map.json, captures baseline screenshots from master branch, compares against current
  branch, reports visual regressions and functional failures. Run at any stage — after Phase 4
  (Android wiring), after Phase 5 (iOS wiring), or independently for debugging completed stories.
  Use when the user says "/kmm-test", "test my migration", "run visual parity", "compare with master",
  "run Maestro tests", "check screenshots", or any request to verify visual/functional parity.
argument-hint: "[android|ios|both] [--screen <name>] [--skip-baseline]"
---

# KMM Test — Maestro Visual & Functional Parity

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

## Step 0: Maestro Prerequisite Check

```bash
which maestro || echo "MAESTRO_NOT_FOUND"
```

If `MAESTRO_NOT_FOUND`: output the following and STOP — do not proceed.

> "Maestro is required but not installed. Install with: `brew install maestro`"

If found, verify version:

```bash
maestro --version
```

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
   - Write the new slot entry to `kmm-device-slots.json`.

4. Verify devices are booted:
   ```bash
   adb devices | grep $ANDROID_SERIAL
   xcrun simctl list devices booted | grep $IOS_UDID
   ```
   If not booted, boot them before continuing.

5. Export: `ANDROID_SERIAL`, `IOS_UDID`, `FAKE_PORT`.

---

## Step 2: Generate Maestro Flows

Read `references/maestro-testing.md` for the full mapping rules and `references/maestro-flow-templates.md` for YAML templates before generating any files.

1. Read `e2e-tests/screen-map.json`.

2. If `--screen` filter is provided, only generate flows for the matching screen/flow name.

3. For each flow in `screen-map.json`, generate:
   - `e2e-tests/maestro-flows/android/<flow-name>.yaml`
   - `e2e-tests/maestro-flows/ios/<flow-name>.yaml`

   Apply platform-specific rules:
   - **Android:** use `- back` for navigation back; prefer `id` selectors
   - **iOS:** use `- tapOn: "Back"` for navigation back; prefer `text` selectors

   After each `verify` step, insert:
   ```yaml
   - takeScreenshot: <screen-name>
   ```

   If the flow starts with login, prepend:
   ```yaml
   - runFlow: subflows/login.yaml
   ```

   If the flow has `blocker` steps, split into numbered segments (e.g., `<flow-name>-segment-1.yaml`, `<flow-name>-segment-2.yaml`).

4. Generate a login subflow at:
   - `e2e-tests/maestro-flows/android/subflows/login.yaml`
   - `e2e-tests/maestro-flows/ios/subflows/login.yaml`

   If the login requires OTP, split into:
   - `login-otp-segment-1.yaml` (enters credentials, triggers OTP send)
   - `login-otp-segment-2.yaml` (enters OTP, completes login)

5. For comparison mode (Step 4), duplicate each flow and add `assertScreenshot` commands after each `takeScreenshot`, referencing the baseline path:
   ```
   e2e-tests/screenshots/<platform>/baseline/<screen-name>.png
   ```

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

d. Run baseline Maestro flows:
```bash
maestro test --device $ANDROID_SERIAL \
  --test-output-dir e2e-tests/screenshots/android/baseline/ \
  -e APP_ID=$APP_ID -e PHONE=$PHONE -e OTP=$OTP -e PIN=$PIN \
  e2e-tests/maestro-flows/android/
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

3. Run comparison Maestro flows (these include `assertScreenshot` commands):
   ```bash
   maestro test --device $ANDROID_SERIAL \
     --format junit \
     --test-output-dir e2e-tests/results/comparison/android/ \
     -e APP_ID=$APP_ID -e PHONE=$PHONE -e OTP=$OTP -e PIN=$PIN \
     e2e-tests/maestro-flows/android/
   ```

4. For flows with blocker segments: same pause-and-resume protocol as Step 3e.

5. Screenshots are saved to `e2e-tests/screenshots/<platform>/comparison/`.

---

## Step 5: Diff and Report

### 1. Check Maestro exit code

- **Exit 0** — all `assertScreenshot` and `assertVisible` commands passed → all screens PASS
- **Exit 1** — at least one assertion failed

### 2. Parse JUnit results

Read from `e2e-tests/results/comparison/<platform>/`. For each failure:
- If the failing command is `assertScreenshot` → visual failure
- If the failing command is `assertVisible` or `tapOn` → functional failure

### 3. Classify passing screens

For screens where Maestro's pixel comparison passed the 97% threshold: mark `PASS`. No AI vision analysis needed.

### 4. Classify failing screens (visual)

For each screen that failed pixel comparison, read BOTH screenshots using Claude vision:
- `e2e-tests/screenshots/<platform>/baseline/<screen-name>.png`
- `e2e-tests/screenshots/<platform>/comparison/<screen-name>.png`

Classify the difference as one of:
- `VISUAL_REGRESSION` — layout shift, missing element, wrong color, dead/missing button → needs a fix
- `EXPECTED_CHANGE` — intentional platform-native rendering difference from the migration
- `FALSE_POSITIVE` — status bar change, animation frame, dynamic content (timestamp, avatar, etc.)

### 5. Classify functional failures

Functional failures (`tapOn`/`assertVisible`) are definitive — the button does not exist or the screen did not load. Always mark `VISUAL_REGRESSION`.

### 6. Generate report

Write `e2e-tests/test-report.md`:

```markdown
# KMM Test Report — <date>

Platform: <android|ios|both>
Baseline: master@<short-hash>
Branch: <current-branch>

| Screen | Platform | Pixel Match | Status | Notes |
|--------|----------|-------------|--------|-------|
| Home | Android | 99.2% | PASS | |
| Settings | Android | 94.1% | VISUAL_REGRESSION | Missing bottom bar |
| Home | iOS | 98.7% | PASS | |
| Settings | iOS | 91.3% | VISUAL_REGRESSION | Layout shift in header |
```

### 7. Present summary to user

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
5. Rebuild → reinstall → rerun ONLY the failing screen's Maestro flow (not all flows):
   ```bash
   maestro test --device $ANDROID_SERIAL \
     --format junit \
     --test-output-dir e2e-tests/results/comparison/android/ \
     -e APP_ID=$APP_ID -e PHONE=$PHONE -e OTP=$OTP -e PIN=$PIN \
     e2e-tests/maestro-flows/android/<flow-name>.yaml
   ```
6. Re-compare: if PASS → move to next failure. If still failing → iterate.
7. **Max 3 iterations per screen.** After 3 failures on the same screen, stop and escalate to the user with:
   - Both screenshots (paths)
   - The source file(s) modified
   - What was tried in each iteration and what the result was

---

## Rules

- **Never skip Maestro testing.** If invoked during Phase 4 or Phase 5 of the KMM workflow, Maestro flows are MANDATORY — the orchestrator cannot mark the phase complete without them passing.
- **Baseline caching is the default.** Only rebuild baselines when master HEAD has changed. The `--skip-baseline` flag skips comparison-mode flows without rebuilding baselines — it does not affect cache validation logic.
- **Token efficiency.** Claude does NOT interact with devices. Maestro handles all device interaction. Claude only reads saved screenshot files when pixel comparison fails — not before.
- **OTP rate limits.** Default test credentials use a fixed OTP (no rate limit). For real OTP flows, warn the user before running: "Login OTP has rate limits (max 2–3 resends → 10-min block). Each baseline + comparison run = 2 logins."
- **One device per worktree.** Never share an emulator or simulator between worktrees. The slot system in `references/device-slot-management.md` guarantees isolation — always follow it.
- **Clean installs.** Always uninstall before installing a new build. Never install over an existing build — leftover state from the previous build can mask bugs.
- **Login is required for all flows** unless a flow is explicitly marked `requiresLogin: false` in `screen-map.json`. Generate the login subflow and prepend it to every flow by default.

---

## References

- `references/maestro-testing.md` — screen-map→YAML mapping rules, iOS selector fallback chain, blocker segmentation, `assertScreenshot` configuration
- `references/device-slot-management.md` — device slot allocation, creation commands, cleanup protocol
- `references/maestro-flow-templates.md` — reusable YAML templates for login, per-screen, and multi-screen flows
