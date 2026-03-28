# Iterative Execution Model

## Overview

Two-phase separation: PLAN captures every decision in files. EXECUTE consumes those files with minimal context. /clear is the boundary — only files survive it.

---

## DURING PLANNING

Before any code is touched:

1. Read every source file in scope. Identify every API endpoint the module calls.
2. Record request/response shapes → write fake server config (`e2e-tests/fake-server-config.json`)
3. Dispatch **Sonnet agent** to write Appium test specs for every critical flow (`e2e-tests/<flow>.test.js`)
4. Commit e2e-tests/ — this becomes the regression suite
5. Write 4 output files:
   - **PLAN.md** — phases + STATUS block (hooks read first 15 lines every message)
   - **PROGRESS.md** — per-file checkboxes + checkpoint commits (created now, filled during execution)
   - **migration-guide.md** — per-file spec consumed by agents (source/target, public API, swaps, rules)
   - **findings.md** — Known Fixes + Gotchas + Library Versions (persists across migrations)
6. Dispatch **Sonnet agent** (`plan-analyzer.md`) to find remaining ambiguity → resolve → user approves
7. Tell user:

```
Planning complete. Run /clear then paste this:

/kmm-workflow execute .claude/gameplans/<name>/
```

Do NOT auto-clear. The user decides when to clear.

---

## SHARED CODE MIGRATION LOOP

For each file in bottom-up dependency order:

```
MIGRATE (sonnet) → VERIFY (haiku diff) → if VERIFY_FAIL → re-dispatch migrator (max 2) → escalate
```

After all files in a phase complete:

```
TEST (./gradlew :shared:testDebugUnitTest)
  → if fail → check findings.md Known Fixes → DEBUG LOOP → FIX → TEST
  → if pass → CHECKPOINT (3-platform build → git commit → update PLAN.md + PROGRESS.md)

Batch any REQUIRES_APPROVAL items → present to user at phase boundary (not one-by-one)
```

Verifier is a fast pre-filter — diffs migrated output vs original source:
- API surface: every method, param, return type matches exactly
- No use cases combined, split, or altered
- Allowed: library swaps, package changes, imports, LiveData→StateFlow
- Gradle tests + Appium are the real catch-all for subtle bugs

---

## ANDROID PHASE (after all shared phases done)

**Step 1: Wire Android** — read `wire-android.md`

**Step 2: Android build + test**
```
./gradlew :app:testDebugUnitTest
  → if fail → check findings.md → DEBUG LOOP → FIX → retest
```

**Step 3: Runtime Verify (mobile-mcp, fallback: adb)**

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` |
| adb (fallback) | `adb install -r <apk>` → `adb shell am start` |

For each screen in migration-guide.md:
- `mobile_take_screenshot` → verify layout
- `mobile_list_elements_on_screen` → verify data
- `mobile_click_on_screen_at_coordinates` → navigate

If crash → DEBUG LOOP (Android): instrument with Napier `[DebugScreenName]` → `adb logcat -s DebugScreenName`

**Step 4: Automated Flow Test (Appium + fake server)**
```
Start fake server (deterministic responses from planning)
Run Appium tests for every critical flow (e2e-tests/)
  → if fail → DEBUG LOOP → fix → rerun
  → all pass → proceed to manual test
```

**Step 5: Summary Table** (promised vs achieved per file — show before manual test)

**Step 6: Manual Test**
```
User tests against REAL backend (not fake server)
Bug → DEBUG LOOP → mobile-mcp smoke after each fix
All flows pass → COMMIT (Android complete)
```

---

## iOS PHASE (after Android committed)

**Step 1: UI Migration** — per screen per migration-guide.md (CMP / SwiftUI / Hybrid per spec)

**Step 2: Wire iOS** — read `wire-ios.md`

**Step 3: iOS build**
```
xcodebuild -workspace <name>.xcworkspace -scheme <name> -destination 'platform=iOS Simulator,...'
  → if fail → DEBUG LOOP (iOS) → fix → rebuild
```

**Step 4: Runtime Verify (mobile-mcp on simulator, fallback: xcrun)**

| Tool | Commands |
|------|----------|
| mobile-mcp (primary) | `mobile_install_app` → `mobile_launch_app` (iOS simulator) |
| xcrun (fallback) | `xcrun simctl install booted <app>` → `xcrun simctl launch booted <bundle-id>` |

For each screen in migration-guide.md:
- `mobile_take_screenshot` → compare with Android screenshot (visual parity check)
- `mobile_list_elements_on_screen` → verify same data as Android
- `mobile_click_on_screen_at_coordinates` → navigate

If crash → DEBUG LOOP (iOS): `xcrun simctl launch --console-pty booted <bundle-id> 2>&1 | grep DebugScreenName`

**Step 5: Automated Flow Test (Appium + same fake server)**
```
Same fake server config as Android (same deterministic responses)
Run Appium tests adapted for iOS (same flows, iOS selectors)
  → if fail → DEBUG LOOP (iOS) → fix → rerun
  → all pass → proceed to manual test
```

**Step 6: Summary Table** (promised vs achieved — compare Android vs iOS columns)

**Step 7: Manual Test**
```
User tests against REAL backend on iOS
Bug → DEBUG LOOP (iOS) → fix → retest
All flows pass → COMMIT (iOS complete)
```

---

## DONE

- All phases in PROGRESS.md marked [x]
- Appium tests in e2e-tests/ committed — CI-ready regression suite
- findings.md saved for next migration (Known Fixes, Gotchas, Library Versions)
- migration-guide.md and PLAN.md kept for reference or deleted per user preference
