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

### Skip rules (when no baseline is written)

Not every in-scope file gets a baseline. The skip rules below are the canonical list — refer here from per-type files rather than re-deriving.

| Rule | Detail | Source |
|---|---|---|
| Pure data class | `data class Foo(val x: Int)` with no logic, no computed properties, no overridden `equals`/`hashCode`. Round-trip-by-copy isn't a test. | `models.md` |
| Pure interface | `interface XRepository { ... }` / `interface XUseCase { ... }` with no default impls, no `companion object` logic. Coverage transitive through `*Impl`. | `repositories.md`, `usecases.md` |
| Pure-factory UseCase impl | Impl just constructs and returns a domain object; private-vals not assertable; no branching, no side effects. Coverage transitive through returned object's baseline. | `usecases.md` |
| `lib-swap: path-b` deferral | SUT exposes lib-specific types (Retrofit exception in public Result, `@SerializedName` IS the contract). Baseline deferred to Phase D — see §Library-substitution below. | this file, Phase A audit |
| Static-service-locator deferral | SUT calls non-injectable static deps (e.g., `UserModel.getUcc()`). Baseline deferred to Phase D after the inject-the-collaborator refactor. Tracked in `phase-d-followups.md`. | Phase B |
| Pre-existing broken test (not in scope) | `@Ignore`'d in B.2 / E.0. Not the migration's job. | this file §Quarantine |

Skipped rows flip `coverage.md` status `relocated` → `audited` directly with `baseline-deferred-to-phase-d` (for the deferral rules) or no baseline path (for the pure-* rules).

### Library-substitution targets (Retrofit→Ktor, Joda→kotlinx-datetime, Gson→kotlinx.serialization)

A SUT migrated alongside a library swap gets classified during Phase A audit. **Default Path A**; Path B only when Path A is impossible.

**Path A — contract baseline (default).** SUT output is assertable without referencing the old-lib types. Write the baseline against parsed model / returned DTO using MockWebServer or a hand-rolled HTTP fake (no Retrofit imports), against the SUT's date-string output (no Joda imports), or against round-tripped objects (no Gson imports). The baseline survives the swap unchanged because it never touched the swapped surface.

```kotlin
// GOOD — Path A. Asserts on SUT output; HTTP layer is contract-faked.
class ReportRemoteStoreTest {
    private val mockWebServer = MockWebServer()
    private val sut = ReportRemoteStoreImpl(baseUrl = mockWebServer.url("/").toString())

    @Test
    fun `getReports parses ISO dates correctly`() = runTest {
        mockWebServer.enqueue(MockResponse().setBody("""[{"date":"2026-05-19","amount":100}]"""))
        val out = sut.getReports().getOrThrow()
        assertEquals(LocalDate(2026, 5, 19), out[0].date)
        assertEquals(100, out[0].amount)
    }
}
```

**Path B — defer to Phase D (fallback only).** SUT public surface unavoidably exposes old-lib types — e.g., a RemoteStore method returning `Result<T, retrofit2.HttpException>` to callers, or a DTO whose contract IS its `@SerializedName`-annotated wire format. Phase A audit marks the row `lib-swap: path-b`. Phase B writes a `phase-d-followups.md` entry (Source row / Reason / Proposed action / Status: open) and skips the baseline. Phase D writes the baseline against the migrated impl, runs it red against pre-migration code as an inverted equivalence check, then flips green post-swap.

```kotlin
// BAD for Path A — couples baseline to Retrofit. Defer to Phase D instead.
@Test
fun `getReports returns HttpException on 500`() = runTest {
    // ...
    val failure = sut.getReports().exceptionOrNull()
    assertIs<retrofit2.HttpException>(failure)  // ← can't survive Retrofit removal
}
```

**Decision rule**: if a baseline can be written that compiles unchanged before and after the lib swap → Path A. Only otherwise → Path B. Bias hard toward A — most lib swaps don't expose swapped types in the public surface.

### Gson → kotlinx.serialization: preserve every leniency at migration time

**Root cause (memorize this).** Gson is lenient by default in five ways; kotlinx.serialization is strict by default in all five. Every serialization bug in a migration is the swap silently dropping one of Gson's tolerances. Fix each **at migration time in the DTO/config**, not reactively in prod — reproducing the old leniency is **equivalence-preserving, not an improvement** (Principle #1). Source of truth is **pre-migration master**; it's the only thing that encodes the real wire contract.

