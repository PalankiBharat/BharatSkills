# Guardrail Cheat Sheet

- **No type casting.** Never use `as`, `as?`, `as!` in Kotlin or Swift. Use polymorphism, generics, protocol conformance, or `is` checks instead.
- **kotlinx.serialization only.** Never use Gson or Moshi in shared/common code.
- **`sealed interface`, not `sealed class`.** Prefer `sealed interface` for KMM discriminated unions.
- **Ktor only.** Never use Retrofit or OkHttp in `commonMain`. Use Ktor client.
- **Koin 4 only.** Never use Hilt or Dagger in shared code. Use Koin 4 for DI.
- **`kotlinx-datetime` only.** Never use `java.time` or platform date APIs in `commonMain`.
- **`StateFlow` only.** Never use `LiveData` in shared/KMM code.
- **No `runBlocking` on the main thread.** Use structured concurrency; `runBlocking` only in tests or background entry points.
- **`expect`/`actual` for platform-specific code.** Never use `#ifdef`, runtime platform checks, or conditional imports as a substitute.
- **Context-first.** Before modifying any file, read the target, all its dependencies (imports, interfaces, base classes), and all its consumers. Never modify with partial context.
- **Escalate unclear failures — never suppress.** If a build fails and the cause is unclear: stop, present the problem, list options with pros/cons, give a recommendation, wait for the user. Never add no-op stubs or use `--no-verify` / `@Suppress` to force a pass.
- **Completion promise required.** Every agent must emit a completion promise string as its last output. No promise = work not accepted.
- **Tests are immutable after baseline.** Once the orchestrator runs baseline and tests pass, test files must not be modified. If tests fail after migration, fix the migration.
- **API signature parity.** Migrated KMM code must have identical method signatures to Android — same method names, parameter names, parameter order, return types.
- **Always use latest docs.** Use Context7, `/find-docs`, or web search for library APIs, versions, and patterns. Never rely on training data — it may be outdated.
- **Latest stable deps.** When adding new dependencies, check the latest stable version via live docs, not training data.
