> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 3. Repositories

> Path: `app/src/main/java/.../repository/**`
> Stack: **KMM-portable**. Repositories are coordination logic and
> head to `:shared` along with the domain layer.
> Pattern: `*RepositoryImpl(remote: *RemoteStore, local: *LocalStore)` — typically with stale-while-revalidate semantics (Constitution III).

### Responsibility

Coordinate one or more `RemoteStore`s and `LocalStore`s. Decide
whether to serve cache, refresh in background, fall through to
network, or fail. The most-violated layer for concurrency bugs —
test as if the trading floor depends on it, because it does.

### When to skip the baseline

- **Pure interface** (`interface XRepository { ... }` with no default impls, no `companion object` logic) → **skip**. Coverage is transitive through the `*Impl` baseline or the feature surface (Phase B.6). Audit row flips `relocated` → `audited` directly; no test file written.
- Implementation classes (`*RepositoryImpl`) always get a baseline.

### What to fake

- ✅ `RemoteStore` collaborators — hand-rolled fake (their HTTP layer is tested separately at the RemoteStore level).
- ✅ `LocalStore` collaborators — hand-rolled fake (their persistence layer is tested separately at the LocalStore level).
- ✅ Logger, time source (`kotlinx.datetime.Clock`) — fakes.
- ❌ Don't use a real `BoxStore` / SQLDelight driver here — that's a `LocalStore` test.
- ❌ Don't use a real Ktor client — that's a `RemoteStore` test.
- ❌ **No MockK** in baseline source sets. Write fakes (see Template).

### Coverage checklist

**Cache semantics (mandatory — every repo with a cache)**
- [ ] Cold read: cache empty → network call → cache write → return.
- [ ] Warm read: cache present and fresh → returns cache, **does not** hit network.
- [ ] Warm-but-stale: returns cache *immediately*, refreshes in background, second emission is the fresh value.
- [ ] Network failure with warm cache: returns cached value with no user-visible error.
- [ ] Network failure with empty cache: returns failure / error state.
- [ ] Cache invalidation on write (POST/PUT/DELETE) — second read goes to network.

**Concurrency**
- [ ] Two concurrent readers issue **one** network call (request coalescing) when the implementation uses `Mutex` / `SharedFlow.shareIn` / single-flight.
- [ ] Read-during-write does not return torn state.
- [ ] If the repo exposes a `Flow`, it emits on every upstream change.

**Contract**
- [ ] Each public method has a happy + sad test.
- [ ] Repository preserves error type — `IOException` does not become `IllegalStateException`.

**Time** (when stale-while-revalidate is involved)
- [ ] Inject a fake `kotlinx.datetime.Clock`; assert the staleness boundary at exactly `T-1`, `T`, `T+1`.

### Template

```kotlin
// Fakes — co-locate with the test or share via fakes/ package.
class FakeWatchlistRemoteStore : WatchlistRemoteStore {
    var nextGetAll: Result<List<Scrip>> = Result.success(emptyList())
    val getAllCalls = mutableListOf<Unit>()

    override suspend fun getAll(): Result<List<Scrip>> {
        getAllCalls += Unit
        return nextGetAll
    }
}

class FakeWatchlistLocalStore : WatchlistLocalStore {
    var storedScrips: List<Scrip> = emptyList()
    var lastFetchedAtValue: Instant = Instant.fromEpochMilliseconds(0)
    val insertCalls = mutableListOf<List<Scrip>>()

    override suspend fun getAll(): List<Scrip> = storedScrips
    override suspend fun lastFetchedAt(): Instant = lastFetchedAtValue
    override suspend fun insert(scrips: List<Scrip>) {
        insertCalls += scrips
        storedScrips = scrips
    }
}

// MutableClock — a fake Clock controllable from the test body.
class MutableClock(initial: Instant = Instant.fromEpochMilliseconds(0)) : Clock {
    var now: Instant = initial
    override fun now(): Instant = now
}

@OptIn(ExperimentalCoroutinesApi::class)
class WatchlistRepositoryImplTest {

    private val testDispatcher = StandardTestDispatcher()

    private val remote = FakeWatchlistRemoteStore()
    private val local = FakeWatchlistLocalStore()
    private val clock = MutableClock()

    private lateinit var sut: WatchlistRepositoryImpl

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        sut = WatchlistRepositoryImpl(remote, local, clock)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `getAll cold read fetches network and writes to cache`() = runTest {
        // Given: empty cache, network returns NIFTY
        local.storedScrips = emptyList()
        remote.nextGetAll = Result.success(listOf(SCRIP_NIFTY))

        // When
        val out = sut.getAll()

        // Then
        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
        assertEquals(listOf(listOf(SCRIP_NIFTY)), local.insertCalls)
    }

    @Test
    fun `getAll warm read returns cache and does not hit network`() = runTest {
        // Given: cache has data; clock is inside the fresh window
        local.storedScrips = listOf(SCRIP_NIFTY)
        local.lastFetchedAtValue = Instant.fromEpochMilliseconds(0)
        clock.now = Instant.fromEpochMilliseconds(FRESH_WINDOW_MS - 1)

        // When
        val out = sut.getAll()

        // Then
        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
        assertEquals(0, remote.getAllCalls.size)
    }

    @Test
    fun `getAll stale-while-revalidate emits cache then fresh`() = runTest {
        local.storedScrips = listOf(SCRIP_NIFTY)
        local.lastFetchedAtValue = Instant.fromEpochMilliseconds(0)
        clock.now = Instant.fromEpochMilliseconds(FRESH_WINDOW_MS + 1)
        remote.nextGetAll = Result.success(listOf(SCRIP_NIFTY, SCRIP_BANK_NIFTY))

        sut.observe().test {
            assertEquals(listOf(SCRIP_NIFTY), awaitItem())
            assertEquals(listOf(SCRIP_NIFTY, SCRIP_BANK_NIFTY), awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `getAll network failure with warm cache surfaces cache silently`() = runTest {
        local.storedScrips = listOf(SCRIP_NIFTY)
        remote.nextGetAll = Result.failure(IOException())

        val out = sut.getAll()

        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
    }
}
```

### Anti-patterns

- Tests that go through both real `RemoteStore` and real `LocalStore` — that's a 4-tier integration test.
- Fakes that always succeed — every repo test class needs at least one failure test per public method.
- Asserting on log lines instead of cache contents.
- Forgetting to test the *invalidation* path on writes.
- **Using MockK** (`mockk<T>()`, `every { }`, `coEvery { }`, `coVerify { }`) — banned in baseline source sets; write fakes. Recorded calls on fakes (`fake.getAllCalls.size`, `fake.insertCalls`) replace `coVerify`.

---

