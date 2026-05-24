---
name: maestro-android-testing
description: Use when writing or executing Maestro YAML UI tests for Android, or when the user says "maestro test", "write a test", "test this screen", "UI test", "test this flow", "test", "test manually", "verify", "run the flow", "QA this", or "check the screen". Also triggers when qa-autopilot or any skill needs to generate Maestro YAML for an Android app.
---

# Maestro Android Testing

## Overview

Maestro tests interact with composables via accessibility IDs — never coordinates, never ambiguous domain text. Always verify Maestro MCP is live before writing a single line of YAML.

---

## Trigger Keywords

This skill MUST auto-invoke when the user mentions any of:

`test`, `test manually`, `verify`, `run the flow`, `QA this`, `check the screen`, `maestro test`, `write a test`, `test this screen`, `UI test`, `test this flow`.

Do not proceed with ad-hoc manual testing on an Android Compose feature without applying Maestro discipline first.

---

## STEP 0 — MCP CHECK (MANDATORY, BLOCKING)

**Do this before any test authoring:**

1. Check if Maestro MCP tools are available in this session (look for `maestro_*` tools)
2. If NOT available — **STOP. Do not write tests.** Ask:
   > "Maestro MCP is not configured in this session. Please share your Maestro API key or run `/oh-my-claudecode:mcp-setup` to wire it up first."
3. Only continue after MCP tools are confirmed.

**No workarounds.** "I'll write the YAML and you run it" is not acceptable.

---

## STEP 0b — READ EXISTING FLOWS FIRST (MANDATORY, BLOCKING)

**Before writing a single line of YAML, you MUST inspect existing flows.** Skipping this step causes duplicate logic, `runFlow` collisions, and `when: visible:` text matches firing on the wrong screen.

Run these in order:

```bash
# 1. List every existing flow
find maestro/ -name "*.yaml" | sort

# 2. Read every related flow file in full (do NOT skim)
#    Pay attention to subflows referenced by runFlow.

# 3. Catalogue every `when: visible:` value already used in the flow tree
grep -rn "when:" -A 2 maestro/ | grep -E "visible:" | sort -u
```

**Decision rules after inspection:**
- If an existing subflow already covers a step → reuse it via `runFlow`. Do not re-implement.
- Every new `when: visible: "<text>"` you plan to add MUST be cross-checked against the catalogue above. If the same text could appear on another screen in the flow tree, it is a collision — pick a unique anchor (a screen-level `testTag`, see STEP 2) instead.
- If you cannot prove the `visible:` anchor is unique across all screens the parent flow may be on, you do NOT have permission to use it.

---

## STEP 1 — DISCOVER TAGS BEFORE WRITING

```bash
grep -rh "\.testTag\|\.semanticsTag" app/src/main/java --include="*.kt" \
  | grep -v "import\|fun Modifier\|//" | grep -o '"[^"]*"' | sort -u

find . -name "*Tags*.kt" -not -path "*/build/*"
```

---

## MANDATORY: Flow File Header

**Every Maestro YAML file MUST start with this header block.** It helps AI agents understand context without reading the entire file:

```yaml
# =============================================================================
# FLOW: <human-readable flow name>
# PART: <N of M> — <what this part covers>
# SCREEN: <starting screen name>
# PRECONDITIONS: <what must be true before this flow runs>
# TESTS: <bullet list of what is being verified>
# RELATED FLOWS: <comma-separated list of connected .yaml files>
# =============================================================================
appId: com.marketpulse.sniper.vte
name: <descriptive name>
tags:
  - <smoke|regression|critical|auth|trading|chart>
---
```

**Example:**
```yaml
# =============================================================================
# FLOW: New User Registration
# PART: 2 of 4 — Phone number entry and OTP verification
# SCREEN: IntroScreen (story slides shown to logged-out users)
# PRECONDITIONS: Fresh install or cleared app state, no prior login
# TESTS:
#   - Phone number field accepts 10-digit input
#   - "Continue" button navigates to OTP screen
#   - OTP screen shows masked phone number
# RELATED FLOWS: 01-intro.yaml, 03-set-pin.yaml, 04-trial-screen.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: New User — Part 2 — Phone + OTP
tags:
  - smoke
  - auth
---
```

