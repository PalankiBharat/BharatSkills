# kmm-workflow v4.0

A self-contained KMM migration orchestrator built around one rule: **1:1 MECHANICAL PORT**. Only Android-to-KMM specifics change. Any behavioral change requires explicit user approval.

The key design: two-phase context separation. Phase 1 (planning) is context-heavy — read everything, resolve all decisions, write four output files. After user approves, `/clear` resets context. Phase 2 (execution) is lean — agents consume migration-guide.md entries (~100 tokens each) and execute with zero improvisation.

---

## Part 1: How to Use This Skill

### Starting a New Migration

```
1. /kmm-workflow                    ← always ask: Create or Continue?
2. Pick "Create"                    ← enter module name, base branch, describe goal
3. Answer questions one at a time   ← all decisions captured in files
4. Review plan files                ← approve or adjust
5. /clear                           ← reset context
6. /kmm-workflow → pick Continue    ← fresh context loads plan files
```

Planning produces four files in `~/dev/gameplans/<name>/`:
- `PLAN.md` — phases, status block, rules
- `PROGRESS.md` — empty checkboxes for every task (filled during execution)
- `migration-guide.md` — per-file migration spec (agents consume this, never re-read source)
- `findings.md` — known fixes, gotchas, verified library versions

A Sonnet agent also writes Appium test specs + fake server config to `e2e-tests/` during planning.

---

### Resuming After a Break (same session)

Just keep working. Hooks auto-inject PLAN.md status on every message.

If context feels stale: read PLAN.md + PROGRESS.md manually to re-orient, then continue.

---

### Resuming in a New Session

```
/kmm-workflow → pick Continue → pick gameplan from list
```

Hooks auto-load plan state on the first message. The orchestrator reads PROGRESS.md, finds the last checkpoint commit, and continues from there.

---

### After a Crash / Disconnect

Same as a new session.

```
/kmm-workflow → pick Continue → pick gameplan from list
```

The orchestrator:
1. Reads PROGRESS.md to find last confirmed state
2. Runs `git diff --stat` to see what was written before the crash
3. Re-dispatches only agents whose completion promise was never confirmed
4. Does not re-read source files or re-assess anything already decided

---

### During Debugging

The debug loop runs within the current session — no `/clear` needed.

Each fix cycle: uninstall → install → launch → capture logs → user reproduces → analyze → fix → verify.

After fix confirmed: orchestrator updates PROGRESS.md and continues.

If the debug loop runs many iterations and context becomes heavy:
```
/clear
/kmm-workflow → pick Continue → pick gameplan from list
```
Hooks restore state from PROGRESS.md. Execution continues from the last checkpoint.

---

### Between Android and iOS

Android and iOS are distinct phases, always in this order:

```
/kmm-workflow → pick Continue → pick the same gameplan → fresh context for iOS
```

Fresh context for iOS work. `migration-guide.md` already has iOS screen specs from planning.

---

### When Done

- All phases in PROGRESS.md marked `[x]`
- Final commit: Appium tests in `e2e-tests/` (regression suite for CI)
- `findings.md` saved — reusable for the next migration (known fixes, gotchas, verified versions)
- `PLAN.md` and `migration-guide.md` can be deleted or kept for reference

---

## Part 2: Sample Workflow — Login Module Migration

This shows the full two-phase flow for a Login module with 6 files to migrate.

### Phase 1: Planning

The orchestrator enters planning mode (read-only, all decisions resolved upfront).

**Step 1: Discover and classify files**

Haiku agents grep for Login-related files. Orchestrator classifies each:

```
LoginRepository.kt  → migrate-swap  (Retrofit → Ktor)
LoginApi.kt         → migrate-swap  (Retrofit → Ktor)
SessionStore.kt     → migrate-swap  (SharedPreferences → MultiplatformSettings)
TokenManager.kt     → migrate-pure  (no platform deps)
LoginUseCase.kt     → migrate-pure  (no platform deps)
AuthCredentials.kt  → migrate-pure  (no platform deps)
LoginViewModel.kt   → platform-stay (Android ViewModel + Compose state)
LoginScreen.kt      → platform-stay (iOS screen needed)
```

