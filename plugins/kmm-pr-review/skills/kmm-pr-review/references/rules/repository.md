# Repository rules

Loaded for files with `role=repository`.

Cite as `references/rules/repository.md#<rule-id>`.

---

### REPO-01 — Repository defined as interface in commonMain, implemented per layer
**Severity:** P1
**Pattern:** repository defined as a concrete `class` directly in commonMain with platform-specific bodies via expect/actual.
**Why:** Repositories are the canonical case for interface+DI (per `_base.md#s-ea-02`). Interface in commonMain + implementations bound via Koin gives test fakes for free and clean iOS surface.
**Suggestion:** `interface XRepository` in commonMain; `class XRepositoryImpl(...) : XRepository` in commonMain or platform set; bind in Koin.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html + https://insert-koin.io/docs/reference/koin-mp/kmp/

### REPO-02 — Returns `Flow` for streams, `suspend` for one-shot
**Severity:** P1
**Pattern:** repository exposes Rx types (Observable/Single), callbacks, or LiveData.
**Why:** KMP canonical is `Flow` + `suspend`. Other types either don't survive iOS bridging (LiveData) or require additional adapters.
**Suggestion:** `fun observe(): Flow<X>` for streams, `suspend fun get(): X` for one-shot.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-upgrade-app.html

### REPO-03 — No direct Android/iOS platform types in repository interface
**Severity:** P0
**Pattern:** repository interface mentions `Context`, `NSURL`, `Cursor`, `NSManagedObject`, etc.
**Why:** Public API leaks platform; iOS or Android consumer can't use the interface.
**Suggestion:** Map platform types to domain types inside the implementation; expose only domain types on the interface.
**Source:** `_base.md#s-type-01`

### REPO-04 — `suspend` exposed to iOS has `@Throws`
**Severity:** P0
**Pattern:** public `suspend fun` in repository interface, consumed from iOS, without `@Throws`.
**Why:** Same as `_base.md#s-coro-03`.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### REPO-05 — Caching strategy explicit
**Severity:** P2
**Pattern:** repository function name doesn't communicate whether it hits cache, network, or both (e.g., `getX()` could mean any).
**Why:** Ambiguous caching is a recurring source of bugs and platform inconsistencies.
**Suggestion:** Name explicitly (`fetchFromNetwork()`, `getCached()`, `observe()` for cache-then-fresh), or parameterize with a `CachePolicy` enum.
**Source:** Industry-standard; team convention.
