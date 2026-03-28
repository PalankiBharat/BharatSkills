# Battle-Tested KMM Migration Gotchas

Hard-won learnings from real production KMM migrations. Every item here burned time on a real project. Project-agnostic.

## Table of Contents

- [iOS Build Environment](#ios-build-environment)
  - [New Swift Files Need pbxproj Registration](#new-swift-files-need-pbxproj-registration)
  - [pod install After Worktree Setup](#pod-install-after-worktree-setup)
  - [local.properties Must Be Copied to Worktrees](#localproperties-must-be-copied-to-worktrees)
  - [SourceKit False Positives — Trust xcodebuild](#sourcekit-false-positives--trust-xcodebuild)
  - [:shared:build vs :shared:assemble](#sharedbuild-vs-sharedassemble)
- [SwiftUI Gotchas](#swiftui-gotchas)
  - [Sheet Must Be Dismissed Before Navigation](#sheet-must-be-dismissed-before-navigation)
  - [UIKit Touch Callbacks Need Main Queue Dispatch](#uikit-touch-callbacks-need-main-queue-dispatch)
  - [WKWebView Needs WKUIDelegate for JavaScript window.open()](#wkwebview-needs-wkuidelegate-for-javascript-windowopen)
  - [UIApplication.shared.open() Async Context](#uiapplicationsharedopen-async-context)
  - [Keyboard Handling Pattern](#keyboard-handling-pattern)
  - [Racy Fallback Routing](#racy-fallback-routing)
- [KMM/Kotlin Gotchas](#kmmkotlin-gotchas)
  - [Enum Case Sensitivity](#enum-case-sensitivity)
  - [Lost Concurrency During Migration](#lost-concurrency-during-migration)
  - [Data Class Field Additions Break iOS](#data-class-field-additions-break-ios)
  - [Multiple Flows on a Single ViewModel](#multiple-flows-on-a-single-viewmodel)
  - [SKIE Nested Dot Notation](#skie-nested-dot-notation)
  - [Backtick Test Names Crash Kotlin/Native](#backtick-test-names-crash-kotlinnative)
  - [Standalone Enum Serialization Crashes on Native](#standalone-enum-serialization-crashes-on-native)
  - [expect/actual VMs Can't Be Instantiated in commonTest](#expectactual-vms-cant-be-instantiated-in-commontest)
- [Process Gotchas](#process-gotchas)
  - [Always Audit Routing After Building Screens](#always-audit-routing-after-building-screens)
  - [iOS VMs May Be Simpler Than Android VMs](#ios-vms-may-be-simpler-than-android-vms)
  - [Reference Legacy Code Without Checkout](#reference-legacy-code-without-checkout)
  - [Field Additions Require Cross-Platform Check](#field-additions-require-cross-platform-check)
  - [Pre-Existing Test Failures Are Not Your Problem](#pre-existing-test-failures-are-not-your-problem)

---

## iOS Build Environment

### New Swift Files Need pbxproj Registration
- Every new .swift file must be manually registered in the Xcode project file (project.pbxproj)
- Required entries: PBXBuildFile, PBXFileReference, and PBXGroup
- Without this: file exists on disk but is NOT compiled. No clear error message — the types just don't exist
- This is the #1 most common iOS build failure for KMM migrations

### pod install After Worktree Setup
- Running `pod install` in the iosApp/ directory is REQUIRED after:
  - Creating a new git worktree
  - Adding new CocoaPods dependencies
  - Switching branches that modify the Podfile
- Podfile.lock is tracked but Pods/ directory is not
- Missing this causes immediate xcodebuild failure: "framework not found"

### local.properties Must Be Copied to Worktrees
- Each git worktree needs its own local.properties file (Android SDK path)
- Not automatically propagated — must be copied manually
- Missing this causes Gradle to fail with "SDK location not found"

### SourceKit False Positives — Trust xcodebuild
- Xcode/SourceKit frequently shows "No such module 'shared'" or "No such module 'sesamekmmsdk'"
- These are IDE indexing false positives — NOT real errors
- xcodebuild succeeds regardless
- Rule: NEVER spend time debugging SourceKit errors. Run xcodebuild — if it passes, ignore IDE errors

### :shared:build vs :shared:assemble
- `:shared:build` runs tests. If pre-existing tests are failing, it will fail even if your code is fine
- `:shared:assemble` compiles without running tests
- `:shared:linkDebugFrameworkIosSimulatorArm64` compiles iOS framework only
- Use assemble or linkDebugFramework when pre-existing test failures block build verification

---

## SwiftUI Gotchas

### Sheet Must Be Dismissed Before Navigation
- If you navigate away while a `.sheet` is presented, the sheet persists to the next screen
- Root cause: SwiftUI does not automatically dismiss sheets when the presenting view navigates
- Fix: Use a pendingAction flag + onDismiss callback to sequence: dismiss sheet first, THEN navigate
- Code pattern:
```swift
@State private var pendingNavigation: Destination? = nil
.sheet(isPresented: $showSheet, onDismiss: {
    if let destination = pendingNavigation {
        pendingNavigation = nil
        router.navigate(to: destination)
    }
}) { ... }
```

### UIKit Touch Callbacks Need Main Queue Dispatch
- When using UIViewRepresentable with touch delegates (e.g., signature drawing)
- touchesEnded callback fires but does not trigger SwiftUI re-render
- Fix: Wrap state update in `DispatchQueue.main.async { }`
- Why: UIKit touch callbacks are on main thread but SwiftUI binding update needs explicit dispatch

```swift
// In UIViewRepresentable Coordinator:
func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    DispatchQueue.main.async {
        self.parent.didFinishDrawing = true  // triggers SwiftUI re-render
    }
}
```

### WKWebView Needs WKUIDelegate for JavaScript window.open()
- Some web pages (e.g., e-sign flows) use `window.open()` for popups
- Without WKUIDelegate, WKWebView SILENTLY discards these requests — button appears to do nothing
- Fix: Add WKUIDelegate conformance, implement `webView(_:createWebViewWith:)`, set `javaScriptCanOpenWindowsAutomatically = true`

### UIApplication.shared.open() Async Context
- In iOS 16+, `open()` is async
- Inside `.task {}` blocks: needs `await` — `await UIApplication.shared.open(url)`
- Inside sync closures (button actions, sheet callbacks): does NOT need await
- Getting this wrong: compile error in one direction, missing await warning in the other

### Keyboard Handling Pattern
- Standard pattern for screens where CTA button should float above keyboard:
```swift
@State private var keyboardHeight: CGFloat = 0
// In body:
.onReceive(Publishers.keyboardHeight) { height in
    keyboardHeight = height
}
.offset(y: -keyboardHeight)
```
- When fixing keyboard issues, audit ALL screens of the same type, not just the one reported

### Racy Fallback Routing
- Never use `asyncAfter`/`DispatchQueue.main.asyncAfter` as a fallback for "if VM doesn't respond in time"
- Race condition: both the VM callback and the timer fallback can fire, causing double navigation
- Fix: Use a proper state machine. If concerned about VM responsiveness, add a timeout to the VM itself

---

## KMM/Kotlin Gotchas

### Enum Case Sensitivity
- "CONTROL" vs "control" breaks feature flags silently
- Kotlin is case-sensitive. If Android sends "control" and KMM expects "CONTROL", the enum won't match
- SerialName annotations and case-insensitive comparison can help
- Always verify enum string values match between Android and KMM

### Lost Concurrency During Migration
- Android code using async/await for parallel uploads can silently become sequential in KMM
- If you see multiple API calls that were concurrent, ensure they remain concurrent:
```kotlin
// WRONG — sequential:
val result1 = api.upload(file1)
val result2 = api.upload(file2)

// RIGHT — concurrent:
coroutineScope {
    val deferred1 = async { api.upload(file1) }
    val deferred2 = async { api.upload(file2) }
    awaitAll(deferred1, deferred2)
}
```

### Data Class Field Additions Break iOS
- Adding fields to a Kotlin data class used in the shared framework (e.g., UserCredentials) requires updating Swift call sites
- Swift uses positional constructors for Kotlin data classes — adding a field shifts all positions
- Always check Swift callers after modifying shared data classes

### Multiple Flows on a Single ViewModel
- Some VMs expose both `effect: SharedFlow<Effect>` AND a separate `navigationEvents: SharedFlow<Route?>`
- You MUST subscribe to BOTH separately from Swift
- If you only subscribe to effect, you miss ALL navigation events from navigationEvents
- Always check the VM for ALL public Flow properties, not just state and effect

### SKIE Nested Dot Notation
- SKIE generates nested dot notation for sealed class subtypes
- Swift: `PinVerificationEvent.OTPEnter`, NOT flat `OTPEnter`
- This affects action dispatch and effect handling from Swift
- Sealed subtypes from Swift: `Effect.NavigateToNext`, not `NavigateToNext`

### Backtick Test Names Crash Kotlin/Native
- `fun \`test my behavior\`()` compiles on JVM but CRASHES on Kotlin/Native
- Always use camelCase: `fun testMyBehavior()`
- This is a commonTest rule — tests must work on BOTH JVM and Native

### Standalone Enum Serialization Crashes on Native
- Encoding a non-`@Serializable` enum standalone crashes on Kotlin/Native
- Fix: test serialization within the context of a parent `@Serializable` class, not standalone

### expect/actual VMs Can't Be Instantiated in commonTest
- If your ViewModel uses expect/actual (e.g., `expect abstract class KMMViewModel`), it can't be directly created in commonTest
- Fix: create a test wrapper class in the test directory that extends the VM

---

## Process Gotchas

### Always Audit Routing After Building Screens
- A screen can be fully implemented — correct layout, correct state handling — but not wired in navigation
- After building any screen, always check: is it reachable? Is the Destination case in Router? Is it in RootView's navigationDestination?
- The most common "it doesn't work" bug is a missing navigation wire, not a code bug

### iOS VMs May Be Simpler Than Android VMs
- Don't assume iOS and Android VMs are identical
- iOS often has: fewer routes, different edge cases, simpler error handling
- Always parity-check the VM before building the screen — read the actual implementation

### Reference Legacy Code Without Checkout
- Use `git show <base-branch>:<path>` to read legacy code without checking out the branch (substitute the actual branch name, e.g. `master`, `main`, or your project's default branch)
- Keeps the worktree clean while still having access to the original implementation

### Field Additions Require Cross-Platform Check
- Any field added to a shared data class or interface must be checked on BOTH platforms
- Android: do existing callers pass the new field?
- iOS: Swift positional constructors — does the new field break existing call sites?

### Pre-Existing Test Failures Are Not Your Problem
- If tests were failing BEFORE your changes, they are not your responsibility
- Use `:shared:assemble` instead of `:shared:build` to bypass pre-existing test failures
- Document pre-existing failures so they are not confused with regression
