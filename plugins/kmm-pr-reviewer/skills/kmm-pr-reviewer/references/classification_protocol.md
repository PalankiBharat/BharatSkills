# Classification Protocol

> Run by `00_bootstrap` (Haiku) at the start of a review. Every changed
> path in the PR is bucketed into exactly one classification. The
> classification is written into `state.json` and is read-only thereafter.
> Misclassifications must be surfaced as `STATUS: NEEDS_CONTEXT` by the
> per-file reviewer — never silently overridden.

## Contents

- [Inputs](#inputs)
- [Buckets](#buckets)
- [Procedure](#procedure)
- [Tie-breaking rules](#tie-breaking-rules)
- [Output shape](#output-shape)

## Inputs

- `gh pr view <pr#> --json files` — list of changed paths with status (`ADDED` / `MODIFIED` / `REMOVED` / `RENAMED`).
- `gh pr diff <pr#>` — full unified diff at `head_sha` vs `base_sha`.
- `git ls-tree -r <base_sha> -- <path>` — to confirm a path's existence on master (used for `migrated` detection).

## Buckets

The five classifications, in tie-breaker priority order:

| Order | Bucket | Definition |
|---|---|---|
| 1 | `baseline` | Path matches one of the baseline-asset patterns (see below). Wins over every other bucket — baseline mods are always BLOCKERs. |
| 2 | `ios_port` | Path lies under any `*/iosMain/**`, `*/iosArm64Main/**`, `*/iosX64Main/**`, `*/iosSimulatorArm64Main/**`, or contains a `.swift` extension within an iOS-target source set. |
| 3 | `migrated` | Path is **added or modified** under a multiplatform source set (`*/commonMain/**`, `*/commonTest/**`, `*/androidMain/**`, `*/androidUnitTest/**`, `*/androidInstrumentedTest/**`) **and** there exists a corresponding **removed or modified** path on master under a non-multiplatform Android source root (e.g. `*/src/main/java/**`, `*/src/main/kotlin/**`, `*/src/test/java/**`, `*/src/androidTest/**`) that the new path supersedes — the OG Android source becoming a KMP port. |
| 4 | `build_config` | Path matches `**/build.gradle.kts`, `**/build.gradle`, `**/settings.gradle.kts`, `**/settings.gradle`, `**/libs.versions.toml`, `**/gradle.properties`, `**/Package.swift`, `**/Podfile`, `**/Podfile.lock`, `**/*.podspec`. |
| 5 | `nonmigrated` | Anything else — files in the diff that are not baseline assets, not iOS ports, not multiplatform source-set additions, and not build config. By definition these are files that were *not* the target of migration but are being touched anyway. |

### Baseline-asset patterns (Law 9 trigger)

A path is `baseline` if it matches any of:

```
**/snapshots/**
**/screenshots/**
**/goldens/**
**/__snapshots__/**
**/roborazzi/**
**/paparazzi/**
**/golden_images/**
**/golden_data/**
kmm_migration/baseline/**
```

Plus any of these file extensions inside the directories above: `.png`, `.webp`, `.jpg`, `.jpeg`, `.json`, `.txt`, `.bin`, `.pb`, `.proto`. A `.kt` file under `**/snapshots/` is **not** a baseline asset (test code, not artifact); only the listed extensions count.

If a path matches multiple bucket definitions, the **lowest-numbered** bucket wins (baseline > ios_port > migrated > build_config > nonmigrated).

## Procedure

1. **Fetch the PR file list** via `gh pr view <pr#> --json files,baseRefOid,headRefOid` and parse `files[].path` plus `files[].changeType`.
2. **Materialize `base_sha` and `head_sha`** from the response. Run `git fetch origin <base_branch>:<base_branch>` if the local repo is missing the base ref. If `git fetch` fails (auth, network), emit `STATUS: BLOCKED` with the exact error.
3. **For each path**, evaluate the buckets in priority order:
   - Match against baseline patterns first. If matched → `baseline`.
   - Else, match against iOS source-set patterns. If matched → `ios_port`.
   - Else, check the multiplatform source-set patterns. If matched, run the **paired-deletion check**: was there a corresponding removed or modified path on master that this addition supersedes? Use the heuristic in [Tie-breaking rules](#tie-breaking-rules). If yes → `migrated`. If no (e.g. the file is a brand-new commonMain file with no Android predecessor) → still `migrated`, but record `paired_master_path: null` for the per-file reviewer to handle (it will note the absence in the parity check).
   - Else, match against build-config patterns. If matched → `build_config`.
   - Else → `nonmigrated`.
4. **Emit the result** to `state.json` per `schemas/state_schema.md`.
5. **Sanity-check counts**: write a one-line summary to `pr_metadata.md` — e.g. `classifications: migrated=14 ios_port=3 nonmigrated=2 baseline=0 build_config=1 (total: 20)`. If the total does not equal `gh pr view files[].length`, emit `STATUS: BLOCKED` — a path was lost.

## Tie-breaking rules

### Paired-deletion heuristic for `migrated`

A new commonMain or androidMain path `P_new` is paired with a master path `P_old` if any of:

- `P_old` was deleted in the diff and the basename matches (`basename(P_new) == basename(P_old)`) and the package path is a substring match (e.g. `app/src/main/java/com/app/login/LoginViewModel.kt` ↔ `shared/src/commonMain/kotlin/com/app/login/LoginViewModel.kt`).
- The PR contains a git rename (`changeType: RENAMED`) where `oldPath` is on a non-multiplatform source root and `newPath` is on a multiplatform source root.
- `P_old` was modified (not deleted) but the diff shows almost all of its body was removed and the equivalent body now lives in `P_new` — detect by comparing line-count deltas.

If none match, the new file is `migrated` with `paired_master_path: null`. The per-file reviewer treats this as a brand-new addition and runs only the half of the checklist that does not require master comparison.

### Mixed-case files

A `commonMain` file that ALSO appears under a baseline pattern (e.g. `commonTest/.../snapshots/foo.png`) is `baseline` — Law 9 wins. There is no scenario in which a baseline asset should be classified anything else.

### iOS source-set without `.swift`

A `.kt` file under `iosMain/**` is `ios_port` — Kotlin `actual` declarations in iOS source sets count.

### Bot / generated files

Files matching `**/build/**`, `**/.gradle/**`, `**/generated/**`, `**/node_modules/**` MUST NOT appear in a real KMM-migration PR. If detected, classify as `nonmigrated` and the reviewer will flag them as `BUILD_OUTPUT_LEAKED` (BLOCKER).

## Output shape

`state.json.files` is an array of:

```json
{
  "path": "shared/src/commonMain/kotlin/com/app/login/LoginViewModel.kt",
  "change_type": "ADDED",
  "classification": "migrated",
  "paired_master_path": "app/src/main/java/com/app/login/LoginViewModel.kt",
  "review_status": "pending"
}
```

`review_status` starts as `pending` and is updated by the orchestrator after each per-file dispatch completes — values `pending`, `done`, `done_with_concerns`, `blocked`, `needs_context`.
