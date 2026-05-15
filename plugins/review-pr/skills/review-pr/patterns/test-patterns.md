# Test Pattern Anti-Patterns

**`@Test(expected = ...)` is unreliable inside coroutine test runners.**
The coroutine framework wraps exceptions before they reach JUnit, so the annotation may never see the thrown type and the test silently passes. Use `assertFailsWith<SomeException> { ... }` inside the coroutine block instead.

> Kotlin: `@Test(expected = FirebaseFirestoreException::class) fun test() = runTest { ... }` 
> → `@Test fun test() = runTest { assertFailsWith<FirebaseFirestoreException> { ... } }`

**Shared setup called in every test → `@Before`.**
If `wireUccAndLiveModeChainTo(settingsDocRef)` or similar setup calls appear at the top of every test method, move to a `@Before setUp()` method. Repeated setup code means a single change requires updating every test.

**Test names should describe the scenario and expected outcome.**
`testGetSettings()` tells you nothing. `tryGetSettings returns null when firestore offline with UNAVAILABLE code` tells you everything. Flag generic test names.

**Use assertion libraries for readable failures.**
`assertTrue(result != null)` gives a useless failure message. `assertThat(result).isNotNull()` (Truth) or `assertNotNull(result)` gives context. Flag bare `assertTrue`/`assertFalse` where richer assertions exist.
