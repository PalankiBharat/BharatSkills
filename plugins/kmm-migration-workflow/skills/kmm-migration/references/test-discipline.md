
# Test Discipline

This reference is the source of truth for **how** to write tests in
Android/Kotlin codebases that are either already on a KMM journey
or expect to be. Loaded by `kmm-migration` Phase B (and any other
phase that touches test code). A test that "passes" but does not exercise the
bug-prone path is worse than no test — it creates false confidence.
A test that passes today but cannot move to `commonTest` tomorrow
silently locks the codebase to Android. Every rule here exists to
prevent both.

The companion human-readable doc (if your project has one) lives at
`docs/claude/TESTING.md`. Project constitutions referenced as
illustrative anchors here (V — Testing Excellence, X — Regression
Discipline, XIII — Concurrency by Reasoning) — substitute your own
project's principles where they exist.

---

## How to use this skill

1. Identify the file type being tested (use the section headings —
   ViewModel, UseCase, Repository, etc.). If it doesn't fit cleanly,
   say so to the user and ask before proceeding.
2. Pick the right protocol — **normal test** or **migration baseline
   test** (decision matrix below). They have different rules; mixing
   them produces tests that lock in implementation details and break
   on the migration.
3. **Pick the right stack from the start** — if the SUT is in or
   near the migration's blast radius, default to the KMM-portable
   stack (kotlin.test + MockK + Turbine). The JVM stack (JUnit 4 +
   Mockito + Truth) is reserved for code confirmed staying in
   `app/`. See Toolbox for the decision.
4. Follow the section's checklist exhaustively. Each unchecked box
   is a real-world bug class going un-asserted.
5. Use the section's template as scaffolding. Don't invent a fourth
   way of structuring tests in this codebase.
6. Before claiming done, run the gates in the **Verification**
   section and paste output. Constitution IX is non-negotiable.

### Pre-flight: verify anchors before quoting

This skill cites real files when used in-project (e.g.,
`MainCoroutineRule.kt`, `TradeButtonUseCaseTest.kt`,
`ActivateIndicatorRemoteStoreTest.kt`, specific lines in
`app/dependencies.gradle`). File paths and line numbers rot. Before
quoting any anchor to the user as a copy-paste reference,
**confirm it still exists** with a quick `Read`/`Grep`. If it's
gone, say so, fall back to the principle, and flag the stale
anchor for cleanup.

If the current working directory is not the host project (no
`docs/claude/`, no recognizable package root), treat project-
specific anchors as illustrative only and apply the principles
abstractly.

---

## Normal test vs. migration baseline test (pick one)

| Question | Normal test | Migration baseline test |
|---|---|---|
| Will the SUT change implementation during the KMM migration? | No / not soon | Yes — code is moving to `shared/` or being rewritten |
| Goal | Catch regressions during ongoing work | Prove migrated code is **behaviorally identical** to pre-migration |
| Who can edit the test after writing? | Anyone, any time | **Frozen** — no edits without a migration-exception |
| Allowed to use Mockito? | Yes (if SUT stays in `app/`) | **No** — Mockito doesn't run in `commonTest` |
| Allowed to assert on `verify(mock).method(...)`? | Yes, sparingly | **No** — only observable outputs |
| Lives where? | `app/src/test/...` mirroring main | `<dest>/src/androidUnitTest/...` (promoted to `<dest>/src/commonTest/...` in Phase E when code reaches `commonMain`) |

**If the SUT is anywhere in the migration's blast radius, default to
baseline-test rules.** When in doubt, ask the user which one this is.
Rewriting a baseline test mid-migration silently relaxes the safety
net you were trying to build.

---

## Toolbox (already wired — use these, don't reinvent)

Two stacks. Pick by SUT's migration trajectory, not by habit.

### Decision: which stack?

**KMM-portable stack (default for migration-bound code)**

