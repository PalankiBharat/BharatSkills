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
- Base URL: <vault|hulk|none — which Mystique DNS alias / Retrofit base URL builder this file uses>
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
- Base URL: vault (uses buildVaultApiService)
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
- **Base URL** — which Retrofit base URL builder / Mystique DNS alias this remote store uses (e.g., `vault`, `hulk`, `none`). Migration agents must use the correct base URL when converting Retrofit builders to Ktor — using the wrong base URL causes all API calls to fail silently or return wrong data. `none` for files that don't make API calls.
- **expect/actual** — describe the boundary if needed; "none" if the file has no platform split
- **Migrate after** — dependency order; the migrator will not start this file until listed files are VERIFY_PASS
- **Consumers** — files whose imports must be updated after migration completes
- **Rules** — file-specific constraints that override general behavior; written to prevent the most common agent mistakes (combining, splitting, renaming)
