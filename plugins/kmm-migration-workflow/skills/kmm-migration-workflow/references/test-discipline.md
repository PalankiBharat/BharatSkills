# Test Discipline (Migration Baselines)

Read this before writing or reviewing any baseline test in `commonTest`. Baseline tests must survive migration unchanged and prove behavioral parity, not implementation parity.

## Baselines vs. normal tests

| | Normal test | Migration baseline |
|---|---|---|
| Goal | Catch regressions during ongoing work | Prove migrated code is **behaviorally identical** to pre-migration |
| Editable? | Anyone, any time | **Frozen** post-T-LOCK; sanctioned exceptions only |
| Mock collaborators? | Sometimes | **No mocks** — hand-rolled fakes only |
| `verify(mock).method(...)`? | Sparingly | **No** — observable outputs only |
| Coupling | OK to test implementation | **Forbidden** — only public API |

A baseline that "passes" but couples to internal class shape produces false confidence and breaks for the wrong reason.

## Allowed assertions

- Return values from public methods
- Emitted values from public `Flow`s, `StateFlow`s, `Channel`s
- Recorded HTTP requests on a fake `ApiClient`: URL, method, body, headers
- Database / store rows after the operation, read through the public store API
- Callback invocations on a real listener: count, args
- Exceptions / `Result.failure` types
- Snapshot/golden file comparisons of serialized output

## Denied assertions

- `verify(mock).method(...)` on internal collaborators
- Asserting which class executed the work
- Asserting on dispatcher type, coroutine context, scope identity
- Asserting on log lines, log tags, breadcrumbs
- Asserting on internal field names (private via reflection)
- Asserting on package-qualified names of types in error messages

**Rule of thumb**: if a clean-room re-implementation could pass functional acceptance and still fail your test, the test is implementation-coupled — rewrite it.

## Black-box at the feature surface

Don't write a baseline for an internal use case impl. Write it for the **public entry point** a real caller uses. Internal classes are migration-volatile; the feature surface isn't.

```kotlin
// BAD — locks in OrderInteractor as a class
@Test fun OrderInteractor_setLot_computesMargin() { ... }

// GOOD — tests observable behavior
@Test fun placingTwoLotOrderRecordsPostToOrdersEndpoint() = runTest {
    val api = RecordingApiClient()
    val feature = OrderFeature.test(api, fixedClock(0L))

    feature.setLot(2)
    feature.place()
    advanceUntilIdle()

    assertEquals("https://api.test/orders", api.lastPostUrl)
    assertEquals(2, api.lastPostBody["lot"])
}
```

The `<Feature>.test(...)` factory is the contract.

## Hand-rolled fakes > mocks

Mocks record *interactions*. Fakes record *state*. Baselines need state.

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
}
```

## KMM-portable test stack

| Concern | Use |
|---|---|
| Runner | `kotlin.test` (`@Test`, `assertEquals`, `assertTrue`, `assertFailsWith`) |
| Coroutines | `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, `advanceUntilIdle`, `advanceTimeBy`) |
| Flows | Turbine |
| Mocks | Hand-rolled fakes (preferred); MockK if unavoidable |
| HTTP | `ktor-client-mock` or hand-rolled `RecordingApiClient` |
| Storage | KMM-compatible store, or hand-rolled in-memory fake |

Verify exact versions live (Constitution §4) at planning time; record in `findings.md`.

## Forbidden in baseline tests

- Mockito (JVM-only)
- Robolectric (Android-only)
- `org.junit.*` runners (use `kotlin.test`)
- `androidx.*` test libraries
- `Truth` (use `kotlin.test.assertEquals`)
- Backticked test names — crash on Kotlin/Native; use camelCase
- `Thread.sleep` — use the test scheduler
- Real time / real I/O / real `Dispatchers.IO` — inject

## Branch coverage

Number every `if` / `when` / `?:` / `let`/`run` / early-`return` in the public method. Each numbered branch needs at least one test. Skipping a branch silently moves untested code into `commonMain`.

## Clock-bound code without an injection seam (Constitution §8)

Some classes have a public no-arg constructor consumers depend on; adding a `Clock` parameter would break public-API preservation. These classes are not exhaustively unit-testable on master.

