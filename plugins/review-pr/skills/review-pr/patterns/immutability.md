# Immutability Patterns

**Unnecessary `var`.**
A `var` that is only assigned once (at declaration) should be `val`. Flag `var` declarations that are never reassigned after initialisation.
Anti-trigger: `var state by mutableStateOf(...)` (Compose state delegation requires `var`), `lateinit var` (intentional deferred initialisation), and `var` inside builders/DSLs are all acceptable.

**Mutable state exposed from public API.**
`MutableList`, `MutableStateFlow`, `MutableLiveData` returned from a public function or exposed as a public property — flag. Expose the read-only type (`List`, `StateFlow`, `LiveData`) and keep mutation private.

**Mutable collections returned where immutable suffice.**
`fun getItems(): MutableList<Item>` — flag if callers don't need to mutate the returned collection. Return `List<Item>`.

**Shared mutable state without justification.**
A `var` or mutable collection shared across coroutines, threads, or components without a documented reason — flag and suggest an immutable + event-driven approach.
