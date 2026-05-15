# Bug Detection Patterns

**Logic errors.**
- Off-by-one: loop bounds `< n` vs `<= n`, index `size - 1` vs `size`, `until` vs `..` in ranges.
- Inverted condition: `if (!isValid)` where `if (isValid)` was intended, `>` vs `>=`.
- Wrong operator: `&&` vs `||` in multi-condition guards.

Flag these when the code compiles but the logic appears inconsistent with the surrounding context or the PR description's stated intent.

**Incorrect `.copy()` field assignment.**
Kotlin data class `.copy()` calls that reference the wrong field name (silently copies the old value) or omit a field that should change — flag when the copied field name doesn't match the PR's stated intent.

**Null dereference that compiles but crashes at runtime.**
`map["key"]!!`, `list.first()` on a potentially empty list, `result!!` where null is a realistic return value — flag when the null case is reachable.

**Unchecked empty collection access.**
`list[0]` or `.first()` without a prior `isEmpty()` / `isNotEmpty()` guard — flag.

**Silent data truncation.**
Casting `Long` to `Int`, `Double` to `Float`, or similar narrowing conversions without a range check — flag when the value could realistically overflow.

**Floating-point equality comparison.**
`a == b` where `a` and `b` are `Float` or `Double` — flag. Floating-point arithmetic is imprecise; use `abs(a - b) < epsilon` or a domain-appropriate tolerance check instead.

**TOCTOU (time-of-check time-of-use).**
A value is checked (e.g. `isLoggedIn()`, `cache != null`, `file.exists()`) and then re-fetched or re-accessed after a gap where state could change. Flag when: (1) check and use are separate calls with logic in between, AND (2) a state change during the gap could cause incorrect behaviour that has no safety net (no server-side rejection, no transaction, no lock). Severity: blocker when stale state causes data corruption or a crash; non-blocking when an external guard (API 401, DB constraint) prevents harm. Fix: snapshot the value once and reuse — `val model = fetch(); if (model.isValid()) { use(model) }`.
