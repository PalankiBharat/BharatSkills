# OOP & Visibility Patterns

**Module-internal plumbing should not be public.**
If a function exists to serve sibling classes in the same module and has no contract with the outside world, exposing it publicly leaks implementation detail and invites misuse.

> Kotlin: `public suspend fun tryGetSettings()` called only from the same module → `internal`

**Prefer composition over inheritance for behavior sharing.**
If a class inherits primarily to reuse method implementations (not to express is-a), flag it. Favour delegation or extension instead.

**Encapsulation: don't expose internal representation.**
Classes should expose what callers need, not how they store it. If a caller reaches into a data structure to compute something the owning class could provide, flag it.
