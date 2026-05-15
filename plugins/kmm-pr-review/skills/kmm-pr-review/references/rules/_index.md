# Rule index

**This is what specialists always load.** It's the triage layer: one terse line per rule. When a pattern looks like it might fire, the specialist reads the full rule body from the file path shown and emits a finding only if the full body confirms.

## Format

```
<RULE-ID> [<severity>{, iOS_blocking}{, root}] — <trigger pattern>. → <where to load full body>
```

- `severity` is the base; `P0/P1` means context-dependent (the rule body says when).
- `iOS_blocking` means: on migration PRs, the aggregator auto-promotes to P0.
- `root` means: this rule is a parent in `references/derivative-map.md`; if it fires, certain derivative findings get collapsed under it.

## Always loaded in full (skip the index for these)

- `_base.md` — KMP fundamentals (expect/actual, type leakage, coroutines, idiomatic Kotlin base). ~5 rule families, 17 rules.
- `hygiene.md` — TODOs, stubs, comments, KDoc. 6 rules.
- `<role>.md` — the file's detected role rules. 5-7 rules.

## Conditional — load body only when a candidate fires

### iOS readiness (`ios-readiness.md`) — when surface ∈ {SHARED_COMMON, SHARED_PLATFORM} or migration=true

- I-READY-01 [P0, iOS_blocking] — `kotlin.Result<T>`, `value class`, `inline class`, `Duration` in iOS-exposed public API. → erases at bridge.
- I-READY-02 [P0, iOS_blocking] — public `interface Foo<T>` or top-level `fun <T> bar(...)` exported to iOS. → type param erases to AnyObject.
- I-READY-03 [P1] — generic interface where a generic class would serve.
- I-READY-04 [P0, iOS_blocking] — public `suspend` callable from iOS, can throw, no `@Throws`. → terminates app on iOS.
- I-READY-05 [P1] — complex enum (generics/behavior) exposed to iOS.
- I-READY-06 [P1] — sealed root with generic param, or non-data-class children, exposed to iOS.
- I-READY-07 [P2] — iOS code uses `MyObject()` instead of `.shared`/`.companion`.
- I-READY-08 [P2] — top-level `fun`/`val` in commonMain consumed from iOS (becomes `<File>Kt.x()`).
- I-READY-09 [P2] — `Map`/`List`/`Set` exposed to iOS in a hot path (per-frame/per-scroll/tight loop).
- I-READY-10 [P1, iOS_blocking] — public API returns `MutableList`/`MutableMap`/`MutableSet` expecting iOS mutation.
- I-READY-11 [P2] — internal-only API exported in iOS framework (bloats surface).
- I-READY-12 [P3] — awkward auto-translated Swift name (could use `@ObjCName`).
- I-READY-13 [P1/P2] — public Kotlin declaration in iOS surface lacking KDoc.
- I-READY-14 [P2/P3] — lambda with primitive parameter types in iOS hot path (boxing cost).
- I-READY-15 [P1, iOS_blocking] — newer platform-class API used in shared without availability check.
- I-SKIE-01 [P0/P1, iOS_blocking, root] — `:shared/build.gradle.kts` missing `id("co.touchlab.skie")` but shared exports Flow/suspend/sealed.
- I-SKIE-02 [P1] — SKIE version outside supported range for project Kotlin version.
- I-SKIE-03 [P1] — iOS uses manual `Flow.collect` wrapper when SKIE would expose `SkieSwiftFlow<T>`.
- I-SKIE-04 [P0, iOS_blocking] — iOS code treats `SkieSwiftFlow<T>` and `SkieSwiftOptionalFlow<T>` as the same type.
- I-SKIE-05 [P1] — sealed type annotated `@SealedInterop.Disabled` but consumed from iOS.
- I-SKIE-06 [P1] — `@SealedInterop.EntireHierarchyExport.Disabled` leaving Swift unable to reach children.
- I-SKIE-07 [P0, iOS_blocking] — SKIE annotation imported without `co.touchlab.skie:configuration-annotations` dependency.
- I-SKIE-08 [P2] — iOS Swift calls Kotlin defaults without `@DefaultArgumentInterop.Enabled`.
- I-SKIE-09 [P0, iOS_blocking] — Swift `as!`/`as?`/`is` on `SkieKotlinFlow`/`SkieKotlinStateFlow`.
- I-SKIE-10 [P2] — both SKIE and KMP-NativeCoroutines wrap the same boundary.