Recognise at architect-time:
- Class reads `System.currentTimeMillis()`, `Calendar.getInstance()`, `Clock.System.now()`, `Random.Default.nextInt(...)`, or process-wide singleton.
- Class has a no-arg constructor (or constructor whose parameters are already-injected).
- No place to add a parameter without changing public API.

The architect emits a LOW-risk Refactor entry that **extracts the pure mapping into an internal helper** the test source set can exercise:

```kotlin
// Before — clock-bound, untestable:
class TimeBoundUseCase {
    fun classify(): Category = when (Clock.System.now().hour) {
        in 0..11 -> Category.Morning
        in 12..16 -> Category.Afternoon
        else -> Category.Evening
    }
}

// After — extract creates the seam:
internal fun classifyHour(hour: Int): Category = when (hour) {
    in 0..11 -> Category.Morning
    in 12..16 -> Category.Afternoon
    else -> Category.Evening
}
class TimeBoundUseCase {
    fun classify(): Category = classifyHour(Clock.System.now().hour)
}
```

**Test capture protocol:**

1. **At T-1**: capture only what IS deterministic on master (public-API surface invariants, smoke test asserting the return is in the valid output set).
2. **At M-1**: introduce the seam-creating Refactor's behaviour-preservation tests against the internal helper (parameterised over the input space, boundary tests at every regime change).
3. **Log as structural deviation** in `migration-report.md` — Title: "Hour-mapping branches not testable pre-migration", Status: `RATIFIED`, Closure: `{ type: "manual" }`.

Behaviour-preservation comes from three independent guarantees: the Refactor is a mechanical extract (body byte-identical to master), the new exhaustive test covers the input space, the architecture-reviewer verifies R-N stays inside the in-scope file. Forcing a `Clock` parameter into the public API would violate §7.

## Boundary values

- Money / quantity: `0`, `1`, max-allowed, max+1, negative
- Strings: empty, blank, unicode, very long
- Collections: empty, single-element, duplicates
- Time: epoch boundary, leap year, DST transition (if relevant)
- Nullables: explicit null where the type allows it

## Verify-red

Before recording a baseline as green, deliberately break the production code in a way the test should detect. Confirm the test reds. Revert. Run again — green.

If the test stays green when production is broken, it asserts on the wrong thing. Rewrite.

The `test-capturer` MUST perform verify-red for every test. The `CAPTURE_COMPLETE` promise is rejected if `verify-red:` is missing or `0`.

## Snapshot files for complex outputs

When output is a structured object (DTO, payload), enumerate-every-field assertions are too brittle:

1. Serialize to canonical JSON (sorted keys, fixed formatting).
2. Commit JSON next to the test: `commonTest/.../snapshots/<test-name>.json`.
3. `assertEquals` against file contents.

Updating a snapshot post-T-LOCK requires a `RATIFIED` deviation.

## Immutable post-T-LOCK

Every file under `commonTest/` is frozen. The completeness-verifier walks `git log` from the locked SHA forward; any commit touching `commonTest/` without a corresponding `RATIFIED` deviation fails verification.

If migration genuinely requires a baseline edit:
1. Subagent escalates as `REQUIRES_APPROVAL`.
2. User approves with rationale.
3. Orchestrator logs `D-N`, status `RATIFIED`.
4. Only then does the test edit happen.

Silently relaxing assertions to make the build green is a §7 violation.

## Pre-migration checklist (before T-LOCK)

- [ ] Frozen baseline tests cover every public method on every in-scope file
- [ ] Branch coverage: every numbered branch has at least one test
- [ ] Boundary-value tests for every input type
- [ ] Each test verify-red proven
- [ ] No baseline imports Mockito, Robolectric, or `org.junit.runner`
- [ ] No baseline contains `verify(mock)`
- [ ] All assertions on the allowed list
- [ ] All test names camelCase
- [ ] All tests pass against the staged `androidMain` source

## Post-migration checklist (verified by `/kmm-verify`)

- [ ] All baseline tests green against migrated `commonMain` code
- [ ] No baseline modified post-T-LOCK without a `RATIFIED` deviation
- [ ] All test files use only KMM-portable libraries
