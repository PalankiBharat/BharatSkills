
# Test Discipline

This reference is the source of truth for **how** to write tests in
Android/Kotlin codebases that are either already on a KMM journey
or expect to be. A test that "passes" but does not exercise the
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

## How this reference is loaded (read first)

This reference is split. **Always loaded** when test code is touched:
`index.md` (this file) — Toolbox, decision matrices, cross-cutting
rules, file-level skeletons, Verification gates, When-in-doubt.

**Loaded on demand** per file type — only when the current task
actually touches that type. The per-type files are siblings in this
directory:

| File type | Reference file | When to load |
|---|---|---|
| ViewModel | `viewmodels.md` | Baseline / audit for a ViewModel SUT |
| UseCase | `usecases.md` | Baseline / audit for a UseCase SUT |
| Repository | `repositories.md` | Baseline / audit for a Repository SUT |
| RemoteStore | `remote-stores.md` | Baseline / audit for a RemoteStore SUT |
| LocalStore | `local-stores.md` | Baseline / audit for a LocalStore SUT |
| Mapper | `mappers.md` | Baseline / audit for a Mapper SUT |
| Model | `models.md` | Baseline / audit for a Model SUT |
| Interactor | `interactors.md` | Baseline / audit for an Interactor SUT |
| Presenter | `presenters.md` | Baseline / audit for a Presenter SUT |
| Composable / Page | `composables-pages.md` | UI testing in scope this session |
| Worker / Receiver / Service | `workers-receivers-services.md` | Any of these in scope |
| Migration baseline tests (§12) | `migration-baselines.md` | **Always load in Phase B** — defines baseline-test rules + denylist + feature-surface pattern |

**Discipline.** Load only the per-type files for file types actually
in scope this session (per `scope.md` Phase 0 classification). A
session that migrates a ViewModel and a Repository loads `index.md`
+ `viewmodels.md` + `repositories.md` + `migration-baselines.md` —
not the rest. **The skill's "Read-many = subagent-mediated" rule
applies here too:** if multiple per-type files need consulting for a
batch decision, dispatch a Haiku/Sonnet subagent that consumes them
and returns a synthesis, rather than pulling all per-type files into
main context.

---

## How to use this reference (per SUT)

1. Identify the file type being tested. If it doesn't fit cleanly,
   say so to the user and ask before proceeding.
2. **Load the matching per-type file** from the table above. If
   already loaded this session, skip.
3. Pick the right protocol — **normal test** or **migration baseline
   test** (decision matrix below). They have different rules; mixing
   them produces tests that lock in implementation details and break
   on the migration.
4. **Pick the right stack from the start** — if the SUT is in or
   near the migration's blast radius, default to the KMM-portable
   stack (kotlin.test + MockK + Turbine). The JVM stack (JUnit 4 +
   Mockito + Truth) is reserved for code confirmed staying in
   `app/`. See Toolbox for the decision.
5. Follow the per-type file's checklist exhaustively. Each unchecked
   box is a real-world bug class going un-asserted.
6. Use the per-type file's template as scaffolding. Don't invent a
   fourth way of structuring tests in this codebase.
7. Before claiming done, run the gates in the **Verification**
   section (this file, near the end) and paste output. Constitution
   IX is non-negotiable.

### Pre-flight: verify anchors before quoting

