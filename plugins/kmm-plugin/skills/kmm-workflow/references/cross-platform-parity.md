# Cross-Platform Parity Reference

This checklist ensures Android and iOS implementations are functionally identical after migration. Run at Phase 4 and Phase 5 boundaries. Every item is a blocker if failed.

`parity-check.sh` automates most of these as grep/diff commands. This reference explains the WHY behind each check for when manual investigation is needed.

---

## SDK & Initialization

### SDK Init Parameters (#56)
Every SDK `initialize()` / `setup()` / `configure()` call must have identical parameters on both platforms.

**How to verify:**
1. Find all SDK init calls in Android app (grep for `initialize(`, `setup(`, `configure(`)
2. Find equivalent calls in iOS app
3. Diff parameter lists — any parameter present on one platform but absent on the other is a blocker

**Why:** Missing init parameters produce silent 500 errors indistinguishable from network issues.

### Lifecycle Listeners (#60)
Every SDK listener/observer/callback registered on Android must have an equivalent on iOS.

**How to verify:**
1. Grep Android for: `setOnCompletionListener`, `addObserver`, `registerCallback`, `setDelegate`, `registerReceiver`
2. For each, verify iOS has equivalent registration (AppDelegate, SceneDelegate, or view lifecycle)
3. Pay special attention to Application.onCreate registrations — most commonly missed

**Why:** Missing listeners cause SDK-driven flows to get stuck silently (e.g., "Continue" button loops forever).

### Session Persistence (#59)
Every field checked by session-validity predicates (`isLoggedIn()`, `isTokenExpired()`) must be written by ALL credential-save paths.

**How to verify:**
1. Identify all fields read by `isLoggedIn()` / `isTokenExpired()` in shared code
2. For every login/token-save/token-refresh path, verify ALL fields are written (not just the token)
3. Check both platforms — iOS may use different storage (Keychain vs SharedPreferences)

**Why:** Partially-saved sessions (token written, expiry not) cause silent logout on cold restart.

---

## Resources & Assets

### Asset Parity (#57)
Every image, Lottie animation, font, and resource file referenced in ported code must exist in the target.

**How to verify:**
1. Diff source `Assets.xcassets` vs target — flag missing imagesets
2. Scan Swift files for `Image("name")` — verify each name exists in target xcassets
3. Scan for `LottieAnimation.named("file")` — verify JSON exists in target bundle
4. Scan for drawable references in CMP — verify files exist in `commonMain/composeResources/drawable/`

**Why:** Missing assets cause blank views and broken animations, only discovered during manual UI testing.

### Info.plist Keys (#58)
Every key read from `Bundle.main.infoDictionary` must exist in the target's `Info.plist`.

**How to verify:**
1. Grep all ported Swift files for `infoDictionary` reads, collect every key name
2. Verify each key exists in target `Info.plist`
3. Diff source `Info.plist` and `.xcconfig` against target — flag missing SDK keys (API keys, app IDs, URL schemes)

**Why:** Missing Info.plist keys produce blank/broken third-party SDK screens.

---

## Navigation & Routing

### Route Mapping Completeness (#61)
Every sealed class/enum variant must have an explicit mapping in every routing function.

**How to verify:**
1. Enumerate all variants of every `SharedRoute` sealed class/enum
2. Find every `sharedRouteToRoute()` / `toAndroidRoute()` / `toIOSRoute()` mapping function
3. Verify each variant has explicit mapping — no variant handled only by `else` or wildcard
4. Recommend replacing `else -> null` with `else -> error("Unhandled route: $route")` for crash-fast

**Why:** Silent navigation drops (`else -> null`) appear as "button does nothing" with no error. Extremely hard to debug.

### Navigation Round-Trip
Every sub-screen flow must verify the parent screen appears after pressing back.

**How to verify:**
- Appium flows: verify-after-back pattern (press back, wait, verify parent selector)
- Do NOT hardcode N back presses — navigation stack depth may differ between builds

---

## UI Parity

### String Preservation
All user-visible strings must be character-for-character identical to the original.

**How to verify:**
- Extract all string literals from original and migrated composables
- Diff them — any difference in casing, wording, or content is a regression
- Common failures: sentence case → title case, abbreviation expansion, word changes

### Default UI State
Initial ViewModel state values must match between original and migrated.

**How to verify:**
- Compare: default constructor params, initial MutableStateFlow values, default function params (e.g., isExpanded=true/false)
- Any default state difference means the screen renders differently on launch

### Callback Wiring
Every callback parameter must reach a real action — no dead buttons.

**How to verify:**
- Scan composables for callback params with default `= {}`
- Trace each from declaration through all call sites to the actual action
- Empty lambdas on onClick/callback params produce buttons that look active but do nothing
