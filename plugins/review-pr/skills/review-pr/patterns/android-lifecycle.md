# Android Lifecycle Patterns

**Context leaks.**
Holding a reference to an `Activity`, `Fragment`, or `View` context in a long-lived object (ViewModel, singleton, companion object, static field) — flag as blocker. Use `ApplicationContext` for long-lived needs, or weak references if unavoidable.

**Activity reference in ViewModel.**
ViewModel outlives the Activity it was created for. Any direct reference to an Activity or its views inside a ViewModel — flag as memory leak risk.

**Wrong coroutine scope.**
- In ViewModel: use `viewModelScope` (cancelled when ViewModel is cleared).
- In Fragment/Activity: use `viewLifecycleOwner.lifecycleScope` (not `lifecycleScope` alone, which survives view destruction).
- `GlobalScope` anywhere — flag as leak.

**StateFlow collected without lifecycle awareness.**
Collecting a `StateFlow` or `SharedFlow` with plain `.collect {}` in any view-bound context (Fragment, Activity, or Composable hosted in a Fragment) without `repeatOnLifecycle` or `collectAsStateWithLifecycle` — the collector runs even when the view is in the background, wasting resources and potentially processing stale events.

**Listener registered without matching unregister.**
`registerReceiver`, `addObserver`, location listener, sensor listener registered in `onStart`/`onResume`/`onViewCreated` without a matching unregister in `onStop`/`onPause`/`onDestroyView` — flag as leak.
