# SOLID Principles

**Single Responsibility Principle.**
A class or function should have one reason to change. Flag classes that own multiple unrelated concerns (e.g. a ViewModel that also handles data parsing, file I/O, and navigation).

**Open/Closed Principle.**
Code should be open for extension, closed for modification. Flag switch/when blocks that need modification every time a new type is added — suggest a polymorphic approach instead.

**Liskov Substitution Principle.**
Subtypes must be substitutable for their base types. Flag overrides that throw exceptions the base doesn't declare, or that narrow preconditions/widen postconditions.

> Kotlin example: a base `Repository.get(id: String)` that returns nullable — if an override throws `UnsupportedOperationException` instead of returning null, any caller that expects null-on-miss will crash.

**Interface Segregation Principle.**
No client should depend on methods it doesn't use. Flag interfaces with many methods where callers only use a subset — split into focused interfaces.

**Dependency Inversion Principle.**
High-level modules should not depend on low-level modules; both should depend on abstractions. Flag direct instantiation (`val repo = UserRepositoryImpl()`) inside classes that should receive dependencies via constructor injection.
