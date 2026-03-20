# Tech Stack Considerations

Stack-specific gotchas and best practices for the default tech stack. Update this file when the tech stack evolves.

## Jetpack Compose considerations
- [ ] Recomposition safety — does the feature cause unnecessary recompositions?
- [ ] State hoisting — is state at the right level?
- [ ] Remember vs rememberSaveable — does state survive config change?
- [ ] LaunchedEffect / DisposableEffect — correct key, cleanup on dispose?
- [ ] derivedStateOf — is it used for expensive computations on state?
- [ ] Lazy list performance — key provided for items? Stable types used?
- [ ] Side effects — are they in the right Compose lifecycle callback?
- [ ] Preview support — is @Preview provided for the new composables?
- [ ] Modifier ordering — does it follow the correct convention?
- [ ] Theme/Material3 — consistent use of design tokens, not hardcoded colors?

## Hilt / Dependency Injection
- [ ] Correct scope for new dependencies (Singleton, ActivityRetained, ViewModelScoped)
- [ ] Are interfaces used for testability? (Repository interface → Impl)
- [ ] Qualifier annotations for multiple implementations of same interface
- [ ] Assisted inject for runtime parameters
- [ ] No direct constructor instantiation of injected classes
- [ ] Component hierarchy — feature module dependencies declared correctly

## Kotlin Coroutines / Flow
- [ ] Correct dispatcher usage (IO for network/db, Default for CPU, Main for UI)
- [ ] Structured concurrency — coroutines tied to proper scope
- [ ] Flow vs StateFlow vs SharedFlow — correct choice for the data pattern
- [ ] combine / zip / flatMapLatest — correct operator for the merge pattern
- [ ] flowOn for upstream dispatcher switching
- [ ] cancellation handling — are resources cleaned up on cancel?
- [ ] Exception handling — CoroutineExceptionHandler in the right place
- [ ] SupervisorJob where child failures shouldn't cancel siblings

## Room Database
- [ ] Migration strategy — auto vs manual migration
- [ ] Index on frequently queried columns
- [ ] Foreign key constraints — cascade behavior defined
- [ ] TypeConverters for complex types (Date, Enum, JSON)
- [ ] Transaction annotation for multi-table operations
- [ ] Query optimization — no N+1 queries, proper JOIN usage
- [ ] Flow return type for observable queries
- [ ] Conflict strategy — REPLACE vs IGNORE vs ABORT

## Retrofit / Network
- [ ] Request/response models — @SerialName for JSON field mapping
- [ ] Nullable vs non-nullable fields match API contract
- [ ] Interceptors — auth token refresh, logging, error mapping
- [ ] Timeout configuration appropriate for the endpoint
- [ ] Multipart / streaming if needed
- [ ] Certificate pinning if required

## Navigation (Compose Navigation)
- [ ] Type-safe navigation arguments
- [ ] Deep link registration for the new screen
- [ ] Back stack behavior — popUpTo, inclusive, launchSingleTop
- [ ] Nested navigation graph if feature is self-contained
- [ ] Result passing between screens (savedStateHandle approach)

## Design patterns to apply
- [ ] MVI/MVVM — consistent with existing patterns in the codebase
- [ ] Command pattern — for undoable actions (order modify/cancel)
- [ ] Strategy pattern — if behavior varies by type (sort, filter, display)
- [ ] Observer pattern — for real-time data updates
- [ ] Repository pattern — single source of truth
- [ ] Mapper pattern — DTO ↔ Entity ↔ UI Model separation

## Output format

```
### Tech stack considerations
- [ ] **[Stack component]**: [Consideration] — Action: [What to do]
```

Only flag considerations that are RELEVANT to the specific feature. Don't dump the entire checklist for every feature.
