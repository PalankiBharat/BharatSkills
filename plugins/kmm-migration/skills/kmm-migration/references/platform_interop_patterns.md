# Platform Interop Patterns

> This file describes HOW to decide between expect/actual and interface+DI
> for each case. It does NOT prescribe one. Rule 13 applies: verify the
> current community preference via context7 at the planning time.

## Contents

- [Decision process](#decision-process)
- [Repo-preservation bias](#repo-preservation-bias)

## Decision process

For each platform-bound class / function in the inventory:

1. Is it a trivial primitive (time, UUID, random)?
   - Yes → `expect fun` / `typealias` is typically fine. Verify via
     context7 whether that remains the current idiom.
   - No → proceed.
2. Does it depend on `Context` / `Application` / `SharedPreferences` / etc.?
   - Yes → interface + DI is typically preferred. Verify via context7.
3. Does the existing repo already use a specific pattern consistently?
   - Yes → preserve it (repo-preservation bias, §5.2) unless it's
     Android-only / KMP-incompatible.

Document the choice with source citation in migration_guide.md.

## Repo-preservation bias

Keep existing patterns when:
- They compile on KMP (verify with a minimal build probe).
- The researcher confirms they are not abandoned / superseded.

Swap only when:
- The pattern is Android-only and literally incompatible with commonMain.
- The researcher provides a live-sourced successor.
