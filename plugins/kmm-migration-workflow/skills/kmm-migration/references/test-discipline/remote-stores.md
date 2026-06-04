> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 4. RemoteStores

> Path: `app/src/main/java/.../data/remotestores/**`
> Stack: **KMM-portable**. RemoteStores wrap Ktor (which is KMP-native)
> and head to `:shared` along with the data layer.

> **Lib-swap note**: RemoteStores backed by Retrofit (or another JVM-only HTTP library) are library-substitution targets — see `migration-baselines.md` §Library-substitution. Default to Path A (contract baseline via MockWebServer / hand-rolled HTTP fake, no Retrofit imports). Only fall back to Path B (defer baseline to Phase D) if the SUT's public surface exposes Retrofit-specific exception types (e.g., `Result<T, retrofit2.HttpException>` in the public signature).

### Responsibility

The HTTP boundary. Build a request from typed args; deserialize the
response into a domain model; call `apiClient.invalidate(url)` after a
mutation. The constructor takes a `baseUrl: String` fed by
`BuildKonfig` (or equivalent) — never a hardcoded URL. Path segments
live in a separate `*Routes.kt` constants file.

### What to mock

- ✅ The `ApiClient` — but **prefer a hand-rolled `RecordingApiClient` fake** over any mock library. It records the URL, body, headers, query params, and lets you script the next response. Fakes are KMM-portable by construction and survive any mock-library churn.
- ✅ Time, randomness, `BuildKonfig` reads.
- ❌ Don't fire real HTTP. `ktor-client-mock` is the KMM-portable choice for end-to-end serialization tests when a fake equivalent won't do.

### Coverage checklist

**Request shape (highest-leverage tests in this section)**
- [ ] URL exactly matches `"$baseUrl/api/$path/$pathParam"` — hardcode the expected URL and assert character-for-character.
- [ ] HTTP method matches (`GET`/`POST`/`PUT`/`DELETE`).
- [ ] Path parameters URL-encoded correctly when they contain special chars.
- [ ] Query parameters present, in expected order if the backend cares.
- [ ] Body serializes to expected JSON shape.
- [ ] Headers (auth, content-type, x-trace-id) attached when the store manages them.

**Response handling**
- [ ] 2xx → `Result.success(domainModel)` with field-level assertions.
- [ ] 4xx → `Result.failure` with the right typed error, surfaces backend error code.
- [ ] 5xx → `Result.failure`.
- [ ] Network failure (IOException) → `Result.failure`, no cache invalidation.
- [ ] Empty body / unexpected null fields → defensive parse; no NPE leak.
- [ ] Malformed JSON → `Result.failure`, not a thrown exception.
- [ ] **Decode failure is surfaced, never swallowed** — no empty `onFailure {}` / empty `catch` around the parse (a swallowed strict-decode error once became an infinite status-poll). Assert the failure propagates. On a Gson→kotlinx swap, decode via the one shared lenient `Json` and fixture from a **real captured BE payload** (numeric amounts, missing fields), not clean hand-written JSON. See `migration-baselines.md` §"Gson → kotlinx.serialization".

**Side effects**
- [ ] Mutating endpoints call `apiClient.invalidate(url)` once on success.
- [ ] Mutating endpoints **do not** invalidate on failure.
- [ ] Read endpoints **do not** invalidate.

**Multiple overloads**
- [ ] If the store has overloads, prove the typed one delegates to the string-key one with the right key.

### Template

```kotlin
class WatchlistRemoteStoreTest {

    private lateinit var apiClient: RecordingApiClient
    private lateinit var store: WatchlistRemoteStoreImpl

    private val baseUrl = "https://hulk.test"
    private val ucc = "UCC123"
    private val expectedUrl = "$baseUrl/api/users/$ucc/watchlist"

    @BeforeTest
    fun setUp() {
        apiClient = RecordingApiClient()
        store = WatchlistRemoteStoreImpl(apiClient, baseUrl)
    }

    @Test
    fun `getAll on 200 returns domain list and does not invalidate`() = runTest {
        apiClient.nextGetResponse = ApiResponse(Result.success(WATCHLIST_DTO), 200)

        val result = store.getAll(ucc)

        assertTrue(result.isSuccess)
        assertEquals(expectedUrl, apiClient.lastGetUrl)
        assertTrue(apiClient.invalidateCalls.isEmpty())
    }

    @Test
    fun `add on 200 invalidates the GET url exactly once`() = runTest {
        apiClient.nextPostResponse = ApiResponse(Result.success(Unit), 200)

        store.add(ucc, SCRIP_NIFTY)

        assertEquals(listOf(expectedUrl), apiClient.invalidateCalls)
    }

    @Test
    fun `add on 500 returns failure and skips invalidate`() = runTest {
        apiClient.nextPostResponse = ApiResponse(Result.failure(RuntimeException()), 500)

        val result = store.add(ucc, SCRIP_NIFTY)

        assertTrue(result.isFailure)
        assertTrue(apiClient.invalidateCalls.isEmpty())
    }

    @Test
    fun `add serializes scrip into JSON body with isin and tradingSymbol`() = runTest {
        apiClient.nextPostResponse = ApiResponse(Result.success(Unit), 200)

        store.add(ucc, SCRIP_NIFTY)

        assertEquals(
            mapOf("isin" to "INE040A01034", "tradingSymbol" to "HDFCBANK"),
            apiClient.lastPostBody
        )
    }
}
```

### Anti-patterns

- Hardcoded `http://localhost` URLs in tests — pretend to be real but assert nothing about production URL shape.
- Using mock-library matchers (MockK / Mockito) over typed `KSerializer<*>` — fragile, AND MockK is banned in baseline source sets. Use a recording fake of the HTTP client interface, or `ktor-client-mock` for Ktor.
- Skipping the URL-equality assertion. URL drift is the most common silent backend regression.
- One giant test asserting request **and** response. Split.

---