### NEW files in commonMain (`new-commonmain-file.md`) — when change_type=NEW AND surface=SHARED_COMMON

- NC-01 [P1] — new file's primary class duplicates ≥70% of an existing master file (same package/role).
- NC-02 [P1] — structure deviates from canonical KMP patterns (`expect class` for business logic, hand-rolled Flow wrapper where SKIE would handle).
- NC-03 [P2] — new class with single small responsibility on one input type — could be extension function.
- NC-04 [P2] — public declarations missing explicit visibility or explicit return type.
- NC-05 [P0] — imports `java.*`/`javax.*`/`android.*`/`kotlin.jvm.*`/non-KMP `androidx.*`. → same as S-TYPE-01.
- NC-06 [P1] — non-trivial branching/computation but no `commonTest` counterpart in the PR.
- NC-07 [P1] — package doesn't match sibling-file conventions in master.
- NC-08 [P2] — name diverges from team naming patterns (verb/suffix conventions).
- NC-09 [P1] — file's only call sites in this PR are Android; no iOS consumer change.
- NC-10 [P2] — ≤30 lines of substance, could live in an existing related file.
- NC-11 [P0] — exposes generic interface or top-level generic function to iOS. → same as I-READY-02.
- NC-12 [P1] — sealed type for iOS with class (non-data) children or generic root.

### NEW files anywhere (`new-file-clean-code.md`) — when change_type=NEW

- NF-CLEAN-01 [P1] — function nesting >3 levels OR cyclomatic complexity >10.
- NF-CLEAN-02 [P0/P1] — duplicates a master file (same package/role) ≥70% line-similarity.
- NF-CLEAN-03 [P1] — file >300 lines OR class with >7 public methods/properties without clear cohesion.
- NF-CLEAN-04 [P1] — new `interface` with single `Impl`, no test fake, no platform impls, no documented future use.
- NF-CLEAN-05 [P0/P2] — class name `*Util`/`*Helper`/`*Manager`/`*Wrapper`/`*Handler`/`*Service` without justification; or function name not a verb phrase.
- NF-CLEAN-06 [P2] — single-class file whose name doesn't match the class; or generic `Utils.kt` name with multiple declarations.
- NF-CLEAN-07 [P1] — function body >30 lines (verify against master average first).
- NF-CLEAN-08 [P1] — function with >5 parameters.
- NF-CLEAN-09 [P2] — `Boolean` flag parameter (`isStrict`, `skipCache`, `useNewMode`).
- NF-CLEAN-10 [P2] — magic numeric/string literals in business logic (not 0/1/-1/2).
- NF-CLEAN-11 [P3] — micro-optimization without a comment-justified benchmark.

### Migration drift (`migration-drift.md`) — when `is_migration_file=true`

- M-CLEANUP-01 [P0/P1, root] — addition under `:shared/src/commonMain/.../<X>.kt` without deletion of `app/src/main/.../<X>.kt`.
- M-CLEANUP-02 [P1] — moved class still has `@Inject constructor`/`@Module`/`@Provides`/`@Binds`; or orphan Hilt `@Provides` referencing the deleted Android-only class.
- M-CLEANUP-03 [P1] — moved class has a test under `androidTest/` or `app/src/test/` that wasn't moved to `commonTest`.
- M-PARITY-01 [P0, root] — migrated class has no iOS consumer call site (only Android-side consumer changes in the diff).
- M-PARITY-02 [P1] — iOS Koin module binds the concrete class instead of the new interface.
- M-PARITY-03 [P0/P1] — signature differences between master version and new commonMain version (params, return, suspend, generics, nullability, defaults).
- M-PARITY-04 [P1] — visibility tightened during migration (e.g., `internal` added where master was public).
- M-VISUAL-01 [P1] — migrated Compose screen without Paparazzi/Roborazzi baseline carryover.
- M-VISUAL-02 [P1] — regenerated `.png` baselines without PR-description explanation.
- M-BUILD-01 [P0, iOS_blocking] — Android-only dependency added to `commonMain.dependencies { }`.
- M-BUILD-02 [P1] — same dependency in commonMain/androidMain/iosMain with different versions.
- M-DOC-01 [P2] — migration PR description doesn't enumerate moved files / consumer impact / test coverage / baselines.

