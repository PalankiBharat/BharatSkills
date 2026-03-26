# Android to SwiftUI Mapping Reference

Project-agnostic reference for KMM migration. Use this when writing SwiftUI screens from Android Compose or XML sources.

## Table of Contents

- [Fidelity Rules (NON-NEGOTIABLE)](#fidelity-rules-non-negotiable)
- [Standard Screen Template](#standard-screen-template)
- [Compose to SwiftUI Component Mapping](#compose-to-swiftui-component-mapping)
  - [Layout](#layout)
  - [Navigation](#navigation)
  - [Input](#input)
  - [Display](#display)
  - [Modifiers](#modifiers)
  - [State](#state)
  - [Other Components](#other-components)
  - [Dialogs and Sheets](#dialogs-and-sheets)
- [Fragment / XML to SwiftUI Mapping](#fragment--xml-to-swiftui-mapping)
  - [Layout Containers](#layout-containers)
  - [Widgets](#widgets)
  - [XML Attributes](#xml-attributes)
- [Effect Handling Pattern](#effect-handling-pattern)
- [Navigation Wiring Checklist](#navigation-wiring-checklist)
- [pbxproj Registration](#pbxproj-registration)

---

## Fidelity Rules (NON-NEGOTIABLE)

**Android is the source of truth. Match EVERYTHING.**

- Match layout structure exactly: if Android uses a list, use a list. If it uses a grid, use a grid. Do not substitute or "improve".
- Match spacing exactly: `16.dp` becomes `16` (points). `8.dp` becomes `8`. Do not round or normalize.
- Match selection indicators, dividers, typography hierarchy, and padding values exactly.
- Match variable and function names: if Android has `onSubmitClick`, Swift has `onSubmitClick`. If Android has `isLoading`, Swift has `isLoading`.
- Match state handling exactly: same error states, same loading states, same empty states.
- Match colors, font sizes, and text styles as closely as the platform allows.
- Only adapt platform idioms: use `NavigationStack` instead of `NavHost`, `@EnvironmentObject` instead of `hiltViewModel()`. These are the only permitted divergences.
- NEVER improve. NEVER add extra error handling. NEVER reorganize the layout. NEVER add convenience nil checks that aren't in Android.
- If the Android screen has a bug or looks bad, the SwiftUI screen should have the same bug and look bad in the same way. Flag it to the user — do not silently fix it.

---

## Standard Screen Template

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
- `init()` calls `PresenterProvider.shared.getMyViewModel()` — this is one common way to obtain a VM. **Note:** The VM acquisition pattern (`PresenterProvider.shared`) is one common approach. Your project may use Koin, manual injection, or a different provider. Adapt to match the project's existing DI conventions.
- First `.task` collects state. Second `.task` collects effects. Keep them separate.
- `guard let effect = effect else { continue }` — required pattern before switching on nullable effect flows.
- `switch onEnum(of:)` — always use SKIE's `onEnum` helper, never raw enum switch.

---

## Compose to SwiftUI Component Mapping

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

---

## Fragment / XML to SwiftUI Mapping

### Layout Containers

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

### Widgets

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

### XML Attributes

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

## Effect Handling Pattern

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

---

## Navigation Wiring Checklist

When adding a new screen that requires navigation, complete all four steps:

1. Add new `Destination` case to the `Router` enum:
   ```swift
   enum Destination: Hashable {
       case home
       case myNewScreen(id: String)  // add here
   }
   ```

2. Add `.navigationDestination(for:)` in `RootView`:
   ```swift
   .navigationDestination(for: Router.Destination.self) { destination in
       switch destination {
       case .home: HomeScreen()
       case .myNewScreen(let id): MyNewScreen(id: id)
       }
   }
   ```

3. Map KMM `Route` to `Router.Destination` in the route callback (wherever routes are resolved):
   ```swift
   switch onEnum(of: route) {
   case .myNewScreen(let r): return .myNewScreen(id: r.id)
   }
   ```

4. Wire effects that trigger navigation in the screen's effect observer `.task`:
   ```swift
   case .openMyNewScreen(let e):
       router.navigate(to: .myNewScreen(id: e.id))
   ```

Missing any step causes silent failures: the destination exists but is never reachable, or is reachable but renders nothing.

---

## pbxproj Registration

Every new `.swift` file MUST be manually registered in `project.pbxproj`. Xcode does this automatically when you use the GUI, but since files are created via code or terminal, they are not registered automatically.

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
