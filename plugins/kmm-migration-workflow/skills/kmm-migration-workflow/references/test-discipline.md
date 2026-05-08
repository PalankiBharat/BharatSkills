# Test Discipline (Migration Baselines)

Read this before writing or reviewing any baseline test in `commonTest`. Every rule exists to ensure baseline tests survive migration unchanged and prove behavioral parity, not implementation parity.

## Why baselines are different from normal tests

| | Normal test | Migration baseline test |
|---|---|---|
| Goal | Catch regressions during ongoing work | Prove migrated code is **behaviorally identical** to pre-migration |
| Editable? | Anyone, any time | **Frozen** post-`T-LOCK`; only sanctioned exceptions can edit |
| Mock collaborators? | Sometimes (mock framework) | **No mocks** — hand-rolled fakes only |
| `verify(mock).method(...)`? | Yes, sparingly | **No** — observable outputs only |
| Coupling | OK to test implementation specifics | **Forbidden** — only public API |

A baseline test that "passes" but couples to internal class shape is worse than no test: it produces false confidence and breaks during the migration for the wrong reason.

## Allowed assertions (these survive migration)

- Return values from public methods
- Emitted values from public `Flow`s, `StateFlow`s, `Channel`s
- Recorded HTTP requests on a fake `ApiClient`: URL string, HTTP method, body bytes / parsed JSON, headers
- Database / store rows after the operation, read through the public store API
- Callback invocations on a real listener interface: count, args
- Exceptions thrown / `Result.failure` types
- Snapshot/golden file comparisons of serialized output

## Denied assertions (these break across the migration — reject during review)

- `verify(mock).method(...)` on internal collaborators — migration may replace, split, or rename the collaborator while preserving behavior
- Asserting which class executed the work
- Asserting on dispatcher type, coroutine context, scope identity
- Asserting on log lines, log tags, breadcrumbs
- Asserting on internal field names (anything `private` accessed via reflection)
- Asserting on package-qualified names of types in error messages

**Rule of thumb**: if a clean-room re-implementation could pass functional acceptance and still fail your test, the test is implementation-coupled — rewrite it.

## Black-box at the feature surface

Don't write a baseline test for an internal use case impl. Write it for the **public entry point** a real caller uses. Internal classes are migration-volatile; the feature surface isn't.

```kotlin
// BAD — locks in OrderInteractor as a class
@Test fun OrderInteractor_setLot_computesMargin() { ... }

// GOOD — tests observable behavior of "placing an order via the order feature"
@Test fun placingTwoLotOrderRecordsPostToOrdersEndpoint() = runTest {
    val api = RecordingApiClient()
    val feature = OrderFeature.test(api, fixedClock(0L))   // factory wraps internal graph

    feature.setLot(2)
    feature.place()
    advanceUntilIdle()

    assertEquals("https://api.test/orders", api.lastPostUrl)
    assertEquals(2, api.lastPostBody["lot"])
    // no verify(mock) anywhere
}
```

The `<Feature>.test(...)` factory is the contract. It can construct the production graph today and a rewritten KMM graph tomorrow — the test is unchanged because it asserts only on observables.

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

Tests assert on `lastPostUrl`, `lastPostBody`, `invalidateCalls`. All observable, all KMM-portable, all survive any internal refactor.

## KMM-portable test stack (mandatory)

Every baseline test uses ONLY these:

| Concern | Use |
|---|---|
| Runner | `kotlin.test` (`@Test`, `assertEquals`, `assertTrue`, `assertFailsWith`) |
| Coroutines | `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`, `advanceUntilIdle`, `advanceTimeBy`) |
| Flows | Turbine — assert on `Flow` emissions deterministically |
| Mocks | **Hand-rolled fakes (preferred)** — or MockK if mocking is unavoidable |
| HTTP | `ktor-client-mock` (when not using a hand-rolled `RecordingApiClient`) |
| Storage | KMM-compatible store, or a hand-rolled in-memory fake of the public interface |

Verify exact versions live (Constitution §3) at planning time; record in `findings.md`. Never rely on training data for versions.