---

## Sniper App — Navigation Map

```
App Launch
└── Splash Screen
    ├── [Returning user, has PIN + biometric] → TFA Screen (biometric prompt)
    │   ├── [Biometric success] → Dashboard
    │   └── [Biometric fail / "Use OTP"] → OTP Login Screen → Dashboard
    ├── [Returning user, has PIN, no biometric] → PIN Verification → Dashboard
    ├── [Returning user, fully logged in] → Dashboard
    ├── [Risk disclosure not accepted today] → Risk Disclosure → Dashboard
    ├── [No funds added] → Funds Dashboard
    └── [New / logged out user] → Intro Screen (story slides)
        └── [Phone number entry] → OTP Screen
            └── [OTP verified, new user] → Set PIN → Trial Screen → Dashboard
                └── [OTP verified, existing user] → Dashboard

Dashboard
├── Chart Header (symbol, exchange chip, timeframe, indicators)
├── Chart Canvas (price chart, drawing tools)
├── Bottom Panel (positions, orders, funds)
└── Punch Button → Order Entry Form → Confirm/Cancel
```

**App IDs:**
- Production: `com.marketpulse.sniper.vte`
- Staging: `com.marketpulse.sniper.vte.staging`

---

## Selector Hierarchy — MANDATORY

| Priority | Maestro syntax | When |
|----------|---------------|------|
| ✅ 1st | `id: "tag_name"` | testTag (`testTagsAsResourceId=true`) or semanticsTag |
| ✅ 2nd | `accessibilityId: "tag_name"` | Equivalent alternative |
| ⚠️ Last | `text: "..."` | System dialogs ONLY: "Allow", "Deny", "OK", "Cancel" |
| ❌ Never | `point: "x%, y%"` | Banned — breaks on every device size |

### ⚠️ `when: visible:` ONLY accepts plain text strings

```yaml
# ❌ WRONG — runtime parse error in Maestro
- runFlow:
    when:
      visible:
        id: "biometric_continue"
    file: ./04_biometric.yaml

# ✅ CORRECT — plain text only
- runFlow:
    when:
      visible: "Enable fingerprint ID"   # must be a string UNIQUE across all flows in the tree
    file: ./04_biometric.yaml
```

**Why:** `when: visible:` does NOT accept an object form (`{id: "..."}` / `{text: "..."}`). Passing one fails at parse time, not at runtime — your whole flow refuses to start.

**For id-based presence checks**, do the check INSIDE the subflow using `extendedWaitUntil` or `assertVisible`, which DO accept `{id: "..."}`:

```yaml
# Inside the subflow file
- extendedWaitUntil:
    visible:
      id: "biometric_continue"
    timeout: 8000
- assertVisible:
    id: "biometric_continue"
```

**Text collisions are silent and dangerous.** `when: visible: "CONTINUE"` will match the FIRST screen in the flow tree that shows the word "CONTINUE" — biometric, risk disclosure, OTP, anywhere. Always pick a text anchor unique to ONE screen (see Screen-Level Tags below), or use a screen-level `testTag` via `extendedWaitUntil` inside the conditional subflow.

---

### The Stock App Text Trap

Stock symbols (NIFTY, BANKNIFTY, etc.) appear in chart candles, price labels, order book, and header **simultaneously**. Text selectors will match the wrong element.

```yaml
# ❌ WRONG — matches chart candle label, not the header button
- tapOn: "NIFTY"

# ✅ CORRECT — targets only the composable with this tag
- tapOn:
    id: "chart_symbol_label"
```

---

## Sniper Tag Reference

### Screens — MANDATORY top-level testTags

Every screen's top-level Composable MUST carry `Modifier.testTag("screen_<name>")`. This is the only collision-free anchor for `when:` conditions and for cross-flow assertions — text labels like "CONTINUE" or "OK" reappear across screens and produce silent wrong-screen matches.

