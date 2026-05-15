> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

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
| Test doubles | **Hand-rolled fakes only — MockK is banned.** A fake implements the dep's interface; stubs return values in `var` properties; records calls in `MutableList`. See "Hand-rolled fakes" section below for the pattern. Forbidding MockK preserves the freeze contract: any test using MockK requires gradle wiring deltas, K/N target adjustments, or version-skew handling to move from `androidUnitTest` to `commonTest` — that's not a frozen test, that's a deferred rewrite. |
| HTTP | `ktor-client-mock` (KMM-portable; an HTTP-level fake, not a mocking framework) |
| DB | Real KMM-compatible store (SQLDelight `JdbcSqliteDriver(IN_MEMORY)`, ObjectBox-mp) — or a hand-rolled in-memory fake of the public interface |

**Forbidden in baseline tests** (`<dest>/androidUnitTest` and `<dest>/commonTest`):
- **MockK** (`io.mockk.*`) — see rationale above. Use hand-rolled fakes.
- Mockito (JVM-only) — `org.mockito.*`, `org.mockito.kotlin.*`.
- Robolectric (Android-only) — `org.robolectric.*`.
- `org.junit.runner.*`, `org.junit.Rule`, `org.junit.Before`/`After` (use kotlin.test annotations).
- `androidx.*` test libraries (`androidx.test.*`, `androidx.compose.ui:ui-test-junit4`).
- Truth (`com.google.common.truth.*` — JVM-only).
- `System.currentTimeMillis()`, `java.time.*`, `java.util.Date` (JVM-only — use `kotlinx.datetime`).
- `MainCoroutineRule` or any `@get:Rule` JUnit rule.

Mechanical enforcement: the detekt rule bootstrapped in Phase C.2 fails the build on any of these imports/usages in baseline source sets.

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

### Hand-rolled fakes (mandatory; the ONLY allowed test double for baselines)

Mocks record *interactions*. Fakes record *state*. For baselines you
want state — and you want a test double that can move to `commonTest`
with zero edits. Hand-rolled fakes are the only test double allowed
in baseline source sets (per the table above).

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

Baseline tests are immutable from the moment migration starts. **Four** layers of enforcement:

1. **Hook (primary, mechanical).** The `frozen_baseline_guard` PreToolUse hook blocks any write to a baseline in status `frozen`/`migrated`/`promoted` unless a `.kmm/exceptions/*.md` references it. Configured in the plugin's `hooks/hooks.json`. This is now the strongest layer — silent bypass is impossible at the tool-call layer.

2. **Skill-behavioral.** The kmm-migration skill itself refuses to edit frozen baselines without a corresponding `.kmm/exceptions/<id>.md` file — the rule the hook enforces. Skill behavior + hook are belt-and-braces.

3. **Detekt rule (mechanical).** A custom detekt rule that fails on baseline tests importing JVM-stack libraries (Mockito, Truth, Robolectric, etc.) AND on MockK imports — catches stack-drift even if the rest of the test body looks innocuous. Bootstrapped first-time per repo via Phase C.2.

4. **Reviewer attention (human).** PR review compares the baseline file diff against the frozen-at SHA recorded in `coverage.md`. Any edit without a `[migration-exception <id>]` tag in the commit message + matching exception file is flagged.

No CODEOWNERS dependency. No pre-commit / commit-msg hook (these were dropped — hook setup is fiddly in worktrees, and the layers above cover the same ground).

**Detekt rule** (custom — extend `customRules/` if it exists, or
add it):

**Fail on import of:**
- `io.mockk.*` (MockK — baselines must use hand-rolled fakes; see "Fakes vs mocks — when?" in `index.md`)
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
- `mockk<`, `mockk(`, `every {`, `coEvery {`, `verify {`, `coVerify {` (MockK API surface)

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

