# Test file rules

Loaded for files with `role=test`.

Cite as `references/rules/test.md#<rule-id>`.

---

### T-01 — Shared behavior tested in `commonTest`, not platform-only tests
**Severity:** P1
**Pattern:** behavior in commonMain tested only in `androidUnitTest` or `iosTest`, not in `commonTest`.
**Why:** Shared code runs everywhere; tests should run everywhere. A commonTest test runs on all platforms, validating behavior parity.
**Suggestion:** Move portable tests to `commonTest` using `kotlin.test`. Keep platform-only tests for things that genuinely need platform APIs.
**Source:** https://kotlinlang.org/api/core/kotlin-test/

### T-02 — Use `runTest` (not `runBlocking`) for suspend tests
**Severity:** P2
**Pattern:** suspend function tests use `runBlocking { ... }`.
**Why:** `runTest` skips real `delay()`, handles uncaught exceptions, integrates with `TestDispatcher`. Faster and more deterministic.
**Suggestion:** `import kotlinx.coroutines.test.runTest; @Test fun myTest() = runTest { ... }`.
**Source:** https://github.com/Kotlin/kotlinx.coroutines/tree/master/kotlinx-coroutines-test

### T-03 — Mocking framework JVM-only → keep test platform-specific
**Severity:** P1
**Pattern:** `commonTest` uses Mockito, MockK with JVM-only artifacts, Robolectric, or other JVM-only test infrastructure.
**Why:** commonTest compiles for all platforms. Mockito/Robolectric require JVM. Will fail to build for iOS targets.
**Suggestion:** Use a multiplatform mocking library (MockK has KMP support — verify version), use hand-written test doubles in commonTest, or keep the test in `androidUnitTest`.
**Source:** Library docs — verify the specific mocking library's KMP support before suggesting.

### T-04 — Flow tested with Turbine
**Severity:** P2
**Pattern:** Flow tests manually collect into a list and assert, instead of using Turbine's `test { awaitItem() }` pattern.
**Why:** Turbine handles timeouts, cancellation, and per-emission assertions cleanly. Manual collection is verbose and easy to get wrong.
**Suggestion:** `myFlow.test { assertEquals(expected, awaitItem()); awaitComplete() }`.
**Source:** https://github.com/cashapp/turbine

### T-05 — One assertion focus per test
**Severity:** P2
**Pattern:** new test with many unrelated assertions across multiple system states.
**Why:** Tests that fail with "one of these 8 things broke" are slower to diagnose than focused tests.
**Suggestion:** Split into separate `@Test` functions per scenario.
**Source:** Industry-standard.
