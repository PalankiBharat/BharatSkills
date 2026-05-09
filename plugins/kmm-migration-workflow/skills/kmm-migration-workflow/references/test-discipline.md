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

## Clock-bound code without an injection seam

**The structural exception to branch coverage at T-1.** Per Constitution §8's expanded clause (v2.1.0), some classes have a public no-arg constructor whose signature consumers depend on (e.g., `class GreetingUseCaseImpl()`); adding a `Clock` (or `Random`, or `IO`) parameter to enable deterministic tests would break Principle 7's public-API preservation. These classes are **not exhaustively unit-testable on master** — their hidden branches are gated behind a non-deterministic input.

Recognise this case at architect-time, not at T-1. Indicators:

- The class reads `System.currentTimeMillis()`, `Calendar.getInstance()`, `Clock.System.now()`, `Random.Default.nextInt(...)`, or any other process-wide singleton that's not a test seam.
- The class has a no-arg constructor (or a constructor whose parameters are all already-injected dependencies that consumers can't easily reconstruct).
- The architect's clean-code lens detects no place where a constructor parameter could be added without changing public API.

When recognised, the architect emits a LOW-risk Refactor entry that **extracts the pure mapping into an internal helper** the test source set can exercise. Example:

```kotlin
// Before (master) — clock-bound, untestable:
class TimeBoundUseCase {
    fun classify(): Category = when (Clock.System.now().hour) {
        in 0..11 -> Category.Morning
        in 12..16 -> Category.Afternoon
        else -> Category.Evening
    }
}

// After (commonMain) — extract creates the seam:
internal fun classifyHour(hour: Int): Category = when (hour) {
    in 0..11 -> Category.Morning
    in 12..16 -> Category.Afternoon
    else -> Category.Evening
}
class TimeBoundUseCase {
    fun classify(): Category = classifyHour(Clock.System.now().hour)
}
```

**Test capture protocol for this case:**

1. **At T-1** (pre-migration), capture only what IS deterministic on master:
   - Public-API surface invariants (e.g., enum display strings, constructor reflection).
   - A smoke test that exercises the wrapper and asserts the return is in the valid output set (always passes regardless of runtime input — pins the public contract that a value is *some* valid value).
2. **At M-1** (migration), introduce the seam-creating Refactor's behaviour-preservation tests against the new internal helper:
   - Exhaustive coverage over the input space (e.g., parameterised over `0..23`).
   - Boundary-hour tests at every regime change.
3. **Log as a structural deviation** in `migration-report.md`:
   - Title: "Hour-mapping branches not testable pre-migration (R-N's tests introduced at M-N)"
   - Status: `RATIFIED`
   - Closure: `{ type: "manual" }` (the gap is structural, accepted permanently for this scope)
   - Mitigation: cite the LOW-risk classification of the Refactor (mechanical extract; body verbatim) plus the visual diff inspection plus the post-migration exhaustive test.

**Why this is safe:** the migrated form's behaviour-preservation comes from three independent guarantees:
- The Refactor is a mechanical extract — the `when` block body is byte-identical to master's.
- The new exhaustive test runs against the post-migration form and covers the entire input space.
- The architecture-reviewer subagent verifies R-N's `Boundary` field stays inside the in-scope file (Constitution §6).

If all three hold, the structural gap (no master test for hidden branches) is bounded — a behaviour change cannot pass undetected.

**Why this is constitutionally acceptable:** the alternative (forcing a `Clock` parameter into the public API) violates Principle 7's "Public API stays" rule, which is non-negotiable. The choice is "structural test gap with mitigations" vs. "API change", and Principle 7 dominates.

The skill recognises this case automatically when the in-scope file matches the indicators above. The architect proposes the seam-creating Refactor; T-1 captures the deterministic subset; M-1 introduces the exhaustive tests. The structural deviation is logged at architect-phase entry, not discovered mid-T-1.

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