1. **One shared lenient `Json`** — `isLenient = true` + `coerceInputValues = true` + `ignoreUnknownKeys = true` + `explicitNulls = false`, on the **single** API `Json` instance every decoder uses. `isLenient` is what reproduces Gson's number↔string coercion (BE sends `amount: 183.0`; a `String`-typed field decodes only under `isLenient` — otherwise `JsonDecodingException`, an actual prod bug this caught). **Never create ad-hoc `Json {}` instances** that drift from it. The repo's shared-Json object name is a `project.md` fact (`networking.json_config`).
2. **Every server-decoded DTO field is nullable or defaulted.** Gson sets an absent field to null/default; kotlinx throws `MissingFieldException` unless the field has `?` or `= default`. **`isLenient`/`coerceInputValues` do NOT help here — only `?` / `= default` does.** Tripwire: a `decode("{}")` test per response DTO.
3. **Keep master's exact wire type — no opportunistic `String`→`Double`/`Long` "upgrades."** A migration is behavior-preserving; a type refactor is a separate PR with its own BE verification (someone "improving" `MinimumFunds`/`validUpto` types here broke an edge payload and forced `.toString()` round-trips on consumers). Reinforces Phase D's verbatim-old-behavior pre-flight.
4. **Diff every `@SerialName` against master's `@SerializedName` — zero drift required.** A wrong/missing key doesn't crash; the field reads as its default **forever**. No lenient config and no round-trip test catches it — the scariest class precisely because it's invisible. Make the field-by-field diff a Phase D gate for every migrated DTO.
5. **Never swallow a decode/parse failure.** An empty `onFailure {}` / empty `catch` turns a strict-decode error into a silent failure (a prior session: an infinite status-poll, invisible for the full timeout). Log/surface it — a strict-decode bug must be loud, not a silent loop.
6. **Golden/snapshot inputs must be real BE payloads** — captured numeric amounts, missing fields, edge shapes — not hand-written clean JSON. The clean-shape gap is exactly what ships these bugs past the snapshot (see "Snapshot / golden files" below).

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

**For a decode golden, the JSON fixture must be a real captured BE payload** — actual numeric amounts, missing fields, edge shapes — not a hand-written clean object. A clean-shape fixture is exactly what lets a strict-decode bug ship past the snapshot (see "Gson → kotlinx.serialization" above, trap 6).

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

**Quarantine is for *unrelated, pre-existing* breakage only.** A test that is in this migration's scope, or that breaks *because of* the migration, gets a **root-cause fix — never a quarantine** (no bandages). Quarantine applies solely to breakage that pre-dates and is unrelated to the migration.

**Run-broken vs compile-broken (different mechanics):**
- **Run-broken** (compiles, fails at runtime): `@Ignore` as above.
- **Compile-broken** (references removed types — won't compile to reach `@Ignore`, so `@Ignore` is useless): exclude at the **build level** (e.g., gradle `KotlinCompile.exclude` for the file). This is a committed change that widens the PR diff — **list every excluded file in the PR out-of-scope follow-ups**. Accepted and reviewable; there's no clean way to exclude a compile-broken test without a committed change.

**Flow:** Phase 0 step 8 surfaces broken pre-existing tests. Phase B.2 quarantines them as its first sub-step, before any baseline is written — in **`<dest>/androidUnitTest`** (relocate-first path) or **`:app/src/test/`** (baseline-in-place path; the source module inherits the same need). Phase E.0 does the same check on `<dest>/commonTest` before baseline promotion. The migration's own new tests are never quarantined — only pre-existing unrelated broken ones.

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

1. Open `.kmm/exceptions/<YYYY-MM-DD>-<short-id>.md` in the same
   PR as the baseline edit. Required fields:
   - **What changed**: the observable difference.
   - **Why**: rooted in the migration plan (link to spec).
   - **Risk**: who could be affected, how it would surface in prod.
   - **Sign-off**: tech lead approval (file mention or link).
   - **Authorizes**: explicit scope of what this exception unblocks. Three sub-lists, each required (use `none` if nothing applies):
     - `behavior-change`: short prose describing the observable behavior shift this exception sanctions.
     - `baseline-edit`: list of test file paths whose assertions need adjustment under this exception, or `none`. **The `frozen_baseline_guard` hook keys off this list** — only files listed here may be edited despite being `frozen` / `migrated` / `promoted`.
     - `frozen-source-edit`: list of production file paths that need touch-up despite being frozen, or `none`. Hook keys off this list for source-file edits.
   - **Amendments** (append-only history; populated only when the exception is later extended):
     ```
     - <YYYY-MM-DD>: Extended `Authorizes.baseline-edit` to also cover <file list>. Reason: <rationale>. Sign-off: <user>.
     ```
2. The baseline edit references the exception file in its commit
   message: `[migration-exception 2026-05-12-tz-dst]`.
3. The skill itself refuses to edit frozen baselines without the exception file present **and the target file listed under `Authorizes.baseline-edit`** — that's the primary mechanical check (enforced by the `frozen_baseline_guard` hook). PR reviewer verifies the exception file exists, the commit message tag matches, and the edit scope matches `Authorizes` before approving.

**Extending an existing exception.** When the same phase's exception needs to cover additional files (e.g., E.0b portability scope grew during E.4), append to the existing exception's `Authorizes.baseline-edit` list and add an entry to the `Amendments` section above. Extensions are user-curated: they pass through the same `.kmm/project.md`-style diff-confirm gate (skill drafts the append, user accepts/edits/rejects). Append-only history preserves the audit trail in a single file per phase concern, rather than fragmenting into N exception files for what is really one expanding scope.

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