| Concern | Use |
|---|---|
| Test runner | `kotlin.test` (`@Test`, `@BeforeTest`, `@AfterTest`, `assertEquals`, `assertTrue`, `assertFailsWith`) |
| Mocking | MockK (`mockk`, `every`, `coEvery`, `verify`, `coVerify`) — or hand-rolled fakes (preferred for baselines, see §12) |
| Flow assertions | Turbine 1.2.1 (`flow.test { … }`) |
| Coroutine control | `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, `advanceUntilIdle`, `advanceTimeBy`) |
| `Dispatchers.Main` swap | `Dispatchers.setMain(testDispatcher)` in `@BeforeTest`, `Dispatchers.resetMain()` in `@AfterTest` — **not** `MainCoroutineRule` (JUnit `@get:Rule` doesn't exist in `commonTest`) |
| Time | `kotlinx.datetime.Clock` (inject) |
| HTTP mocking | `ktor-client-mock` for Ktor RemoteStores; hand-rolled `Recording*` fakes when serializer types make any mocking ugly |
| DB | Real in-memory store via the platform driver — SQLDelight's `JdbcSqliteDriver(IN_MEMORY)`, ObjectBox-mp test artifacts, etc. **Never** mock the DAO/Box. |

**JVM-only stack (for code confirmed staying in `app/`)**

| Concern | Use |
|---|---|
| Test runner | JUnit 4 (`@Test`, `@Before`, `@After`) |
| Mocking | Mockito + `mockito-kotlin` (`whenever`, `verify`, `argumentCaptor`) |
| Flow assertions | Turbine 1.2.1 |
| Coroutine control | `kotlinx-coroutines-test` |
| `Dispatchers.Main` swap | `MainCoroutineRule` (if your project has it) — JUnit `@get:Rule` is fine here |
| Time | `kotlinx.datetime.Clock` (preferred even here for forward-compat) or `() -> Long` |
| Assertions | `com.google.common.truth.Truth.assertThat` (more readable) or `org.junit.Assert` |
| HTTP mocking | `ktor-client-mock`, or hand-rolled fakes |
| ObjectBox (JVM) | `objectbox-linux/macos/windows` test artifacts — real in-memory `BoxStore`, not mocked `Box<T>` |
| Compose UI | `androidx.compose.ui:ui-test-junit4` + Robolectric — runs as JVM unit tests |

### Mockito vs MockK — when?

**Default: MockK + kotlin.test.** For any SUT that is, or plausibly
will be, in the migration's blast radius — UseCases, Repositories,
RemoteStores, LocalStores, Mappers, domain Models, Interactors,
Presenters, and any ViewModel built on `androidx.lifecycle.ViewModel`
(KMP-compatible). Writing these in Mockito + Truth means rewriting
them when the file moves to `:shared`.

**Mockito + JUnit 4 only when**: the SUT is permanently Android —
`Activity`, `Fragment`, `Composable` page, `Service`,
`BroadcastReceiver`, `Worker`, or anything that tightly binds to
the Android framework (`Context`, `View`, `LifecycleOwner`).

**Never mix Mockito and MockK in one test file.** Pick the stack
when you start.

### Truth → kotlin.test mapping (when porting or starting fresh)

`kotlin.test`'s assertion argument order is `(expected, actual)` —
the **opposite** of Truth (which reads `assertThat(actual).isEqualTo(expected)`).
Get this wrong and your error messages are misleading.

| Truth | kotlin.test |
|---|---|
| `assertThat(actual).isEqualTo(expected)` | `assertEquals(expected, actual)` |
| `assertThat(actual).isNotEqualTo(unexpected)` | `assertNotEquals(unexpected, actual)` |
| `assertThat(actual).isNull()` | `assertNull(actual)` |
| `assertThat(actual).isNotNull()` | `assertNotNull(actual)` |
| `assertThat(actual).isTrue()` | `assertTrue(actual)` |
| `assertThat(actual).isFalse()` | `assertFalse(actual)` |
| `assertThat(list).containsExactly(a, b)` | `assertEquals(listOf(a, b), list)` |
| `assertThat(list).isEmpty()` | `assertTrue(list.isEmpty())` |
| `assertThat(d).isWithin(0.001).of(expected)` | `assertEquals(expected, d, 0.001)` |
| `assertThat(s).contains(sub)` | `assertTrue(s.contains(sub))` |

For richer fluent assertions in `commonTest`, consider Kotest's
assertion library (`io.kotest.assertions.core`) — it's KMM-portable.
Don't add it without team agreement.

---

## Cross-cutting rules (apply to every section)

1. **Mirror the package.** Test for `…/usecases/orders/PlaceOrderUseCaseImpl.kt` lives at `…/usecases/orders/PlaceOrderUseCaseImplTest.kt`. No exceptions.
2. **Name tests as sentences.** Backtick form, English grammar: ` ``when scalper mode is OFF and chart is tradeable trade button is shown`` `. `test_x_should_y` is legacy — do not introduce new ones.
3. **Arrange-Act-Assert** with explicit `// Given`, `// When`, `// Then` comments. The reviewer should be able to delete the bodies and still know what each test proves.
4. **One concept per test.** If you need two `verify(...)` calls asserting *different* behaviors, split the test.
5. **No `Thread.sleep` ever in unit tests.** Use the test scheduler (`advanceTimeBy`, `advanceUntilIdle`).
6. **No real time, no real I/O, no real `Dispatchers.IO`.** Inject `kotlinx.datetime.Clock` (preferred — KMM-portable) or a `() -> Long` for monotonic timing. Inject the dispatcher. Mock the network/DB at the boundary.
7. **Mock at the boundary, not the subject.** A `UseCaseTest` mocks *its* dependencies (with MockK by default — see Toolbox); it does not mock the use case it is testing. Constitution V: "Never mock what you're testing."
8. **Negative paths are mandatory.** Every section's checklist includes them. Skipping them fails review.
9. **Tests must fail for the right reason.** When you write a new test, run it once *before* the production change to confirm it reds for the intended cause. For bug-fix tests this is non-negotiable (Constitution V) — no failing-first proof ⇒ fix not accepted.
10. **No `@Ignore` without a tracked TODO** referencing a ticket and a concrete unblocking condition.
11. **Do not assert on log output, internal `_state` field names, or `private` properties.** Assert on the public API and observable side effects only.
12. **`sut` ("subject under test")** is the project convention for the field name. Stay consistent.
13. **Pick the test stack at file creation time.** Don't write a JVM-only test for migration-bound code "and rewrite later." Migration deadlines slip, rewrites get skipped.

### File-level skeleton — primary (KMM-portable)

Use for any SUT in or near the migration's blast radius.

```kotlin
package com.example.<mirrored.path>

import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class <Subject>Test {

    private val testDispatcher = StandardTestDispatcher()

    // mockk<T>() for strict; mockk<T>(relaxed = true) returns defaults for
    // any unstubbed call. Use relaxed sparingly — it hides design smells.
    private val dep1 = mockk<Dep1>()
    private val dep2 = mockk<Dep2>(relaxed = true)

    private lateinit var sut: <Subject>

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        // shared default stubs go here — keep them MINIMAL.
        // every { ... } for non-suspend; coEvery { ... } for suspend.
        sut = <Subject>(dep1, dep2, testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `<descriptive sentence>`() = runTest {
        // Given
        every { dep1.foo() } returns FOO_VALUE
        coEvery { dep2.bar() } returns Result.success(BAR_VALUE)

        // When
        sut.execute()
        advanceUntilIdle()

        // Then
        // verify { } for non-suspend; coVerify { } for suspend.
        coVerify { dep2.bar() }
        // kotlin.test: (expected, actual) order — opposite of Truth!
        assertEquals(EXPECTED_STATE, sut.state.value)
    }
}
```

### File-level skeleton — secondary (JVM-only)

Use only for code confirmed staying in `app/` (Activities,
Composables, Workers, Receivers, anything Android-framework bound).

```kotlin
package com.example.<mirrored.path>

import com.example.vte.MainCoroutineRule
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.mockito.Mock
import org.mockito.MockitoAnnotations
import org.mockito.kotlin.whenever
import org.mockito.kotlin.verify

@OptIn(ExperimentalCoroutinesApi::class)
class <Subject>Test {

    private val testDispatcher = StandardTestDispatcher()

    @get:Rule val mainRule = MainCoroutineRule(testDispatcher)

    @Mock private lateinit var dep1: Dep1
    @Mock private lateinit var dep2: Dep2

    private lateinit var sut: <Subject>

    @Before
    fun setup() {
        MockitoAnnotations.openMocks(this)
        sut = <Subject>(dep1, dep2, testDispatcher)
    }

    @Test
    fun `<descriptive sentence>`() = runTest {
        // Given
        whenever(dep1.foo()).thenReturn(...)

        // When
        sut.bar()
        advanceUntilIdle()

        // Then
        verify(dep1).baz()
        assertThat(sut.state.value).isEqualTo(...)
    }
}
```

---

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

### What to mock

