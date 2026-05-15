# Null Safety Patterns

**Use language idioms for null early-exit.**
A null check + log + return is correct but verbose. Most languages have a compact form that makes the "null = bail" intent clearer at the call site.

> Kotlin: `if (x == null) { log; return }` → `val x = getX() ?: run { log; return }`

**`!!` operator abuse.**
Every `!!` is a potential NullPointerException. Flag `!!` on values that could realistically be null (e.g. results from optional lookups, network responses). Accept `!!` only when null is genuinely impossible and the code can't express that through types.

**Missing null guards on collection access.**
`list[0]`, `map["key"]!!`, `firstOrNull()!!` without prior empty/null check — flag these. Use `firstOrNull()`, `getOrNull()`, or guard with `isEmpty()` first.