## Forbidden in baseline tests

- Mockito (JVM-only)
- Robolectric (Android-only)
- `org.junit.*` runners (use `kotlin.test`)
- `androidx.*` test libraries
- `Truth` (JVM-only — use `kotlin.test.assertEquals`)
- Backticked test names (` `` ... `` `) — crash on Kotlin/Native; use camelCase
- `Thread.sleep` — use the test scheduler
- Real time / real I/O / real `Dispatchers.IO` — inject

## Branch coverage requirement

Eyeball the public method before writing tests. Number every `if` / `when` / `?:` / `let`/`run` / early-`return`. Each numbered branch needs at least one test that exercises it.

Per Constitution §7 — "exhaustive tests on the pre-migration source of truth — every case, every edge case." Skipping a branch silently moves untested code into `commonMain`.

## Boundary values (mandatory)

- Money / quantity: `0`, `1`, max-allowed, max+1, negative
- Strings: empty, blank (whitespace), unicode, very long
- Collections: empty, single-element, duplicates
- Time: epoch boundary, leap year, DST transition (if relevant)
- Nullables: explicit null where the type allows it

## Tests fail for the right reason (verify-red)

Before recording a baseline test as green, deliberately break the production code in a way the test should detect. Confirm the test reds. Revert the breakage. Run again — green.

This proves the test isn't tautologically green. If the test stays green when production is broken, it asserts on the wrong thing. Rewrite.

The `test-capturer` subagent must perform this verify-red step for every test it writes. The subagent's `CAPTURE_COMPLETE` promise is rejected by the orchestrator if the verify-red step was skipped.

## Snapshot / golden files for complex outputs

When the output is a structured object (DTO, mapped domain model, payload), enumerate-every-field assertions are too brittle to freeze. Use a snapshot:

1. Serialize output to canonical JSON (sorted keys, fixed formatting)
2. Commit JSON next to the test: `shared/src/commonTest/.../snapshots/<test-name>.json`
3. Test: serialize the output and `assertEquals` against the file contents

Updating a snapshot post-`T-LOCK` requires a deviation in `migration-report.md` (status: `RATIFIED`) — same as any other baseline edit.

## Immutable post-`T-LOCK`

After `T-LOCK`, every file under `commonTest/` is frozen. The completeness-verifier (`/kmm-verify`) walks `git log` from the locked SHA forward; any commit that touches a `commonTest/` file without a corresponding `RATIFIED` deviation in `migration-report.md` fails verification.

If migration genuinely requires a baseline edit (e.g., the migration changes observable behavior intentionally per a user-approved deviation):

1. The orchestrator escalates as `REQUIRES_APPROVAL` to the user.
2. User approves the change with rationale.
3. Orchestrator logs a deviation: numbered ID, status `RATIFIED`, root cause, replacement path.
4. Only then does the migrator (or test-capturer in remediation mode) edit the test.

Silently relaxing assertions to make the build green is a Constitution §7 violation.

## Pre-migration checklist (before `T-LOCK`)

- [ ] Frozen baseline tests cover every public method on every in-scope file
- [ ] Branch coverage: every numbered branch has at least one test
- [ ] Boundary-value tests for every input type
- [ ] Each test is verify-red — proven to red on a deliberate breakage
- [ ] No baseline test imports Mockito, Robolectric, or `org.junit.runner`
- [ ] No baseline test contains `verify(mock)`
- [ ] All assertions are on the allowed list above
- [ ] All test names are camelCase (no backtick names)
- [ ] All tests pass against the staged `androidMain` source

## During-migration checklist

- [ ] Every migrate task re-runs the file's baseline tests against the migrated `commonMain` code
- [ ] Any baseline edit goes through the deviation process — never silent
- [ ] Snapshot updates require a `RATIFIED` deviation entry

## Post-migration checklist (verified by `/kmm-verify`)

- [ ] All baseline tests green against migrated `commonMain` code
- [ ] No baseline test modified post-`T-LOCK` without a corresponding deviation
- [ ] All test files use only KMM-portable libraries (no Mockito, Robolectric, etc.)