| Screen | Tag ID |
|--------|--------|
| Biometric authorization | `screen_biometric` |
| Risk disclosure | `screen_risk_disclosure` |
| Mobile verification | `screen_mobile_verification` |
| OTP verification | `screen_otp` |
| Dashboard | `screen_dashboard` |
| Intro / story slides | `screen_intro` |
| Trial plan | `screen_trial` |
| PIN entry | `screen_pin` |

```kotlin
@Composable
fun BiometricAuthorizationContent(modifier: Modifier = Modifier, ...) {
    Column(modifier = modifier.testTag("screen_biometric")) { ... }
}
```

**If a screen is missing its tag, add it before writing the flow.** Do not work around the gap with text selectors.

### Registration / Auth

| Element | Tag ID |
|---------|--------|
| Mobile number screen | `moble_number_screen` _(typo in codebase — use as-is)_ |
| Phone number input | `phone_number` |
| Request OTP button | `phone_number_continue` |
| OTP screen | `otp_screen` |
| OTP input field | `otp_text_field` |
| OTP continue button | `otp_continue_button` |
| Resend OTP button | `resend_otp_button` |
| Trial screen | `trial_screen` |
| Activate trial button | `register` |
| Trial login button | `login_trial_button` |

### Chart / Feed

| Element | Tag ID |
|---------|--------|
| Chart header row | `chart_header` |
| Symbol label in feed | `chart_symbol_label` |
| Chart canvas | `canvas` |
| Exchange chip | `exchange_tag_NSE`, `exchange_tag_BSE` |
| Expiries dropdown | `expiries_menu` |
| Selected duration | `selected_duration` |
| View mode button | `${name}_view_mode_button` (e.g. `candle_view_mode_button`) |
| Market protection indicator | `market_protection_indicator` |
| Market protection section | `market_protection_section` |
| Indicators menu | `indicators_menu` |
| Indicator search | `indicator_search_input` |
| Add analytics button | `add_analytics_button` |

### Order Placement

| Element | Tag ID |
|---------|--------|
| Punch / place order button | `punch` |
| Call (Buy) button | `call` |
| Put (Sell) button | `put` |
| Sell button | `sell_button` |
| Order toast | `order_toast` |
| Cancel order button | `order_cancel_button` |
| Edit order button | `order_edit_button` |
| Cancel order dismiss | `dismiss_cancel_order_view` |
| Order card expand | `order_card_expand` |
| Order card collapse | `order_card_collapse` |

### Search / Navigation

| Element | Tag ID |
|---------|--------|
| Search input | `search_input` |
| Search result (dynamic) | `search_result_NIFTY`, `search_result_BANKNIFTY`, etc. |
| Back button | `back_button` |
| Growth bottom sheet | `growth_bs` |
| Trial growth sheet | `trial_growth_bs` |
| Close charges screen | `close_charges_screen` |

### Input Fields (Dynamic)

| Element | Pattern |
|---------|---------|
| Input scroll wrapper | `${tag}_scroll` |
| Input field | `${tag}_field` |

---

## Concrete Flow Templates

### Flow 1 — Fresh Install: Intro → Phone → OTP

```yaml
# =============================================================================
# FLOW: New User Registration
# PART: 1 of 3 — Intro screen through OTP verification
# SCREEN: IntroScreen (logged-out entry point with story slides)
# PRECONDITIONS: App freshly installed OR clearState: true used at launch
# TESTS:
#   - Intro story screen loads for logged-out users
#   - Phone number field is tappable and accepts 10-digit input
#   - "Continue" navigates to OTP screen
#   - OTP screen appears after submission
# RELATED FLOWS: 02-set-pin.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: New User — Intro to OTP
tags:
  - smoke
  - auth
---
- launchApp:
    clearState: true

# Intro screen loads — wait for the trial login button (story slide CTA)
- extendedWaitUntil:
    visible:
      id: "login_trial_button"
    timeout: 15000

- tapOn:
    id: "login_trial_button"

# Phone number screen
- extendedWaitUntil:
    visible:
      id: "phone_number"
    timeout: 10000

- tapOn:
    id: "phone_number"
- inputText: "9876543210"

- tapOn:
    id: "phone_number_continue"

# OTP screen must appear
- assertVisible:
    id: "otp_screen"
```

