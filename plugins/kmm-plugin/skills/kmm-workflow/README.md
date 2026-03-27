# kmm-workflow v2.0

A self-contained KMM migration orchestrator that drives multi-file Android-to-shared migrations through a strict state machine (ASSESS → PLAN → EXECUTE → VERIFY → RUNTIME → MANUAL TEST → DONE). The key innovation is that the orchestrator never touches migration code directly — it dispatches Haiku agents for cheap discovery, Sonnet agents for TDD and migration work, enforces completion promise strings before accepting any agent output, and uses Claude hooks to auto-inject plan state on every message so sessions survive disconnects without losing context.

---

## Sample Workflow: Login Module Migration

### Phase A: Assess

The orchestrator dispatches Haiku agents in parallel to discover files, then classifies each one.

**Step 1 — Haiku discovery agents (parallel, background):**

Agent 1 prompt: `Grep for "Login" in androidApp/src. Return file paths only. No explanation.`

Agent 2 prompt: `Grep for "Session|Token" in androidApp/src. Return file paths only. No explanation.`

Agent 3 prompt: `Grep for "LoginViewModel|LoginRepository" in androidApp/src. Return file paths only. No explanation.`

Returns (all three finish ~simultaneously):

```
Agent 1:
androidApp/src/main/java/com/acme/login/LoginRepository.kt
androidApp/src/main/java/com/acme/login/LoginApi.kt
androidApp/src/main/java/com/acme/login/LoginUseCase.kt
androidApp/src/main/java/com/acme/login/ui/LoginScreen.kt

Agent 2:
androidApp/src/main/java/com/acme/login/SessionStore.kt
androidApp/src/main/java/com/acme/login/TokenManager.kt
androidApp/src/main/java/com/acme/auth/AuthCredentials.kt

Agent 3:
androidApp/src/main/java/com/acme/login/LoginViewModel.kt
androidApp/src/main/java/com/acme/login/ui/LoginScreen.kt  (duplicate — deduplicated)
```

**Step 2 — Haiku classification agents (parallel, background), one per file:**

Each agent receives the file contents and returns a single classification line.

```
LoginRepository.kt  -> migrate-pure
LoginApi.kt         -> migrate-swap  (Retrofit -> ktor-client)
SessionStore.kt     -> migrate-swap  (SharedPreferences -> multiplatform-settings)
TokenManager.kt     -> migrate-pure
LoginUseCase.kt     -> migrate-pure
AuthCredentials.kt  -> migrate-pure
LoginViewModel.kt   -> platform-stay (uses Android ViewModel, Compose state)
LoginScreen.kt      -> platform-stay (Compose UI)
```

**Step 3 — Orchestrator presents classification table and confirms with user:**

```
Discovered 8 files in the Login module. Proposed classification:

File                    | Classification          | Notes
------------------------|-------------------------|----------------------------------
LoginRepository.kt      | migrate-pure            | no platform deps
LoginApi.kt             | migrate-swap            | Retrofit -> ktor-client
SessionStore.kt         | migrate-swap            | SharedPreferences -> multiplatform-settings
TokenManager.kt         | migrate-pure            | no platform deps
LoginUseCase.kt         | migrate-pure            | no platform deps
AuthCredentials.kt      | migrate-pure            | no platform deps
LoginViewModel.kt       | platform-stay           | Android ViewModel + Compose state
LoginScreen.kt          | platform-stay           | Compose UI

Migration order (bottom-up): AuthCredentials -> TokenManager -> LoginRepository ->
  LoginApi -> SessionStore -> LoginUseCase -> (LoginViewModel, LoginScreen stay)

Does this look right? Any files missing or misclassified?
```

---

### Phase B: Plan

After user confirms, the orchestrator writes three planning files and waits for approval.

**FINDINGS.md (abbreviated):**

```markdown
# FINDINGS: Login Module

## File Table
| File               | Classification  | Migration Phase |
|--------------------|-----------------|-----------------|
| AuthCredentials.kt | migrate-pure    | Phase 1         |
| TokenManager.kt    | migrate-pure    | Phase 1         |
| LoginRepository.kt | migrate-pure    | Phase 1         |
| LoginApi.kt        | migrate-swap    | Phase 2         |
| SessionStore.kt    | migrate-swap    | Phase 2         |
| LoginUseCase.kt    | migrate-pure    | Phase 3         |
| LoginViewModel.kt  | platform-stay   | Phase 4         |
| LoginScreen.kt     | platform-stay   | Phase 4         |

## Dependency Map (selected entries)
- LoginUseCase -> LoginRepository, LoginApi, SessionStore
- LoginRepository -> AuthCredentials, TokenManager
- LoginApi -> AuthCredentials

## Known Fixes
| Symptom                                      | Fix                                                  |
|----------------------------------------------|------------------------------------------------------|
| Gradle: Could not resolve ktor-client-okhttp | Add `resolutionStrategy.force "io.ktor:..."` in app  |
| ksp not found in commonMain                  | Move ksp() to androidMain sourceSet in build.gradle  |
```