- ✅ Every `IUseCase`, `IRepository`, `IGet*` collaborator → mock with MockK.
- ✅ Time source (`kotlinx.datetime.Clock`) → mock or fake.
- ✅ `SavedStateHandle` abstraction → real fake or MockK mock.
- ❌ Never mock the ViewModel itself, its emitted `StateFlow`s, or Kotlin data classes the ViewModel constructs.
- ❌ Don't mock `viewModelScope` — let `Dispatchers.setMain(testDispatcher)` do the swap.

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
@OptIn(ExperimentalCoroutinesApi::class)
class PositionViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private val getPositionsUseCase = mockk<IGetPositionsUseCase>()
    private val exitPositionUseCase = mockk<IExitPositionUseCase>()

    private lateinit var sut: PositionViewModel

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        every { getPositionsUseCase.observe() } returns emptyFlow()
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
        every { getPositionsUseCase.observe() } returns flowOf(listOf(positionInProfit()))
        sut = PositionViewModel(getPositionsUseCase, exitPositionUseCase)
        sut.onLaunch()
        advanceUntilIdle()

        sut.state.test {
            val s = expectMostRecentItem() as PositionUiState.Loaded
            assertEquals(PnlColor.GREEN, s.pnlColor)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `Exit action while previous Exit is in flight does not double-fire`() = runTest {
        coEvery { exitPositionUseCase.perform(any()) } coAnswers {
            delay(1_000); Result.success(Unit)
        }

        sut.onAction(PositionAction.Exit("p1"))
        advanceTimeBy(100)
        sut.onAction(PositionAction.Exit("p1"))
        advanceUntilIdle()

        coVerify(exactly = 1) { exitPositionUseCase.perform(any()) }
    }
}
```

### Anti-patterns

- Asserting on `_state.value` (private). Use the public `StateFlow`.
- `runBlocking` inside the test body — always `runTest`.
- Using `Thread.sleep` to wait for emissions — use Turbine.
- Constructing the ViewModel with real network/DB collaborators — that's an integration test, move it to `androidTest/`.
- Mocking `StateFlow` itself — construct a real `MutableStateFlow` in the test instead.
- Using `MainCoroutineRule` for a VM that's headed to `:shared` — won't move to `commonTest`.

---

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

### What to mock

- ✅ Every collaborating repository / store / SDK boundary (MockK).
- ✅ Other use cases this one composes.
- ✅ Time, randomness, IDs.
- ❌ Pure data classes the use case constructs.
- ❌ The use case itself.
- ❌ The use case's input or output models — build real instances with test fixtures.

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
@OptIn(ExperimentalCoroutinesApi::class)
class GetPositionsUseCaseImplTest {

    private val testDispatcher = StandardTestDispatcher()

    private val positionRepo = mockk<IPositionRepository>()
    private val protectionRepo = mockk<IProtectionOrderRepository>()

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
        coEvery { positionRepo.getAll() } returns listOf(mis("HDFCBANK"))
        coEvery { protectionRepo.getAll() } returns listOf(protection("HDFCBANK", NRML))

        val out = sut.perform()

        assertEquals(1, out.size)
        assertNotNull(out.single().protectionOrder)
    }
    // endregion

    // region edge: ISIN merge collision (regression for #358)
    @Test
    fun `MIS and CNC positions with same ISIN bind to their respective product type`() = runTest {
        coEvery { positionRepo.getAll() } returns listOf(mis("HDFCBANK"), cnc("HDFCBANK"))
        coEvery { protectionRepo.getAll() } returns listOf(protection("HDFCBANK", MIS))

        val out = sut.perform()

        assertNotNull(out.single { it.productType == MIS }.protectionOrder)
        assertNull(out.single { it.productType == CNC }.protectionOrder)
    }
    // endregion

    // region sad
    @Test
    fun `perform propagates repository failure`() = runTest {
        coEvery { positionRepo.getAll() } throws IOException("boom")
        assertFailsWith<IOException> { sut.perform() }
    }
    // endregion
}
```

### Anti-patterns

- Smoke tests that only call `perform()` and assert it returned. Prove nothing.
- Test bodies mocking 8 collaborators when the use case only uses 2 — delete the dead mocks; they hide design smell.
- Sharing mutable setup state across tests.
- Skipping the bug-reproducer test "because the fix is obvious."

---

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

### What to mock

- ✅ `RemoteStore` collaborators (MockK; their HTTP layer is tested separately).
- ✅ `LocalStore` collaborators (MockK; their persistence layer is tested separately).
- ✅ Logger, time source (`kotlinx.datetime.Clock`).
- ❌ Don't use a real `BoxStore` / SQLDelight driver here — that's a `LocalStore` test.
- ❌ Don't use a real Ktor client — that's a `RemoteStore` test.

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
@OptIn(ExperimentalCoroutinesApi::class)
class WatchlistRepositoryImplTest {

    private val testDispatcher = StandardTestDispatcher()

    private val remote = mockk<WatchlistRemoteStore>()
    private val local = mockk<WatchlistLocalStore>(relaxUnitFun = true)
    private val clock = mockk<Clock>()
    private var now = Instant.fromEpochMilliseconds(0)

    private lateinit var sut: WatchlistRepositoryImpl

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        every { clock.now() } answers { now }
        sut = WatchlistRepositoryImpl(remote, local, clock)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `getAll cold read fetches network and writes to cache`() = runTest {
        coEvery { local.getAll() } returns emptyList()
        coEvery { remote.getAll() } returns Result.success(listOf(SCRIP_NIFTY))

        val out = sut.getAll()

        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
        coVerify { local.insert(listOf(SCRIP_NIFTY)) }
    }

    @Test
    fun `getAll warm read returns cache and does not hit network`() = runTest {
        coEvery { local.getAll() } returns listOf(SCRIP_NIFTY)
        coEvery { local.lastFetchedAt() } returns Instant.fromEpochMilliseconds(0)
        now = Instant.fromEpochMilliseconds(FRESH_WINDOW_MS - 1)

        val out = sut.getAll()

        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
        coVerify(exactly = 0) { remote.getAll() }
    }