### Role-specific summaries (loaded automatically with `<role>.md`, listed here for cross-reference)

**usecase (`usecase.md`)** — UC-01 single `operator fun invoke` [P1]; UC-02 constructor injection [P1]; UC-03 sealed result, not exceptions [P1]; UC-04 `@Throws` on iOS-consumed suspend [P0]; UC-05 no business logic leak to ViewModel [P2].

**viewmodel (`viewmodel.md`)** — VM-01 extends `androidx.lifecycle.ViewModel` [P1]; VM-02 `StateFlow` for state [P1]; VM-03 private mutable / public immutable [P2]; VM-04 `viewModelScope` not free scope [P1]; VM-05 dispatcher injected [P1]; VM-06 no platform types in shared VM [P0]; VM-07 `Channel`/`SharedFlow(replay=0)` for one-shot events [P2].

**repository (`repository.md`)** — REPO-01 interface in commonMain [P1]; REPO-02 `Flow`/`suspend`, not Rx/LiveData [P1]; REPO-03 no platform types in interface [P0]; REPO-04 `@Throws` on iOS-consumed suspend [P0]; REPO-05 explicit caching strategy in name [P2].

**model (`model.md`)** — MOD-01 domain models separate from DTOs [P1]; MOD-02 sealed children as data class/object [P1]; MOD-03 specialize sealed root for iOS [P1]; MOD-04 no inline/value classes in public surface [P0]; MOD-05 plain enums for iOS [P1]; MOD-06 consistent `equals`/`hashCode` [P1].

**di-module (`di-module.md`)** — DI-01 `viewModel`/`factory`, not `single` for per-screen [P1]; DI-02 `expect val platformModule` [P1]; DI-03 bind interfaces, not concrete types [P1]; DI-04 no Hilt annotations [P1]; DI-05 too many `get()` chains [P2].

**compose-screen (`compose-screen.md`)** — CS-01 state-driven composable, not VM-coupled [P1]; CS-02 side effects via `LaunchedEffect`/`DisposableEffect` [P1]; CS-03 state in VM, not `remember` [P2]; CS-04 `collectAsStateWithLifecycle` [P2]; CS-05 `Modifier` parameter [P2].

**swiftui-view (`swiftui-view.md`)** — SV-01 `for await` consumption via SKIE [P1]; SV-02 `.shared`/`.companion` singletons [P2]; SV-03 `onEnum(of:)` exhaustive switch [P2]; SV-04 `.task` lifecycle-bound async [P1]; SV-05 no `as!`/`as?`/`is` on `SkieKotlin___Flow` [P0]. (SV-05 duplicates I-SKIE-09 for emphasis from the iOS side.)

**test (`test.md`)** — T-01 shared behavior in `commonTest` [P1]; T-02 `runTest` not `runBlocking` [P2]; T-03 JVM-only mocking → keep platform-specific [P1]; T-04 Turbine for Flow tests [P2]; T-05 focused assertions per test [P2].

**build (`build.md`)** — B-01 versions in `libs.versions.toml` [P2]; B-02 deps in correct source set [P0]; B-03 SKIE plugin applied [P0] (overlaps I-SKIE-01); B-04 same Kotlin version across modules [P1]; B-05 `export(...)` for iOS framework public-API transitives [P1].

## Lazy-load protocol

1. Read this index + the always-loaded files in full.
2. Scan the file content for likely triggers (use `current_content`).
3. For each candidate that matches an index entry: **read the full rule body** from the file path indicated, confirm the rule's pattern actually applies, and only then emit the finding.
4. If the candidate is ambiguous and the full body resolves it, document the resolution in the finding's `why`.
5. If you skip loading a body and emit anyway, mark `confidence: "low"` — the aggregator will scrutinize.