### Flow 2 — OTP Verification → Trial Screen

```yaml
# =============================================================================
# FLOW: New User Registration
# PART: 2 of 3 — OTP entry and trial plan selection
# SCREEN: OTP screen (shown after phone number submission)
# PRECONDITIONS: Phone number submitted, OTP SMS received
# TESTS:
#   - OTP field accepts 6-digit input
#   - Continue navigates to trial screen
#   - Trial screen shows plan options
#   - Activate trial button is visible
# RELATED FLOWS: 01-intro-to-otp.yaml, 03-dashboard-smoke.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: New User — OTP to Trial
tags:
  - auth
---
# Enter OTP (use a real OTP received on the test number)
- tapOn:
    id: "otp_text_field"
- inputText: "123456"

- tapOn:
    id: "otp_continue_button"

# Trial screen
- extendedWaitUntil:
    visible:
      id: "trial_screen"
    timeout: 15000

- assertVisible:
    id: "register"
```

### Flow 3 — Returning User: PIN Login → Dashboard

```yaml
# =============================================================================
# FLOW: Returning User — PIN Authentication
# PART: 1 of 1 — PIN entry through to Dashboard
# SCREEN: PIN verification screen (shown when user has PIN but no biometric)
# PRECONDITIONS: User previously registered and set PIN, biometric NOT enabled
# TESTS:
#   - PIN screen appears at launch for returning users
#   - Dashboard loads after correct PIN
#   - Chart header is visible on Dashboard
# RELATED FLOWS: 04-chart-interaction.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: Returning User — PIN to Dashboard
tags:
  - smoke
  - auth
---
- launchApp:
    clearState: false

# PIN verification screen — wait (splash may take time)
- extendedWaitUntil:
    visible: "Enter PIN"
    timeout: 20000

# Enter 4-digit PIN (system PIN pad — no testTag, use text after each digit)
- inputText: "1234"

# Dashboard should load
- extendedWaitUntil:
    visible:
      id: "chart_header"
    timeout: 20000

- assertVisible:
    id: "chart_header"
```

### Flow 4 — Dashboard: Chart Interaction

```yaml
# =============================================================================
# FLOW: Chart Interaction
# PART: 1 of 2 — Symbol picker and exchange chip
# SCREEN: Dashboard with chart (main trading screen)
# PRECONDITIONS: User is logged in and on Dashboard (chart visible)
# TESTS:
#   - Chart header is present
#   - Tapping symbol label opens search
#   - Exchange chip NSE is visible
#   - Chart canvas renders
# RELATED FLOWS: 05-chart-order-placement.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: Chart — Symbol and Exchange
tags:
  - smoke
  - chart
---
- launchApp:
    clearState: false

- extendedWaitUntil:
    visible:
      id: "chart_header"
    timeout: 20000

# Verify chart header elements
- assertVisible:
    id: "chart_symbol_label"
- assertVisible:
    id: "exchange_tag_NSE"

# Tap symbol to open search
- tapOn:
    id: "chart_symbol_label"

- extendedWaitUntil:
    visible:
      id: "search_input"
    timeout: 8000

# Search for a symbol
- tapOn:
    id: "search_input"
- inputText: "BANKNIFTY"

- extendedWaitUntil:
    visible:
      id: "search_result_BANKNIFTY"
    timeout: 8000

- tapOn:
    id: "search_result_BANKNIFTY"

# Chart header updates with new symbol
- assertVisible:
    id: "chart_symbol_label"
- assertVisible:
    id: "chart_header"
```

### Flow 5 — Order Placement (Punch Flow)

