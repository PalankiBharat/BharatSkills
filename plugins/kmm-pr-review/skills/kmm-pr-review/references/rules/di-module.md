# DI Module rules (Koin, per team convention)

Loaded for files with `role=di-module`.

Cite as `references/rules/di-module.md#<rule-id>`.

---

### DI-01 — Per-screen objects use `viewModel { }` / `factory { }`, not `single { }`
**Severity:** P1
**Pattern:** `single { MyScreenViewModel(...) }` or `single { MyScopedUseCase(...) }` for objects that should be per-screen.
**Why:** `single` is a singleton — survives across screen lifecycles, retains stale state, leaks coroutine scopes.
**Suggestion:** `viewModel { ... }` for ViewModels (requires `koin-core-viewmodel` or platform equivalent); `factory { ... }` for other screen-scoped objects.
**Source:** https://insert-koin.io/docs/reference/koin-mp/kmp-viewmodel/

### DI-02 — Platform-specific bindings via `expect val platformModule`
**Severity:** P1
**Pattern:** platform-specific wiring done via hand-rolled `expect class` or manual factories instead of Koin's `expect val platformModule: Module`.
**Why:** Canonical KMP DI pattern per JetBrains: declare `expect val platformModule` in common, provide `actual val platformModule` in each platform set.
**Suggestion:** Move platform-specific bindings into the platform module's actual `platformModule`.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html (Dependency injection framework)

### DI-03 — Interfaces bound, not concrete types
**Severity:** P1
**Pattern:** Koin module binds a concrete class directly without going through an interface (`single { MyRepositoryImpl() }`), where a corresponding interface exists.
**Why:** Binding the interface (`single<MyRepository> { MyRepositoryImpl() }`) lets consumers depend on the interface and enables test fakes.
**Suggestion:** `single<MyRepository> { MyRepositoryImpl(get(), get()) }`.
**Source:** https://insert-koin.io/docs/reference/koin-mp/kmp/

### DI-04 — No Hilt annotations (team migrated to Koin)
**Severity:** P1
**Pattern:** `@Inject`, `@Module`, `@Provides`, `@Binds`, `@InstallIn`, `@Singleton` (the Dagger one) annotations in a file under the DI module folder, or on a class in commonMain.
**Why:** Team migrated from Hilt to Koin for KMP compatibility. Mixed DI strategies create wiring confusion.
**Suggestion:** Convert to Koin module declarations.
**Source:** Team convention + https://insert-koin.io/docs/reference/koin-mp/kmp/

### DI-05 — No `get()` parameter resolution that hides dependencies
**Severity:** P2
**Pattern:** Koin module uses `get()` inside the bind block in ways that aren't visible at the class's call site — e.g., `single { MyClass(get(), get(), get(), get()) }` for a class with 6 unrelated dependencies.
**Why:** Heavy `get()` chains make dependencies invisible and create implicit ordering. Reasonable for 2-3 deps; smell beyond that.
**Suggestion:** If the class genuinely needs many dependencies, that's a separate code smell (see `new-file-clean-code.md#nf-clean-08`). Reduce dependencies, group via parameter objects, or split the class.
**Source:** Industry-standard; corroborate with master patterns.
