# The Seam Model

From Chapter 4 of "Working Effectively with Legacy Code."

## What Is a Seam?

**A seam is a place where you can alter behavior in your program without editing in that place.**

Every seam has an **enabling point** — the place where you choose which behavior to activate.

This is the fundamental concept for getting legacy code under test. If you can find
seams, you can substitute test doubles for real dependencies WITHOUT modifying the
code you're testing.

## Object Seams (Most Useful — Prefer These)

A method call on an object is a seam when you can change which implementation
runs by passing a different object — without editing the calling code.

```kotlin
// Is `repository.findUser(id)` a seam?
class UserService(private val repository: UserRepository) {
    fun getUser(id: String): User {
        return repository.findUser(id) // ← SEAM (object seam)
    }
}
// Enabling point: the constructor parameter
// In tests, pass a FakeUserRepository instead of the real one
```

### When Is It NOT a Seam?

When the object is created AND used in the same method with no way to substitute:

```kotlin
fun processOrder() {
    val validator = CreditValidator() // Created right here
    validator.validate(order)         // No way to substitute
}
// NOT a seam — enabling point doesn't exist
// Fix: Parameterize Constructor → pass validator in
```

### Creating Object Seams

Techniques to create object seams where none exist:
- **Parameterize Constructor** — Pass dependency in instead of creating it internally
- **Extract Interface** — Create an interface, pass fakes in tests
- **Subclass and Override Method** — Override the method that creates/uses the dependency
- **Extract and Override Call** — Extract the problematic call to its own method, override in test subclass

## Link Seams

Swap implementations at build/link time. The enabling point is the build configuration.

**Java/Kotlin**: Use classpath manipulation or DI frameworks (Hilt, Dagger)
**C/C++**: Use different libraries at link time, or different object files

```kotlin
// Hilt provides a link seam via DI
@Module
@InstallIn(SingletonComponent::class)
object TestModule {
    @Provides
    fun provideRepository(): UserRepository = FakeUserRepository()
}
```

## Preprocessing Seams (C/C++ Only)

Use `#ifdef`, `#define`, and `#include` to substitute code at compile time.

```c
#ifdef TESTING
#define db_update(account, item) { last_item = (item); }
#endif
```

The enabling point is the preprocessor define (e.g., `-DTESTING` compiler flag).

## How to Find Seams

1. Look at the code you need to test
2. Identify each external call (database, network, file system, other objects)
3. For each call, ask: "Can I change what runs here WITHOUT editing this method?"
4. If yes → you have a seam. If no → you need to create one.

## Seams in Kotlin/Android

| Dependency | Seam Technique |
|-----------|---------------|
| Retrofit API | Extract Interface → inject fake implementation |
| Room Database | Already uses DAO interfaces → inject in-memory DB |
| SharedPreferences | Extract Interface → inject fake |
| Android Context | Use ApplicationProvider in tests, or extract an interface |
| Singleton/Object | Introduce setter for testing, or use DI |
| System.currentTimeMillis() | Extract to Clock interface → inject fake clock |
| Coroutine Dispatchers | Inject dispatchers → use TestDispatcher in tests |

## Key Principle

When you see code in terms of seams, you can see where to test.
When you can't find a seam, you know you need to create one before you can test.
Object seams are almost always the right choice in object-oriented code.