```yaml
# =============================================================================
# FLOW: Order Placement
# PART: 1 of 2 — Punch button through order confirmation toast
# SCREEN: Dashboard with chart (order entry overlay)
# PRECONDITIONS: User logged in, trading account active, chart visible
# TESTS:
#   - Punch button is visible on chart screen
#   - Call (BUY) button is tappable in order form
#   - Order confirmation toast appears after placement
#   - Toast disappears after auto-dismiss
# RELATED FLOWS: 04-chart-interaction.yaml, 06-cancel-order.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: Order Placement — Punch to Toast
tags:
  - critical
  - trading
---
- launchApp:
    clearState: false

- extendedWaitUntil:
    visible:
      id: "punch"
    timeout: 20000

- tapOn:
    id: "punch"

# Order entry form opens
- extendedWaitUntil:
    visible:
      id: "call"
    timeout: 8000

- tapOn:
    id: "call"

# Order confirmation toast
- extendedWaitUntil:
    visible:
      id: "order_toast"
    timeout: 10000

- assertVisible:
    id: "order_toast"

# Toast auto-dismisses — verify it goes away
- extendedWaitUntil:
    notVisible:
      id: "order_toast"
    timeout: 10000
```

---

## Biometric / Fingerprint

**Maestro 2.5.1 has NO native biometric command.** There is no `biometric:`, `fingerprint:`, or `simulateBiometrics:` command.

### Option A — ADB (Emulator only, local only)

The Android emulator supports finger simulation via `adb emu finger touch`. This does NOT work on real devices or Maestro Cloud.

**Pre-requisite (one-time):** Enroll a fingerprint in the emulator:
1. Emulator Settings → Security → Fingerprint → enroll with ID `1`
2. Set any PIN backup when prompted

**Trigger from terminal (run while Maestro flow is waiting):**
```bash
adb -e emu finger touch 1
```

### Option B — HTTP Bridge (local testing, emulator only)

Run this Node.js server before your Maestro flow, then call it from `runScript`:

```javascript
// fingerprint-bridge.js — run: node fingerprint-bridge.js
const http = require('http');
const { exec } = require('child_process');

http.createServer((req, res) => {
  if (req.url === '/fingerprint') {
    exec('adb -e emu finger touch 1', (err, stdout) => {
      res.end(JSON.stringify({ ok: !err, out: stdout }));
    });
  }
}).listen(4567, () => console.log('Fingerprint bridge ready on :4567'));
```

**Maestro flow using the bridge:**
```yaml
# =============================================================================
# FLOW: Biometric Login
# PART: 1 of 1 — TFA screen fingerprint authentication
# SCREEN: TFA screen (shown to returning users with biometric enrolled)
# PRECONDITIONS:
#   - Fingerprint enrolled in emulator (Settings > Security > Fingerprint)
#   - fingerprint-bridge.js server running on port 4567
#   - User previously enabled biometric login in the app
# TESTS:
#   - TFA screen loads at app launch
#   - Fingerprint simulation triggers auth
#   - Dashboard loads after successful biometric
# RELATED FLOWS: 02-otp-fallback-login.yaml
# =============================================================================
appId: com.marketpulse.sniper.vte
name: Biometric Login — TFA to Dashboard
tags:
  - auth
---
- launchApp:
    clearState: false

# TFA screen appears (biometric prompt auto-triggers)
- extendedWaitUntil:
    visible: "Use fingerprint"
    timeout: 15000

# Simulate fingerprint via HTTP bridge
- runScript: fingerprint-bridge-trigger.js

# Dashboard loads
- extendedWaitUntil:
    visible:
      id: "chart_header"
    timeout: 15000

- assertVisible:
    id: "chart_header"
```

```javascript
// fingerprint-bridge-trigger.js (Maestro JavaScript file)
var response = http.post('http://localhost:4567/fingerprint', {});
output.result = response.body;
```

### Option C — Skip Biometric (recommended for CI)

Test the OTP fallback path instead — it's deterministic and works everywhere:

