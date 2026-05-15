# UseCase / Interactor rules

Loaded for files with `role=usecase`.

Cite as `references/rules/usecase.md#<rule-id>`.

---

### UC-01 — UseCase has a single `operator fun invoke`
**Severity:** P1
**Pattern:** UseCase class with multiple public functions, or with non-`invoke` public entry points.
**Why:** UseCase per Clean Architecture represents one cohesive operation. Multiple entry points mean the class is doing more than one thing.
**Suggestion:** Split into multiple UseCases (`GetXUseCase`, `UpdateXUseCase`), or expose one `operator fun invoke` and keep helpers private.
**Source:** Industry-standard Clean Architecture pattern; corroborate with master.

### UC-02 — Dependencies via constructor only
**Severity:** P1
**Pattern:** UseCase that instantiates collaborators directly (`val repo = Repository()` in body) instead of receiving via constructor.
**Why:** Direct instantiation prevents test substitution and short-circuits the DI graph.
**Suggestion:** `class GetXUseCase(private val repo: XRepository)`. Wire via Koin `factory { ... }`.
**Source:** https://insert-koin.io/docs/reference/koin-mp/kmp/

### UC-03 — Returns a sealed result type, not raw exceptions
**Severity:** P1
**Pattern:** UseCase's public function throws exceptions for routine error paths (network failure, validation failure, not-found).
**Why:** UseCases are consumed by ViewModels on both platforms. Exception-based error paths force asymmetric handling on iOS (see `_base.md#s-coro-03` and `s-clean-04`).
**Suggestion:** `sealed interface Result<out T>` with `Success(value: T)` and `Failure(error: DomainError)` variants.
**Source:** `_base.md#s-clean-04`

### UC-04 — `suspend operator fun invoke` annotated with `@Throws` if exposed to iOS
**Severity:** P0
**Pattern:** public `suspend operator fun invoke` in a UseCase consumed from iOS, without `@Throws(...)`.
**Why:** Same as `_base.md#s-coro-03`.
**Source:** https://kotlinlang.org/docs/native-objc-interop.html

### UC-05 — No business logic leak from UseCase to ViewModel
**Severity:** P2
**Pattern:** UseCase delegates to repository without transformation, while ViewModel performs significant business transformations on the result.
**Why:** UseCases should encapsulate business rules. Logic in ViewModels can't be reused across platforms.
**Suggestion:** Move the transformation into the UseCase.
**Source:** Industry-standard Clean Architecture; team convention.
