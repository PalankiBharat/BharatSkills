# Compose screen rules

Loaded for files with `role=compose-screen` (Android).

Cite as `references/rules/compose-screen.md#<rule-id>`.

---

### CS-01 — Composable receives state, not ViewModel
**Severity:** P1
**Pattern:** screen-level `@Composable` function takes a `ViewModel` parameter directly and calls its methods inside the composable body.
**Why:** Coupling the composable to a specific ViewModel prevents preview and testability. Canonical: stateless composables that receive `state` and event lambdas.
**Suggestion:** Two functions: `MyScreen(viewModel)` (one-line wrapper that collects state and forwards) and `MyScreenContent(state, onAction)` (stateless, testable, previewable).
**Source:** https://developer.android.com/jetpack/compose/state

### CS-02 — Side effects use `LaunchedEffect`, `DisposableEffect`, `rememberCoroutineScope`
**Severity:** P1
**Pattern:** `@Composable` function calls `viewModel.startSomething()` or launches coroutines directly in the composable body (not in an effect).
**Why:** Composables can recompose at any time. Direct side effects run on every recomposition, causing bugs or work amplification.
**Suggestion:** `LaunchedEffect(key) { viewModel.startSomething() }` to run once per key change; `DisposableEffect` if cleanup needed.
**Source:** https://developer.android.com/jetpack/compose/side-effects

### CS-03 — State hoisted to ViewModel, not local `remember`
**Severity:** P2
**Pattern:** UI state that should survive process death stored in `remember { mutableStateOf(...) }`.
**Why:** `remember` survives recomposition but not config change or process death. Persistent state belongs in ViewModel.
**Suggestion:** Use ViewModel + `StateFlow`. For purely UI-transient state (e.g., scroll position), `rememberSaveable` is acceptable.
**Source:** https://developer.android.com/jetpack/compose/state-hoisting

### CS-04 — `collectAsStateWithLifecycle` (not `collectAsState`) for Flow → State
**Severity:** P2
**Pattern:** `viewModel.state.collectAsState()` in a screen.
**Why:** `collectAsState` collects regardless of lifecycle, wasting work when the screen isn't visible. `collectAsStateWithLifecycle` stops when STOPPED.
**Suggestion:** `viewModel.state.collectAsStateWithLifecycle()` (requires `androidx.lifecycle:lifecycle-runtime-compose` dependency).
**Source:** https://developer.android.com/jetpack/compose/lifecycle

### CS-05 — Modifier as parameter, defaulted to `Modifier`
**Severity:** P2
**Pattern:** composable function without a `modifier: Modifier = Modifier` parameter, or with the modifier parameter in a position other than first-after-required.
**Why:** Compose canonical guideline: every composable accepts a Modifier, defaulted, immediately after required parameters.
**Suggestion:** `@Composable fun MyComponent(text: String, modifier: Modifier = Modifier, ...)`.
**Source:** https://developer.android.com/jetpack/compose/api-guidelines (Modifier parameter)
