# Performance Patterns

**N+1 query pattern.**
A loop that makes a database or network call per iteration — flag. Batch the call outside the loop or use a bulk query.

**Eager load opportunity in ViewModel.init.**
If a ViewModel *unconditionally* needs a piece of data on every screen visit, fetching it in `init {}` starts loading before the first frame. If data loading is triggered by a UI event (`fun onScreenVisible()`), flag as a missed eager-load opportunity — move to `init {}` with constructor-injected parameters.

> This project injects parameters directly via constructor (not SavedStateHandle).
> Anti-trigger: Do NOT flag if loading depends on user state, requires a runtime parameter unavailable at construction, or if the screen may not always need the data (lazy-load pattern is correct).

**Unnecessary object allocation in hot paths.**
Creating new lists, maps, or objects inside `onDraw`, `onMeasure`, per-frame callbacks, or `RecyclerView.onBindViewHolder` — flag.

**Inefficient data structure choice.**
Using `List` for membership checks (`contains`) that run frequently — suggest `Set` for O(1) lookup. Using `Map` when a `List` indexed by position would suffice.

**Memory leaks.**
Holding a reference to a `Context`, `Activity`, or `View` in a long-lived object (ViewModel, singleton, static field) — flag.