**PLAN.md STATUS block (first 15 lines — what hooks inject on every message):**

```
STATUS: EXECUTE Phase 1
MODULE: :feature:login
PHASES: 4
DONE: 0/4
CHECKPOINT: none yet
PLAN_DIR: .claude/gameplans/login-20241015-143200
PROGRESS: .claude/gameplans/login-20241015-143200/PROGRESS.md
FINDINGS: .claude/gameplans/login-20241015-143200/FINDINGS.md
---
Phase 1: Domain layer (AuthCredentials, TokenManager, LoginRepository) — migrate-pure, Full Batched
Phase 2: API + Storage (LoginApi, SessionStore) — migrate-swap, Full Batched
Phase 3: Use case (LoginUseCase) — migrate-pure, Simplified
Phase 4: Platform screens (LoginViewModel, LoginScreen) — platform-stay, SwiftUI
---
```

**Orchestrator approval prompt:**

```
Plan ready. 4 phases, 8 files total.
Phase 1: 3 pure domain files (Full Batched, TDD enforced)
Phase 2: 2 swap files with lib deps (Full Batched, TDD enforced)
Phase 3: 1 use case (Simplified, no intra-phase deps)
Phase 4: 2 platform-stay files (SwiftUI screens)

Approve to start execution?
```

---

### Phase C: Execute

#### Phase 1 — Domain Layer (Full Batched Mode)

Three files with internal deps: `AuthCredentials.kt`, `TokenManager.kt`, `LoginRepository.kt`.
`LoginRepository` depends on the other two, so Full Batched mode is required.

**Step 1: Dispatch 3 parallel Sonnet test-writing agents (background):**

The orchestrator reads `references/agent-prompts/test-writer.md` and constructs each prompt. Example for `LoginRepository.kt`:

```
You are a KMM test-writing agent. Do NOT write migration code. Do NOT run Gradle.

TASK: Write characterization tests for:
  androidApp/src/main/java/com/acme/login/LoginRepository.kt

TARGET TEST FILE:
  shared/src/commonTest/kotlin/com/acme/login/LoginRepositoryTest.kt

GUARDRAILS (from references/guardrail-cheatsheet.md):
- Tests go in commonTest, not androidTest
- Use kotlin.test, not JUnit
- Mock only external boundaries (LoginApi, SessionStore)
- Do not import android.* in commonTest
- Cover the happy path + at least one error path per public function

COMPLETION PROMISE (required — last line of your output):
  TDD_COMPLETE: com.acme.login.LoginRepository | tests: LoginRepositoryTest.kt | count: N
```

All 3 agents run in parallel. Returns:

```
Agent 1: TDD_COMPLETE: com.acme.login.AuthCredentials | tests: AuthCredentialsTest.kt | count: 4
Agent 2: TDD_COMPLETE: com.acme.login.TokenManager | tests: TokenManagerTest.kt | count: 6
Agent 3: TDD_COMPLETE: com.acme.login.LoginRepository | tests: LoginRepositoryTest.kt | count: 8
```

All 3 returned valid promises. Orchestrator advances.

**Step 2: Orchestrator runs baseline:**

```bash
./gradlew :shared:testDebugUnitTest

> Task :shared:testDebugUnitTest
AuthCredentialsTest > test_credentials_serialization PASSED
AuthCredentialsTest > test_empty_username_rejected PASSED
TokenManagerTest > test_token_stored PASSED
...
LoginRepositoryTest > test_login_success PASSED
LoginRepositoryTest > test_login_network_error PASSED
...

BUILD SUCCESSFUL in 14s
18 tests passed, 0 failed
```

Baseline green. Orchestrator advances to migration.

**Step 3: Dispatch 3 parallel Sonnet migration agents (background):**

Example prompt for `LoginRepository.kt`:

```
You are a KMM migration agent. Do NOT run Gradle. Do NOT modify test files.

TASK: Migrate to commonMain:
  FROM: androidApp/src/main/java/com/acme/login/LoginRepository.kt
  TO:   shared/src/commonMain/kotlin/com/acme/login/LoginRepository.kt

DEPS ALREADY MIGRATED: AuthCredentials.kt, TokenManager.kt (check commonMain)

GUARDRAILS (from references/guardrail-cheatsheet.md):
- Remove android.* imports
- Use kotlinx.coroutines.flow.Flow (not LiveData)
- Update package to com.acme.login (shared)
- Do not add expect/actual unless classification says migrate-expect-actual

COMPLETION PROMISE (required — last line of your output):
  MIGRATION_COMPLETE: com.acme.login.LoginRepository | swaps: [] | expect-actual: []
```

Returns:

```
Agent 1: MIGRATION_COMPLETE: com.acme.login.AuthCredentials | swaps: [] | expect-actual: []
Agent 2: MIGRATION_COMPLETE: com.acme.login.TokenManager | swaps: [] | expect-actual: []
Agent 3: MIGRATION_COMPLETE: com.acme.login.LoginRepository | swaps: [] | expect-actual: []
```

