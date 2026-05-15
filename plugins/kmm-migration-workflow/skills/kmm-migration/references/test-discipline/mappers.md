> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both.

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

