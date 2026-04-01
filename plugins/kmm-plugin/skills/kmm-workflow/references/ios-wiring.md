# iOS Wiring Reference

Consolidated reference for wiring the iOS phase of a KMM migration. Covers the full protocol from first screen to commit, component mapping, SKIE interop patterns, and build/runtime verification.

Runs AFTER Android is committed. Fresh context recommended — tell user to `/clear` before starting.

---

## Table of Contents

1. [Wire iOS Protocol](#1-wire-ios-protocol)
2. [Parallel Execution (Sonnet per screen ‖ Sonnet Koin iOS)](#2-parallel-execution)
3. [Compose/XML → SwiftUI Component Mapping](#3-composexml--swiftui-component-mapping)
   - [Layout](#layout)
   - [Navigation](#navigation)
   - [Input](#input)
   - [Display](#display)
   - [Modifiers](#modifiers)
   - [State](#state)
   - [Other Components](#other-components)
   - [Dialogs and Sheets](#dialogs-and-sheets)
   - [Fragment / XML → SwiftUI](#fragment--xml--swiftui)
4. [SKIE Interop (StateFlow, sealed, suspend→async)](#4-skie-interop)
5. [Screen Template + Effect Handling](#5-screen-template--effect-handling)
6. [Navigation & pbxproj Registration](#6-navigation--pbxproj-registration)
7. [Build & Runtime Verification](#7-build--runtime-verification)
8. [iOS Gotchas](#8-ios-gotchas)
9. [REQUIRES_APPROVAL Triggers](#9-requires_approval-triggers)

---

## 1. Wire iOS Protocol

### Goal

Create iOS screens per `migration-guide.md`, wire shared module into the iOS app (Koin iOS module, navigation, SKIE StateFlow observations), build passes, app verified working on simulator and real device.

### Steps

#### Step 1 — UI Migration (per screen)

Read `migration-guide.md` for each screen's assigned strategy:

- **CMP** — Compose Multiplatform: reuse shared composable, minimal iOS wrapper
- **SwiftUI** — Native: implement screen in SwiftUI, bind to shared ViewModel via SKIE
- **Hybrid** — Mixed: shared logic + SwiftUI layout where CMP falls short

Dispatch **Sonnet agent** (`ui-migrator.md`) per screen (see Section 2 for parallel dispatch).

#### Step 2 — Wire Koin iOS Module

In `iosApp/src/.../di/` (or equivalent):
- Add `initKoin()` call in `AppDelegate` or `@main` entry
- Register shared module classes: `single { LoginRepository() }`, etc.
- Match Android Koin declarations exactly — same classes, same scopes

#### Step 3 — Wire Navigation

- Add new screens to iOS navigation graph / coordinator
- Register routes that match Android navigation (same flow names from `migration-guide.md`)
- Do not add screens not in `migration-guide.md`

#### Step 4 — Register New Files in pbxproj

Every new `.swift` file must be added to the Xcode project (see [Section 6](#6-navigation--pbxproj-registration) for full details):

```bash
# Verify registration after adding files
xcodebuild -list -project iosApp/iosApp.xcodeproj
```

Missing registration = build error `file not found`.

#### Step 5 — iOS Build

```bash
xcodebuild \
  -workspace iosApp/iosApp.xcworkspace \
  -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  build
```

Failures: check `findings.md` Known Fixes first, then 3-strike rule.

#### Step 6 — Runtime Verify

See [Section 7](#7-build--runtime-verification) for the full verification protocol.

#### Step 7 — mobile-mcp Automated Flow Tests (iOS)

Same fake server config from planning (same deterministic responses as Android):

```
Start fake server
Run mobile-mcp automated flows with iOS selectors (same flows as Android, adapted for iOS accessibility IDs)
  → if fail → DEBUG LOOP (iOS) → fix → rerun
  → all pass → proceed to manual test
```

#### Step 8 — Summary Table

| Screen | Strategy | Android | iOS | Visual Parity | Flow Tests |
|--------|----------|---------|-----|---------------|------------|
| Login | SwiftUI | PASS | ... | ... | ... |

Compare Android vs iOS columns. Present before manual test.

#### Step 9 — Manual Test → Commit

User tests on real iOS device against real backend. Bug → DEBUG LOOP (iOS). All flows pass:

```bash
git add -p
git commit -m "Wire iOS: <module> screens + Koin wiring"
```

Update `PROGRESS.md` checkpoint. `PLAN.md` status block updated.

---

## 2. Parallel Execution

### Dispatch pattern

Launch one Sonnet agent per screen concurrently. Each agent handles one screen end-to-end (SwiftUI implementation, state wiring, effect handling). A separate Sonnet agent handles Koin iOS module wiring in parallel with the screen agents.

```
Sonnet agent: screen-1 (ui-migrator.md)  ─┐
Sonnet agent: screen-2 (ui-migrator.md)  ─┤─→ merge results → build verify
Sonnet agent: screen-N (ui-migrator.md)  ─┤
Sonnet agent: Koin iOS wiring            ─┘
```

### Per-screen agent input

Each screen agent receives:
- The screen's entry from `migration-guide.md` (strategy, ViewModel name, route)
- The Android source files for that screen
- This reference file (or the relevant sections)

### Merge step

After all agents complete, the orchestrator:
1. Verifies no duplicate `Destination` cases in `Router`
2. Verifies no duplicate Koin registrations
3. Runs the build (Section 7) and resolves any cross-screen conflicts

---

## 3. Compose/XML → SwiftUI Component Mapping

**Fidelity Rules (NON-NEGOTIABLE)**

Android is the source of truth. Match EVERYTHING.

- Match layout structure exactly: if Android uses a list, use a list. If it uses a grid, use a grid. Do not substitute or "improve".
- Match spacing exactly: `16.dp` becomes `16` (points). `8.dp` becomes `8`. Do not round or normalize.
- Match selection indicators, dividers, typography hierarchy, and padding values exactly.
- Match variable and function names: if Android has `onSubmitClick`, Swift has `onSubmitClick`. If Android has `isLoading`, Swift has `isLoading`.
- Match state handling exactly: same error states, same loading states, same empty states.
- Match colors, font sizes, and text styles as closely as the platform allows.
- Only adapt platform idioms: use `NavigationStack` instead of `NavHost`, `@EnvironmentObject` instead of `hiltViewModel()`. These are the only permitted divergences.
- NEVER improve. NEVER add extra error handling. NEVER reorganize the layout. NEVER add convenience nil checks that aren't in Android.
- If the Android screen has a bug or looks bad, the SwiftUI screen should have the same bug and look bad in the same way. Flag it to the user — do not silently fix it.

### Layout

| Compose | SwiftUI | Notes |
|---|---|---|
| `Column` | `VStack` | |
| `Row` | `HStack` | |
| `Box` | `ZStack` | |
| `LazyColumn` | `List` or `ScrollView + LazyVStack` | Use `List` when rows are uniform; `ScrollView + LazyVStack` when mixing content |
| `LazyRow` | `ScrollView(.horizontal) { LazyHStack { } }` | |
| `Scaffold` | `NavigationStack` + `.toolbar` | |
| `Surface` | No direct equivalent | Use `.background()` and `.overlay()` |
| `Card` | `RoundedRectangle` with `.shadow()` | See snippet below |
| `Spacer()` | `Spacer()` | |
| `Spacer(modifier = Modifier.height(8.dp))` | `Spacer().frame(height: 8)` | |

**Card snippet:**
```swift
// Compose: Card(elevation = CardDefaults.cardElevation(4.dp)) { ... }
RoundedRectangle(cornerRadius: 8)
    .fill(Color.white)
    .shadow(radius: 4)
    .overlay {
        // card content
    }
```

### Navigation

| Compose | SwiftUI | Notes |
|---|---|---|
| `NavHost` | `NavigationStack` | Defined once in `RootView` |
| `navController.navigate("route")` | `router.navigate(to: .destination)` | Via effect handling |
| `TopAppBar` | `.toolbar` + `.navigationTitle` | |
| `BottomNavigation` | `TabView` with `.tabItem` | |
| `BackHandler { }` | Handled automatically by `NavigationStack` | No equivalent needed |
| `popBackStack()` | `router.pop()` | |

### Input

| Compose | SwiftUI | Notes |
|---|---|---|
| `TextField` | `TextField` | |
| `TextField` (password) | `SecureField` | Match `visualTransformation = PasswordVisualTransformation()` |
| `Button` | `Button` | |
| `Checkbox` | `Toggle` with custom checkbox style | |
| `RadioButton` | `Picker` with `.radioGroup` or custom | |
| `Switch` | `Toggle` | |
| `Slider` | `Slider` | |
| `DropdownMenu` | `Menu` or `Picker` | |
| `OutlinedTextField` | `TextField` with `.textFieldStyle(.roundedBorder)` or custom border overlay | |

### Display

| Compose | SwiftUI | Notes |
|---|---|---|
| `Text` | `Text` | |
| `Image(painterResource(...))` | `Image("name")` | Local asset |
| `AsyncImage` (Coil) | `AsyncImage` | Available iOS 15+ |
| `Icon(Icons.Default.X)` | `Image(systemName: "x")` | Map icon names manually |
| `CircularProgressIndicator()` | `ProgressView()` | |
| `LinearProgressIndicator(progress)` | `ProgressView(value: progress)` | |
| `Divider()` | `Divider()` | |
| `Spacer()` | `Spacer()` | |
| `HorizontalPager` | `TabView` with `.tabViewStyle(.page)` | |

### Modifiers

| Compose Modifier | SwiftUI Modifier | Notes |
|---|---|---|
| `.padding(16.dp)` | `.padding(16)` | |
| `.padding(horizontal = 16.dp)` | `.padding(.horizontal, 16)` | |
| `.padding(vertical = 8.dp)` | `.padding(.vertical, 8)` | |
| `.padding(top = 8.dp, bottom = 4.dp)` | `.padding(.top, 8).padding(.bottom, 4)` | |
| `.fillMaxWidth()` | `.frame(maxWidth: .infinity)` | |
| `.fillMaxHeight()` | `.frame(maxHeight: .infinity)` | |
| `.fillMaxSize()` | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | |
| `.width(100.dp)` | `.frame(width: 100)` | |
| `.height(48.dp)` | `.frame(height: 48)` | |
| `.size(24.dp)` | `.frame(width: 24, height: 24)` | |
| `.background(Color.Red)` | `.background(Color.red)` | |
| `.clip(RoundedCornerShape(8.dp))` | `.clipShape(RoundedRectangle(cornerRadius: 8))` | |
| `.clip(CircleShape)` | `.clipShape(Circle())` | |
| `.clickable { }` | `.onTapGesture { }` or wrap in `Button` | Prefer `Button` for semantic correctness |
| `.weight(1f)` | `Spacer()` or `.frame(maxWidth: .infinity)` | Inside `HStack` |
| `.align(Alignment.Center)` | `.frame(alignment: .center)` | |
| `.border(1.dp, Color.Gray)` | `.overlay(RoundedRectangle(cornerRadius: 0).stroke(Color.gray, lineWidth: 1))` | |
| `.wrapContentWidth()` | Default — no modifier needed | |
| `.alpha(0.5f)` | `.opacity(0.5)` | |
| `.rotate(45f)` | `.rotationEffect(.degrees(45))` | |
| `.zIndex(1f)` | `.zIndex(1)` | |
| `.offset(x = 8.dp)` | `.offset(x: 8)` | |
| `.testTag("tag")` | `.accessibilityIdentifier("tag")` | |

### State

| Compose | SwiftUI | Notes |
|---|---|---|
| `remember { mutableStateOf(x) }` | `@State var x` | |
| `collectAsState()` | `for await in .task { }` | |
| `LaunchedEffect(key) { }` | `.task(id: key) { }` | Restarts when key changes |
| `LaunchedEffect(Unit) { }` | `.task { }` | Runs once on appear |
| `rememberCoroutineScope()` | Not needed | `.task` handles lifecycle automatically |
| `derivedStateOf { }` | Computed property (`var x: T { }`) | |
| `SideEffect { }` | `.onChange(of:)` | |
| `DisposableEffect { onDispose { } }` | `.onDisappear { }` | |
| `produceState` | `@State` + `.task` | |

### Other Components

| Compose | SwiftUI | Notes |
|---|---|---|
| `Snackbar` | Custom overlay or `.toast` modifier | No direct equivalent |
| `AnimatedVisibility` | `if condition { view.transition(.opacity) }` with `withAnimation` | |
| `FlowRow` | Custom `Layout` (iOS 16+) or wrapped `UICollectionViewLayout` | |
| `FloatingActionButton` | `.overlay` with positioned `Button` or `.toolbar` button | |

### Dialogs and Sheets

| Compose | SwiftUI | Notes |
|---|---|---|
| `AlertDialog` | `.alert` modifier | |
| `BottomSheetScaffold` | `.sheet` modifier | |
| `ModalBottomSheet` | `.sheet` modifier | |
| `Dialog { }` | `.sheet` or `.fullScreenCover` | |

### Fragment / XML → SwiftUI

#### Layout Containers

| Android XML | SwiftUI | Notes |
|---|---|---|
| `LinearLayout` (vertical) | `VStack` | |
| `LinearLayout` (horizontal) | `HStack` | |
| `FrameLayout` | `ZStack` | |
| `ConstraintLayout` | `VStack` / `HStack` composition | Use `GeometryReader` for complex absolute positioning |
| `RelativeLayout` | `ZStack` with alignment | |
| `ScrollView` | `ScrollView` | |
| `RecyclerView` | `List` or `ScrollView + LazyVStack` | |
| `ViewPager2` | `TabView` with `.tabViewStyle(.page)` | |
| `CoordinatorLayout` | `ScrollView` with `.toolbar` | No direct equivalent |
| `NestedScrollView` | `ScrollView` | |

#### Widgets

| Android XML | SwiftUI | Notes |
|---|---|---|
| `TextView` | `Text` | |
| `EditText` | `TextField` | |
| `ImageView` | `Image` / `AsyncImage` | |
| `Button` | `Button` | |
| `ProgressBar` (circular) | `ProgressView()` | |
| `ProgressBar` (horizontal) | `ProgressView(value:)` | |
| `WebView` | `WKWebView` via `UIViewRepresentable` | |
| `CheckBox` | `Toggle` | |
| `RadioGroup` / `RadioButton` | `Picker` | |
| `Spinner` (dropdown) | `Picker` | |
| `SeekBar` | `Slider` | |
| `Switch` | `Toggle` | |
| `CardView` | `RoundedRectangle` + `.shadow()` | |
| `ChipGroup` / `Chip` | Custom `HStack` with tags | |

#### XML Attributes

| Android Attribute | SwiftUI Modifier | Notes |
|---|---|---|
| `android:padding="16dp"` | `.padding(16)` | |
| `android:paddingHorizontal="16dp"` | `.padding(.horizontal, 16)` | |
| `android:layout_width="match_parent"` | `.frame(maxWidth: .infinity)` | |
| `android:layout_width="wrap_content"` | Default — no modifier needed | |
| `android:layout_height="48dp"` | `.frame(height: 48)` | |
| `android:visibility="gone"` | `if condition { view }` | Remove from layout |
| `android:visibility="invisible"` | `.opacity(0)` | Keeps layout space |
| `android:gravity="center"` | `.frame(alignment: .center)` or `.multilineTextAlignment(.center)` | |
| `android:textColor="#FF0000"` | `.foregroundColor(Color.red)` | |
| `android:textSize="16sp"` | `.font(.system(size: 16))` | |
| `android:textStyle="bold"` | `.fontWeight(.bold)` | |
| `android:background="@color/primary"` | `.background(Color.primary)` | |
| `android:elevation="4dp"` | `.shadow(radius: 4)` | |
| `android:layout_margin="8dp"` | `.padding(8)` on parent or `.padding(8)` on view | |
| `android:layout_weight="1"` | `.frame(maxWidth: .infinity)` inside `HStack` | |
| `android:drawableStart` | `Label("text", systemImage: "icon")` or custom `HStack` | |
| `android:hint="Placeholder"` | `TextField("Placeholder", text: $text)` | |
| `android:inputType="textPassword"` | `SecureField` | |
| `android:maxLines="2"` | `.lineLimit(2)` | |
| `android:ellipsize="end"` | `.truncationMode(.tail)` | |
| `android:letterSpacing` | `.kerning(value)` | |
| `android:lineSpacingExtra` | `.lineSpacing(value)` | |
| `android:layout_height="match_parent"` | `.frame(maxHeight: .infinity)` | |
| `TabLayout` | `Picker` with `.segmented` style or custom tab bar | |
| `FloatingActionButton` | `.overlay` with positioned `Button` | |

---

## 4. SKIE Interop

SKIE (Swift Kotlin Interface Enhancer) improves the Swift API generated from Kotlin/Native, replacing clunky wrapper types with idiomatic Swift constructs.

### Setup

```kotlin
// build.gradle.kts (shared module or root)
plugins {
    id("co.touchlab.skie") version "0.10.10"
}
```

**Blocking prerequisites:**
- Gradle 8.8+ is required. Check with `./gradlew --version` before adding SKIE. Older Gradle versions will fail silently or with cryptic errors.
- No additional dependencies are needed. SKIE automatically instruments all exported Kotlin code.

**Pre-flight SKIE compatibility check:** Before Phase 5, verify SKIE configuration against all `api()` + `export()` dependencies. Third-party KMM artifacts that were NOT built with SKIE may generate broken `Companion` wrappers (e.g., `SuspendInterop` on pre-compiled SDK types). For each such artifact, disable SKIE processing:

```kotlin
// build.gradle.kts
skie {
    analytics { enabled.set(false) }
    // Disable SuspendInterop for pre-compiled third-party KMM SDKs
    features {
        coroutinesInterop.set(false) // per-package override below
    }
}
```

Or use per-package exclusion in `skie.config.json`:
```json
{
  "packages": {
    "com.thirdparty.sdk": {
      "SuspendInterop": { "Enabled": false }
    }
  }
}
```

Check this BEFORE the iOS build — SKIE failures at link time are hard to diagnose.

**Optional: per-function annotations**

```kotlin
// build.gradle.kts
dependencies {
    commonMainImplementation("co.touchlab.skie:configuration-annotations:0.10.10")
}
```

Use `@SealedInterop.Enabled`, `@FlowInterop.Enabled`, etc. to opt in/out per declaration when the global defaults aren't appropriate.

### StateFlow/SharedFlow → AsyncSequence

SKIE automatically converts `StateFlow<T>` and `SharedFlow<T>` to Swift `AsyncSequence`. No wrappers, no Combine bridges.

**State observation:**
```swift
.task {
    for await state in viewModel.state {
        self.state = state
    }
}
```

**Effect observation (nullable SharedFlow):**
```swift
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        // handle non-nil effect
    }
}
```

**Rules:**
- `.task {}` attaches to a SwiftUI view and auto-cancels when the view disappears. No manual `cancel()` call needed.
- Use **separate** `.task {}` blocks for state and effect flows. Each block runs as an independent async loop. Combining them into one block means the second loop never starts — the first loop runs forever.
- `.task(id:)` restarts the async block when `id` changes. Use this when you need to restart observation on a key change.

### Sealed Classes → Swift Enums

SKIE converts Kotlin sealed classes into exhaustive Swift enums via the `onEnum(of:)` function.

**Object variants (no associated data):**
```swift
// Kotlin: object Exit : Effect()
switch onEnum(of: effect) {
case .exit:
    dismiss()
}
```

**Data class variants (with properties):**
```swift
// Kotlin: data class ShowError(val message: String) : Effect()
switch onEnum(of: effect) {
case .showError(let e):
    showAlert(e.message)
}
```

**Nested sealed classes:**
```swift
switch onEnum(of: effect) {
case .navigate(let nav):
    switch onEnum(of: nav) {
    case .toHome:
        router.push(.home)
    case .toDetail(let d):
        router.push(.detail(id: d.id))
    }
}
```

No `default` case needed. The compiler enforces exhaustiveness. If you add a new sealed subclass in Kotlin, Swift will produce a compile error at every switch site — which is the desired behavior.

Subtypes use nested dot notation. SKIE generates `Effect.NavigateToNext`, not flat `NavigateToNext`. This applies to both effect handling and action dispatching.

### Suspend Functions → async throws

Kotlin `suspend` functions are exposed as Swift `async throws` functions directly.

```swift
Task {
    do {
        let result = try await viewModel.loadData()
        self.items = result
    } catch {
        self.errorMessage = error.localizedDescription
    }
}
```

Cancellation is propagated. Cancelling the Swift `Task` also cancels the underlying Kotlin coroutine — structured concurrency works across the boundary.

### Protocol Conformance Gotcha (CRITICAL)

When a Swift class conforms to a Kotlin interface (protocol) that contains `suspend` functions, SKIE **prefixes the overriding method with `__`**.

```kotlin
// Kotlin
interface BiometricHandler {
    suspend fun isEnabled(): Boolean
    fun label(): String
}
```

```swift
// Swift — generated protocol
class SwiftBiometricHandler: BiometricHandler {
    // suspend fun → prefixed with __ and returns KotlinBoolean
    func __isEnabled() async throws -> KotlinBoolean {
        return KotlinBoolean(bool: await checkBiometrics())
    }

    // non-suspend fun → original name, native Swift type
    func label() -> String {
        return "Face ID"
    }
}
```

This is intentional SKIE design to avoid naming conflicts with the generated async wrapper. Non-suspend functions keep their original names and use native Swift types. Do not rename `__isEnabled` — the Kotlin runtime looks it up by that exact symbol.

The `__` prefix applies ONLY to suspend functions themselves, not to non-suspend functions in the same interface. The `__` prefix for suspend functions in protocols and the `__` prefix for Kotlin-backed enum types (see below) are separate SKIE mechanisms — unrelated despite using the same prefix.

### Kotlin Enums → Swift Enums

SKIE converts Kotlin enums to Swift enums for exhaustive switching.

```swift
// Exhaustive switch — no default needed
switch occupation {
case .privateSector:
    label = "Private"
case .publicSector:
    label = "Public"
}
```

**Accessing Kotlin enum properties or methods** requires converting back to the Kotlin enum first:

```swift
let description = Occupation.privateSector.toKotlinEnum().description()
```

The original Kotlin enum is accessible in Swift with a `__` prefix (`__Occupation`). The SKIE-generated Swift enum is the unqualified name (`Occupation`).

**Conversion helpers:**
- `swiftEnum.toKotlinEnum()` — Swift → Kotlin
- `kotlinEnum.toSwiftEnum()` — Kotlin → Swift

### SKIE Quick Reference

| Kotlin type | Swift type (SKIE) | Access pattern |
|---|---|---|
| `StateFlow<T>` | `AsyncSequence` | `for await x in vm.state` |
| `SharedFlow<T?>` | `AsyncSequence` | `for await x in vm.effect` + guard |
| `sealed class` | `enum` (via `onEnum`) | `switch onEnum(of: x)` |
| `suspend fun` | `async throws func` | `try await vm.op()` |
| `enum class` | Swift enum | `switch x` / `.toKotlinEnum()` |
| interface w/ suspend | Swift protocol | override as `func __name() async throws` |

---

## 5. Screen Template + Effect Handling

### Standard Screen Template

Every screen follows this exact structure:

```swift
import SwiftUI

struct MyScreen: View {
    @EnvironmentObject private var router: Router
    private let viewModel: MyViewModel
    @State private var state: MyState = MyState()

    init() {
        self.viewModel = PresenterProvider.shared.getMyViewModel()
    }

    var body: some View {
        // UI driven entirely by `state`
        content
            .task {
                // State observation — matches collectAsState() in Compose
                for await newState in viewModel.state {
                    state = newState
                }
            }
            .task {
                // Effect observation — matches LaunchedEffect / SideEffect in Compose
                for await effect in viewModel.effects {
                    guard let effect = effect else { continue }
                    switch onEnum(of: effect) {
                    case .navigateToHome:
                        router.navigate(to: .home)
                    case .showError(let e):
                        // handle error
                        break
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        // main layout here
    }
}
```

Key points:
- `@EnvironmentObject private var router: Router` — always present, even if screen does not navigate. Matches Android's `NavController` availability.
- `private let viewModel: MyViewModel` — concrete type, no protocol wrapping.
- `@State private var state: MyState` — single state object mirrors Compose's `uiState`.
- `init()` calls `PresenterProvider.shared.getMyViewModel()` — this is one common way to obtain a VM. The VM acquisition pattern (`PresenterProvider.shared`) is one common approach. Your project may use Koin, manual injection, or a different provider. Adapt to match the project's existing DI conventions.
- First `.task` collects state. Second `.task` collects effects. Keep them separate.
- `guard let effect = effect else { continue }` — required pattern before switching on nullable effect flows.
- `switch onEnum(of:)` — always use SKIE's `onEnum` helper, never raw enum switch.

### Effect Handling Pattern

Effects from KMM ViewModels are observed in a dedicated `.task` block. Always use `onEnum(of:)` from SKIE — never switch on the raw Kotlin enum.

**Flat sealed class:**
```swift
// Kotlin: sealed class Effect { data class Navigate(val route: String); object ShowError }
.task {
    for await effect in viewModel.effects {
        guard let effect = effect else { continue }
        switch onEnum(of: effect) {
        case .navigate(let e):
            router.navigate(to: routeFor(e.route))
        case .showError:
            showError = true
        }
    }
}
```

**Nested sealed class:**
```swift
// Kotlin: sealed class Effect { sealed class Auth { object LoggedIn; object LoggedOut }; object Dismiss }
.task {
    for await effect in viewModel.effects {
        guard let effect = effect else { continue }
        switch onEnum(of: effect) {
        case .auth(let authEffect):
            switch onEnum(of: authEffect) {
            case .loggedIn:
                router.navigate(to: .home)
            case .loggedOut:
                router.navigate(to: .login)
            }
        case .dismiss:
            router.pop()
        }
    }
}
```

Rules:
- Every `case` in the Kotlin sealed class MUST be handled. No `default:` fallthrough that silently drops cases.
- Nested sealed classes require nested `switch onEnum(of:)` calls — one level per nesting.
- `guard let effect = effect else { continue }` is always required before the switch to unwrap the nullable flow value.

### Multiple Flows on a ViewModel

Some ViewModels expose more than one reactive flow (e.g., a primary `effect: SharedFlow<Effect?>` and a secondary `navigationEvents: SharedFlow<Route?>`). Both must be subscribed to independently.

```swift
// Subscribe to both — missing one means missing navigation events
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        handleEffect(effect)
    }
}
.task {
    for await route in viewModel.navigationEvents {
        guard let route = route else { continue }
        handleRoute(route)
    }
}
```

If you only subscribe to `effect` and navigation uses `navigationEvents`, the screen will appear broken with no error or log output.

---

## 6. Navigation & pbxproj Registration

### Navigation Wiring Checklist

When adding a new screen that requires navigation, complete all four steps:

**Step 1** — Add new `Destination` case to the `Router` enum:
```swift
enum Destination: Hashable {
    case home
    case myNewScreen(id: String)  // add here
}
```

**Step 2** — Add `.navigationDestination(for:)` in `RootView`:
```swift
.navigationDestination(for: Router.Destination.self) { destination in
    switch destination {
    case .home: HomeScreen()
    case .myNewScreen(let id): MyNewScreen(id: id)
    }
}
```

**Step 3** — Map KMM `Route` to `Router.Destination` in the route callback (wherever routes are resolved):
```swift
switch onEnum(of: route) {
case .myNewScreen(let r): return .myNewScreen(id: r.id)
}
```

**Step 4** — Wire effects that trigger navigation in the screen's effect observer `.task`:
```swift
case .openMyNewScreen(let e):
    router.navigate(to: .myNewScreen(id: e.id))
```

Missing any step causes silent failures: the destination exists but is never reachable, or is reachable but renders nothing.

### PBXFileSystemSynchronizedRootGroup (Xcode 16+)
If the project uses `PBXFileSystemSynchronizedRootGroup`, new .swift files are auto-discovered — no manual `PBXBuildFile`, `PBXFileReference`, or `PBXGroup` entries needed. Check `project.pbxproj` for this group type before planning manual registration tasks.

### pbxproj Registration

**Project format detection:** Before registering files, check if the Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ modern format). If present, Xcode auto-discovers all files in the group directory — skip manual pbxproj registration entirely. Only proceed with manual registration for legacy `PBXGroup`-based projects.

```bash
# Check project format
grep -c "PBXFileSystemSynchronizedRootGroup" iosApp/iosApp.xcodeproj/project.pbxproj
# If > 0 → modern format, skip manual registration
# If 0 → legacy format, register manually below
```

For legacy projects, every new `.swift` file MUST be manually registered in `project.pbxproj`. Xcode does this automatically when you use the GUI, but since files are created via code or terminal, they are not registered automatically.

A missing registration means the file exists on disk and can be imported but is never compiled. Errors will appear as "use of unresolved identifier" elsewhere — not as a missing-file error on the new file itself.

Four entries are required per file:

**1. PBXBuildFile** — links the file reference to the compile sources build phase:
```
A1B2C3D4E5F60001 /* MyNewScreen.swift in Sources */ = {
    isa = PBXBuildFile;
    fileRef = A1B2C3D4E5F60002 /* MyNewScreen.swift */;
};
```

**2. PBXFileReference** — declares the file on disk:
```
A1B2C3D4E5F60002 /* MyNewScreen.swift */ = {
    isa = PBXFileReference;
    lastKnownFileType = sourcecode.swift;
    path = MyNewScreen.swift;
    sourceTree = "<group>";
};
```

**3. PBXGroup** — adds the file reference to its parent folder group:
```
/* Screens group */
children = (
    A1B2C3D4E5F60002 /* MyNewScreen.swift */,
    // ... other files
);
```

**4. PBXSourcesBuildPhase** — adds the build file to the compile sources list:
```
files = (
    A1B2C3D4E5F60001 /* MyNewScreen.swift in Sources */,
    // ... other files
);
```

Use unique UUIDs (24 hex characters). Check existing entries in `project.pbxproj` for the correct UUID format used in the project. UUIDs must be unique across the entire file.

Verify after adding files:
```bash
xcodebuild -list -project iosApp/iosApp.xcodeproj
```

---

## 7. Build & Runtime Verification

### iOS Build

```bash
xcodebuild \
  -workspace iosApp/iosApp.xcworkspace \
  -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  build
```

Failures: check `findings.md` Known Fixes first, then 3-strike rule.

### pod install Sequence (CMP Projects)
For projects using Compose Multiplatform with CocoaPods:
1. Full shared framework build (`./gradlew :shared:build` or `:shared:linkDebugFrameworkIosSimulatorArm64`)
2. `cd iosApp && pod install` — re-run AFTER the full build, not just after `generateDummyFramework`
3. `xcodebuild` — only after pod install picks up populated compose-resources

`generateDummyFramework` + `pod install` produces an empty framework with no compose resources. The full build must populate `build/compose/cocoapods/compose-resources` first.

### Runtime Verify (mobile-mcp on simulator, fallback: xcrun)

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` |
| xcrun (fallback) | `xcrun simctl install booted <app.app>` → `xcrun simctl launch booted <bundle-id>` |

For each screen:
- `mobile_take_screenshot` → compare side-by-side with Android screenshot (visual parity)
- `mobile_list_elements_on_screen` → verify same data fields as Android
- `mobile_click_on_screen_at_coordinates` → navigate critical paths

---

## 8. iOS Gotchas

**pbxproj registration** — New `.swift` files not added to the Xcode project are silently ignored at edit time but fail at build time. Always verify after adding files.

**Mandatory `pod install` after shared module changes** — After ANY shared module dependency change (new `api()` or `implementation()` dependency, framework rebuild, Compose resource addition), re-run `pod install` in the `iosApp/` directory. CocoaPods does not regenerate the framework copy script automatically — the `spec.resources` line may be correct but the actual copy script in the generated Xcode project won't update until `pod install` runs again. Missing this causes Compose resources to not be bundled in the iOS app (blank images, missing strings) with no build error.

**Compose resources verification** — After iOS build, verify CMP resources exist at the expected path in the app bundle: `<App>.app/compose-resources/`. If the directory is missing or empty, re-run `pod install` and rebuild.

**SKIE build time** — First build after adding SKIE declarations is slow (2–5 min). Do not cancel. Subsequent incremental builds are fast. SKIE adds approximately 20–50% to the Kotlin/Native link step. This is expected and not a bug. CI pipelines should account for this in timeout budgets.

**SKIE version coupling** — SKIE 0.10.10 supports Kotlin 2.0.x through 2.x — check the SKIE GitHub releases page for exact version compatibility before upgrading. When upgrading Kotlin, check SKIE compatibility first at [touchlab.co/skie](https://touchlab.co/skie) or the GitHub releases page. An incompatible combination produces link-time failures that can be hard to diagnose. Pin the SKIE version explicitly — do not use version ranges or `+` wildcards.

**SourceKit trust dialog** — On first launch of a new simulator build, Xcode may show a trust dialog. User must accept before the app can run. Not a code bug.

**Framework linking** — If shared KMM framework is not linked in the iOS target's "Frameworks, Libraries" section, you get `dyld: Library not loaded`. Check Build Phases → Link Binary With Libraries.

**Kotlin/Native memory model** — All shared objects must be accessed from the main thread on iOS unless explicitly annotated. Crashes with `IncorrectDereferenceException` indicate off-thread access to frozen objects. Fix: ensure ViewModel collects flows on main dispatcher.

**SKIE StateFlow observation** — Use `.collect { }` or `ObservingTask` pattern (Section 4). Direct property access on `StateFlow` from Swift does not trigger updates.

**Nullable effects guard** — `SharedFlow<Effect?>` can and does emit `nil`. Without a guard, iterating over the flow will pass nil to handlers expecting a non-nil value, causing unexpected behavior or a runtime crash if force-unwrapped downstream. Always use `guard let effect = effect else { continue }`.

**UIApplication.shared.open(url) — Async context rules** — `UIApplication.shared.open(_:)` is async on iOS 16+. The rule depends on where the call lives:

```swift
// Inside .task {} — NEEDS await
.task {
    for await effect in viewModel.effect {
        guard let effect = effect else { continue }
        if case .openUrl(let e) = onEnum(of: effect) {
            await UIApplication.shared.open(e.url)  // required
        }
    }
}

// Inside synchronous closure (button action, sheet callback) — NO await
Button("Open") {
    UIApplication.shared.open(url)  // no await — sync context
}
```

Adding `await` in a sync context breaks compilation. Omitting it in an async context also breaks compilation. Match the call style to the surrounding context.

**import Combine must be preserved** — When removing old `KmmFlow` / `CombineWrapper` subscriptions during a SKIE migration, do not remove `import Combine` if the file still uses Combine elsewhere (e.g., `Publishers.keyboardHeight`, `.sink`, `.store(in:)`).

```swift
// Keep this even after removing KmmFlow subscriptions
import Combine  // still needed for Publishers.keyboardHeight

// If you remove it, keyboard handling silently stops working —
// no compile error because the keyboard publisher extension
// may be defined in another file
```

Check all usages of Combine in the file before removing the import.

**Nested dot notation for sealed subtypes** — Sealed class subtypes in Swift use nested dot notation, not flat names.

```swift
// CORRECT
viewModel.onEvent(event: LoginEvent.SubmitOtp(otp: pin))

// WRONG — does not compile
viewModel.onEvent(event: SubmitOtp(otp: pin))
```

The same applies to effect handling:

```swift
switch onEnum(of: effect) {
case .navigateToNext:   // Effect.NavigateToNext in Kotlin
    router.push(.next)
}
```

**Simulator vs device behavior** — Keychain, push notifications, and biometrics behave differently on simulator. If a feature fails only on device, check entitlements and provisioning.

### ComposeUIViewController Theme Wrapping
Every `ComposeUIViewController` factory function MUST wrap its content in `PunchTheme { ... }`. Unlike Android where the Activity's theme propagates, iOS ComposeUIViewControllers start with no theme context. Missing theme = wrong fonts + light mode colors.

### iOS Safe Area Insets
When the SwiftUI wrapper uses `.ignoresSafeArea(.all)`, CMP composables get the full screen. The root composable MUST apply:
- `Modifier.statusBarsPadding()` — prevents content behind the notch
- `Modifier.navigationBarsPadding()` — prevents buttons in the home indicator zone (touches are silently swallowed by iOS)
- Parent `Surface` color should match the app's background (e.g., `Background5`) so the status bar area isn't white

---

## 9. REQUIRES_APPROVAL Triggers

- Screen strategy differs from `migration-guide.md` assignment (CMP vs SwiftUI vs Hybrid)
- New iOS-only UI not present in Android (adds behavior not in scope)
- Navigation structure differs from Android (different flow)
- Koin scope change (singleton vs factory) for a shared class
- Any SKIE workaround that changes the Swift-visible API surface