**Step 4: Orchestrator runs re-test:**

```bash
./gradlew :shared:testDebugUnitTest

BUILD SUCCESSFUL in 13s
18 tests passed, 0 failed
```

Same 18 tests pass without modification. Orchestrator advances.

**Step 5: Checkpoint commit:**

```bash
./gradlew :shared:build :androidApp:assembleDebug :iosApp:build

BUILD SUCCESSFUL (all 3 platforms)

git add shared/src/commonMain/kotlin/com/acme/login/AuthCredentials.kt \
        shared/src/commonMain/kotlin/com/acme/login/TokenManager.kt \
        shared/src/commonMain/kotlin/com/acme/login/LoginRepository.kt \
        shared/src/commonTest/kotlin/com/acme/login/
git commit -m "chore(login): Phase 1 — migrate domain layer to commonMain"
```

PLAN.md STATUS block updated: `DONE: 1/4`, `CHECKPOINT: login-phase1`.

---

#### Phase 2 — API + Storage Layer (Full Batched Mode, migrate-swap)

`LoginApi.kt` swaps Retrofit for ktor-client. `SessionStore.kt` swaps SharedPreferences for multiplatform-settings. These files have no dependency on each other, but both need Full Batched because the swap libs require careful test coverage before touching the implementation.

Same TDD → baseline → migration → re-test → checkpoint cycle as Phase 1. The migration agents receive additional swap instructions injected from `references/dependency-map.md`:

```
SWAP INSTRUCTIONS:
- retrofit2.Call -> suspend fun (ktor-client)
- SharedPreferences -> com.russhwolf.settings.Settings
- See references/dependency-map.md for import replacements
```

Returns:

```
Agent 1: MIGRATION_COMPLETE: com.acme.login.LoginApi | swaps: [retrofit2->ktor-client] | expect-actual: []
Agent 2: MIGRATION_COMPLETE: com.acme.login.SessionStore | swaps: [SharedPreferences->multiplatform-settings] | expect-actual: []
```

Checkpoint commit: `"chore(login): Phase 2 — swap Retrofit + SharedPreferences to KMM equivalents"`

PLAN.md STATUS block: `DONE: 2/4`.

---

### Hook Activity

**UserPromptSubmit — on session start (or reconnect):**

```
[kmm-workflow] ACTIVE MIGRATION:
STATUS: EXECUTE Phase 2
MODULE: :feature:login
PHASES: 4
DONE: 1/4
CHECKPOINT: login-phase1
...

=== recent progress ===
[x] Phase 1: Domain layer — checkpoint committed (18 tests pass)
[ ] Phase 2: API + Storage — in progress
```

**PreToolUse — before any Write or Edit:**

```
STATUS: EXECUTE Phase 2
MODULE: :feature:login
PHASES: 4
DONE: 1/4
CHECKPOINT: login-phase1
...
```

**PostToolUse — after any Write or Edit:**

```
[kmm-workflow] Update PROGRESS.md with what you just did.
```

**Stop hook — orchestrator tries to end session mid-migration:**

```
[kmm-workflow] Migration in progress: 1/4 phases complete. Update PROGRESS.md before stopping.
```

**PreCompact — context window nearing limit:**

```
[kmm-workflow] Plan files backed up before compaction. Re-read PLAN.md + PROGRESS.md now.
```

Backup written to: `.claude/gameplans/login-20241015-143200/backups/PLAN_1729003200.md`

---

### Session Recovery Example

Session dies mid-Phase 2. User reconnects and sends any message.

UserPromptSubmit hook fires immediately:

```
[kmm-workflow] ACTIVE MIGRATION:
STATUS: EXECUTE Phase 2
MODULE: :feature:login
PHASES: 4
DONE: 1/4
CHECKPOINT: login-phase1
PLAN_DIR: .claude/gameplans/login-20241015-143200
...

=== recent progress ===
[x] Phase 1: Domain layer — checkpoint committed (18 tests pass)
[ ] Phase 2: API + Storage — TDD_COMPLETE received, baseline passed, migration dispatched (lost session)
```

Orchestrator reads injected state, runs `git diff --stat` to see what was written before the crash, then re-dispatches only the migration agents whose `MIGRATION_COMPLETE` was never confirmed. No re-reading of all files. No re-assessment. Continues from the last known good state.

---

### Known Fixes in Action

Phase 2 re-test fails:

```
> Task :shared:testDebugUnitTest FAILED

Could not resolve io.ktor:ktor-client-okhttp:2.3.4.
```

Before spending tokens diagnosing, orchestrator checks FINDINGS.md Known Fixes table:

```
Symptom: Could not resolve ktor-client-okhttp
Fix: Add `resolutionStrategy.force "io.ktor:ktor-client-okhttp:2.3.4"` to app/build.gradle
```

Match found. Orchestrator applies the fix directly, re-runs the build, passes. Zero tokens spent re-diagnosing a known issue.
