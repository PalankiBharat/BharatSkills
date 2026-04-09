# Project Knowledge: Sniper V2

**Repo:** ~/dev/sesame-kmm-project/sniper-v2-android
**Type:** Android app with KMM shared module migration

## SDK & Infrastructure

- **ObjectBox:** No KMM support. Requires Android bridge (androidMain impl) + iOS Swift bridge (iosMain expect/actual). Xcode 16+ breaks ObjectBox due to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — set to `nonisolated` in build settings.
- **Sesame SDK:** Demo app source may differ from published artifact. Verify enums, methods, and types against the actual Maven/CocoaPods artifact — not the demo source (e.g., `SesameState.gender` in demo vs `.personal` in published).
- **WebEngage:** Analytics SDK. Grep for `track(`, `analytics.`, `logEvent(`, `WebEngage` when auditing analytics event coverage during Phase 3.
- **PresenterProvider:** iOS DI access pattern — `PresenterProvider.shared.getMyViewModel()`. This is a KoinComponent bridge specific to this project.

## Architecture

- **RemoteStore:** Infrastructure class used inline in domain/data models (e.g., `RemoteStore(…)` called inside model method bodies). These create silent reattach debt when migrating to commonMain. Flag as "requires DI refactor" during planning.
- **CustomerSupportUseCase / WithdrawalsTopBar:** Example of transitive Koin dependency — UI components (WithdrawalsTopBar) depend on use cases (CustomerSupportUseCase) that aren't direct ViewModel constructor params. Check transitively during Koin binding verification.
- **FundsActivity:** Example of deep callback tracing — `onAddFundsClick()` requires tracing through 3+ composable layers to find the real action handler.

## Backend

- **x-request-token header:** Server expects `x-request-token`, not standard `Authorization` for some endpoints. When migrating from OkHttp to Ktor, verify header names match.
- **platform header:** Staging server returns 500 when the `platform` header is present in certain requests. Use curl bisection to debug API 500s.
- **Session token naming:** `session_token` (not `sessionToken`) in API responses. Case-sensitive after gson→kotlinx.serialization migration.

## Build

- **Gradle task names:** Verify with `./gradlew :shared:tasks --all | grep -i <platform>`. Don't assume — this project uses production flavors (e.g., `compileProductionDebugKotlin` not `compileDebugKotlin`).

## Known Fixes (project-specific)

| Symptom | Fix | Category |
|---------|-----|----------|
| Login API returns 500 on staging | Remove `platform` header — staging server rejects it | ktor |
| ObjectBox crash on Xcode 16+ | Set SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated | ios-build |
| SesameState enum mismatch | Check published artifact, not demo source | interop |
| Analytics events missing after migration | Grep for WebEngage-specific calls, not just generic track() | audit |

## Migration History

<!-- Updated by retrospective after each migration -->
| Module | Status | Skill Version | PR |
|--------|--------|--------------|-----|
