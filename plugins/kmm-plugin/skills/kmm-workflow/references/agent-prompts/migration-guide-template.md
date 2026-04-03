# Migration Guide Template

This file is the template for `migration-guide.md` — the per-file spec created during planning and consumed by agents during execution. One entry per file. Every decision point must be resolved before execution begins. After `/clear`, only this file survives — all chat context is gone.

---

## Template

```markdown
## <FileName.kt>
- Source: <androidApp/src/main/java/.../FileName.kt>
- Target: <shared/src/commonMain/kotlin/.../FileName.kt>
- Classification: <migrate-swap | migrate-expect-actual | platform-stay | delete>
- Public API: <methodA(param: Type): ReturnType, methodB(): Unit, ...>
- Swaps: <AndroidLib Foo → KMM Bar vX.Y.Z, ...>
- Platform APIs: <android.util.Log → Napier (line 12, 34), System.currentTimeMillis() → Clock.System.now().toEpochMilliseconds() (line 57) | none>
- Breaking changes: <Swap X changes constructor from (A, B) to (A, B, C); swap Y changes return type from T to Result<T> | none>
- Callbacks: <onSuccess: (User) -> Unit in login() → wire to LoginViewModel.onLoginSuccess; onError: (Throwable) -> Unit → wire to LoginViewModel.onLoginError | none>
- Expected tests: <N tests — 1 per public method + error paths: login email (success, invalid creds, network error), login phone (success, invalid), logout, isLoggedIn>
- Serialization: <JSON fields: "access_token" (@SerialName("access_token")), "expires_in" (Int, never null), "user" (nullable → default null) | none>
- Decisions: <Retrofit → Ktor: Replace (KMM-native, same suspend API surface); SharedPreferences → MultiplatformSettings: Replace (drop-in wrapper, no API change needed)>
- expect/actual: <none | describe boundary>
- Migrate after: <FileName1.kt, FileName2.kt | none>
- Consumers: <FileA.kt, FileB.kt (update imports after)>
- Rules: <file-specific constraints — DO NOT combine, keep X and Y as SEPARATE methods, etc.>
```

---

## Example Entry

```markdown
## LoginRepository.kt
- Source: androidApp/src/main/java/com/example/auth/LoginRepository.kt
- Target: shared/src/commonMain/kotlin/com/example/auth/LoginRepository.kt
- Classification: migrate-swap
- Public API: login(email: String, pwd: String): Result<User>, login(phone: String): Result<User>, logout(): Unit, isLoggedIn(): Flow<Boolean>
- Swaps: Retrofit Call<T> → suspend fun (Ktor 3.1.0), SharedPreferences → MultiplatformSettings 1.3.0
- Platform APIs: android.util.Log → Napier (lines 23, 47, 61), SharedPreferences → MultiplatformSettings (lines 38–42)
- Breaking changes: Retrofit swap converts login() from callback-based to suspend — callers must be in a coroutine scope; SharedPreferences swap changes constructor to inject Settings instead of Context
- Callbacks: onLoginResult: (Result<User>) -> Unit in login() → wire to LoginViewModel.handleLoginResult; onTokenExpired: () -> Unit → wire to SessionManager.onTokenExpired
- Expected tests: 7 tests — login email (success, wrong password, network error), login phone (success, invalid format), logout (clears prefs), isLoggedIn (emits correct state after login/logout)
- Serialization: JSON fields: "email" (String, never null), "phone" (String, nullable → omit if null), "token" (@SerialName("access_token"), String), "expires_in" (Int, never null)
- Decisions: Retrofit → Ktor: Replace (suspend API is identical surface, no abstraction needed); SharedPreferences → MultiplatformSettings: Replace (wraps NSUserDefaults on iOS transparently, zero consumer changes)
- expect/actual: none
- Migrate after: AuthCredentials.kt, TokenManager.kt
- Consumers: LoginUseCase.kt, LoginViewModel.kt (update imports after)
- Rules: keep login(email, pwd) and login(phone) as SEPARATE methods — DO NOT combine into a single login(credential) overload
```

---

## Field Definitions

- **Source** — absolute path to the Android file being migrated
- **Target** — absolute path to the new commonMain file to create
- **Classification** — one of:
  - `migrate-swap` — all deps have KMM equivalents, no expect/actual needed
  - `migrate-expect-actual` — requires platform-specific implementations
  - `platform-stay` — UI or platform code; gets iOS equivalent, not moved to commonMain
  - `delete` — duplicate or dead code; safe to remove after consumers are updated
- **Public API** — full method signatures the migrator must match exactly; this is the contract
- **Swaps** — exact library replacements with verified versions (not training data guesses)
- **Platform APIs** — every Android-only or JVM-only API occurrence in this file (with line numbers) and its exact commonMain replacement from platform-api-gotchas.md; "none" if no prohibited APIs present
- **Breaking changes** — how each swap changes the visible surface for consumers: constructor signature changes, parameter additions, return type changes, callback → suspend conversions; "none" if no consumer-visible changes
- **Callbacks** — every callback parameter in the file, its parent caller method, and the exact wiring target in consumer code; "none" if the file has no callback parameters
- **Expected tests** — minimum test count with explicit list: 1 test per public method plus error paths for methods that can throw or return Result/Flow; used by the reviewer to fail under-tested migrations
- **Serialization** — wire format requirements if the file touches JSON: exact JSON field names, @SerialName mappings, nullability rules, and default values; "none" if the file has no serialization
- **Decisions** — for each dependency swap, the chosen strategy (Replace / Port / Abstract) and one-line rationale; Replace = drop-in KMM lib, Port = rewrite logic without a lib, Abstract = hide behind expect/actual or interface
- **expect/actual** — describe the boundary if needed; "none" if the file has no platform split
- **Migrate after** — dependency order; the migrator will not start this file until listed files are VERIFY_PASS
- **Consumers** — files whose imports must be updated after migration completes
- **Rules** — file-specific constraints that override general behavior; written to prevent the most common agent mistakes (combining, splitting, renaming)
