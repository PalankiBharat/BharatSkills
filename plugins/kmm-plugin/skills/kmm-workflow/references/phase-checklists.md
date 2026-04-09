# Phase Checklists

Run the relevant checklist at every phase boundary. Every unchecked item is a BLOCKER — do not proceed to the next phase until all items pass. Read `cross-platform-parity.md` for detailed guidance on cross-platform items.

---

## Phase 1: PLAN — Pre-Approval Gate

Run before presenting plan to user.

- [ ] migration-guide.md: ALL 15 fields populated for every file (no TBD, no blanks)
- [ ] migration-guide.md: Platform APIs field lists every Android-only API with replacement
- [ ] migration-guide.md: Expected tests field has minimum count >= 1 per public method
- [ ] migration-guide.md: Callbacks field lists every callback param with parent and wiring target
- [ ] migration-guide.md: Decisions field has rationale for every library swap
- [ ] findings.md: Decisions table populated with all planning decisions + rationale
- [ ] findings.md: Library versions verified via web search (not training data)
- [ ] PLAN.md: Build commands use verified Gradle task names (from Task 1.13)
- [ ] PLAN.md: Device serials recorded in header
- [ ] Dependency DAG: no cycles, topological order matches PLAN.md task order
- [ ] manual-test-checklist.md generated with per-screen test steps
- [ ] Plan quality review: zero BLOCKERs, zero HIGH issues remaining
- [ ] build-verify.sh generated with verified build commands
- [ ] parity-check.sh generated with all 10 static checks
- [ ] Worktree builds clean (build-verify.sh passes)

## Phase 2: SCAFFOLD — Post-Scaffold Gate

Run after scaffold commit, before Phase 3.

- [ ] All interfaces from migration-guide.md created in commonMain
- [ ] All androidMain actuals delegate to original implementations
- [ ] commonTest source set configured with kotlin("test") + kotlinx-coroutines-test
- [ ] kotlinx-atomicfu added if any migrated file uses @Synchronized or java.util.concurrent
- [ ] Fakes writable in commonTest for all scaffolded interfaces
- [ ] build-verify.sh passes (all platforms compile)
- [ ] .gitignore uses `**/build/` (not `/build`) — KMM adds nested build dirs (shared/build/) that `/build` misses
- [ ] settings.gradle has `pluginManagement` block with google(), mavenCentral(), gradlePluginPortal() — required for AGP plugin resolution in KMM modules
- [ ] Checkpoint committed

## Phase 3: SHARED CODE MIGRATION — Post-Migration Gate

Run after all dependency levels complete, before /clear.

- [ ] Every file: FILE_VERIFIED with tests >= Expected tests from migration-guide.md
- [ ] Test fixture sync: all fake/stub classes in commonTest match current public API of migrated classes (no stale enum names, parameter counts, or field types). After modifying any interface in commonMain, grep commonTest for all implementations/fakes of that interface and add new members — missing members cause iOS test compilation failures.
- [ ] Analytics event audit: for each migrated ViewModel, grep original for `track(`, `analytics.`, `logEvent()`, and project-specific analytics SDK calls — inventory all analytics events and verify they fire in the shared VM.
- [ ] Every file: VERIFY_PASS from structural verification
- [ ] No FILE_BLOCKED remaining (all resolved or escalated)
- [ ] Full unit test suite passes: ./gradlew :shared:testDebugUnitTest
- [ ] API surface diff recorded in findings.md (Breaking Changes for Consumers)
- [ ] SharedFlow collector audit: no SharedFlow with multiple concurrent collectors on replay=0
- [ ] Interactor disposal: every ViewModel field with a `dispose()`/`close()`/`cancel()` method is called in `handleDispose()`
- [ ] Mapper dedup: grep for duplicate class names (*Mapper, *Converter) across commonMain — extract any duplicates to shared files
- [ ] Strategy/algorithm coverage: every *Strategy, *Calculator, *Algorithm, *Resolver, *Selector class has at least one test per public method
- [ ] Cross-platform Koin binding verification: every VM constructor param has binding in BOTH androidBridgeModule AND iosBridgeModule
- [ ] Auditor sweep: AUDIT_COMPLETE with zero CRITICAL issues; HIGH/MEDIUM items either fixed or documented as intentional in FINDINGS.md
  (The above checklist items are checked BOTH by the migrator's self-verification AND by the auditor sweep. The auditor should find zero new issues — if it does, the migrator's self-verification was incomplete.)
