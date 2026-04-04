# appium-mcp E2E Testing Reference

Central reference for automated E2E testing using the official Appium MCP server (`appium/appium-mcp`). Replaces the old YAML flow pipeline, Python driver, and device-slot management. Claude reads `migration-guide.md` and drives appium-mcp tools directly — no intermediate test scripts or flow definitions.

---

## 1. Prerequisites

- Appium server: `npm install -g appium`
- Appium drivers: `appium driver install uiautomator2` (Android), `appium driver install xcuitest` (iOS)
- appium-mcp: `npx appium-mcp@latest` (v1.44.0+, official Appium org)
- Claude Code config: `claude mcp add appium-mcp -- npx -y appium-mcp@latest`
- No Python dependencies needed — no appium_driver.py, no PyYAML, no Appium-Python-Client

## 2. appium-mcp Tool Inventory

Key tools available through the MCP server:

| Category | Tools |
|----------|-------|
| Setup | `select_platform`, `select_device`, `create_session`, `delete_session` |
| Element interaction | `appium_find_element`, `appium_click`, `appium_set_value`, `appium_scroll`, `appium_swipe` |
| Verification | `appium_screenshot`, `appium_get_page_source`, `appium_get_element_attribute` |
| App management | `appium_activate_app`, `appium_install_app`, `appium_is_app_installed` |
| Navigation | `appium_back`, `appium_get_window_size` |

**AI vision-based element finding:** appium-mcp can find elements by natural language description (e.g., "the yellow search button at the bottom"). Uses Qwen3-VL or Gemini Flash as vision backend. LRU cache (50 entries, 5 min TTL) prevents repeated vision calls for the same element.

**NO_UI mode:** Reduces token consumption 60-90% by stripping HTML artifacts from tool responses. Enable via appium-mcp config.

## 3. Session Management

One appium-mcp session per platform per test run. No manual port allocation, no device-slot JSON file, no Appium server start/stop.

```
1. select_platform → "android" or "ios"
2. select_device → target emulator serial or simulator UDID
3. create_session → returns session ID (handles server lifecycle internally)
4. ... run tests ...
5. delete_session → cleanup
```

Record device identifiers in PLAN.md header:
```
<!-- DEVICE: android=emulator-5554 | ios=<UDID> -->
```

## 4. The 3-Build Comparison Protocol

The core testing protocol for KMM migrations. Ensures 100% visual + functional parity across master Android, migrated Android, and iOS.

### 4.1 Build 1: Master Android (reference)

1. Create temp worktree from master: `git worktree add /tmp/kmm-master-$(date +%s) master`
2. Build master APK from the temp worktree
3. Create appium-mcp Android session, install and launch the master APK
4. For each screen listed in migration-guide.md (platform-stay files):
   - Navigate to the screen using vision-based element finding
   - Take screenshot via `appium_screenshot`
   - Store in `e2e-tests/screenshots/android/master/<screen-name>.png`
5. Delete session, clean up temp worktree
6. Write master commit SHA to `e2e-tests/screenshots/android/master/.cache-key`

### 4.2 Build 2: Migrated Android

1. Build migrated APK from the feature branch worktree
2. Create appium-mcp Android session, install and launch the migrated APK
3. Navigate same screens, take screenshots
4. Store in `e2e-tests/screenshots/android/migrated/<screen-name>.png`
5. Delete session

### 4.3 Build 3: iOS

1. Build iOS app from the feature branch worktree
2. Create appium-mcp iOS session, install on simulator and launch
3. Navigate same screens, take screenshots
4. Store in `e2e-tests/screenshots/ios/migrated/<screen-name>.png`
5. Delete session

### 4.4 Comparison Matrix

Claude Vision reads all 3 screenshots per screen and classifies differences:

| Comparison | What it checks | Classification |
|-----------|---------------|----------------|
| Master Android vs Migrated Android | Visual regression from migration | REGRESSION / EXPECTED / FALSE_POSITIVE |
| Migrated Android vs iOS | Cross-platform parity | PARITY_GAP / EXPECTED / FALSE_POSITIVE |

**Per-screen report format:**
```
Screen: <name>
Master vs Migrated: <classification> — <description if not identical>
Migrated vs iOS: <classification> — <description if not identical>
```

### 4.5 Baseline Caching

Skip Build 1 if master screenshots are current:
```bash
CACHED=$(cat e2e-tests/screenshots/android/master/.cache-key 2>/dev/null)
CURRENT=$(git rev-parse master)
[ "$CACHED" = "$CURRENT" ] && echo "Master baseline current — skipping Build 1"
```

