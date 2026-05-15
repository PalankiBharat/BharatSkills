# Error Handling Patterns

**Don't conflate cancellation with failure.**
Cancellation is a control-flow signal, not an error. Catching it in an error handler silently suppresses the cancellation and breaks structured concurrency. This applies to coroutines, async/await, futures, RxJava.

> Kotlin: `FirebaseFirestoreException.Code.CANCELLED` caught inside a network-failure handler → remove it; let cancellation propagate.

**Narrow catches should match what they claim.**
If a function is named `isNetworkFailure` or `isTransientError`, every code it returns `true` for must actually be a network/transient failure.

**Prefer exhaustive pattern matching over chained conditionals.**
Chained `||` comparisons hide the set of valid cases. A `when`/`switch`/`match` expression makes the set explicit.

> Kotlin: `code == A || code == B || code == C` → `when (code) { A, B, C -> true; else -> false }`

**`when`/`switch` with `else` is not exhaustive — check the `else` branch.**
`else -> false` silently absorbs any future enum variant. After confirming `when` is used, check whether `else` is present and flag it if the author claims compile-time safety or the set of valid cases may grow.

> Kotlin: `when (code) { A, B -> true; else -> false }` — a new `Code` variant silently returns `false`. Fix: enumerate all known variants and drop `else`.
