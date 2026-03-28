# Wire Android Phase

Runs AFTER all shared code migration phases are checkpointed. BEFORE iOS.

## Goal

Switch the Android app module from its original Android-only source files to the newly migrated shared module. All consumers updated, originals deleted, Android build passes, app verified working.

---

## Steps

### 1. Update Imports in Android Consumers

For every file listed under "Consumers" in migration-guide.md:
- Update import paths from `androidApp/...` to `shared/...` (or the shared module package)
- Do not change call sites — signatures are identical (1:1 rule)
- Dispatch parallel Haiku agents if consumer count > 5

### 2. Update DI (Hilt → Koin)

- Wire shared module classes into the Android Koin module (`androidApp/src/.../di/`)
- Remove Hilt bindings for migrated classes
- Add Koin `single { }` or `factory { }` declarations for shared classes
- If the project uses Hilt throughout: flag as REQUIRES_APPROVAL before changing DI framework

### 3. Delete Original Android Files

Before deleting each file:
```
grep -r "OriginalClassName" androidApp/src/ --include="*.kt" -l
```
Confirm all usages now point to shared. If any remain → update them first.

Then delete. Do not defer deletions — stale files cause ambiguous imports.

If deletion would break a non-migrated consumer (consumer is `platform-stay` or outside scope):
→ REQUIRES_APPROVAL: present options (migrate consumer now, keep original alongside shared, use typealias)

### 4. Android Build + Test

```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

Failures:
- Check findings.md Known Fixes first
- 3-strike rule: max 3 distinct approaches → escalate if still failing
- Never repeat the same failed fix

### 5. Runtime Verify

See iterative-execution.md Android phase for full protocol.
Short form:
```
mobile_install_app → mobile_launch_app
  → screenshot each screen → verify layout + data
  → navigate critical paths
```
Fallback: `adb uninstall <pkg>` → `adb install -r <apk>` → `adb logcat -s DebugScreenName`

### 6. Appium Flow Tests

Start fake server → run e2e-tests/ → all pass required before manual test.

### 7. Summary Table

| File | Promised API | Actual API | Verify | Tests |
|------|-------------|------------|--------|-------|
| LoginRepository.kt | login(email,pwd):Result | ... | PASS | PASS |

Present to user before manual test.

### 8. Manual Test → Commit

User tests against real backend. Bug → DEBUG LOOP. All flows pass → commit:
```bash
git add -p
git commit -m "Wire Android: <module> migrated to shared"
```

Update PROGRESS.md checkpoint. PLAN.md status block updated.

---

## REQUIRES_APPROVAL Triggers

- DI framework change (Hilt → Koin) affects files outside migration scope
- Deletion would break a non-migrated consumer
- Import update requires a signature change (means migration was not 1:1 — re-verify)
- Any Android-specific behavior change not covered in migration-guide.md
