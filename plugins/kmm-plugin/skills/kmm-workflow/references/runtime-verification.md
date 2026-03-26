# Runtime Verification Execution Model

Launch the app on both platforms after completeness verification to catch KMM-specific runtime
crashes before handing off to manual testing.

## Android Runtime Verification

```bash
# Build & install
./gradlew :app:installProductionDebug

# Launch app and capture logcat (clear first, then filter for crashes)
adb logcat -c
adb shell am start -n <package>/<activity>
sleep 3
adb logcat -d *:E | grep -E "FATAL|AndroidRuntime|KoinApplication|SKIE|ClassCastException|IllegalStateException|NullPointerException|CoroutineException|JobCancellation"
```

To find the package and activity: check `AndroidManifest.xml` for the package name and the
launcher activity (the one with `MAIN` + `LAUNCHER` intent filters).

## iOS Runtime Verification

```bash
# Install and launch with console output
xcrun simctl install booted path/to/App.app
xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | head -100
```

The `.app` bundle path comes from the build output (`xcodebuild` logs the `.app` path under
`CONFIGURATION_BUILD_DIR`). The bundle ID is in `Info.plist` as `CFBundleIdentifier`.

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

1. **Build & install** (or use existing build from checkpoint if it's fresh)
2. **Launch app, capture logs for 5 seconds**
3. **Parse crash output** — match against the six patterns above
4. **If crash detected:**
   - Identify crash category from patterns above
   - Read the crashing file + its dependencies (context-first)
   - Apply fix based on category (follow `/kmm bugfix` patterns)
   - Incremental rebuild only — `./gradlew :app:assembleProductionDebug` or `./gradlew :app:installProductionDebug`
   - Re-launch and re-capture logs
   - Repeat until clean launch (**max 5 iterations per platform**, then escalate to user)
5. **If clean launch on both platforms** → proceed to Manual Testing Loop

Each fix attempt must be logged in PROGRESS.md.

## Escalation

If after 5 fix attempts the app still crashes on a platform, **STOP** and present to the user:

- All crash logs collected (full stacktraces, not just the filtered lines)
- All fixes attempted (what was changed, why, what happened)
- Recommendation for next steps

Do not attempt a 6th fix. Escalate immediately.
