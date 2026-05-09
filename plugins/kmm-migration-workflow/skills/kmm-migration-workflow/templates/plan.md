<!-- TEMPLATE: copied to <repo>/kmm/<scope>/plan.md by plan-phase -->

# Migration plan — [scope-name]

## Context

[one paragraph from spec.md's "Goal" plus what we discovered while reading the scope files. cite a few file:line references that anchor the plan.]

## Constitution version

This plan is governed by `kmm-migration-workflow/constitution.md` v[VERSION] as of [DATE].

## Baseline SHA

`<from spec.md>`

## Declared shared targets

`<from spec.md>`

## Verification commands

The exact commands `/kmm-verify` will run. **Verified** by running `./gradlew :<module>:tasks --all` against the worktree at plan time — never assumed.

```
# Per-target compile
./gradlew :shared:compileCommonMainKotlinMetadata
./gradlew :shared:compileKotlinAndroid
./gradlew :shared:compileKotlinIosArm64
./gradlew :shared:compileKotlinIosX64
# (or similar — populated from real `gradle :tasks --all` output)

# Per-target tests (where source set has tests)
./gradlew :shared:testDebugUnitTest
./gradlew :shared:iosX64Test
# ...

# Consumer compile
./gradlew :app:compileDebugKotlin
./gradlew :app:assembleDebug
# (and any other consumers)
```

## Migration unit summary

- Total in-scope files: `<N>`
- Dependency levels (DAG depth): `<L>`
- Library swaps proposed: `<count>` (full list with versions in `findings.md`)
- expect/actual declarations needed: `<count>`
- Required scaffolding interfaces: `<count>`

## Dependency DAG

Files grouped by topological level. Level 0 has no in-scope dependencies. Each later level depends only on earlier levels.

```
Level 0 (no in-scope deps; can capture & migrate first):
  - [FileA].kt
  - [FileB].kt

Level 1 (depend on Level 0):
  - [FileC].kt → depends on [FileA]
  - [FileD].kt → depends on [FileA], [FileB]

Level 2:
  - [FileE].kt → depends on [FileC], [FileD]
  - ...
```

## Required scaffolding interfaces

Created in Phase A before any baseline capture. These are the seams `commonTest` will use to fake external dependencies.

[one entry per interface]

### Interface: `[InterfacePath].kt` (in commonMain)

- **Path:** `shared/src/commonMain/kotlin/[package]/[InterfaceName].kt`
- **Purpose:** abstracts `[external dependency: e.g., the Android-only AuthSdk]` so consumers can be tested in `commonTest` with hand-written fakes
- **Methods (exact signatures):**
  - `fun [name]([params]): [ReturnType]`
  - ...
- **Consumers (in-scope files that will use this interface):**
  - `[FileA].kt` (line [N] currently calls `[external dep].method` directly; will call interface after capture)
  - ...

[if there are no scaffolding interfaces, write "None — every external dependency has a multiplatform replacement library."]

## Per-file plan summary

[a one-line summary per in-scope file. full per-file specs are in `migration-guide.md`.]

| File | Classification | Library swaps | expect/actual | Migrate after | Expected tests |
|---|---|---|---|---|---|
| [FileA].kt | migrate-pure | none | none | none | 5 |
| [FileB].kt | migrate-expect-actual | Logging → [Multiplatform Logger v3.4] | [PlatformClock] | none | 7 |
| [FileC].kt | migrate-pure | Networking → [Ktor Client v3.0.3] | none | [FileA] | 9 |
| ... | ... | ... | ... | ... | ... |

## Open questions

[list any decision the user owes before tasks-phase. examples: "for [Library X], which of two equally-valid replacements?". if zero, write "None — plan is self-contained."]

## Constitution check

[populated by plan-phase after plan-analyzer returns clean]

- §1 Understand before acting: every entry cites file:line — [pass/fail]
- §3 + §4 Live sources: every library version sourced live — [pass/fail]
- §5 Scope discipline: scope unchanged from spec.md — [pass/fail]
- §6 1:1 port: no behaviour-change tasks — [pass/fail]
- §7 Baseline first: every file has Expected tests count — [pass/fail]
- Platform-boundary §1–3: every expect/actual has level + justification — [pass/fail]

`PLAN_STATUS: APPROVED` (after user signs off)
