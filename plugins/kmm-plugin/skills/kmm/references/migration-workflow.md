# KMM TDD Migration Workflow

## Table of Contents

- [Philosophy](#philosophy)
- [Step 1: Read](#step-1-read)
- [Step 2: Assess](#step-2-assess)
- [Step 3: Stage](#step-3-stage)
- [Step 4: Test (TDD)](#step-4-test-tdd)
- [Step 5: Baseline](#step-5-baseline)
- [Step 6: Migrate](#step-6-migrate)
- [Step 7: Re-test](#step-7-re-test)
- [Step 8: Wire + Cleanup](#step-8-wire--cleanup)
- [Step 9: Audit](#step-9-audit)
- [Step 10: Build Verify](#step-10-build-verify)
- [Build Verification Protocol](#build-verification-protocol)
- [Testing Hard Rules (Summary)](#testing-hard-rules-summary)

## Philosophy

Tests are the backbone. They are written BEFORE migration and must pass AFTER migration without modification. This proves behavioral parity. Android is the source of truth — API signatures must be preserved exactly.

The Android app is already in production. Matching API signatures exactly means Android-side wiring after migration is minimal — just swap the import path and DI provider. Less change on Android = less risk to prod.

---

## Step 1: Read

- Read the original Android code thoroughly
- Document: public API surface (all public methods, properties, types)
- Document: behavioral contract (what it does, not how)
- Document: dependencies (what it imports, what it calls)
- Document: exact method signatures (names, parameters, return types)
- Document: who calls this code (what files import/use it)
- Understand ALL edge cases and invariants before proceeding

---

## Step 2: Assess

- Check if a KMM version already exists in commonMain
- If yes, compare parity with Android source:
  - ≥80% parity: Patch existing KMM version to match Android signatures and behavior exactly
  - <80% parity: Rewrite from scratch based on Android source. Don't fight divergent code
  - API signature mismatch: Update KMM signatures to match Android. Android is prod, Android wins
- If no KMM version exists: Proceed to Step 3

---

## Step 3: Stage

- Copy Android code to staging area (androidMain in the KMM project)
- MINIMAL changes only: package/namespace/import fixes to make it compile
- No behavioral changes. No dependency replacements. No API adaptations
- Goal: code that behaves identically to original but compiles in the KMM project

---

## Step 4: Test (TDD)

Write characterization tests in commonTest against the staged code's public API. Tests define the behavioral contract that must survive migration.

**Rules:**
- Cover ALL public methods, state transitions, edge cases
- Hand-written fakes only — MockK and Mockito DO NOT work in commonTest/Kotlin Native
- CamelCase test names only — backtick names (`fun \`test my behavior\`()`) crash on Kotlin/Native
- Test BEHAVIOR, not implementation details
- Standalone enum serialization can crash on Native — test within parent `@Serializable` class
- `expect/actual` VMs can't be directly instantiated in commonTest — use test wrapper pattern

**Test wrapper pattern for expect/actual VMs:**

```kotlin
// In commonTest: define a wrapper that exposes the VM for testing
// androidTest / iosTest: provide the concrete instantiation via expect/actual

// commonTest/TestMyViewModel.kt
expect fun createMyViewModel(repo: MyRepository): MyViewModel

// androidTest/TestMyViewModel.android.kt
actual fun createMyViewModel(repo: MyRepository): MyViewModel =
    MyViewModel(repo)

// iosTest/TestMyViewModel.ios.kt
actual fun createMyViewModel(repo: MyRepository): MyViewModel =
    MyViewModel(repo)

// commonTest/MyViewModelTest.kt
class MyViewModelTest {
    @Test
    fun initialStateIsLoading() {
        val vm = createMyViewModel(FakeMyRepository())
        assertEquals(MyUiState.Loading, vm.uiState.value)
    }
}
```

---

## Step 5: Baseline

- Run ALL tests: `./gradlew :module:allTests` (or `testDebugUnitTest` for speed)
- Every test MUST pass
- If tests fail at baseline, the test has a bug — fix the test so it correctly describes the staged Android behavior. This is the ONLY time tests may be modified. After baseline is green, tests become immutable.
- Green baseline = tests correctly describe Android behavior
- This is the contract. Do not proceed until baseline is green

---

## Step 6: Migrate

- Move code from staging (androidMain) to target (commonMain)
- Replace platform-specific dependencies:
  - Retrofit → Ktor (see dependency-map.md)
  - Hilt → Koin
  - SharedPreferences → Multiplatform-Settings
  - etc.
- Apply `expect/actual` for genuine platform differences
- Remove the staged copy — code exists ONLY in commonMain after this step
- API signatures MUST match Android exactly

---

## Step 7: Re-test

Run the SAME tests from Step 4 against migrated code. They MUST pass WITHOUT modification.

**If tests fail:**
- FIX THE MIGRATION CODE, never modify the tests
- The tests are the contract — if they fail, the migration broke something
- Iterate: fix migration → re-run tests → repeat until ALL pass

**When tests CAN be modified (rare):**
- Only if the API surface itself genuinely changed (e.g., callback → suspend)
- Adapt the test CALL-SITE only (how you invoke the method)
- Assert the SAME behavioral outcome
- Document with: `// API-CHANGE: callback→suspend, same behavior verified`
- This should be rare — flag it and document it
- If the behavioral outcome itself cannot be preserved because the API fundamentally changed in a way that alters behavior, STOP and escalate to the user.

**NEVER:**
- Add `@Ignore` or `@Suppress` to skip failing tests
- Add stubs that return dummy data to make tests pass
- Modify test assertions to match different behavior
- Remove tests that are "too hard" to make pass

---

## Step 8: Wire + Cleanup

- Wire both platforms to consume the migrated shared code:
  - Android: `koinViewModel<MyViewModel>()` replaces `hiltViewModel<MyViewModel>()`
  - iOS: `PresenterProvider.shared.getMyViewModel()` + SwiftUI screen (your project's DI provider — pattern varies by project)
- Delete old Android-only copies (the original file in `app/src/main/`)
- Delete any old divergent KMM files that were rewritten
- No dead code left behind

---

## Step 9: Audit

- Run audit checklist (see audit-checklist.md) against the migrated code
- Check for: `runBlocking`, leaked scopes, type casting, non-atomic state updates, etc.
- Fix any issues found

---

## Step 10: Build Verify

Run ALL platform builds:

```bash
# 1. Full Android app build (NOT just :shared:build)
./gradlew :app:compileProductionDebugKotlin --no-configuration-cache

# 2. iOS framework
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64

# 3. xcodebuild
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp \
  -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.2' build
```

**If any build fails:**
- Do NOT fix it "just to pass"
- If the fix is obvious (missing import, typo): fix and move on
- If the fix is non-obvious: STOP. Present to user:
  - Problem: what failed and the error
  - Possible solutions: 2-3 approaches with pros/cons
  - Recommendation: what you'd do as a KMM expert and why
  - Let user decide

---

## Build Verification Protocol

- All 3 builds must pass before any commit
- `:shared:build` may fail with pre-existing test failures — use `:shared:assemble` or `linkDebugFramework` instead
- `xcodebuild` is the final arbiter — SourceKit errors are unreliable (they're false positives)
- NEVER fix builds "just to pass"

---

## Testing Hard Rules (Summary)

- All tests in commonTest from the start
- Hand-written fakes only
- CamelCase test names (backtick crashes Native)
- Tests are IMMUTABLE after baseline (except documented API-surface changes)
- If a test fails after migration, the migration is wrong — not the test
- Document behavioral gaps via `// GAP:` comments — never suppress them
