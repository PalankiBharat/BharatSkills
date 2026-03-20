# Phone Driver Bridge — Interfacing QA Autopilot with Phone Driver

## Overview

The phone-driver skill is a Claude Code command (`/phone-driver "task"`) that controls an Android device via ADB. QA Autopilot generates test cases and delegates execution to phone-driver.

## Checking Phone Driver Availability

Before attempting execution, verify phone-driver is installed:

```bash
# Check if phone-driver command exists
if [ -f "$HOME/.claude/commands/phone-driver.md" ]; then
    echo "PHONE_DRIVER_AVAILABLE"
else
    echo "PHONE_DRIVER_NOT_INSTALLED"
fi
```

```bash
# Check if a device is connected
adb devices -l 2>/dev/null | grep -v "^List" | grep -v "^$" | head -1
```

If either check fails, switch to **Plan Only** mode — generate the test plan but skip execution.

## Execution Interface

### Invoking Phone Driver for a Test Case

Each test case is executed as a separate phone-driver invocation. The invocation is a natural language task description.

**Pattern:**
```
/phone-driver "{navigation_steps}. {action_steps}. {verification_steps}"
```

**Example invocations:**

```
/phone-driver "Open MyTradingApp. Navigate to the Watchlist tab. Verify that the watchlist screen loads and shows at least one stock symbol"

/phone-driver "Open MyTradingApp. Go to Order Entry screen. Tap on the quantity input field. Type '0'. Tap the 'Place Order' button. Verify that an error message appears indicating quantity must be greater than zero"

/phone-driver "Open MyTradingApp. Go to Settings. Toggle the 'Enable Notifications' switch off. Press back. Go to Settings again. Verify the notification toggle is still off (persisted)"
```

### Writing Effective Phone Driver Tasks

**DO:**
- Be explicit about app name: `"Open MyTradingApp"` not `"open the app"`
- Use visible element text: `"tap on 'Place Order'"` not `"tap submit button"`
- Include navigation path: `"Go to Settings > Account > Profile"` not `"go to profile"`
- State verification clearly: `"Verify text 'Order Placed Successfully' is visible"` 
- Include waits when needed: `"Wait for the screen to load, then verify..."` 

**DON'T:**
- Don't reference code identifiers: ~~`"tap on btn_submit"`~~ → `"tap on 'Submit'"`
- Don't assume app state: ~~`"type the quantity"`~~ → `"Open the app, navigate to Order Entry, tap quantity field, type '5'"`
- Don't use vague verification: ~~`"check it works"`~~ → `"verify the success toast shows 'Order #12345 placed'"`

### Structuring Complex Test Cases

For multi-step test cases, break into logical chunks:

```
SETUP: "Open MyTradingApp and navigate to Order Entry screen"
ACTION: "Enter quantity 100, price 250.50, select BUY, tap Place Order"
VERIFY: "Verify success message appears with order details"
CLEANUP: "Press back to return to main screen"
```

Combine into a single invocation when possible:
```
/phone-driver "Open MyTradingApp, navigate to Order Entry, enter quantity 100 and price 250.50, select BUY, tap Place Order, verify success message appears, then press back to main screen"
```

### Handling Test Prerequisites

Some tests need specific app state. Handle with chained phone-driver calls:

```
# Test: Verify order cancellation
# Prerequisite: An active order must exist

# Step 1: Create the order
/phone-driver "Open MyTradingApp, go to Order Entry, place a BUY order for 10 qty at market price"

# Step 2: Cancel the order  
/phone-driver "Open MyTradingApp, go to Order Book, find the most recent pending order, tap on it, tap Cancel Order, confirm cancellation, verify order status changes to Cancelled"
```

## Interpreting Phone Driver Results

After each phone-driver execution, interpret the output:

### Pass Indicators
- Phone driver reports "Task complete: {summary matching expected result}"
- Final screenshot shows expected UI state
- No error messages or crashes

### Fail Indicators
- Phone driver reports unexpected screen state
- Element not found errors (UI changed or not navigable)
- App crash (phone driver reports force-close dialog)
- Wrong text/data displayed
- Timeout waiting for element

### Blocked Indicators
- Device not connected
- App not installed
- Phone driver can't find the app
- ADB connection lost
- Test data not available

### Recording Results

After each execution, record in the report:

```markdown
#### TC-{ID}: {Title}
- **Status**: ✅ PASS
- **Executed**: {timestamp}
- **Phone Driver Output**: {key output summary}
- **Duration**: {seconds}
- **Screenshots**: {paths if captured}
```

For failures, capture extra detail:

```markdown
#### TC-{ID}: {Title}  
- **Status**: ❌ FAIL
- **Executed**: {timestamp}
- **Expected**: {what should have happened}
- **Actual**: {what actually happened}
- **Phone Driver Output**: {relevant output}
- **Screenshot**: `screenshots/TC-{ID}-fail.png`
- **Reproduction**: {exact phone-driver command to reproduce}
```

## Execution Order Strategy

1. **Reset app state** before each test group:
   ```
   /phone-driver "Force stop MyTradingApp and clear its cache, then relaunch it"
   ```

2. **Group tests by screen** to minimize navigation:
   ```
   Group 1: All Order Entry tests (navigate once, test all)
   Group 2: All Watchlist tests
   Group 3: All Settings tests
   Group 4: Cross-feature regression tests
   ```

3. **Execute P0 first** — if critical tests fail, flag immediately and ask the user whether to continue with remaining tests.

4. **Capture screenshots on failures**:
   After a fail, ask phone-driver to take a screenshot:
   ```
   /phone-driver "Take a screenshot of the current screen"
   ```
   Then copy the screenshot:
   ```bash
   cp /tmp/phonedriver_screen.png ./screenshots/TC-{ID}-fail.png
   ```

## Dealing with Dynamic Data

Some tests depend on runtime data (order IDs, timestamps, prices). Handle with:

1. **Relative verification**: Instead of exact values, verify patterns:
   ```
   "Verify an order confirmation with an order number appears" (not "verify order #12345")
   ```

2. **Parametric tests**: When generating the test, note which values are dynamic:
   ```
   Steps: Place order → Note the order ID shown → Go to Order Book → Verify order ID matches
   ```

3. **Time-sensitive tests**: For market-hour-dependent features:
   ```
   Precondition: Execute during market hours (9:15 AM - 3:30 PM IST)
   ```
   If outside hours, mark as SKIP with reason.
