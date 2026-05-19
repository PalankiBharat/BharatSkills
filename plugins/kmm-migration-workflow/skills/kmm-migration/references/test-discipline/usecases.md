> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 2. UseCases

> Path: `app/src/main/java/.../usecases/**` and `.../library/domain/usecases/**`
> Stack: **KMM-portable** by default. UseCases are pure domain logic
> and the most likely migration target — `commonMain` is their
> natural home.

### Responsibility

Encapsulate **one** business operation. Single public method —
typically `suspend fun perform(request): Response` or `fun observe():
Flow<…>`. The most pure-logic layer in the app, and therefore the
layer where bugs cost the most. Test exhaustively.

### When to skip the baseline

- **Pure interface** (`interface XUseCase { suspend fun invoke(...): ... }` with no default impls) → **skip**. Coverage transitive through the `*Impl` baseline.
- **Pure-factory UseCase impl** (the impl just constructs and returns a domain object; private-val collaborators are not directly assertable; no branching, no side effects) → **skip**. Coverage transitive through the returned object's baseline.
- Impls with branching, suspend/Flow coordination, or side effects always get a baseline.

### What to fake

- ✅ Every collaborating repository / store / SDK boundary — hand-rolled fake implementing the interface.
- ✅ Other use cases this one composes.
- ✅ Time, randomness, IDs — fake `Clock`, fake `IdProvider`, etc.
- ❌ Pure data classes the use case constructs.
- ❌ The use case itself.
- ❌ The use case's input or output models — build real instances with test fixtures.
- ❌ **No MockK** in baseline source sets. Mocking libraries are banned (per `index.md` Toolbox); write a fake.

### Coverage checklist

**Happy path**
- [ ] Each input shape that affects branching has a test.
- [ ] Output values verified at the field level (no `assertNotNull`-only assertions).

**Sad path**
- [ ] Each thrown exception type the use case wraps or maps.
- [ ] `Result.failure` propagation when collaborators fail.
- [ ] Empty / null upstream data.

**Branching logic**
- [ ] Every `if`, `when`, `?:`, `let`/`run`, early-`return` branch hit by at least one test. Eyeball the function before writing tests and number the branches — every branch needs a row.

**Concurrency / ordering** (Constitution III, XIII)
- [ ] If the use case launches concurrent work, prove that the observable result is correct under both orderings.
- [ ] If it uses `flow { … }` / `mapLatest` / `combine`/`zip`, write a test that emits out of order and assert latest-wins behavior.

**Boundary values**
- [ ] Money / quantity: `0`, `1`, max-allowed, max+1, negative.
- [ ] Strings: empty, blank (whitespace), unicode, very long.
- [ ] Collections: empty, single-element, duplicates.

**Domain-specific (example: trading)**
- [ ] Order placement: ProductType MIS vs CNC vs NRML behaves correctly when the same ISIN exists in multiple positions.
- [ ] Market hours: market-closed branch covered.
- [ ] Currency formatting: `Locale.US` always — no comma decimals on regional locales.

**Regression prevention** (Constitution X)
- [ ] When fixing a bug: a failing test that reproduces it must come **before** the fix and be reverted-and-rerun once to prove it goes red on the original code path.

### Naming

Group with `// region <area>` blocks when a use case has many cases. Sentence-form names describing the *condition* and the *expected outcome*:

```kotlin
` `Initialize shows trade button when scalper mode is OFF and chart is tradeable` `
` `perform returns failure when balance use case throws` `
` `equity protection order with NRML productType binds to sole MIS position by isin` `
```

### Template

```kotlin
// Fakes co-located with the test (or in a fakes/ package if shared).
class FakePositionRepository : IPositionRepository {
    var positionsToReturn: List<Position> = emptyList()
    var nextException: Throwable? = null
    val getAllCalls = mutableListOf<Unit>()

    override suspend fun getAll(): List<Position> {
        getAllCalls += Unit
        nextException?.let { throw it }
        return positionsToReturn
    }
}

class FakeProtectionOrderRepository : IProtectionOrderRepository {
    var ordersToReturn: List<ProtectionOrder> = emptyList()
    override suspend fun getAll(): List<ProtectionOrder> = ordersToReturn
}

@OptIn(ExperimentalCoroutinesApi::class)
class GetPositionsUseCaseImplTest {

    private val testDispatcher = StandardTestDispatcher()

    private val positionRepo = FakePositionRepository()
    private val protectionRepo = FakeProtectionOrderRepository()

    private lateinit var sut: GetPositionsUseCaseImpl

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        sut = GetPositionsUseCaseImpl(positionRepo, protectionRepo)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // region happy paths
    @Test
    fun `perform returns positions with attached protection orders`() = runTest {
        // Given
        positionRepo.positionsToReturn = listOf(mis("HDFCBANK"))
        protectionRepo.ordersToReturn = listOf(protection("HDFCBANK", NRML))

        // When
        val out = sut.perform()

        // Then
        assertEquals(1, out.size)
        assertNotNull(out.single().protectionOrder)
    }
    // endregion

    // region edge: ISIN merge collision (regression for #358)
    @Test
    fun `MIS and CNC positions with same ISIN bind to their respective product type`() = runTest {
        positionRepo.positionsToReturn = listOf(mis("HDFCBANK"), cnc("HDFCBANK"))
        protectionRepo.ordersToReturn = listOf(protection("HDFCBANK", MIS))

        val out = sut.perform()

        assertNotNull(out.single { it.productType == MIS }.protectionOrder)
        assertNull(out.single { it.productType == CNC }.protectionOrder)
    }
    // endregion

    // region sad
    @Test
    fun `perform propagates repository failure`() = runTest {
        positionRepo.nextException = IOException("boom")
        assertFailsWith<IOException> { sut.perform() }
    }
    // endregion
}
```

### Anti-patterns

- Smoke tests that only call `perform()` and assert it returned. Prove nothing.
- Test bodies setting up 8 fakes when the use case only uses 2 — delete the unused fakes; they hide design smell.
- Sharing mutable setup state across tests — each `@Test` should configure its fakes independently in `// Given`.
- Skipping the bug-reproducer test "because the fix is obvious."
- **Using MockK** (`mockk<T>()`, `every { }`, `coEvery { }`) — banned in baseline source sets; write a fake. See `index.md` Toolbox + "Fakes vs mocks — when?".

---