Orchestrator presents classification table, waits for user confirmation.

**Step 2: Write migration-guide.md**

One entry per file. Example entry:

```markdown
## LoginRepository.kt
- Source: androidApp/src/main/java/com/acme/login/LoginRepository.kt
- Target: shared/src/commonMain/kotlin/com/acme/login/LoginRepository.kt
- Classification: migrate-swap
- Public API:
  - login(email: String, pwd: String): Result<User>
  - logout(): Unit
  - isLoggedIn(): Flow<Boolean>
- Library swaps: Retrofit Call<T> → suspend fun (Ktor 3.1.0)
- API endpoints: POST /api/auth/login, DELETE /api/auth/session
- expect/actual: none
- Migrate after: AuthCredentials.kt, TokenManager.kt
- Consumers: LoginUseCase.kt, LoginViewModel.kt (update imports after)
- Rules: keep login(email) and login(phone) as SEPARATE methods — DO NOT combine
```

**Step 3: Write PLAN.md, PROGRESS.md, findings.md**

PLAN.md STATUS block (first 15 lines — injected by hooks on every message):

```
<!-- STATUS: 1:1 MECHANICAL PORT | Phase 0 of 5 | Setup | planning -->
<!-- NEXT: Task 0.1 — Baseline build verification -->
<!-- VERIFY: ./gradlew :shared:test :app:assembleDebug -->
<!-- CHECKPOINT: none yet -->
## KMM Migration: login
## Rules (always in scope)
- 1:1 MECHANICAL PORT: only Android→KMM specifics change, any behavioral change → REQUIRES_APPROVAL
- Agents return completion promises — no promise = not accepted
- Haiku verifier after every migration — VERIFY_PASS required before continuing
- 3-platform build at every checkpoint
- Escalate after 3 failures, never suppress errors
- migration-guide.md = per-file spec | findings.md = known fixes + research
```

PROGRESS.md (created with empty checkboxes during planning):

```markdown
## Phase 1: Domain
[ ] AuthCredentials.kt
[ ] TokenManager.kt
[ ] LoginUseCase.kt
[ ] Checkpoint 1

## Phase 2: Network/Storage
[ ] LoginRepository.kt
[ ] LoginApi.kt
[ ] SessionStore.kt
[ ] Checkpoint 2

## Wire Android
[ ] Update imports in LoginViewModel.kt
[ ] Update Koin DI module
[ ] Delete original Android files
[ ] Android build + test
[ ] Runtime verify (mobile-mcp)
[ ] Appium flow tests
[ ] Summary Table
[ ] Manual test
[ ] Checkpoint Android

## Wire iOS
[ ] LoginScreen.swift (SwiftUI)
[ ] Wire Koin iOS module
[ ] Wire SKIE StateFlow observations
[ ] iOS build (xcodebuild)
[ ] Runtime verify (mobile-mcp simulator)
[ ] Appium flow tests (iOS)
[ ] Summary Table
[ ] Manual test
[ ] Checkpoint iOS
```

**Step 4: Dispatch Sonnet agent for Appium specs**

The agent records the API endpoints from migration-guide.md and writes:
- `e2e-tests/fake-server-config.json` — deterministic responses for all endpoints
- `e2e-tests/login-flow.test.js` — Appium tests for login, logout, session restore flows

**Step 5: Present plan to user**

```
Planning complete. 5 phases, 8 files.
Phase 1: Domain layer (3 files — pure)
Phase 2: Network/Storage (3 files — library swaps)
Wire Android: imports, DI, delete originals, build + test
Wire iOS: LoginScreen.swift, Koin iOS, SKIE
Final verify: regression suite committed

Review PLAN.md and migration-guide.md. Approve?
```