    @Test
    fun `getAll stale-while-revalidate emits cache then fresh`() = runTest {
        coEvery { local.getAll() } returns listOf(SCRIP_NIFTY)
        coEvery { local.lastFetchedAt() } returns Instant.fromEpochMilliseconds(0)
        now = Instant.fromEpochMilliseconds(FRESH_WINDOW_MS + 1)
        coEvery { remote.getAll() } returns Result.success(listOf(SCRIP_NIFTY, SCRIP_BANK_NIFTY))

        sut.observe().test {
            assertEquals(listOf(SCRIP_NIFTY), awaitItem())
            assertEquals(listOf(SCRIP_NIFTY, SCRIP_BANK_NIFTY), awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `getAll network failure with warm cache surfaces cache silently`() = runTest {
        coEvery { local.getAll() } returns listOf(SCRIP_NIFTY)
        coEvery { remote.getAll() } returns Result.failure(IOException())

        val out = sut.getAll()

        assertEquals(listOf(SCRIP_NIFTY), out.getOrThrow())
    }
}
```

### Anti-patterns

- Tests that go through both real `RemoteStore` and real `LocalStore` — that's a 4-tier integration test.
- Mocks that always succeed — every repo test class needs at least one failure test per public method.
- Asserting on log lines instead of cache contents.
- Forgetting to test the *invalidation* path on writes.

---

# 4. RemoteStores

> Path: `app/src/main/java/.../data/remotestores/**`
> Stack: **KMM-portable**. RemoteStores wrap Ktor (which is KMP-native)
> and head to `:shared` along with the data layer.

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
- Using MockK matchers over typed `KSerializer<*>` — fragile; switch to a recording fake.
- Skipping the URL-equality assertion. URL drift is the most common silent backend regression.
- One giant test asserting request **and** response. Split.

---

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

# 6. Mappers

> Path: `app/src/main/java/.../**/*Mapper.kt`
> Stack: **KMM-portable**. Mappers are pure functions and almost
> always migration-bound — they're the easiest to port and the
> highest-leverage to baseline.

### Responsibility

Pure functions translating one shape to another. Almost always pure,
which means easiest to test exhaustively — and the place where bugs
hide because they "look trivial."

### What to mock

- Nothing. Mappers are pure. If the test file mocks anything, that's a smell — flag it.
- Exception: a mapper taking a `Clock` for a generated timestamp — inject a fixed instant via `kotlinx.datetime.Clock.fixed(...)` or equivalent.

### Coverage checklist

**Field coverage**
- [ ] Every input field maps to the expected output field. Eyeball source and target classes; every property on either side hit by an assertion in at least one test.

**Branching**
- [ ] Each `when` / `?:` branch has a test.

**Defensive parsing**
- [ ] Null inputs in nullable fields → expected default.
- [ ] Out-of-range enum value → fallback enum, no crash.
- [ ] Unknown / new enum value (forward compat) → maps to a sentinel and logs a warning.

**Numeric**
- [ ] `0.0` is preserved (don't accidentally treat it as "missing").
- [ ] Negative numbers preserved where domain allows.
- [ ] Locale: number formatting always `Locale.US` for any to-string code; in `commonMain`, `Locale` is unavailable — use `kotlin.text` formatting or `kotlinx.atomicfu`-friendly helpers.

**Round-trip** (only when the mapper has an inverse)
- [ ] `forward(reverse(x)) == x` for all interesting `x`.

### Template

```kotlin
class TickMapperTest {

    @Test
    fun `maps fresh tick with non-zero upperCircuit`() {
        val src = scripFeed(upper = "100.5", lower = "90.0")
        val out = TickMapper.map(src, previous = TICK_PREVIOUS)
        assertEquals(100.5, out.upperCircuit)
        assertEquals(90.0, out.lowerCircuit)
    }

    @Test
    fun `upperCircuit of 0_0 falls back to previous tick`() {
        val src = scripFeed(upper = "0.0", lower = "90.0")
        val out = TickMapper.map(src, previous = TICK_PREVIOUS.copy(upperCircuit = 110.0))
        assertEquals(110.0, out.upperCircuit)
    }

    @Test
    fun `null upperCircuit string falls back to previous`() {
        val src = scripFeed(upper = null, lower = null)
        val out = TickMapper.map(src, previous = TICK_PREVIOUS.copy(upperCircuit = 110.0))
        assertEquals(110.0, out.upperCircuit)
    }

    @Test
    fun `unparseable string falls back to previous`() {
        val src = scripFeed(upper = "not-a-number", lower = "x")
        val out = TickMapper.map(src, previous = TICK_PREVIOUS.copy(upperCircuit = 110.0))
        assertEquals(110.0, out.upperCircuit)
    }
}
```

### Anti-patterns

- Asserting the mapper "didn't crash" with no field-level assertion.
- Snapshot-style `assertEquals(expectedDomainObject, actual)` without per-field verification — when it fails you can't tell which field is wrong (exception: snapshot files used as a *baseline* — see §12).
- Hidden mutation in a "mapper" — if it holds state, it isn't a mapper. Flag and refactor.

---

# 7. Models (data classes / domain objects)

> Path: `app/src/main/java/.../domain/model/**` and `.../library/models/**`
> Stack: **KMM-portable**. Domain models live in `commonMain`.

### Responsibility

Hold data. Most also have computed properties (`val pnl: Double get() = …`) or factory functions. The computed properties are where the bugs live.

### When to write a test

- ✅ Non-trivial computed property (`pnl`, `isProtected`, `displayName`, derived flags).
- ✅ Factory / static builder.
- ✅ Manually overridden `equals`/`hashCode` (rare in Kotlin — flag if seen).
- ❌ Pure data class with no logic? No test. Don't waste keystrokes asserting that `data class Foo(val x: Int)` round-trips through copy.

### Coverage checklist

**Computed properties**
- [ ] Each computed property tested for each input branch.
- [ ] Boundary inputs: zero quantity, zero price, negative PnL.

**Equality / identity**
- [ ] Only test if `equals` is *manually overridden*. Default data class equality doesn't need a test.

**Serialization**
- [ ] If `@Serializable` and used over the wire, a `Json.encodeToString` round-trip test for the field shape the backend cares about. Serializer behavior is a top KMM migration risk — round-trip is the canonical check.

### Template

```kotlin
class PositionModelTest {

    @Test
    fun `realised PnL is sellAmount minus buyAmount`() {
        val p = PositionModel(buyAmount = 1000.0, sellAmount = 1200.0, /* … */)
        assertEquals(200.0, p.realisedPnl, 0.001)
    }

    @Test
    fun `realised PnL of fully open position is zero`() {
        val p = PositionModel(buyAmount = 1000.0, sellAmount = 0.0, /* … */)
        assertEquals(0.0, p.realisedPnl)
    }

    @Test
    fun `isProtected is true when stoploss and target are both set`() {
        val p = PositionModel(stoploss = 95.0, target = 105.0, /* … */)
        assertTrue(p.isProtected)
    }

