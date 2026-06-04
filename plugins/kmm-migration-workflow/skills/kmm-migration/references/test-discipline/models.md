> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both.

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
- ❌ DTOs with serializer annotations (`@SerializedName`, `@SerialName`) and no logic: library-substitution targets. See `migration-baselines.md` §Library-substitution — almost always Path B (defer to Phase D, write the round-trip test on the migrated `@Serializable` type then).

### Coverage checklist

**Computed properties**
- [ ] Each computed property tested for each input branch.
- [ ] Boundary inputs: zero quantity, zero price, negative PnL.

**Equality / identity**
- [ ] Only test if `equals` is *manually overridden*. Default data class equality doesn't need a test.

**Serialization**
- [ ] If `@Serializable` and used over the wire, a `Json.encodeToString` round-trip test for the field shape the backend cares about. Serializer behavior is a top KMM migration risk — round-trip is the canonical check.
- [ ] **Gson → kotlinx swap?** kotlinx is strict where Gson was lenient — apply `migration-baselines.md` §"Gson → kotlinx.serialization" in full. For this DTO specifically: every server-decoded field nullable-or-defaulted (else `MissingFieldException`), a `decode("{}")` tripwire test, exact wire type kept (no `String`→`Double`/`Long`), and a `@SerialName ↔ @SerializedName` zero-drift diff against master.

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