- [ ] No staged androidMain copies remaining (all deleted after migration)
- [ ] String literal diff: all user-visible strings identical to originals
- [ ] PROGRESS.md updated and committed
- [ ] Checkpoint committed
- [ ] Retrospective run (before /clear)
- [ ] Handoff doc written (handoff-phase-3.md)

## Phase 4: WIRE ANDROID — Post-Wiring Gate

Run after Android wiring, before appium-mcp E2E.

- [ ] All imports updated to use shared module paths
- [ ] DI rewired (Hilt→Koin) — all VM bindings registered
- [ ] Original Android files deleted (grep-before-delete)
- [ ] Stub audit: zero error("…"), TODO(), TODO("…") in non-test migrated files
- [ ] Empty lambda audit: every callback param with default = {} traced to real action
- [ ] Koin binding completeness: all VM constructor params AND child composable types have bindings
- [ ] Build + unit tests pass
- [ ] parity-check.sh passes (all 10 checks green)
- [ ] DI binding audit: every constructor-injected dependency has a Koin binding (run koin-binding-check.py). For each Koin `single<Interface>`, verify the Hilt `@Provides` chain provides the same implementation or decorator — not a simpler substitute. koin-binding-check.py only verifies bindings exist, not decorator equivalence.
- [ ] appium-mcp E2E: all screens pass on Android device (3-build comparison)
- [ ] Manual test: structured checklist from migration-guide.md breaking changes
- [ ] PROGRESS.md updated and committed
- [ ] Checkpoint committed

## Phase 5: WIRE iOS — Post-Wiring Gate

Run after iOS wiring, before final commit.

- [ ] SwiftUI screens wired for all platform-stay files
- [ ] Koin iOS module: all bindings registered (same completeness check as Phase 4)
- [ ] Navigation + pbxproj updated
- [ ] Stub audit: zero error("…"), TODO(), TODO("…"), // TODO, // FIXME, // HACK in non-test files
- [ ] Empty lambda audit (same as Phase 4 — for CMP screens shared with iOS)
- [ ] Info.plist keys: every Bundle.main.infoDictionary read has matching key
- [ ] Asset parity: every Image("x") / LottieAnimation.named("x") resolves to actual file
- [ ] SDK lifecycle listeners: every Android registration has iOS equivalent
- [ ] SDK init parameters: identical parameter lists between platforms
- [ ] Route mapping: every sealed class/enum variant has explicit mapping (no else→null)
- [ ] Session fields: every isLoggedIn/isTokenExpired field is written by all save paths
- [ ] Flow inventory: every SharedFlow/Channel in shared ViewModels has a corresponding iOS `.task {}` collector (run flow-collector-check.sh)
- [ ] Callback audit: every onClick/onAction in Android UI maps to an equivalent iOS handler
- [ ] UI branch audit: every conditional rendering path in Android UI exists in iOS view
- [ ] DI binding audit: every constructor-injected dependency has a Koin binding (run koin-binding-check.py)
- [ ] Build + unit tests pass
- [ ] parity-check.sh passes (all 10 checks green)
- [ ] appium-mcp E2E: all screens pass on iOS simulator (3-build comparison)
- [ ] Cross-platform parity: 3-build comparison (master Android vs migrated Android vs iOS) — all screens classified
- [ ] Manual test: structured checklist — should find zero issues if above passed
- [ ] PROGRESS.md updated and committed
- [ ] Checkpoint committed
- [ ] Retrospective run (final)
