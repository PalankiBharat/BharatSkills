# Compose Patterns

**`remember` without `derivedStateOf` for derived state.**
Computing a value from other state inside a composable without `derivedStateOf` causes the composable to recompose on every state change, even when the derived value doesn't change.

> `val isVisible = items.isNotEmpty()` inside a composable → `val isVisible by remember { derivedStateOf { items.isNotEmpty() } }`

**Unnecessary recomposition.**
Passing unstable lambdas or new object instances as parameters to composables causes them to recompose on every parent recomposition. Fix options: wrap with `remember { }`, pass a method reference (`viewModel::onClick`), or move the lambda outside the composable. Flag when none of these are in place.

**Wrong side-effect API.**
- `LaunchedEffect` for one-time or key-driven async work.
- `DisposableEffect` for setup/teardown (listeners, subscriptions).
- `SideEffect` for non-composable system calls.
Using the wrong one or doing async work directly in the composition (no effect API) — flag.

**State hoisting violations.**
State owned inside a composable that needs to be shared with a parent or sibling — flag. State should be hoisted to the lowest common ancestor.

**`collectAsState()` without lifecycle awareness.**
In Fragments that use Compose, `.collectAsState()` doesn't stop collection in the background. Use `.collectAsStateWithLifecycle()` from `androidx.lifecycle:lifecycle-runtime-compose`.

**`LazyColumn`/`LazyRow` items without stable `key`.**
Items without a `key` parameter recompose by position — inserting or removing an item causes all subsequent items to recompose. Flag `items(list) { item -> ... }` without `key = { it.id }` (or equivalent stable identifier) when the list can change.
