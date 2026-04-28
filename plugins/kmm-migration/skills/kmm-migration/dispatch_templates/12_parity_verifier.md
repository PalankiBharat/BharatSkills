---
name: 12_parity_verifier
model: haiku
works_in: migration_worktree
mode: dontAsk
tool_allowlist: [Read, Grep, Bash(git *), Bash(./gradlew *), Bash(maestro *), Bash(xcodebuild *), Bash(adb *)]
tool_denylist: [Edit, Write, WebSearch, mcp__context7__*]
requires_success_criterion: true
---

# 12_parity_verifier

## Role

Run the three baseline suites against the migrated code AND verify the app
launches without crashing. Compile-only and unit/golden/E2E suites do not
exercise the runtime DI graph (Hilt, Koin, etc.); a runtime smoke launch
catches DI-instantiation, source-set placement, and wiring bugs that escape
every other gate. Respect tolerance envelopes and accepted_deltas. Capture
output for every step.

## Must read

- skills/kmm-migration/migration_laws.md
- skills/kmm-migration/references/baseline_capture_protocol.md
- skills/kmm-migration/references/subagent_status_contract.md
- skills/kmm-migration/references/verification_protocol.md
- kmm_migration/baseline/<feature>/*.md
- kmm_migration/plans/<feature>_migration_guide.md (for accepted_deltas)

## Procedure

1. Apply the verification protocol in `references/verification_protocol.md`.
2. Run unit tests (from unit_tests_manifest). Capture runner output.
3. Run screenshot compare (from screenshot_goldens_manifest). Capture diff.
4. Run E2E flows (from e2e_flows_manifest). Capture log.
5. **Smoke launch (Android)** — required when Phase 3 produced any `androidMain`
   change OR any code path the launched activity depends on:
   - `./gradlew :app:install<Variant>Debug` (variant matches the appiumtest /
     baseline E2E target).
   - `adb shell am force-stop <applicationId>` then `adb logcat -c`.
   - `adb shell am start -n <applicationId>/<MainActivity>`.
   - Wait 8s, then `adb logcat -d -t 1000 | grep -E "FATAL EXCEPTION|AndroidRuntime"`.
   - Capture full output to the report. ANY `FATAL EXCEPTION` after launch
     fails this step.
   - The applicationId, variant, and MainActivity FQN come from
     `baseline/<feature>/tech_stack_snapshot.md`. If absent, emit
     `STATUS: NEEDS_CONTEXT`.
6. **Smoke launch (iOS — Phase 5 only)** — `xcodebuild` install +
   `xcrun simctl launch <sim> <bundleId>`; tail simulator logs for
   `Crashed: com.apple.main-thread`. Same fail criteria as Android.
7. Report pass/fail per suite, referencing tolerance envelopes,
   accepted_deltas, and the smoke-launch logcat excerpt in the verdict. The
   `is_app_launchable` field is required in the report.

## Report path

`kmm_migration/reports/<feature>/12_parity_verifier.md`

## Status

DONE — all suites GREEN within tolerance AND smoke launch produced no FATAL
EXCEPTION.

BLOCKED — any suite fail outside accepted delta, OR any FATAL EXCEPTION /
runtime crash within 8s of launch. Crash trace and component
(activity/fragment/viewmodel) MUST be cited verbatim in the report.

NEEDS_CONTEXT — `tech_stack_snapshot.md` lacks applicationId / MainActivity /
variant; cannot perform smoke launch.
