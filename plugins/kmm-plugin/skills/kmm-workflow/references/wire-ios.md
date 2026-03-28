# Wire iOS Phase

Runs AFTER Android is committed. Fresh context recommended — tell user to /clear before starting.

## Goal

Create iOS screens per migration-guide.md, wire shared module into the iOS app (Koin iOS module, navigation, SKIE StateFlow observations), build passes, app verified working on simulator and real device.

---

## Steps

### 1. UI Migration (per screen)

Read migration-guide.md for each screen's assigned strategy:
- **CMP** — Compose Multiplatform: reuse shared composable, minimal iOS wrapper
- **SwiftUI** — Native: implement screen in SwiftUI, bind to shared ViewModel via SKIE
- **Hybrid** — Mixed: shared logic + SwiftUI layout where CMP falls short

Dispatch **Sonnet agent** (`ui-migrator.md`) per screen. References:
- `android-to-swiftui.md` — Compose/XML → SwiftUI component mapping
- `skie-interop.md` — Swift/SKIE patterns for StateFlow, sealed classes, coroutines

### 2. Wire Koin iOS Module

In `iosApp/src/.../di/` (or equivalent):
- Add `initKoin()` call in `AppDelegate` or `@main` entry
- Register shared module classes: `single { LoginRepository() }`, etc.
- Match Android Koin declarations exactly — same classes, same scopes

### 3. Wire Navigation

- Add new screens to iOS navigation graph / coordinator
- Register routes that match Android navigation (same flow names from migration-guide.md)
- Do not add screens not in migration-guide.md

### 4. Register New Files in pbxproj

Every new `.swift` file must be added to the Xcode project:
```bash
# Verify registration after adding files
xcodebuild -list -project iosApp/iosApp.xcodeproj
```
Missing registration = build error `file not found`. Add via Xcode or `xcodegen` if project uses it.

### 5. iOS Build

```bash
xcodebuild \
  -workspace iosApp/iosApp.xcworkspace \
  -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  build
```

Failures: check findings.md Known Fixes first, then 3-strike rule.

### 6. Runtime Verify (mobile-mcp on simulator, fallback: xcrun)

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` |
| xcrun (fallback) | `xcrun simctl install booted <app.app>` → `xcrun simctl launch booted <bundle-id>` |

For each screen:
- `mobile_take_screenshot` → compare side-by-side with Android screenshot (visual parity)
- `mobile_list_elements_on_screen` → verify same data fields as Android
- `mobile_click_on_screen_at_coordinates` → navigate critical paths

### 7. Appium Flow Tests (iOS)

Same fake server config from planning (same deterministic responses as Android):
```
Start fake server
Run e2e-tests/ with iOS selectors (same flows as Android, adapted for iOS accessibility IDs)
  → if fail → DEBUG LOOP (iOS) → fix → rerun
  → all pass → proceed to manual test
```

### 8. Summary Table

| Screen | Strategy | Android | iOS | Visual Parity | Flow Tests |
|--------|----------|---------|-----|---------------|------------|
| Login | SwiftUI | PASS | ... | ... | ... |

Compare Android vs iOS columns. Present before manual test.

### 9. Manual Test → Commit

User tests on real iOS device against real backend. Bug → DEBUG LOOP (iOS). All flows pass:
```bash
git add -p
git commit -m "Wire iOS: <module> screens + Koin wiring"
```

Update PROGRESS.md checkpoint. PLAN.md status block updated.

---

## iOS-Specific Gotchas

**pbxproj registration** — New `.swift` files not added to the Xcode project are silently ignored at edit time but fail at build time. Always verify after adding files.

**SKIE build time** — First build after adding SKIE declarations is slow (2–5 min). Do not cancel. Subsequent incremental builds are fast.

**SourceKit trust dialog** — On first launch of a new simulator build, Xcode may show a trust dialog. User must accept before the app can run. Not a code bug.

**Framework linking** — If shared KMM framework is not linked in the iOS target's "Frameworks, Libraries" section, you get `dyld: Library not loaded`. Check Build Phases → Link Binary With Libraries.

**Kotlin/Native memory model** — All shared objects must be accessed from the main thread on iOS unless explicitly annotated. Crashes with `IncorrectDereferenceException` indicate off-thread access to frozen objects. Fix: ensure ViewModel collects flows on main dispatcher.

**SKIE StateFlow observation** — Use `.collect { }` or `ObservingTask` pattern from `skie-interop.md`. Direct property access on `StateFlow` from Swift does not trigger updates.

**Simulator vs device behavior** — Keychain, push notifications, and biometrics behave differently on simulator. If a feature fails only on device, check entitlements and provisioning.

---

## REQUIRES_APPROVAL Triggers

- Screen strategy differs from migration-guide.md assignment (CMP vs SwiftUI vs Hybrid)
- New iOS-only UI not present in Android (adds behavior not in scope)
- Navigation structure differs from Android (different flow)
- Koin scope change (singleton vs factory) for a shared class
- Any SKIE workaround that changes the Swift-visible API surface
