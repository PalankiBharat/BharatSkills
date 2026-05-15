# Role detection

`scripts/classify.py` assigns each file a `role` from the table below. Role determines which rule files load alongside `_base.md`.

Detection order: filename suffix → folder path → content sniff. First confident signal wins. If all three are ambiguous, role = `unknown` and only `_base.md` + `hygiene.md` load.

## Roles

| Role | Filename suffix | Folder hints | Content sniff |
|---|---|---|---|
| `usecase` | `*UseCase.kt`, `*Interactor.kt` | `domain/`, `usecase/` | `operator fun invoke(` |
| `viewmodel` | `*ViewModel.kt`, `*VM.kt` | `presentation/`, `ui/` | `class X : ViewModel(`, `androidx.lifecycle.ViewModel`, `@HiltViewModel` |
| `repository` | `*Repository.kt`, `*RepositoryImpl.kt` | `data/`, `repository/` | `interface X : Repository`, `class X(...) : Repository` |
| `model` | `*Model.kt`, `*Entity.kt`, `*Dto.kt`, no-suffix data classes in `domain/` | `domain/`, `model/`, `entity/` | `data class`, `sealed (class\|interface)`, `enum class`, `@Serializable` |
| `di-module` | `*Module.kt`, `*DiModule.kt`, `*KoinModule.kt` | `di/`, `injection/` | `val .* = module {`, `@Module`, `@InstallIn` |
| `compose-screen` | `*Screen.kt`, `*Composable.kt` | `presentation/`, `ui/`, `screens/` | `@Composable`, `import androidx.compose.runtime.*` |
| `swiftui-view` | `*.swift` with `View` suffix | `iosApp/`, `Views/` | `struct .* : View {`, `import SwiftUI` |
| `test` | `*Test.kt`, `*Tests.kt`, `*Test.swift`, `*Spec.kt` | `commonTest/`, `androidUnitTest/`, `iosTest/`, `src/test/` | `@Test`, `import kotlin.test.*`, `import org.junit.*`, `import XCTest` |
| `build` | `build.gradle.kts`, `settings.gradle.kts`, `libs.versions.toml`, `Podfile`, `Package.swift` | `gradle/`, `buildSrc/`, root | — |
| `unknown` | anything else | — | — |

## Surface

Set by path patterns; orthogonal to role.

| Path pattern | Surface |
|---|---|
| `**/src/commonMain/**` | `SHARED_COMMON` |
| `**/src/androidMain/**`, `**/src/iosMain/**`, `**/src/<plat>Main/**` inside a `:shared`-style module | `SHARED_PLATFORM` |
| App-level paths not under `:shared` — `androidApp/**`, `app/src/main/**` | `ANDROID_CONSUMER` |
| `iosApp/**`, `**/*.swift` (outside `:shared`) | `IOS_CONSUMER` |
| Build files | `BUILD` |
| Test source sets | `TESTS` |

## change_type

Set from `git diff --name-status -M`:

| git status | change_type |
|---|---|
| `A` (added) | `NEW` |
| `M` (modified) | `MODIFIED` |
| `D` (deleted) | `DELETED` |
| `R<N>` where N ≥ 95 | `RELOCATION` |
| `R<N>` where N < 95 | `RENAMED_MODIFIED` |

## Migration detection

The PR is flagged as `MIGRATION` if any of:

- A pair where `D app/src/main/.../<X>.kt` + `A :shared/src/commonMain/.../<X>.kt` exists with the same class name and content similarity ≥ 80% by diff stat.
- A rename moves a file from an Android-only path into commonMain.
- PR title or body contains: `migrat`, `move to shared`, `move to :shared`, `move to commonMain`, `move to KMM`, `move to KMP` (case-insensitive).

When `MIGRATION` is detected, each migrated file gets `swarm_tier=sonnet-3-migration` and the master-grounded specialist runs in `drift` mode.

## Rules-to-load matrix

Determined per file from `(surface, role, change_type)`:

```
_base.md            : always
hygiene.md          : always
ios-readiness.md    : surface ∈ {SHARED_COMMON, SHARED_PLATFORM} OR migration=true
<role>.md           : if role != unknown
new-commonmain-file.md  : change_type=NEW AND surface=SHARED_COMMON
new-file-clean-code.md  : change_type=NEW
migration-drift.md  : migration=true (loaded by master-grounded specialist only)
```

The Sonnet receives only the union of these files. Smaller rule context = faster review, less prompt drift.
