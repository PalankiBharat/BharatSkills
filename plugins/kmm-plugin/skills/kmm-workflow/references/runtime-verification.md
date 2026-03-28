# Runtime Verification Execution Model

Launch the app on each platform after wiring to catch KMM-specific runtime crashes before handing
off to manual testing.

**Primary tool:** mobile-mcp (structured, screenshot-capable, works for both Android and iOS)
**Fallback:** adb (Android) / xcrun simctl (iOS) — use when mobile-mcp is unavailable

For debugging failures found during verification, follow the structured debug loop in
`references/agent-prompts/debugger.md`. Do not attempt ad-hoc fixes — use the debug loop.

---

## Android Runtime Verification

### mobile-mcp (primary)

```
mobile_install_app → mobile_launch_app
For each screen in migration-guide.md:
  mobile_take_screenshot → verify layout matches expected
  mobile_list_elements_on_screen → verify data present
  mobile_click_on_screen_at_coordinates → navigate to next screen
Save screenshots to e2e-tests/screenshots/android/
```

### adb (fallback)

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

### Napier log tag filtering

When debugging a specific screen, use Napier log tags for efficient filtering:

```bash
# Filter by debug tag (set during debug loop instrumentation)
adb logcat -s "DebugLoginScreen"

# After fix confirmed, remove Napier instrumentation before committing
```

To find the package and activity: check `AndroidManifest.xml` for the package name and the
launcher activity (the one with `MAIN` + `LAUNCHER` intent filters).

---

## iOS Runtime Verification

### mobile-mcp (primary)

```
mobile_install_app → mobile_launch_app (iOS simulator)
For each screen in migration-guide.md:
  mobile_take_screenshot → compare with Android screenshot (parity check)
  mobile_list_elements_on_screen → verify same data as Android
  mobile_click_on_screen_at_coordinates → navigate
Save screenshots to e2e-tests/screenshots/ios/
```

### xcrun simctl (fallback)

```bash
# Uninstall first to ensure clean state
xcrun simctl uninstall booted <bundle-id>

# Install and launch with console output
xcrun simctl install booted path/to/App.app
xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | head -100
```

### Napier log tag filtering on iOS

```bash
# Filter console output by Napier debug tag
xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | grep "DebugLoginScreen"
```

Napier outputs to OSLog on iOS, which appears in the simulator console. The tag set during
instrumentation is the grep target.

The `.app` bundle path comes from `xcodebuild` output under `CONFIGURATION_BUILD_DIR`.
The bundle ID is in `Info.plist` as `CFBundleIdentifier`.

## Crash Pattern Recognition

Common KMM runtime crash signatures to look for in logs:

1. **SKIE type mismatch** — `ClassCastException` with SKIE-generated class names
   - Root cause: sealed class/interface hierarchy consumed from Swift using wrong subtype
   - Fix: check SKIE dot-notation usage in Swift callers (e.g., `Effect.NavigateToNext`, not `NavigateToNext`)

2. **Missing Koin definition** — `No definition found for class` or `NoBeanDefFoundException`
   - Root cause: type migrated to shared module but DI module not updated for both platforms
   - Fix: verify `expect`/`actual` DI modules; check that the shared module's Koin module is included in both platform DI graphs

3. **Coroutine scope issues** — `JobCancellationException`, `IllegalStateException: Module with the Main dispatcher`
   - Root cause: coroutine launched on wrong scope, or Main dispatcher not initialized before use
   - Fix: ensure platform coroutine dispatcher is initialized before Koin starts; use `Dispatchers.Main.immediate` where needed

4. **Missing expect/actual** — `kotlin.NotImplementedError`
   - Root cause: `expect` declaration has no matching `actual` for the target platform
   - Fix: add the missing `actual` in `androidMain` or `iosMain`

5. **Threading violations** — `IllegalStateException: Must be called on the main thread`
   - Root cause: shared code calling a platform API off the main thread
   - Fix: wrap the call in `withContext(Dispatchers.Main)` or use `@MainThread` dispatching in the VM

6. **Frozen object mutation** (legacy memory manager) — `InvalidMutabilityException`
   - Root cause: mutable state shared across threads under the old K/N memory model
   - Fix: ensure `kotlin.native.binary.memoryModel=experimental` is set, or restructure to avoid cross-thread mutation

## Loop Protocol

1. **Uninstall** old build (ensures clean state — never skip this step)
2. **Build & install**
3. **Launch app, capture logs**
4. **Parse crash output** — match against the patterns above
5. **If crash detected:**
   - Identify crash category from patterns above
   - Check findings.md Known Fixes table first — the fix may already be documented
   - If not found: invoke the structured debug loop from `references/agent-prompts/debugger.md`
   - Each fix attempt logged in PROGRESS.md
   - Incremental rebuild only — `./gradlew :app:assembleProductionDebug` or `xcodebuild`
   - Re-launch and re-capture logs
   - Repeat until clean launch (**max 3 iterations via debug loop**, then escalate to user)
6. **If clean launch** → proceed to Appium automated tests, then Summary Table, then manual test

If still crashing after 3 debug loop iterations, **STOP** and escalate: provide full stacktraces
(not just filtered lines), all fixes attempted, and your recommendation. Do not attempt a 4th fix.

Each fix attempt must be logged in PROGRESS.md.
