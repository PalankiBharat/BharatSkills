# Android Wiring Reference

Complete protocol for wiring the Android platform after shared module migration: imports, DI,
deletions, parallel execution strategy, build, and runtime verification.

Runs AFTER all shared code migration phases are checkpointed. BEFORE iOS.

---

## Table of Contents

1. [Wire Android Protocol](#1-wire-android-protocol)
   - 1.1 [Update Imports in Android Consumers](#11-update-imports-in-android-consumers)
   - 1.2 [Update DI (Hilt → Koin)](#12-update-di-hilt--koin)
   - 1.3 [Delete Original Android Files](#13-delete-original-android-files)
2. [Parallel Execution](#2-parallel-execution)
3. [Build & Test](#3-build--test)
4. [Runtime Verification](#4-runtime-verification)
   - 4.1 [mobile-mcp (primary)](#41-mobile-mcp-primary)
   - 4.2 [adb (fallback)](#42-adb-fallback)
   - 4.3 [Napier Log Tag Filtering](#43-napier-log-tag-filtering)
   - 4.4 [Loop Protocol](#44-loop-protocol)
5. [Crash Patterns](#5-crash-patterns)
6. [REQUIRES_APPROVAL Triggers](#6-requires_approval-triggers)

---

## 1. Wire Android Protocol

**Goal:** Switch the Android app module from its original Android-only source files to the newly
migrated shared module. All consumers updated, originals deleted, Android build passes, app
verified working.

### 1.1 Update Imports in Android Consumers

For every file listed under "Consumers" in migration-guide.md:
- Update import paths from `androidApp/...` to `shared/...` (or the shared module package)
- Do not change call sites — signatures are identical (1:1 rule)
- Dispatch parallel Haiku agents if consumer count > 5 (see Section 2)

### 1.2 Update DI (Hilt → Koin)

- Wire shared module classes into the Android Koin module (`androidApp/src/.../di/`)
- Remove Hilt bindings for migrated classes
- Add Koin `single { }` or `factory { }` declarations for shared classes
- If the project uses Hilt throughout: flag as REQUIRES_APPROVAL before changing DI framework

### 1.3 Delete Original Android Files

Before deleting each file:
```bash
grep -r "OriginalClassName" androidApp/src/ --include="*.kt" -l
```
Confirm all usages now point to shared. If any remain → update them first.

Then delete. Do not defer deletions — stale files cause ambiguous imports.

If deletion would break a non-migrated consumer (consumer is `platform-stay` or outside scope):
→ REQUIRES_APPROVAL: present options (migrate consumer now, keep original alongside shared,
use typealias)

---

## 2. Parallel Execution

**Rule:** Haiku per consumer for import updates; Sonnet for DI wiring.

| Task | Agent | Condition |
|------|-------|-----------|
| Import updates per consumer file | Haiku (one agent per file) | Consumer count > 5 |
| DI module wiring (Koin declarations) | Sonnet | Always |
| Build verification | Sonnet | Always |
| Runtime verification | Sonnet | Always |

Launch all Haiku consumer agents concurrently. Do not wait for one to finish before starting
the next. After all consumer agents report done, Sonnet proceeds to DI wiring.

---

## 3. Build & Test

```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Failures:
- Check findings.md Known Fixes first
- 3-strike rule: max 3 distinct approaches → escalate if still failing
- Never repeat the same failed fix

**Summary Table** (fill before Appium phase):

| File | Promised API | Actual API | Verify | Tests |
|------|-------------|------------|--------|-------|
| LoginRepository.kt | login(email,pwd):Result | ... | PASS | PASS |

Present to user before proceeding to Appium.

**After Wire Android checkpoint:** proceed to Phase 5 (Appium Android) — MANDATORY. Then manual test. See SKILL.md for phase ordering.

Update PROGRESS.md checkpoint. PLAN.md status block updated.

---

## 4. Runtime Verification

Launch the app after wiring to catch KMM-specific runtime crashes before handing off to manual
testing.

**Primary tool:** mobile-mcp (structured, screenshot-capable)
**Fallback:** adb — use when mobile-mcp is unavailable

For debugging failures found during verification, follow the structured debug loop in
`references/agent-prompts/debugger.md`. Do not attempt ad-hoc fixes — use the debug loop.

### 4.1 mobile-mcp (primary)

```
mobile_install_app → mobile_launch_app
For each screen in migration-guide.md:
  mobile_take_screenshot → verify layout matches expected
  mobile_list_elements_on_screen → verify data present
  mobile_click_on_screen_at_coordinates → navigate to next screen
Save screenshots to e2e-tests/screenshots/android/
```

### 4.2 adb (fallback)

```bash
# Uninstall first to ensure clean state
adb uninstall <package>

# Build & install
./gradlew :app:installProductionDebug

# Clear logs, launch, capture errors
adb logcat -c
adb shell am start -n <package>/<activity>
adb logcat -d *:E | grep -E "FATAL|AndroidRuntime|KoinApplication|SKIE|ClassCastException|IllegalStateException|NullPointerException|CoroutineException|JobCancellation"
```

To find the package and activity: check `AndroidManifest.xml` for the package name and the
launcher activity (the one with `MAIN` + `LAUNCHER` intent filters).

### 4.3 Napier Log Tag Filtering

When debugging a specific screen, use Napier log tags for efficient filtering:

```bash
# Filter by debug tag (set during debug loop instrumentation)
adb logcat -s "DebugLoginScreen"

# After fix confirmed, remove Napier instrumentation before committing
```

### 4.4 Loop Protocol

1. **Uninstall** old build (ensures clean state — never skip this step)
2. **Build & install**
3. **Launch app, capture logs**
4. **Parse crash output** — match against the patterns in Section 5
5. **If crash detected:**
   - Identify crash category from Section 5
   - Check findings.md Known Fixes table first — the fix may already be documented
   - If not found: invoke the structured debug loop from `references/agent-prompts/debugger.md`
   - Each fix attempt logged in PROGRESS.md
   - Incremental rebuild only — `./gradlew :app:assembleProductionDebug`
   - Re-launch and re-capture logs
   - Repeat until clean launch (**max 3 iterations via debug loop**, then escalate to user)
6. **If clean launch** → proceed to per-screen verification (navigate, verify data loads, verify CTA, screenshot), then Summary Table, then Phase 5 Appium (MANDATORY), then manual test

If still crashing after 3 debug loop iterations, **STOP** and escalate: provide full stacktraces
(not just filtered lines), all fixes attempted, and your recommendation. Do not attempt a 4th fix.

Each fix attempt must be logged in PROGRESS.md.

---

## 5. Crash Patterns

Common KMM runtime crash signatures to look for in logs:

1. **SKIE type mismatch** — `ClassCastException` with SKIE-generated class names
   - Root cause: sealed class/interface hierarchy consumed from Swift using wrong subtype
   - Fix: check SKIE dot-notation usage in Swift callers (e.g., `Effect.NavigateToNext`, not
     `NavigateToNext`)

2. **Missing Koin definition** — `No definition found for class` or `NoBeanDefFoundException`
   - Root cause: type migrated to shared module but DI module not updated for both platforms
   - Fix: verify `expect`/`actual` DI modules; check that the shared module's Koin module is
     included in both platform DI graphs

3. **Coroutine scope issues** — `JobCancellationException`, `IllegalStateException: Module with
   the Main dispatcher`
   - Root cause: coroutine launched on wrong scope, or Main dispatcher not initialized before use
   - Fix: ensure platform coroutine dispatcher is initialized before Koin starts; use
     `Dispatchers.Main.immediate` where needed

4. **Missing expect/actual** — `kotlin.NotImplementedError`
   - Root cause: `expect` declaration has no matching `actual` for the target platform
   - Fix: add the missing `actual` in `androidMain` or `iosMain`

5. **Threading violations** — `IllegalStateException: Must be called on the main thread`
   - Root cause: shared code calling a platform API off the main thread
   - Fix: wrap the call in `withContext(Dispatchers.Main)` or use `@MainThread` dispatching in the VM

6. **Frozen object mutation** (legacy memory manager) — `InvalidMutabilityException`
   - Root cause: mutable state shared across threads under the old K/N memory model
   - Fix: ensure `kotlin.native.binary.memoryModel=experimental` is set, or restructure to avoid
     cross-thread mutation

---

## 6. REQUIRES_APPROVAL Triggers

- DI framework change (Hilt → Koin) affects files outside migration scope
- Deletion would break a non-migrated consumer
- Import update requires a signature change (means migration was not 1:1 — re-verify)
- Any Android-specific behavior change not covered in migration-guide.md
