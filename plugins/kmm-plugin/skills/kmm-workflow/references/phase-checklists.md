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
- [ ] PLAN.md: Device serial and ports allocated and recorded in header
- [ ] Dependency DAG: no cycles, topological order matches PLAN.md task order
- [ ] plan-analyzer: zero BLOCKERs, zero HIGH issues remaining
- [ ] build-verify.sh generated with verified build commands
- [ ] parity-check.sh generated with all 10 static checks
- [ ] screen-map.json and fake-server-config.json committed in worktree
- [ ] Worktree builds clean (build-verify.sh passes)

## Phase 2: SCAFFOLD — Post-Scaffold Gate

Run after scaffold commit, before Phase 3.

- [ ] All interfaces from migration-guide.md created in commonMain
- [ ] All androidMain actuals delegate to original implementations
- [ ] commonTest source set configured with kotlin("test") + kotlinx-coroutines-test
- [ ] kotlinx-atomicfu added if any migrated file uses @Synchronized or java.util.concurrent
- [ ] Fakes writable in commonTest for all scaffolded interfaces
- [ ] build-verify.sh passes (all platforms compile)
- [ ] Checkpoint committed

## Phase 3: SHARED CODE MIGRATION — Post-Migration Gate

Run after all dependency levels complete, before /clear.

- [ ] Every file: FILE_COMPLETE with tests >= Expected tests from migration-guide.md
- [ ] Every file: VERIFY_PASS from haiku verifier
- [ ] No FILE_BLOCKED remaining (all resolved or escalated)
- [ ] Full unit test suite passes: ./gradlew :shared:testDebugUnitTest
- [ ] API surface diff recorded in findings.md (Breaking Changes for Consumers)
- [ ] SharedFlow collector audit: no SharedFlow with multiple concurrent collectors on replay=0
- [ ] Cross-platform Koin binding verification: every VM constructor param has binding in BOTH androidBridgeModule AND iosBridgeModule
- [ ] Auditor sweep: AUDIT_COMPLETE with zero CRITICAL issues
- [ ] No staged androidMain copies remaining (all deleted after migration)
- [ ] String literal diff: all user-visible strings identical to originals
- [ ] PROGRESS.md updated and committed
- [ ] Checkpoint committed
- [ ] Retrospective run (before /clear)
- [ ] Handoff doc written (handoff-phase-3.md)

## Phase 4: WIRE ANDROID — Post-Wiring Gate

Run after Android wiring, before Appium.

- [ ] All imports updated to use shared module paths
- [ ] DI rewired (Hilt→Koin) — all VM bindings registered
- [ ] Original Android files deleted (grep-before-delete)
- [ ] Stub audit: zero error("…"), TODO(), TODO("…") in non-test migrated files
- [ ] Empty lambda audit: every callback param with default = {} traced to real action
- [ ] Koin binding completeness: all VM constructor params AND child composable types have bindings
- [ ] Build + unit tests pass
- [ ] parity-check.sh passes (all 10 checks green)
- [ ] Appium E2E: all flows pass on Android device (verify-first protocol)
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
- [ ] Build + unit tests pass
- [ ] parity-check.sh passes (all 10 checks green)
- [ ] Appium E2E: all flows pass on iOS simulator (verify-first protocol)
- [ ] Cross-platform parity: Android vs iOS screenshots compared for structural equivalence
- [ ] Manual test: structured checklist — should find zero issues if above passed
- [ ] PROGRESS.md updated and committed
- [ ] Checkpoint committed
- [ ] Retrospective run (final)