    @Test
    fun `isProtected is false when only stoploss is set`() {
        val p = PositionModel(stoploss = 95.0, target = null, /* … */)
        assertFalse(p.isProtected)
    }
}
```

### Anti-patterns

- `@Test fun `data class equality works`` — testing the language.
- Tests for getters / setters of plain fields.
- Tests passing mocked dependencies into a data class — data classes don't have dependencies.

---

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

### What to mock

- ✅ Every injected use case (MockK).
- ✅ The listener (MockK mock — use `slot<T>()` to capture callback args).
- ✅ Time, randomness.
- ❌ Don't mock the `CoroutineScope` — pass a `TestScope` or rely on `Dispatchers.setMain`.

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
@OptIn(ExperimentalCoroutinesApi::class)
class OrderInteractorTest {

    private val testDispatcher = StandardTestDispatcher()

    private val marginUseCase = mockk<IGetEstimatedMarginUseCase>()
    private val placeOrderUseCase = mockk<IPlaceOrderUseCase>()
    private val listener = mockk<OrderInteractorListener>(relaxed = true)
    private val chart = mockk<Chart>()

    private lateinit var sut: OrderInteractor

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        every { chart.scrip } returns SCRIP_NIFTY
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
        coEvery { marginUseCase.perform(any()) } returns Result.success(Margin(750.0))

        sut.setLot(2)
        advanceUntilIdle()

        verify { listener.onMarginUpdated(MarginState.Available, "₹750") }
    }

    @Test
    fun `rapid setLot calls only emit latest`() = runTest {
        coEvery { marginUseCase.perform(any()) } coAnswers {
            delay(500); Result.success(Margin(750.0))
        }

        sut.setLot(1)
        advanceTimeBy(100)
        sut.setLot(3)
        advanceUntilIdle()

        verify(exactly = 1) { listener.onMarginUpdated(any(), any()) }
    }

    @Test
    fun `setLot after onCleared is a no-op`() = runTest {
        sut.onCleared()
        sut.setLot(2)
        advanceUntilIdle()

        verify { listener wasNot Called }
        coVerify(exactly = 0) { marginUseCase.perform(any()) }
    }
}
```

### Anti-patterns

- Asserting without `advanceUntilIdle()` — passes on `UnconfinedTestDispatcher`, fails on `StandardTestDispatcher`. Always advance.
- Holding a strong reference to the listener "for convenience" — defeats the unsubscribe contract.
- Using `WeakReference` for a KMM-bound interactor — JVM-only.

---

# 9. Presenters

> Path: `app/src/main/java/.../presenter/**`
> Stack: **KMM-portable** by default — same rationale as ViewModels.

### Responsibility

Format ViewModel/UseCase output for the UI (button labels, colors,
visible/gone states). Stateless or near-stateless; expose
`StateFlow<UiModel>` to be collected by a Composable.

### What to mock

- ✅ Anything the presenter pulls from (use cases, repositories) — MockK.
- ✅ Resource provider (`IStringResourceRepository`) — define as an interface, fake in tests.
- ❌ Don't mock the presenter itself.

### Coverage checklist

