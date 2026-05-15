# Code Smell Patterns

**Feature Envy — behavior that only touches one type's fields belongs on that type.**
An extension function or utility method that does nothing but arithmetic on another type's own properties is Feature Envy — the logic is in the wrong place.

> Kotlin: `private fun TradingPeriodBars.barCount(): Int = endBar - startBar + 1` defined inside a geometry utility → move to `data class TradingPeriodBars { val barCount: Int get() = endBar - startBar + 1 }`
> Signal: the function touches *only* fields of one type and performs no external logic.

**Long methods — if you need to trace a variable through mutations to understand what a function builds, it's doing too much.**
Signal: function exceeds ~40 lines, OR has 3+ levels of nesting, OR mutates 2+ accumulator variables. Split into named micro-functions. Reach for `generateSequence`, `map`, `fold` instead of mutable loops.

**Magic numbers and strings.**
Bare numeric literals or string literals used as keys/codes without a named constant — flag these. Exempt obvious idioms: `0`, `1`, `-1`, `2` (halving/doubling) in simple arithmetic. Flag anything else where the reader can't know the meaning without context (e.g. `16`, `0.5f`, `1000`, `"key_name"`).

**Duplicate code.**
Identical or near-identical blocks that differ only in a parameter — flag and suggest extracting a shared function.

**Dead code.**
Unreachable branches, unused parameters, commented-out code blocks — flag for removal.