```yaml
# =============================================================================
# FLOW: Biometric Fallback Login
# PART: 1 of 1 — "Use OTP instead" path from TFA screen
# SCREEN: TFA screen (shown to returning users)
# PRECONDITIONS: User has biometric enabled but we test the OTP fallback path
# TESTS:
#   - TFA screen loads at launch
#   - "Use OTP" button navigates to OTP login
#   - OTP login completes successfully
# =============================================================================
appId: com.marketpulse.sniper.vte
name: Biometric Fallback — Use OTP
tags:
  - auth
  - regression
---
- launchApp:
    clearState: false

- extendedWaitUntil:
    visible: "Use OTP instead"
    timeout: 15000

- tapOn: "Use OTP instead"

- extendedWaitUntil:
    visible:
      id: "otp_text_field"
    timeout: 10000

- tapOn:
    id: "otp_text_field"
- inputText: "123456"

- tapOn:
    id: "otp_continue_button"

- extendedWaitUntil:
    visible:
      id: "chart_header"
    timeout: 20000
```

---

## STEP 2 — Add Missing Tags

```kotlin
// Standard (preferred — testTagsAsResourceId=true in MainActivity exposes as resource ID)
Modifier.testTag("screen_component_element")

// When you need to suppress child semantics
Modifier.semanticsTag("screen_component_element")
```

Naming: `screen_component_element` in `snake_case`
- ✅ `chart_header_interval_selector`, `login_phone_field`
- ❌ `button1`, `chartBtn`, `myView`

### Screen-Level Tags — MANDATORY

Every screen's top-level Composable MUST have `Modifier.testTag("screen_<name>")`. Without it, `when: visible:` and `assertVisible` cannot distinguish screens from each other when buttons share labels (CONTINUE, OK, NEXT) — the test will silently fire on the wrong screen.

```kotlin
@Composable
fun BiometricAuthorizationContent(modifier: Modifier = Modifier, ...) {
    Column(modifier = modifier.testTag("screen_biometric")) { ... }
}

@Composable
fun RiskDisclosureContent(modifier: Modifier = Modifier, ...) {
    Column(modifier = modifier.testTag("screen_risk_disclosure")) { ... }
}
```

See the **Screens — MANDATORY top-level testTags** table above for the canonical tag IDs.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `tapOn: "NIFTY"` | `tapOn: {id: "chart_symbol_label"}` |
| `tapOn: {point: "15%, 8%"}` | Add testTag, use `id:` |
| No header comment on YAML | Always add the full header block |
| `assertVisible: "BUY"` | `assertVisible: {id: "call"}` |
| Writing test before checking tags | Grep STEP 1 first |
| Writing YAML before reading existing flows | STEP 0b — `find maestro/ -name "*.yaml"` and read them all first |
| `when: visible: {id: "tag"}` | Parse error — use plain text only; use `extendedWaitUntil` + `id:` inside the subflow |
| `when: visible: "CONTINUE"` (reused word) | Pick a text unique to ONE screen, or add a `screen_<name>` testTag |
| Screen has no top-level `testTag` | Add `Modifier.testTag("screen_<name>")` before writing the flow |
| Skipping MCP check | Step 0 is non-negotiable |
| Using biometric on CI/cloud | Use OTP fallback path instead |

---

## Red Flags — STOP if you think:

| Thought | Reality |
|---------|---------|
| "This text is unique on screen" | Stock symbols appear 4+ times per screen |
| "CONTINUE is fine for `when: visible:`" | Same word appears on 3+ screens — collision is guaranteed |
| "I'll skim the existing flows quickly" | STEP 0b — read them in full, catalogue every `when: visible:` value |
| "I'll use `when: visible: {id: ...}`" | Parse error. `when: visible:` accepts plain text only. |
| "I don't need a screen testTag, the buttons have tags" | Without `screen_<name>`, you cannot disambiguate screens in `when:` conditions |
| "Coordinates are faster" | Breaks on every device size |
| "I'll write YAML, user can run it" | Step 0 required — get MCP key |
| "The tag probably exists" | Grep first. Never assume. |
| "I'll add the tag after" | Tag code first, then write YAML |
| "I can simulate fingerprint natively" | Maestro has no biometric command — use ADB bridge or OTP fallback |