- [ ] Each state branch produces the expected display values (button text, color, icon, visibility).
- [ ] Localisation: use a fake `IStringResourceRepository` that returns string-resource **keys** instead of strings — assert on the key, not the localized output.
- [ ] Number formatting honors `Locale.US` for decimal points (or, in `commonMain`, use `kotlin.text` formatting helpers that don't depend on JVM `Locale`).
- [ ] When upstream emits the same value twice, presenter conflates and emits once (or N times — assert whichever the contract is, document it in the test name).

### Template

Same skeleton as ViewModels (kotlin.test + MockK + Turbine);
substitute `Presenter` for `ViewModel`.

### Anti-patterns

- Asserting on String content. Use string-resource *keys*; they don't break on translation updates.
- Coupling the test to `R.string.foo` ID values — use a fake resource provider, never `R.*` directly (also: `R.*` is androidx-only and won't move to `:shared`).

---

# 10. Composables / Pages

> Path: `app/src/main/java/.../view/**/*Page.kt`
> Stack: **JVM-only.** Native UI strategy: Composables stay in
> `androidMain`, are not migration-bound, and **do not need
> baseline tests** for the KMM migration. Test as normal Android
> unit tests under `app/src/test/`.
> Notes: `androidx.compose.ui:ui-test-junit4` + Robolectric is wired, so Compose tests run as **JVM unit tests**, not instrumented.

### Why no baseline tests

Composables are pure UI. Under the native-UI KMM strategy
(Compose on Android, SwiftUI on iOS), they don't move to `:shared`.
The shared business logic (ViewModel/Presenter) carries the
behavioral contract; visual regressions are caught by
Paparazzi/Roborazzi golden images, not by `commonTest`.

If your project later adopts Compose Multiplatform, revisit — the
Compose test stack has KMP equivalents (`@OptIn(ExperimentalTestApi::class)`,
`runComposeUiTest { … }`), but that's deferred under the current
12–18 month strategy.

### Responsibility

Render a state to pixels and forward gestures to a callback /
ViewModel. Should be **stateless** — state hoisting is non-negotiable
(Constitution I).

### What to mock

- ✅ The state model (`SomeUiState`) — pass a real instance, not a mock.
- ✅ Callbacks — pass lambdas with `var captured: …` assertion variables.
- ❌ Don't mock `Modifier`, `MaterialTheme`, or anything in the Compose API.

### Coverage checklist

**Rendering**
- [ ] Each `UiState` branch (Loading / Loaded / Error / Empty) renders the right content.
- [ ] `testTag` (with `testTagsAsResourceId = true`) set on every element an Appium test or screenreader needs — assert via `onNodeWithTag(...)`.
- [ ] Content descriptions present on icons and clickable surfaces (Constitution VII).
- [ ] Dark mode + light mode previews don't crash.
- [ ] Edge-to-edge insets respected.

**Interaction**
- [ ] Tap on the primary CTA invokes the callback with the right payload, exactly once.
- [ ] Long-press / swipe gestures (where the spec defines them) fire.
- [ ] Disabled state actually blocks the click.

**Accessibility**
- [ ] All interactive elements have a content description or visible text.
- [ ] Touch targets ≥ 48dp.

### Template (JVM-only — JUnit 4 + Robolectric)

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MarketProtectionPageTest {

    @get:Rule val composeRule = createComposeRule()

    @Test fun `Loaded state shows protection toggle`() {
        composeRule.setContent {
            MaterialTheme {
                MarketProtectionPage(
                    state = MarketProtectionUiState.Loaded(isOn = true),
                    onToggle = {}
                )
            }
        }

        composeRule.onNodeWithTag("market_protection_toggle")
            .assertIsDisplayed()
            .assertIsOn()
    }

    @Test fun `tapping toggle invokes callback with new value`() {
        var captured: Boolean? = null
        composeRule.setContent {
            MarketProtectionPage(
                state = MarketProtectionUiState.Loaded(isOn = false),
                onToggle = { captured = it }
            )
        }

        composeRule.onNodeWithTag("market_protection_toggle").performClick()

        assertThat(captured).isTrue()
    }
}
```

### Anti-patterns

- Asserting on pixel positions or screen sizes.
- XPath-like node hierarchy assertions. Use `testTag`.
- Putting business logic inside the Composable to make it "self-contained for testing" — hoist the state.
- Using Espresso for Compose. Wire is `compose.ui.test`.
- Adding Composables to the migration baseline source set. Composables aren't migration-bound.

---

# 11. Workers / Receivers / Services

> Paths: `app/src/main/java/.../**/*Worker.kt`, `*Receiver.kt`, `*Service.kt`.
> Stack: **JVM-only.** WorkManager, `BroadcastReceiver`, and
> `Service` are Android-framework primitives. They stay in `app/`
> and **do not need baseline tests** for the KMM migration.

### Responsibility

WorkManager workers: background jobs (sync, retry queues, polling
fallbacks). BroadcastReceivers: respond to system events. Services:
long-running foreground work (rare in this codebase).

### What to mock

- ✅ Use cases / repositories the worker invokes (Mockito or MockK — pick one consistent with the rest of `app/`).
- ✅ Logger and analytics.
- ❌ Don't mock `WorkerParameters` — pass a real one via `TestListenableWorkerBuilder` (transitive of WorkManager).

### Coverage checklist

**Outcome**
- [ ] Happy path returns `Result.success()` and persists output Data (if any).
- [ ] Transient failure returns `Result.retry()`.
- [ ] Permanent failure returns `Result.failure()` with a typed reason.
- [ ] Cooperative cancellation: stopped mid-run, returns promptly, no partial-write.

**Backoff**
- [ ] After N consecutive failures, the worker stops scheduling itself / surfaces an error.

**Receivers**
- [ ] `onReceive` with the expected `Intent` action triggers the handler.
- [ ] `onReceive` with an unrelated action is a no-op.
- [ ] `onReceive` with a malformed extras bundle does not crash.

### Template (Worker — JVM-only)

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class WatchlistSyncWorkerTest {

    private lateinit var context: Context
    @Mock private lateinit var syncUseCase: ISyncWatchlistUseCase

    @Before fun setUp() {
        MockitoAnnotations.openMocks(this)
        context = ApplicationProvider.getApplicationContext()
    }

    @Test fun `success on remote sync returns success`() = runTest {
        whenever(syncUseCase.perform()).thenReturn(Result.success(Unit))
        val worker = TestListenableWorkerBuilder<WatchlistSyncWorker>(context)
            .setWorkerFactory(workerFactoryWith(syncUseCase))
            .build()

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())
    }

    @Test fun `IOException returns retry`() = runTest {
        whenever(syncUseCase.perform()).thenThrow(IOException())
        val worker = TestListenableWorkerBuilder<WatchlistSyncWorker>(context)
            .setWorkerFactory(workerFactoryWith(syncUseCase))
            .build()

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
    }
}
```

### Anti-patterns

- Calling `worker.doWork()` without injecting test doubles — defaults to real network/DB.
- Assuming WorkManager will retry. Test the worker, not WorkManager.
- Adding workers to the migration baseline source set. They aren't migration-bound.

---

# 12. Migration baseline tests (KMM migration)

> **This is the single most important section in this skill if the
> SUT is in the migration's blast radius.** Default to baseline rules
> when in doubt.

The flow:

1. **Pre-migration**: write tests against current behavior. They go green.
2. **Freeze**: tests become immutable; only sanctioned exceptions can edit.
3. **Migrate**: production code moves to `shared/` (or is rewritten).
4. **Post-migration**: frozen tests must still go green against the migrated code.

This only works if every test is written so that the only thing it
can fail on is **observable behavior change** — never internal code
shape.

### What "observable" means (allowlist + denylist)

**Allowed assertions (these survive migration):**
- Return values from public methods.
- Emitted values from public `Flow`s / `StateFlow`s / `Channel`s.
- Recorded HTTP requests on a fake `ApiClient` (URL string, method, body bytes / parsed JSON, headers).
- Database / store rows after the operation, read through the public store API.
- Callback invocations on a real listener interface (count, args).
- Exceptions thrown / `Result.failure` types.
- Snapshot/golden file comparisons of serialized output.
- `kotlinx.serialization` round-trips on canonical JSON.

**Denied assertions (these break across the migration):**
- `verify(mock).method(...)` on internal collaborators. *Why*: migration may replace, split, or rename the collaborator while preserving behavior.
- Asserting on which class executed the work.
- Asserting on dispatcher type, coroutine context, scope identity.
- Asserting on log lines, Timber tags, breadcrumbs.
- Asserting on internal field names (anything `private` accessed via reflection).
- Asserting on package-qualified names of types in error messages.

**Rule of thumb**: if the assertion would still hold for a hand-rolled re-implementation that produced the same outputs, it's observable. If a clean-room re-implementation could pass functional acceptance and still fail your test, the test is *implementation-coupled* — rewrite it.

### KMM-portable test stack (mandatory for baseline tests)

Anything destined for `shared/commonTest` (or that might move there)
must use only:

| Concern | Use |
|---|---|
| Runner | `kotlin.test` (`@Test`, `@BeforeTest`, `@AfterTest`, `assertEquals`, `assertTrue`, `assertFailsWith`) |
| Coroutines | `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, `advanceUntilIdle`, `advanceTimeBy`) |
| `Dispatchers.Main` | `Dispatchers.setMain` / `resetMain` in `@BeforeTest` / `@AfterTest` |
| Flows | Turbine 1.2.1 |
| Time | `kotlinx.datetime.Clock` (fake via interface or fixed instant) |
| Mocks | **MockK only** (`mockk`, `every`, `coEvery`, `verify`, `coVerify`) — *or* hand-rolled fakes (preferred for baselines) |
| HTTP | `ktor-client-mock` (KMM-portable) |
| DB | Real KMM-compatible store (SQLDelight `JdbcSqliteDriver(IN_MEMORY)`, ObjectBox-mp) — or a hand-rolled in-memory fake of the public interface |

**Forbidden in baseline tests:**
- Mockito (JVM-only)
- Robolectric (Android-only)
- `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`/`After` (use kotlin.test annotations)
- `androidx.*` test libraries (`androidx.test.*`, `androidx.compose.ui:ui-test-junit4`)
- Truth (`com.google.common.truth.*` — JVM-only)
- `System.currentTimeMillis()`, `java.time.*`, `java.util.Date` (JVM-only — use `kotlinx.datetime`)
- `MainCoroutineRule` or any `@get:Rule` JUnit rule

### Pattern: black-box at the feature surface

Don't write a baseline test for `OrderInteractorImpl`. Write it for
the **feature surface** — the public entry point a real caller uses.
Internal classes (`OrderInteractor`, `MarginUseCase`,
`PlaceOrderUseCaseImpl`) are migration-volatile; the feature surface
isn't.

```kotlin
// BAD: locks in OrderInteractor as a class
@Test fun `OrderInteractor setLot computes margin`() { ... }

// GOOD: tests the observable behavior of "placing an order via the order feature"
@Test
fun `placing a 2-lot NIFTY order with valid margin records a POST to hulk orders`() = runTest {
    val api = RecordingApiClient()
    val feature = OrderFeature.test(api, fixedClock(0L))   // factory constructs whatever internal graph

    feature.setLot(2)
    feature.place()
    advanceUntilIdle()

    assertEquals("https://hulk.test/api/orders", api.lastPostUrl)
    assertEquals(2, api.lastPostBody["lot"])
    // no verify(mock) anywhere
}
```

The `OrderFeature.test(...)` factory is the contract. It can construct
the production graph today and a completely rewritten KMM graph
tomorrow — the test is unchanged because it asserts only on
observables.

### Hand-rolled fakes > mocks for baselines

Mocks (MockK) record *interactions*. Fakes record *state*. For
baselines you want state.

```kotlin
class RecordingApiClient : ApiClient {
    var lastPostUrl: String? = null
    var lastPostBody: Map<String, Any?>? = null
    var nextPostResponse: ApiResponse<*> = ApiResponse(Result.success(Unit), 200)
    val invalidateCalls = mutableListOf<String>()

    override suspend fun <T> post(url: String, body: Map<String, Any?>, ser: KSerializer<T>): ApiResponse<T> {
        lastPostUrl = url
        lastPostBody = body
        @Suppress("UNCHECKED_CAST")
        return nextPostResponse as ApiResponse<T>
    }
    override fun invalidate(url: String) { invalidateCalls += url }
    /* … */
}
```

Test asserts on `lastPostUrl`, `lastPostBody`, `invalidateCalls` —
all observable, all KMM-portable, all survive any internal refactor.

### Snapshot / golden files for complex outputs

When the output is a structured object (DTO, mapped domain model, UI
state, payload), enumerate-every-field assertions are too brittle to
freeze. Use a snapshot:

1. Serialize the output to canonical JSON via `kotlinx.serialization`
   (sorted keys, fixed formatting).
2. Commit the JSON next to the test:
   `<dest>/src/androidUnitTest/.../snapshots/order_payload__nifty_2_lot.json`
3. Test: serialize the output and `assertEquals` against the file
   contents.
4. **Updating the snapshot post-freeze requires a migration
   exception** (see below). Pre-freeze, run the test in
   `UPDATE_SNAPSHOTS=true` mode and review the diff carefully — that
   *is* the spec.

```kotlin
@Test
fun `order payload for 2-lot NIFTY MIS matches snapshot`() = runTest {
    val payload = buildOrderPayload(SCRIP_NIFTY, lot = 2, productType = MIS)
    assertSnapshotEquals("order_payload__nifty_2_lot.json", payload.toCanonicalJson())
}
```

The cost is: a snapshot diff that's hard to read on review. The
benefit is: every field on the payload is implicitly asserted, even
the ones you didn't think of. For a migration safety net, that
trade-off is right.

### Where frozen tests live

Recommended source set: **`<dest>/src/androidUnitTest/`** — the destination module's Android unit-test source set. Baselines start here in Phase B (uniform routing — every in-scope file is relocated to `<dest>/androidMain` first), then promote to **`<dest>/src/commonTest/`** in Phase E for files whose production code reached `commonMain`.

Why `androidUnitTest` as the initial destination:

- It's a superset source set — sees both `commonMain` and `androidMain` code, so it can host baselines for files in either source set.
- The KMM-portable test stack works there fine (it's all JVM).
- When a file's production code promotes to `commonMain` (Phase D), its baseline can be `git mv`'d to `commonTest` mechanically (Phase E) — no rewrite, since the stack was already KMM-portable.

Why not `app/src/baselineTest/` as a separate source set: AGP + KGP interactions make custom Android test source sets painful (AGP rejects custom names; KGP's `setSource` overrides; worktree-aware setup is fiddly). The destination module's existing `androidUnitTest` is already configured — use it.

### Quarantine of unrelated broken tests

Target test source sets often contain pre-existing broken tests unrelated to the current migration — flaky, abandoned, infra-rot. Three bad responses:

- **Fix them.** Out of scope. Dilutes the PR, breaks one-thing-at-a-time discipline.
- **Exclude them individually.** Whack-a-mole.
- **Isolate via a separate test module.** Over-engineering.

**Default response: `@Ignore` quarantine.** Each pre-existing broken test gets `@Ignore` with a one-line reason and a follow-up pointer:

```kotlin
@Test
@Ignore("Times out under emulator; see PR #378 out-of-scope follow-ups")
fun `pre-existing flaky test`() { ... }
```

The PR description includes an **"Out-of-scope follow-ups"** section listing these tests for someone else to pick up.

The quarantine is **non-judgmental** — it does not assert the test is bad, only that fixing it is not this migration's job.

**Flow:** Phase 0 step 8 surfaces broken pre-existing tests in `<dest>/androidUnitTest`. Phase B.2 applies `@Ignore` as its first sub-step, before any baseline is written. Phase E.0 does the same check on `<dest>/commonTest` before baseline promotion. The migration's own new tests are never `@Ignore`'d — only pre-existing unrelated broken ones.

### Freeze enforcement (mechanical + behavioral)

Baseline tests are immutable from the moment migration starts. Three layers of enforcement:

1. **Skill-behavioral (primary).** The kmm-migration skill itself refuses to edit frozen baselines without a corresponding `.kmm/exceptions/<id>.md` file present. This is enforced by the skill's cross-cutting Migration-exception process — see SKILL.md. Since all baseline edits should flow through the skill in practice, this is the main enforcement layer.

2. **Detekt rule (mechanical).** A custom detekt rule that fails on baseline tests importing JVM-stack libraries (Mockito, Truth, Robolectric, etc.) — catches stack-drift even if the rest of the test body looks innocuous. Bootstrapped first-time per repo via Phase C.2.

3. **Reviewer attention (human).** PR review compares the baseline file diff against the frozen-at SHA recorded in `coverage.md`. Any edit without a `[migration-exception <id>]` tag in the commit message + matching exception file is flagged.

No CODEOWNERS dependency. No pre-commit / commit-msg hook (these were dropped — hook setup is fiddly in worktrees, and the skill-behavioral + detekt + reviewer layers cover the same ground).

**Detekt rule** (custom — extend `customRules/` if it exists, or
add it):

**Fail on import of:**
- `org.mockito.*` (Mockito is JVM-only)
- `com.google.common.truth.*` (Truth is JVM-only)
- `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`, `org.junit.After` (JUnit 4 patterns; use `kotlin.test`)
- `androidx.test.*`, `androidx.compose.ui.test.*` (Android-only)
- `org.robolectric.*` (Android-only)
- `java.time.*`, `java.util.Date` (JVM-only — use `kotlinx.datetime`)

**Fail on use of:**
- `@get:Rule`, `@Rule` annotations
- `System.currentTimeMillis()`, `System.nanoTime()`
- `Thread.sleep(...)`
- `MainCoroutineRule` (any class name match)

**Warn on:**
- `verify(` calls (any source)
- `mockk(...)` without `relaxed = false` for baseline tests — relaxed mocks hide design issues

### Migration exception process (required escape valve)

Some migration changes intentionally alter observable behavior:
joda-time → kotlinx-datetime DST handling, JSON serializer key
ordering, error-code remapping. The team will silently relax
assertions to make the build green unless there is a sanctioned
process. Make the process the path of least resistance.

For each behavior change requiring a baseline edit:

1. Open `migration-exception/<YYYY-MM-DD>-<short-id>.md` in the same
   PR as the baseline edit. Required fields:
   - **What changed**: the observable difference.
   - **Why**: rooted in the migration plan (link to spec).
   - **Risk**: who could be affected, how it would surface in prod.
   - **Sign-off**: tech lead approval (file mention or link).
2. The baseline edit references the exception file in its commit
   message: `[migration-exception 2026-05-12-tz-dst]`.
3. The skill itself refuses to edit frozen baselines without the exception file present — that's the primary mechanical check. PR reviewer verifies the exception file exists and the commit message tag matches before approving.

### Pre / during / post checklist

Before starting migration:
- [ ] Frozen baseline tests cover every public feature surface in scope.
- [ ] Each baseline test is verified to go red on a deliberate breakage of the production code (proves the test isn't tautologically green).
- [ ] No baseline test imports Mockito, Truth, Robolectric, `org.junit.runner`, or `androidx.test`.
- [ ] No baseline test contains `verify(`, `@get:Rule`, or `System.currentTimeMillis()`.
- [ ] Detekt rule live (bootstrapped first-time per repo via Phase C.2).
- [ ] Pre-existing broken tests in target source sets quarantined via `@Ignore` with follow-up pointer (per "Quarantine of unrelated broken tests" above).
- [ ] `./gradlew :<dest>:testDebugUnitTest` is green.

During migration:
- [ ] Every PR runs `:<dest>:testDebugUnitTest` (and `:<dest>:commonTest` / `:<dest>:iosSimulatorArm64Test` once any baselines have promoted via Phase E). A red baseline blocks the PR by default.
- [ ] Baseline edits only via the exception process.

Post-migration (per surface, as it lands in `<dest>/commonMain` via Phase D):
- [ ] Frozen baseline tests run against the migrated code unchanged.
- [ ] If any test goes red, decide: is this a real regression (fix the migration) or a sanctioned change (open exception)? Default is real regression.
- [ ] Once a surface is fully migrated and baselines are green, the baseline tests are *moved* (not rewritten) into `<dest>/src/commonTest/` via Phase E. Because they only used KMM-portable APIs, the move is mechanical (`git mv` + adjust package).

---

# Cross-cutting

### Concurrency tests (Constitution III, XIII)

Whenever a class launches its own coroutines or transforms a hot
flow, the test must:

- Use `StandardTestDispatcher` so you can `advanceTimeBy` to specific points.
- Express timing in real durations: `delay(500)` in production → assert at `499` (no emission yet) and `500` (emission happened).
- Never use real wall clock or real `Dispatchers.IO`.
- For `mapLatest` / `conflate` / `debounce`: at least one test that fires twice within the window and asserts only one downstream effect.

### Time

If your code reads `System.currentTimeMillis()`, `Instant.now()`
(java.time), or `LocalDateTime.now()` directly, the test cannot
control it deterministically — and the code won't move to
`commonMain` either. Inject `kotlinx.datetime.Clock`:

```kotlin
class MyUseCase(private val clock: Clock = Clock.System) {
    fun perform() {
        val now = clock.now()  // kotlinx.datetime.Instant
        // ...
    }
}

// in tests:
private var fakeInstant = Instant.fromEpochMilliseconds(0)
private val clock = object : Clock {
    override fun now(): Instant = fakeInstant
}
```

`() -> Long` is acceptable only for platform-agnostic monotonic
timing where the value is opaque (e.g., elapsed milliseconds for a
debounce). For wall-clock decisions, use `kotlinx.datetime.Clock`.

**Do not** mock `Instant.now` via `mockito-inline` — works once,
breaks on the next JDK update, won't move to KMM.

### Logging

Inject a `Logger` (interface), pass `FakeLogger` in tests. Do **not**
assert on log content as a substitute for real assertions — logs are
debug aids, not contract.

### Locale & i18n

JVM `java.util.Locale` is not available in `commonMain`. For code
heading to `:shared`, push locale-sensitive formatting to the
platform layer behind an interface (e.g.,
`interface NumberFormatter { fun format(value: Double): String }`)
with Android and iOS adapters. Tests in `commonTest` use a fake
formatter that returns canonical output.

For JVM-only tests using `String.format`, `BigDecimal.toString`,
or `NumberFormat.format`, force `Locale.US`:

```kotlin
@BeforeTest fun forceLocale() { Locale.setDefault(Locale.US) }
```

### Test fixtures

Put shared fixtures in `app/src/test/.../fixtures/` (or
`<dest>/src/androidUnitTest/.../fixtures/` for baselines) as factory
functions:

```kotlin
fun position(
    isin: String = "INE040A01034",
    productType: ProductType = ProductType.MIS,
    qty: Double = 1.0,
    buy: Double = 100.0,
    sell: Double = 0.0
) = PositionModel(/* … */)
```

Pays back the moment a constructor signature changes.

---

# Verification (before claiming done — Constitution IX)

```bash
./gradlew ktlintCheck detekt
./gradlew :app:testDebugUnitTest          # unit tests
./gradlew :<dest>:testDebugUnitTest        # baseline tests (if migration-relevant)
```

Paste output into the reply. Don't claim "tests pass" without
evidence. If a verification step cannot be run, say so explicitly.

---

# When in doubt

A test you wouldn't trust to catch a real production regression isn't
worth keeping. Delete it and replace with one that would. The bar is
"did this assertion go red on the bug we shipped last quarter?" — if
not, the test is decoration. For baselines, the bar is harder: "would
this go red on the only kind of change the migration could plausibly
introduce — a behavior change?" — if it would *also* go red on a pure
refactor, it's miscalibrated; rewrite it as black-box at the feature
surface.
