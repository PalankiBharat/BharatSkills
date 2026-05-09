<!-- TEMPLATE: copied to <repo>/kmm/<scope>/spec.md by specify-phase -->
<!-- Replace bracketed placeholders. Keep the structure. -->

# Migration spec — [scope-name]

## Goal (user's words)

> [paste the user's stated migration goal verbatim — one paragraph]

## In scope

[list every file by exact path. one bullet per file. no patterns, no globs, no "and similar" — every file enumerated.]

- `app/src/main/java/com/example/[path]/[FileA].kt`
- `app/src/main/java/com/example/[path]/[FileB].kt`
- ...

## Explicitly out of scope

[list the adjacent things the user knows about that are NOT being migrated. file paths or named subsystems. omit nothing the user named. defaults: anything not in the in-scope list.]

- `app/src/main/java/com/example/[path]/[AdjacentFile].kt` — [why deferred]
- UI screens for the [feature] feature — UI is out of scope for this skill
- ...

## Base branch

[main | master | <other>]

## Baseline master SHA

`<full SHA from git rev-parse <base-branch> at specify-phase time>`

[populated at specify-phase; immutable from there. Constitution §7]

## Baseline locked SHA

`<full SHA from T-LOCK commit>`

[populated at T-LOCK; immutable from there]

## Worktree

`<repo>/.worktrees/kmm-[scope-name]/`
Branch: `feature/kmm-[scope-name]`

## Declared shared targets

Source sets the migration targets (autodetected from the shared module's `build.gradle.kts`, confirmed by user):

- `commonMain` — always
- `androidMain` — yes
- `iosMain` (arm64+x64) — yes/no
- `jvmMain` — yes/no
- `wasmJsMain` — yes/no
- ...

Test source sets:

- `commonTest` — always
- `androidUnitTest` — yes
- `iosX64Test` — yes/no
- ...

## Declared consumer targets

Apps / modules that consume the shared module and must compile clean after migration:

- `:app` (Android consumer)
- `iosApp` (iOS consumer; compile-only verified)
- ...

## Test command (baseline)

The exact gradle invocation `specify-phase` used to run the existing test suite to detect master-failing tests outside scope. Re-used at `T-LOCK` and at `/kmm-verify`.

```
[./gradlew :<module>:testDebugUnitTest, etc.]
```

## Master-failing tests at specify-phase time

[list every test failing on master at the baseline SHA that lives outside the in-scope list. proposed @Ignore patch is logged as D-1 in migration-report.md.]

| Test | File | Failure mode |
|---|---|---|
| `[ClassName.testMethod]` | `[file path]` | [timeout / assertion / etc.] |
| ... | ... | ... |

[if zero, write "None — master is green outside scope at baseline SHA."]

## Out-of-scope policy

Files not in the in-scope list MAY have their imports updated by `implement-phase` if they are listed as `Consumers` of an in-scope file in `migration-guide.md`. ANY OTHER change to a file outside the in-scope list is a constitution violation and is rejected by `/kmm-verify` unless explicitly logged as a deviation in `migration-report.md`.
