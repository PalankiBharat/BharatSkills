# ViewModel rules

Loaded for files with `role=viewmodel`. Covers shared ViewModels (in commonMain extending `androidx.lifecycle.ViewModel`) and platform Android ViewModels.

Cite as `references/rules/viewmodel.md#<rule-id>`.

---

### VM-01 — Shared ViewModel extends `androidx.lifecycle.ViewModel`
**Severity:** P1
**Pattern:** new ViewModel in commonMain that extends a custom base class or doesn't extend `ViewModel` at all.
**Why:** `androidx.lifecycle.ViewModel` has been KMP-compatible since lifecycle 2.8. It provides `viewModelScope` that works across platforms and integrates with Android lifecycle.
**Suggestion:** `class MyViewModel(...) : ViewModel() { ... }` with `import androidx.lifecycle.ViewModel`.
**Source:** https://developer.android.com/topic/libraries/architecture/viewmodel + team convention.

### VM-02 — State exposed as `StateFlow`, events as `SharedFlow`/`Channel`
**Severity:** P1
**Pattern:** ViewModel exposes mutable state directly (`var state: State`) or uses non-Flow types for observable state.
**Why:** `StateFlow` is the canonical KMP pattern for observable state, and SKIE bridges it cleanly to iOS as AsyncSequence.
**Suggestion:** `private val _state = MutableStateFlow(InitialState); val state: StateFlow<MyState> = _state.asStateFlow()`.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-upgrade-app.html + https://skie.touchlab.co/features/flows

### VM-03 — Mutable Flow stored as `private val _state`, immutable `state` exposed
**Severity:** P2
**Pattern:** ViewModel exposes `MutableStateFlow` directly.
**Why:** Consumers shouldn't be able to mutate ViewModel state from outside.
**Suggestion:** `private val _state = MutableStateFlow(...); val state: StateFlow<...> = _state.asStateFlow()`.
**Source:** https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.flow/-state-flow/

### VM-04 — Long-running work uses `viewModelScope`, not free-standing `CoroutineScope`
**Severity:** P1
**Pattern:** ViewModel launches coroutines via `CoroutineScope(...).launch` or `GlobalScope.launch` instead of `viewModelScope.launch`.
**Why:** `viewModelScope` is cancelled when the ViewModel is cleared. Free-standing scopes leak.
**Suggestion:** `viewModelScope.launch { ... }`.
**Source:** https://developer.android.com/topic/libraries/architecture/coroutines

### VM-05 — Dispatcher injected, not hardcoded
**Severity:** P1
**Pattern:** ViewModel directly references `Dispatchers.IO`/`Default`/`Main` in `launch(...)` or `withContext(...)` calls instead of receiving via constructor.
**Why:** Same as `_base.md#s-coro-01`.
**Source:** `_base.md#s-coro-01`

### VM-06 — No platform types in shared ViewModel
**Severity:** P0
**Pattern:** ViewModel in commonMain imports Android `Context`, `Resources`, `Activity`, or other Android-specific types.
**Why:** Same as `_base.md#s-type-01`.
**Suggestion:** Inject an abstraction (e.g., `ResourceProvider` interface) and provide platform implementations.
**Source:** `_base.md#s-type-01`

### VM-07 — UI events delivered via one-shot `Channel`/`SharedFlow`, not `StateFlow`
**Severity:** P2
**Pattern:** ViewModel uses `StateFlow` for transient UI events (navigation, snackbar, dialog show).
**Why:** `StateFlow` replays the last value to new collectors — a snackbar message would re-show on screen rotation. One-shot events need `Channel` or `SharedFlow(replay=0)`.
**Suggestion:** `private val _events = Channel<MyEvent>(Channel.BUFFERED); val events: Flow<MyEvent> = _events.receiveAsFlow()`.
**Source:** https://kotlinlang.org/docs/channels.html