After user approves:

```
Planning complete. Run /clear then paste:

/kmm-workflow execute ~/dev/gameplans/login-20260326/
```

---

### Context Reset

User runs `/clear`. Chat history is gone. Only the four files in `~/dev/gameplans/login-20260326/` survive.

User pastes: `/kmm-workflow execute ~/dev/gameplans/login-20260326/`

Orchestrator wakes up. Hooks inject PLAN.md status. Orchestrator reads PROGRESS.md — all checkboxes empty — and starts Phase 1.

---

### Phase 2: Execute — Domain Layer

**Migrate → Verify loop for AuthCredentials.kt:**

```
Orchestrator dispatches Sonnet migrator agent:
  "Migrate AuthCredentials.kt per migration-guide.md entry. 1:1 mechanical port."

Agent returns:
  MIGRATION_COMPLETE: com.acme.login.AuthCredentials | swaps: [] | expect-actual: []

Orchestrator dispatches Haiku verifier agent:
  "Diff migrated vs original. Check: API surface match, no logic added/removed."

Verifier returns:
  VERIFY_PASS: AuthCredentials.kt | methods: 3/3 match | behavioral: identical
```

Same loop for TokenManager.kt and LoginUseCase.kt (parallelized — no shared deps).

**After all three pass:**

```bash
./gradlew :shared:testDebugUnitTest

BUILD SUCCESSFUL in 14s
12 tests passed, 0 failed
```

PROGRESS.md updated:
```
[x] AuthCredentials.kt — VERIFY_PASS, migrated
[x] TokenManager.kt — VERIFY_PASS, migrated
[x] LoginUseCase.kt — VERIFY_PASS, migrated
[x] Checkpoint 1 — abc1234
```

---

### Phase 2: Execute — Network/Storage Layer

Same migrate → verify → test loop. LoginApi.kt requires a library swap (Retrofit → Ktor 3.1.0).

**REQUIRES_APPROVAL scenario:**

During migration of LoginApi.kt, the migrator notices the Android code has two methods — `loginWithEmail()` and `loginWithPhone()` — that share 90% identical logic. The migration-guide.md entry says "keep as SEPARATE methods — DO NOT combine". No decision needed — the spec is clear.

But suppose migration-guide.md had NOT specified this. The migrator would stop and present:

```
REQUIRES_APPROVAL: LoginApi.kt

Problem: loginWithEmail() and loginWithPhone() share identical logic. I could
combine them into login(identifier: String) or keep them separate.

Options:
1. Keep separate (two methods)
   - Matches Android source exactly
   - Callers need no changes
   - More code, some duplication
   - Long-term: clear intent, easy to diverge behavior later

2. Combine into login(identifier: String)
   - Less code
   - Callers must change (LoginUseCase.kt, LoginViewModel.kt)
   - Long-term: ambiguous intent, harder to add email-vs-phone specific logic

Recommended: Option 1 (keep separate). 1:1 mechanical port — the Android source
has two methods and we should too. Combining is an improvement, not a port.

Waiting for user choice.
```

---

### Debug Loop Example

Phase 2 re-test fails:

```
> Task :shared:testDebugUnitTest FAILED

LoginApiTest > test_login_success FAILED
java.lang.AssertionError: expected 200 but was 0
```

Orchestrator checks findings.md Known Fixes table — no match.

Orchestrator invokes debugger.md structured loop:

**Step 1 — INSTRUMENT:**
```kotlin
// Added to LoginApi.kt
Napier.d("[DebugLoginApi] login called, endpoint: $endpoint")
Napier.d("[DebugLoginApi] response status: ${response.status.value}")
```

**Step 2 — CAPTURE (Android):**
```bash
adb uninstall com.acme.app
./gradlew :app:installDebug
adb logcat -c
adb logcat -s "DebugLoginApi"
```

