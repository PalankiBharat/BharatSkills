# Naming Patterns

**Generic adjectives are not variable names.**
`current`, `prev`, `next`, `temp`, `result` name position or role, not the thing itself. The reader has to remember what `current` *is* every time they see it.

> Kotlin: `val current = firestoreDataSource.getSettings()` → `val settings = ...`

**`try` prefix on a function signals nullable return — check its visibility.**
If `tryGetX()` is only called within the same module, it should not be public.

**Names should describe WHY or intent, not HOW or mechanism.**
If a name describes what the code does mechanically rather than what it means in the domain, flag it.
