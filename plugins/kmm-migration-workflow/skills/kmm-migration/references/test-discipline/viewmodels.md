> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 1. ViewModels

> Path: `app/src/main/java/.../viewmodels/**`
> Stack: **KMM-portable** by default. `androidx.lifecycle.ViewModel`
> is KMP-compatible — VM tests *can* move to `commonTest` if written
> with the portable stack.

### Responsibility

Hold and emit UI state. Translate user intents (`onAction(...)`) into
use-case calls. Own a `viewModelScope`, emit `StateFlow` /
`SharedFlow`. **Must not** contain business logic or Android framework
references — that's a Constitution-II violation, flag it.

### KMM-portability gotchas

- `androidx.lifecycle.ViewModel` itself is KMP-compatible (artifact:
  `androidx.lifecycle:lifecycle-viewmodel`). Tests of VMs that only
  use the base class are portable.
- `SavedStateHandle` is **androidx-only**. If the VM uses it and is
  going to `:shared`, abstract behind an interface
  (e.g., `interface StateStore { fun <T> get(key: String): T?; fun <T> set(key: String, value: T) }`)
  and provide an Android-side adapter. Tests then mock the interface.
- iOS-side `viewModelScope` lifecycle is **not** tied to a back stack
  the way Android's is — confirm the iOS host explicitly calls
  `onCleared()` / lets the scope cancel. Tests must cover the
  `onCleared` contract rigorously.
- For Swift consumption, `StateFlow` is exposed via SKIE; tests live
  in `commonTest` and don't see SKIE — assert on the `StateFlow`
  directly.

### What to fake

- ✅ Every `IUseCase`, `IRepository`, `IGet*` collaborator → hand-rolled fake (class implementing the interface, stubbed returns in `var`s, recorded calls in `MutableList`s).
- ✅ Time source (`kotlinx.datetime.Clock`) → fake with a fixed instant (or an interface seam if the project doesn't already inject `Clock`).
- ✅ `SavedStateHandle` abstraction → fake of the project's `StateStore`-style interface.
- ❌ Never fake the ViewModel itself, its emitted `StateFlow`s, or Kotlin data classes the ViewModel constructs.
- ❌ Don't fake `viewModelScope` — let `Dispatchers.setMain(testDispatcher)` do the swap.
- ❌ **No MockK in baseline source sets** (per `index.md` Toolbox and detekt enforcement). Even though MockK technically supports K/MP, baselines that use it can't survive the `androidUnitTest` → `commonTest` move without gradle wiring tweaks — violates the freeze contract.

### Coverage checklist

**State emission**
- [ ] Initial state on construction (no `onLaunch()` yet).
- [ ] Loading → success transition (state values asserted at each step).
- [ ] Loading → error transition (error mapped to user-friendly state, not raw exception leaked — Constitution VII).
- [ ] State is conflated correctly when underlying flow emits faster than UI consumes (use Turbine + `expectMostRecentItem()`).

**Intent / action handling**
- [ ] Each `Action`/`Intent` subclass has a happy-path test.
- [ ] Each `Action` has a failure-path test (use case throws / returns `Result.failure`).
- [ ] Concurrent actions: when action B arrives while A's job is in flight, the right one wins (typically `mapLatest` semantics — Constitution III).

**Lifecycle**
- [ ] `onCleared` cancels in-flight jobs and unsubscribes downstream collectors.
- [ ] If the ViewModel re-subscribes on resume, the subscription count does **not** double on rotation.

**Inputs**
- [ ] Null / empty / boundary values for any user-controllable input.
- [ ] Negative / zero where domain allows them (a quantity of `0` must not place an order).
- [ ] Values that exceed the domain's max (quantity > available lot size).

**Edge cases (trading-specific — adapt to your domain)**
- [ ] Market closed / market open transitions if the ViewModel cares.
- [ ] Stale LTP (last tick > N seconds old) does not produce a confident computation.
- [ ] Session-expired error surfaces as a re-login intent, not a blank screen.

### Template

```kotlin
// FakeGetPositionsUseCase.kt — co-located with the test (or in fakes/ if shared)
class FakeGetPositionsUseCase : IGetPositionsUseCase {
    // Stubbed flow — control emissions from the test with `.emit(...)`.
    val positionsFlow = MutableSharedFlow<List<Position>>(replay = 1)
    override fun observe(): Flow<List<Position>> = positionsFlow
}

class FakeExitPositionUseCase : IExitPositionUseCase {
    // Stubbed return (one per next-call pattern).
    var nextResult: Result<Unit> = Result.success(Unit)
    // Optional artificial latency (use the test dispatcher's delay).
    var artificialDelayMs: Long = 0
    // Recorded calls — assert size and arguments.
    val performCalls = mutableListOf<String>()

    override suspend fun perform(positionId: String): Result<Unit> {
        performCalls += positionId
        if (artificialDelayMs > 0) delay(artificialDelayMs)
        return nextResult
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PositionViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private val getPositionsUseCase = FakeGetPositionsUseCase()
    private val exitPositionUseCase = FakeExitPositionUseCase()

    private lateinit var sut: PositionViewModel

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        sut = PositionViewModel(getPositionsUseCase, exitPositionUseCase)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `initial state is Loading`() = runTest {
        assertEquals(PositionUiState.Loading, sut.state.value)
    }

    @Test
    fun `positions in profit emit green PnL color`() = runTest {
        // Given: stub the upstream flow before launch
        getPositionsUseCase.positionsFlow.emit(listOf(positionInProfit()))

        // When
        sut.onLaunch()
        advanceUntilIdle()

        // Then
        sut.state.test {
            val s = expectMostRecentItem() as PositionUiState.Loaded
            assertEquals(PnlColor.GREEN, s.pnlColor)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `Exit action while previous Exit is in flight does not double-fire`() = runTest {
        // Given: first Exit takes 1s; second arrives 100ms in
        exitPositionUseCase.artificialDelayMs = 1_000

        // When
        sut.onAction(PositionAction.Exit("p1"))
        advanceTimeBy(100)
        sut.onAction(PositionAction.Exit("p1"))
        advanceUntilIdle()

        // Then: only one perform() call should have landed
        assertEquals(1, exitPositionUseCase.performCalls.size)
        assertEquals("p1", exitPositionUseCase.performCalls.single())
    }
}
```

### Anti-patterns

- Asserting on `_state.value` (private). Use the public `StateFlow`.
- `runBlocking` inside the test body — always `runTest`.
- Using `Thread.sleep` to wait for emissions — use Turbine.
- Constructing the ViewModel with real network/DB collaborators — that's an integration test, move it to `androidTest/`.
- Faking `StateFlow` itself — construct a real `MutableStateFlow` (or `MutableSharedFlow`) in the test instead.
- Using `MainCoroutineRule` for a VM that's headed to `:shared` — won't move to `commonTest`.
- **Using MockK / `mockk<T>()` for any dep** — banned in baseline source sets. Write a fake.
- **Using `coVerify { ... }` / `verify { ... }`** — fakes record calls; assert on the recorded list (`fake.fooCalls.size`, `fake.fooCalls.single()`, etc.) instead.

---