**Step 3 — WAIT:** Tells user "Reproduce the login flow, then say done."

**Step 4 — ANALYZE:** Logs show response status is 0 — the Ktor client is not sending the Content-Type header required by the fake server.

**Step 5 — ROOT CAUSE:** Ktor 3.1.0 does not auto-set Content-Type for POST bodies without explicit configuration.

**Step 6 — FIX (minimal, 1:1 rule applies):**
```kotlin
// Added to Ktor client config in LoginApi.kt
install(ContentNegotiation) { json() }
```

**Step 7 — VERIFY:** Rebuild, reinstall, re-capture. Status is 200. Test passes.

**Step 8 — Record in findings.md:**
```
| Ktor POST returns status 0 | Content-Type not auto-set in Ktor 4.0.0 | Add ContentNegotiation { json() } to client | ktor |
```

Remove Napier instrumentation. PROGRESS.md updated.

---

### Wire Android Phase

After all shared phases pass:

1. Sonnet agent updates imports in LoginViewModel.kt (androidApp → shared)
2. Sonnet agent updates Koin DI module
3. Grep-before-delete: verify no remaining usages, then delete original Android files
4. Android build + full test suite
5. Runtime verify via mobile-mcp:

```
mobile_uninstall_app
mobile_install_app
mobile_launch_app
mobile_take_screenshot  ← Login screen
mobile_list_elements_on_screen  ← verify email field, password field, login button
mobile_click_on_screen_at_coordinates  ← tap login button
mobile_take_screenshot  ← verify navigation to home screen
```

6. Appium flow tests (fake server):

```bash
# Start fake server
node e2e-tests/fake-server.js

# Run login flow tests
npx appium-runner e2e-tests/login-flow.test.js --platform android

# All 3 flows pass: login success, login failure, session restore
```

7. Summary Table:

```
| File | Promised | Achieved | VERIFY | Notes |
|------|---------|---------|--------|-------|
| LoginRepository.kt | login(email), login(phone) separate | login(email), login(phone) separate | VERIFY_PASS | — |
| LoginApi.kt | Retrofit→Ktor 3.1.0 | Ktor 3.1.0 + ContentNegotiation fix | VERIFY_PASS | known fix applied |
| SessionStore.kt | SharedPreferences→MultiplatformSettings | MultiplatformSettings 1.3.0 | VERIFY_PASS | — |
```

8. Manual test: user tests against real backend. Bug found → debug loop → fix → retest.

9. Commit: `feat(login): Android wiring complete — shared module migration`

---

### Wire iOS Phase

After Android commits, fresh `/clear`:

```
/kmm-workflow execute ~/dev/gameplans/login-20260326/
```

Orchestrator reads PROGRESS.md — Android phase complete, iOS phase next.

1. Sonnet agent writes LoginScreen.swift per migration-guide.md iOS spec
2. Wire Koin iOS module (register shared dependencies)
3. Wire SKIE StateFlow observations in SwiftUI
4. Register new files in pbxproj
5. iOS build: `xcodebuild -scheme App -sdk iphonesimulator`
6. Runtime verify on simulator via mobile-mcp — screenshots saved to `e2e-tests/screenshots/ios/`
7. Parity check: compare iOS screenshots against Android screenshots from Wire Android phase
8. Appium flow tests adapted for iOS selectors
9. Summary Table (compare Android vs iOS)
10. Manual test on iOS simulator
11. Commit: `feat(login): iOS wiring complete — SwiftUI screen + SKIE observations`

---

### Done

```
All phases complete:
[x] Phase 1: Domain — abc1234
[x] Phase 2: Network/Storage — def5678
[x] Wire Android — ghi9012
[x] Wire iOS — jkl3456

Regression suite committed to e2e-tests/
findings.md ready for next migration
```

Appium tests in `e2e-tests/` run on CI for every PR touching shared code.
