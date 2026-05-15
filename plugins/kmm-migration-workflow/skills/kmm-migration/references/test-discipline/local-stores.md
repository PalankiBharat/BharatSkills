> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 5. LocalStores

> Path: `app/src/main/java/.../data/localstore/**`
> Stack: depends on DB choice. **KMM-portable** if the DB has a
> multiplatform driver (SQLDelight, ObjectBox-mp); **JVM-only** if
> tied to androidx (`Room` without the experimental KMP target,
> `SharedPreferences`/`DataStore` directly).

### Responsibility

Persistence boundary. Write/read typed entities. Expose `Flow<T>` for
observable state where applicable.

### DB-agnostic rule

**Never mock the DAO / `Box<T>` / `Queries`.** Always use the real
in-memory store via the platform driver. Mocked-DAO tests are
notorious for passing while production storage silently corrupts.

| DB | In-memory test setup |
|---|---|
| SQLDelight | `JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)` — KMM-portable |
| ObjectBox (Android-only) | `BoxStore` in a `createTempDir()` — JVM-only; needs `objectbox-{linux,macos,windows}` test artifacts |
| ObjectBox-mp (multiplatform) | Same `BoxStore` API, KMM driver |
| Room (Android-only) | Robolectric + `Room.inMemoryDatabaseBuilder` — JVM-only |
| `SharedPreferences` | Robolectric's real `SharedPreferences` — Android-only; abstract behind an interface if heading to `:shared` |

If the project migrates from ObjectBox/Room to SQLDelight as part of
the KMM move, the **test pattern is unchanged** — real in-memory
store, round-trip assertions. Only the driver setup line differs.

### What to mock

- ✅ Logger, time (`kotlinx.datetime.Clock`), `BuildKonfig` reads.
- ❌ **Do not mock** `Box<T>`, `BoxStore`, SQLDelight's `Queries`, or Room DAOs.
- For `SharedPreferences`-backed stores moving to `:shared`: abstract behind an interface, fake the interface in `commonTest`, keep an Android-side adapter test in `androidTest/`.

### Coverage checklist

**Round-trip (every entity, every method)**
- [ ] Insert → read returns the same entity, field-equal.
- [ ] Update → read returns the new value, not the old.
- [ ] Delete → read returns empty / null.
- [ ] Insert duplicate primary key → expected merge / replace behavior asserted explicitly.

**Schema migration**
- [ ] Pre-migration data shape produces the expected post-migration shape.
- [ ] Migration is idempotent.
- [ ] `clearPreferences()` (or equivalent) wipes legacy keys too — not just the V2 key.

**Observability**
- [ ] `observe()` emits initial value on subscribe.
- [ ] `observe()` emits a new value when `put()` is called.
- [ ] `observe()` does not emit when an unrelated entity changes (selectivity).

**Boundary**
- [ ] Empty store reads return empty list / null, not crash.
- [ ] Store full / unique-constraint violation surfaces a typed failure.

**Threading**
- [ ] Concurrent writers from two coroutines do not corrupt; final state is one of the two valid orderings.

### Template — SQLDelight (KMM-portable)

```kotlin
class WatchlistLocalStoreTest {

    private lateinit var driver: SqlDriver
    private lateinit var db: WatchlistDatabase
    private lateinit var sut: WatchlistLocalStoreImpl

    @BeforeTest
    fun setUp() {
        driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        WatchlistDatabase.Schema.create(driver)
        db = WatchlistDatabase(driver)
        sut = WatchlistLocalStoreImpl(db)
    }

    @AfterTest
    fun tearDown() {
        driver.close()
    }

    @Test
    fun `insert and getAll round-trips`() = runTest {
        sut.insert(listOf(SCRIP_NIFTY))
        assertEquals(listOf(SCRIP_NIFTY), sut.getAll())
    }

    @Test
    fun `observe emits on insert`() = runTest {
        sut.observe().test {
            assertEquals(emptyList(), awaitItem())
            sut.insert(listOf(SCRIP_NIFTY))
            assertEquals(listOf(SCRIP_NIFTY), awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }
}
```

### Template — ObjectBox (JVM-only, for code staying in `app/`)

```kotlin
class WatchlistLocalStoreTest {

    private lateinit var boxStore: BoxStore
    private lateinit var sut: WatchlistLocalStoreImpl

    @Before fun setUp() {
        val dir = createTempDir()
        boxStore = MyObjectBox.builder().directory(dir).build()
        sut = WatchlistLocalStoreImpl(boxStore)
    }

    @After fun tearDown() {
        boxStore.close()
        boxStore.deleteAllFiles()
    }

    @Test fun `insert and getAll round-trips`() = runTest {
        sut.insert(listOf(SCRIP_NIFTY))
        assertThat(sut.getAll()).containsExactly(SCRIP_NIFTY)
    }

    @Test fun `concurrent inserts converge to consistent state`() = runTest {
        val a = launch { sut.insert(listOf(SCRIP_NIFTY)) }
        val b = launch { sut.insert(listOf(SCRIP_BANK_NIFTY)) }
        a.join(); b.join()
        assertThat(sut.getAll()).containsExactly(SCRIP_NIFTY, SCRIP_BANK_NIFTY)
    }
}
```

### Anti-patterns

- Mocking `Box<T>` / `Queries` and asserting `verify(box).put(scrip)` — proves nothing about real storage semantics.
- Forgetting `driver.close()` / `boxStore.close()` in tear-down — flaky on shared CI.
- Sharing a single DB across tests — leaks state.
- Not testing migration paths after a schema bump (Constitution X).

---

