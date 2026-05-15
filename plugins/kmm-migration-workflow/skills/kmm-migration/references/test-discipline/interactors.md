> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 8. Interactors

> Path: `app/src/main/java/.../features/**/*Interactor.kt`
> Stack: **KMM-portable** when the interactor is pure coordination
> over use cases. If it holds android-framework references, treat
> as JVM-only and refactor toward portability.

### Responsibility

Stateful coordinator scoped to a feature surface (one chart, one
preset selector). Holds short-lived state, owns a `CoroutineScope`,
listens via a `Listener` interface, calls multiple use cases. Sits
between ViewModel and use cases when the ViewModel would otherwise
be too fat.

### What to fake

- ✅ Every injected use case — hand-rolled fake implementing the use-case interface.
- ✅ The listener — fake that records callbacks in a `MutableList` (see `FakeOrderInteractorListener` in Template). Assertion target = the recorded list.
- ✅ Time, randomness — fake `Clock`, fake `IdProvider`.
- ❌ Don't fake the `CoroutineScope` — pass a `TestScope` or rely on `Dispatchers.setMain`.
- ❌ **No MockK** in baseline source sets. The recorded-callbacks pattern on a fake listener replaces `slot<T>()` capture from MockK — and survives the `commonTest` move with zero edits.

### Coverage checklist

**Listener wiring**
- [ ] Each event the interactor produces fires the listener with expected payload exactly once.
- [ ] Listener held via weak reference (if that's the project convention): assert that calling a method after the strong ref is gone doesn't crash. **Note:** weak references are JVM-only — for KMM-bound interactors, prefer an explicit `unsubscribe()` contract instead.

**State transitions**
- [ ] Each state transition (lot count, product type swap, transaction type flip) updates internal state and fires the matching listener callback.

**Concurrency** (Constitution XIII)
- [ ] Two rapid intent calls (`setLot(2)` immediately followed by `setLot(3)`) emit only the latest computation (`mapLatest` semantics).
- [ ] In-flight margin compute is cancelled when the chart context changes.

**Lifecycle**
- [ ] `onCleared()` cancels the scope and stops emitting.
- [ ] Calling a method after `onCleared` is a no-op (or throws — assert whichever the spec says).

### Template

```kotlin
class FakeGetEstimatedMarginUseCase : IGetEstimatedMarginUseCase {
    var nextResult: Result<Margin> = Result.success(Margin(0.0))
    var artificialDelayMs: Long = 0
    val performCalls = mutableListOf<MarginRequest>()

    override suspend fun perform(request: MarginRequest): Result<Margin> {
        performCalls += request
        if (artificialDelayMs > 0) delay(artificialDelayMs)
        return nextResult
    }
}

class FakePlaceOrderUseCase : IPlaceOrderUseCase {
    var nextResult: Result<OrderId> = Result.success(OrderId("o1"))
    val performCalls = mutableListOf<PlaceOrderArgs>()
    override suspend fun perform(args: PlaceOrderArgs): Result<OrderId> {
        performCalls += args
        return nextResult
    }
}

// FakeListener records every callback; assertion on the recorded list
// replaces verify { listener.onMarginUpdated(...) }.
class FakeOrderInteractorListener : OrderInteractorListener {
    data class MarginUpdate(val state: MarginState, val display: String)
    val marginUpdates = mutableListOf<MarginUpdate>()
    override fun onMarginUpdated(state: MarginState, display: String) {
        marginUpdates += MarginUpdate(state, display)
    }
    // ... other callbacks similarly recorded.
}

class FakeChart(override val scrip: Scrip) : Chart { /* … */ }

@OptIn(ExperimentalCoroutinesApi::class)
class OrderInteractorTest {

    private val testDispatcher = StandardTestDispatcher()

    private val marginUseCase = FakeGetEstimatedMarginUseCase()
    private val placeOrderUseCase = FakePlaceOrderUseCase()
    private val listener = FakeOrderInteractorListener()
    private val chart = FakeChart(SCRIP_NIFTY)

    private lateinit var sut: OrderInteractor

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        sut = OrderInteractor(
            chart = chart,
            listener = listener, // for KMM, drop WeakReference; use explicit unsubscribe()
            getEstimatedMarginUseCase = marginUseCase,
            placeOrderUseCase = placeOrderUseCase,
            /* … */
        )
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `setLot fires margin update with computed amount`() = runTest {
        marginUseCase.nextResult = Result.success(Margin(750.0))

        sut.setLot(2)
        advanceUntilIdle()

        assertEquals(
            FakeOrderInteractorListener.MarginUpdate(MarginState.Available, "₹750"),
            listener.marginUpdates.single()
        )
    }

    @Test
    fun `rapid setLot calls only emit latest`() = runTest {
        marginUseCase.nextResult = Result.success(Margin(750.0))
        marginUseCase.artificialDelayMs = 500

        sut.setLot(1)
        advanceTimeBy(100)
        sut.setLot(3)
        advanceUntilIdle()

        // mapLatest semantics: only the latest setLot produced an update.
        assertEquals(1, listener.marginUpdates.size)
    }

    @Test
    fun `setLot after onCleared is a no-op`() = runTest {
        sut.onCleared()
        sut.setLot(2)
        advanceUntilIdle()

        assertTrue(listener.marginUpdates.isEmpty())
        assertEquals(0, marginUseCase.performCalls.size)
    }
}
```

### Anti-patterns

- Asserting without `advanceUntilIdle()` — passes on `UnconfinedTestDispatcher`, fails on `StandardTestDispatcher`. Always advance.
- Holding a strong reference to the listener "for convenience" — defeats the unsubscribe contract.
- Using `WeakReference` for a KMM-bound interactor — JVM-only.
- **Using MockK** (`mockk<T>()`, `every { }`, `coEvery { }`, `verify { }`, `coVerify { }`) — banned in baseline source sets. Write fakes that record callbacks (see `FakeOrderInteractorListener` above). Recorded-list assertions replace verify calls.

---