## 5. Functional Verification Protocol

Beyond visual comparison, verify functionality per migration-guide.md fields:

### 5.1 Per-Screen Verification

For each platform-stay screen in migration-guide.md:

1. **Navigate** to the screen using vision-based element finding
2. **Verify elements** — for each item in the Callbacks field, find the element and confirm it exists
3. **Test interactions** — tap buttons, type in fields, verify expected outcomes:
   - Button tap → verify navigation or state change via screenshot
   - Text input → verify field accepts input
   - Toggle/switch → verify state toggles
4. **Verify flows** — for each item in the Flows field, trigger the action and confirm the flow fires (e.g., tap submit → verify success screen appears)
5. **Verify UI branches** — for each item in the UI Branches field, trigger the condition and verify the correct branch renders

### 5.2 Interactive Element Audit

For thorough screen verification:
1. Take initial screenshot
2. Get page source (`appium_get_page_source`) to enumerate interactive elements
3. For each interactive element: tap → screenshot → back
4. Report: element present? tap produced visible change? dead button?

## 6. Blocker Handling

No segment files needed. When Claude encounters a blocker during E2E testing:

1. Pause execution
2. Report to user:
   ```
   BLOCKER: <description — e.g., "OTP screen reached, need real OTP entry">
   Platform: <android/ios>
   Screen: <current screen>
   Complete the action on device, then confirm to continue.
   ```
3. Wait for user confirmation
4. Resume with next appium-mcp tool call

Common blockers: OTP/SMS verification, biometric prompts, payment gateway, KYC/identity verification.

## 7. Failure Recovery

### Element not found
1. Try describing the element differently (natural language)
2. Get page source and search for the element in the hierarchy
3. If still not found after 3 attempts → screenshot + report to user

### Session timeout or crash
1. Create a new session (`create_session`)
2. Navigate back to the screen that was being tested
3. Resume from that screen

### App crash during testing
1. Capture logs: `adb -s $ANDROID_SERIAL logcat -d *:E | tail -50` (Android) or simulator console (iOS)
2. Record crash in findings.md
3. Restart app, resume testing from the crashed screen
4. Max 3 crash recoveries per screen → escalate

### Max retries
- 3 retries per screen for element finding failures
- 3 crash recoveries per screen
- After exhausting retries → escalate to user with screenshots and findings

## 8. What appium-mcp Catches vs Doesn't

### Catches
- **Visual regressions** — layout shifts, missing elements, wrong colors (via Claude Vision)
- **Unwired buttons** — tap produces no navigation or state change
- **Navigation breaks** — expected screen doesn't load after interaction
- **Missing data** — screens render empty or with placeholder text
- **Platform parity gaps** — Android and iOS render differently
- **Cross-migration regressions** — migrated app differs from master

### Doesn't Catch
- Performance regressions (no timing metrics)
- Memory leaks (no heap monitoring)
- Network error handling (needs mock server setup)
- Animation quality (screenshots are static frames)
- Accessibility compliance (no contrast/touch-target auditing)

## 9. Integration with Verification Pipeline

appium-mcp E2E is step 5 in the verification pipeline:

1. `build-verify.sh` — build + unit tests
2. `parity-check.sh` — static analysis
3. `flow-collector-check.sh` — ViewModel flow → iOS collector cross-reference
4. `koin-binding-check.py` — DI binding verification
5. **appium-mcp E2E** — this reference
6. Manual test — structured checklist, should find near-zero issues

Steps 1-4 run first (fast, deterministic, zero tokens). Step 5 runs only after steps 1-4 pass. Step 6 is the final gate before handoff.

## 10. Rules

- Do NOT generate YAML flow files — Claude drives appium-mcp directly
- Do NOT use appium_driver.py — it no longer exists
- Do NOT allocate device slots via kmm-device-slots.json — appium-mcp manages sessions
- Do NOT start/stop Appium servers manually — appium-mcp handles server lifecycle
- Do NOT use coordinate-based tapping as primary strategy — use vision-based finding
- Do NOT use mobile-mcp tools (any tool prefixed with `mcp__mobile-mcp__`) — they conflict with appium-mcp sessions and will corrupt device state. If these tools appear in your available tools, ignore them entirely during E2E testing.
- Do NOT read screenshot images in main context for batch comparison — use subagents
- Always run deterministic checks (steps 1-4) BEFORE appium-mcp E2E
- Always delete sessions after testing (`delete_session`)
- Record all findings in findings.md, not just in conversation
