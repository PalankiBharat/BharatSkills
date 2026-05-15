# Concurrency Patterns

**`GlobalScope.launch` is a leak.**
`GlobalScope` creates coroutines that outlive the component that launched them. Use `viewModelScope` in ViewModels, `lifecycleScope` in Activities/Fragments, or a custom scope with a defined lifetime.

**Shared mutable state without synchronisation.**
A mutable variable (`var`, `MutableList`, non-thread-safe collection) accessed from multiple coroutines without a `Mutex`, `StateFlow`, or `@GuardedBy` annotation — flag as potential race condition.

**Don't catch `CancellationException`.**
Catching `CancellationException` (or its parent `Exception` without rethrowing it) breaks cooperative cancellation. Either catch only non-cancellation exceptions or rethrow `CancellationException` immediately.

> Kotlin: `catch (e: Exception) { log(e) }` inside a coroutine without `if (e is CancellationException) throw e` → flag.
> Anti-trigger: `finally` blocks that perform cleanup (close resources, log, cancel child jobs) are correct and should not be flagged.

**Blocking calls on the main thread.**
`runBlocking`, `Thread.sleep`, or synchronous I/O inside a suspend function called from `Dispatchers.Main` — flag.

**Missing `withContext(Dispatchers.IO)` for I/O work.**
File reads, database queries, or network calls done without switching to `Dispatchers.IO` inside a coroutine — flag.

**Cold Flow exposed without `stateIn`/`shareIn` causes redundant work.**
A cold `Flow` returned from a repository and collected by multiple subscribers re-runs its producer for each collector. If the same data is collected by 2+ observers, convert to `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), initialValue)` to share a single upstream subscription.
