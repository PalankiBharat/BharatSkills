---
paths:
  # Compose Multiplatform source sets (primary)
  - "**/src/commonMain/kotlin/**/*.kt"
  - "**/src/androidMain/kotlin/**/*.kt"
  - "**/src/iosMain/kotlin/**/*.kt"
  - "**/src/desktopMain/kotlin/**/*.kt"
  - "**/src/jvmMain/kotlin/**/*.kt"
  - "**/src/wasmJsMain/kotlin/**/*.kt"
  # Android-only projects
  - "app/src/main/java/**/*.kt"
  - "app/src/main/kotlin/**/*.kt"
---

# Jetpack Compose Rules

## Contents
- State hoisting is non-negotiable
- Recomposition hygiene
- No side effects in composition
- Inline lambdas
- Modifier discipline
- Previews are documentation
- Composable naming
- What NOT to do

These rules apply when editing files that contain `@Composable` functions.
Generic clean-code rules (naming, SRP, function length, comments) come from
the clean-code skill and are not duplicated here.

## State hoisting is non-negotiable

- UI state that drives business decisions or must survive recomposition
  belongs in the ViewModel, not inside a Composable.
- Composables receive immutable state (`State<T>`, data classes) and emit
  events (lambdas). They do not fetch, mutate, or persist state themselves.
- `remember { mutableStateOf(...) }` is only for **UI-local ephemeral**
  state: text field focus, scroll position, expand/collapse toggles that
  don't matter across navigation. If it matters to the feature, hoist it.
- Use `rememberSaveable` for UI-local state that must survive
  process death (dialog open-state on a long form, etc.).

## Recomposition hygiene

- Data classes passed into Composables must be `@Immutable` or `@Stable`.
  An unstable parameter forces the whole subtree to recompose on every
  parent state change.
- Do not create new lambdas inline for `onClick` inside `LazyColumn`
  item scopes unless you've confirmed Compose's stability inference
  handles your key. Prefer `remember(key) { { ... } }` or hoisted
  lambdas.
- Use `derivedStateOf` for computed state that depends on other state
  but changes less often than its inputs (e.g., `derivedStateOf { list.firstOrNull { it.isSelected } }`).
- Every `remember` with captured values must declare those values as
  keys: `remember(userId) { ... }`. Missing keys = stale state bug.

## No side effects in composition

- Network, database, analytics, navigation must not run during
  composition. Put them in `LaunchedEffect`, `DisposableEffect`, or
  call them from the ViewModel.
- `LaunchedEffect` keys must match the actual dependencies. A key of
  `Unit` or `true` is a smell — justify it or fix it.

## Inline lambdas

- If an `onClick = { ... }` or similar lambda exceeds ~5 lines or
  contains branching logic, extract it to a named top-level lambda
  (`val onPlaceOrder: () -> Unit = { ... }`) or a ViewModel method.
- Composables should read top-to-bottom like prose, not pyramid
  sideways into nested lambdas.

## Modifier discipline

- No magic `dp` values scattered in modifier chains. Define named
  constants (`OrderCardPadding = 12.dp`, `SectionGap = 16.dp`) in a
  per-feature `Dimensions.kt` or in the theme.
- Modifier chains stay readable: break long chains onto multiple lines,
  one modifier per line.
- `Modifier` parameter must be the first optional parameter of every
  Composable, defaulted to `Modifier`. Never accept a modifier and not
  apply it, and never apply a modifier internally that the caller
  cannot override.

## Previews are documentation

- Every non-trivial Composable (anything that renders a screen, a card,
  or a reusable component) must have at least one `@Preview`.
- Cover meaningful states: light/dark, loading, empty, error, long-text,
  small-screen. One preview per state, not one mega-preview with
  everything stacked.
- Previews must compile without the real ViewModel — use fake state
  objects. If a Composable can't be previewed without the real VM, it's
  doing too much.

## Composable naming

- PascalCase, noun phrases: `OrderCard`, not `renderOrderCard` or
  `orderCardView`.
- Composables that return a value (rare) are camelCase verb phrases:
  `rememberOrderFormState()`.

## What NOT to do

- No `ViewModel` references inside reusable Composables. Pass state +
  events. Top-level screen Composables are the only place that reads a
  ViewModel directly.
- No `LocalContext.current` to do work. If you need Context for
  non-display reasons (e.g., sharing, intent), hoist to the ViewModel
  via `AndroidViewModel` or an injected wrapper.
- No `Thread.sleep`, `runBlocking`, or blocking calls inside a
  Composable or `LaunchedEffect`.
- Never suppress recomposition warnings from the Compose compiler
  without a written reason.