This reference cites real files when used in-project (e.g.,
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
| Test doubles | **Hand-rolled fakes — mandatory for any test landing in `<dest>/androidUnitTest` or `<dest>/commonTest`** (i.e., every baseline test). A fake is a Kotlin class implementing the dep's interface, storing stubbed return values in plain properties and recording calls in plain lists. No external mocking library. See `migration-baselines.md` → "Hand-rolled fakes" and the file-level skeleton in this file. **MockK is banned in baseline source sets** — even though it claims K/MP support, in practice the JVM-only → KMM transition produces gradle wiring deltas, Kotlin/Native target friction, and version-skew gotchas that break the freeze contract (a test that requires *any* edit to move from `androidUnitTest` to `commonTest` is not frozen). |
| Flow assertions | Turbine 1.2.1 (`flow.test { … }`) |
| Coroutine control | `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, `advanceUntilIdle`, `advanceTimeBy`) |
| `Dispatchers.Main` swap | `Dispatchers.setMain(testDispatcher)` in `@BeforeTest`, `Dispatchers.resetMain()` in `@AfterTest` — **not** `MainCoroutineRule` (JUnit `@get:Rule` doesn't exist in `commonTest`) |
| Time | `kotlinx.datetime.Clock` (inject) |
| HTTP fakes | `ktor-client-mock` (an HTTP-level fake, not a mocking framework) for Ktor RemoteStores; hand-rolled `Recording*` fakes when serializer types make `ktor-client-mock` setup ugly. |
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

### Fakes vs mocks — when?

**Default for KMM-portable / baseline-bound code: hand-rolled fakes.**
For any SUT that is, or plausibly will be, in the migration's blast
radius — UseCases, Repositories, RemoteStores, LocalStores, Mappers,
domain Models, Interactors, Presenters, and any ViewModel built on
`androidx.lifecycle.ViewModel` (KMP-compatible) — every test
dependency is a hand-rolled fake implementing the dep's interface.
No MockK, no Mockito. The freeze contract demands that the test
move from `<dest>/androidUnitTest` to `<dest>/commonTest` with a
pure `git mv`; any test that requires gradle wiring tweaks, K/N
target adjustments, or library-version negotiation at the boundary
isn't frozen.

The fake pattern is consistent and cheap:

```kotlin
class FakeFundsApi : FundsApi {
    // Stubbed return values — set by the test before exercising the SUT.
    var fundsResult: Result<List<FundDto>> = Result.success(emptyList())

    // Recorded calls — assert on these in tests instead of `verify { }`.
    val getFundsCalls = mutableListOf<UserId>()

    override suspend fun getFunds(userId: UserId): Result<List<FundDto>> {
        getFundsCalls += userId
        return fundsResult
    }
}
```

Each fake lives next to its tests under `<dest>/androidUnitTest`
(promoted with the tests in Phase E to `<dest>/commonTest` if all
consumers migrated). Reusable across multiple tests of multiple
SUTs that share the dep.

**Mockito + JUnit 4 only when**: the SUT is permanently Android —
`Activity`, `Fragment`, `Composable` page, `Service`,
`BroadcastReceiver`, `Worker`, or anything that tightly binds to
the Android framework (`Context`, `View`, `LifecycleOwner`). These
tests stay in `:app/src/test/`; they don't promote to `commonTest`,
so the rewrite-at-boundary argument doesn't apply.

**MockK** — banned in `<dest>/androidUnitTest` and `<dest>/commonTest`
(enforced by detekt per Phase C.2). Permitted only in `:app/src/test/`
for tests of permanently-Android SUTs, and even there fakes are
preferred for consistency.

**Never mix mocking libraries with fakes in one test file.** Pick
the fake approach when you start; baselines stay fake-only.

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
7. **Fake at the boundary, not the subject.** A `UseCaseTest` fakes *its* dependencies (hand-rolled fakes by default — see Toolbox); it does not fake the use case it is testing. Constitution V: "Never mock what you're testing."
8. **Negative paths are mandatory.** Every section's checklist includes them. Skipping them fails review.
9. **Tests must fail for the right reason.** When you write a new test, run it once *before* the production change to confirm it reds for the intended cause. For bug-fix tests this is non-negotiable (Constitution V) — no failing-first proof ⇒ fix not accepted.
10. **No `@Ignore` without a tracked TODO** referencing a ticket and a concrete unblocking condition.
11. **Do not assert on log output, internal `_state` field names, or `private` properties.** Assert on the public API and observable side effects only.
12. **`sut` ("subject under test")** is the project convention for the field name. Stay consistent.
13. **Pick the test stack at file creation time.** Don't write a JVM-only test for migration-bound code "and rewrite later." Migration deadlines slip, rewrites get skipped.

### File-level skeleton — primary (KMM-portable, fakes-only)

Use for any SUT in or near the migration's blast radius. Every dependency is a hand-rolled fake; no mocking library imports.

```kotlin
package com.example.<mirrored.path>

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

// Fakes live next to the test (or in a shared <package>/fakes/ folder
// when shared across multiple SUT tests). Pattern: implement the dep's
// interface; stubbed return values in `var`s; recorded calls in `val`
// MutableLists. No external library.
class FakeDep1 : Dep1 {
    var fooResult: FooValue = FooValue.DEFAULT
    val fooCalls = mutableListOf<Unit>()
    override fun foo(): FooValue {
        fooCalls += Unit
        return fooResult
    }
}

class FakeDep2 : Dep2 {
    var barResult: Result<BarValue> = Result.success(BarValue.DEFAULT)
    val barCalls = mutableListOf<Unit>()
    override suspend fun bar(): Result<BarValue> {
        barCalls += Unit
        return barResult
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class <Subject>Test {

    private val testDispatcher = StandardTestDispatcher()

    private val dep1 = FakeDep1()
    private val dep2 = FakeDep2()

    private lateinit var sut: <Subject>

    @BeforeTest
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        // Per-test setup of stubbed values goes in the test bodies under
        // // Given — keep `setup` minimal.
        sut = <Subject>(dep1, dep2, testDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `<descriptive sentence>`() = runTest {
        // Given
        dep1.fooResult = FOO_VALUE
        dep2.barResult = Result.success(BAR_VALUE)

        // When
        sut.execute()
        advanceUntilIdle()

        // Then
        // Assert on recorded calls instead of verify { } / coVerify { }.
        assertEquals(1, dep2.barCalls.size)
        // kotlin.test: (expected, actual) order — opposite of Truth!
        assertEquals(EXPECTED_STATE, sut.state.value)
    }
}
```

**Reusable fakes.** When a fake is shared across multiple test files
(common for Repository, Api, Clock, NumberFormatter), put it in a
`fakes/` package under the same source set as the tests. Promote
alongside the tests in Phase E.

**Recording arguments.** If a call takes meaningful arguments, store
them in the recorded-calls list:

```kotlin
data class GetFundsCall(val userId: UserId, val cursor: String?)
val getFundsCalls = mutableListOf<GetFundsCall>()
override suspend fun getFunds(userId: UserId, cursor: String?) = ...
  .also { getFundsCalls += GetFundsCall(userId, cursor) }
```

Then assert in the test: `assertEquals(USER_ID, dep.getFundsCalls.single().userId)`.

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

# Cross-cutting topics (concurrency, time, logging, locale, fixtures)

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
