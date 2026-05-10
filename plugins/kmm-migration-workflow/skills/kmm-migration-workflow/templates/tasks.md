<!-- TEMPLATE: generated to <repo>/kmm/<scope>/tasks.md by tasks-phase -->
<!-- Single source of truth for progress. Each task has a metadata block parsed by implement-phase. -->

# Tasks — [scope-name]

Checkbox states:
- `[ ]` pending
- `[x]` done
- `[!]` blocked on user input (REQUIRES_APPROVAL escalated)

Tasks are batched by checkpoint per Constitution §13. Each checkpoint runs to completion (capture → lock → migrate → verify → PR), then the next.

---

## CP-1: [checkpoint-name]

### Phase A: Scaffold (sequential)

[one task per scaffolding interface from plan.md whose dependents are in this checkpoint. Zero tasks if plan needs no scaffolding.]

- [ ] **CP-1/S-1: Create `[shared/src/commonMain/kotlin/[package]/[Interface].kt]`**
        checkpoint: [name]
        subagent: migrator
        mode: scaffold
        interface-path: `shared/src/commonMain/kotlin/[package]/[Interface].kt`
        consumers-of-interface: `[FileA].kt`, `[FileB].kt`

### Phase B: Baseline capture (parallel within checkpoint)

- [ ] **CP-1/T-1: Capture baseline tests for `[FileA].kt`**
        checkpoint: [name]
        subagent: test-capturer
        mode: baseline
        source: `app/src/main/java/[package]/[FileA].kt`
        target-staging: `shared/src/androidMain/kotlin/[package]/[FileA].kt`
        expected-tests: 5
        depends-on: `CP-1/S-1`  [if test-capturer needs a scaffolding interface]
        consumers: `[ConsumerA].kt`, `[ConsumerB].kt`

- [ ] **CP-1/T-2: Capture baseline tests for `[FileB].kt`**
        ...

### Phase B-smoke: Smoke test capture (single task per scope, in the first capture-bearing checkpoint)

- [ ] **CP-1/T-SMOKE: Write smoke test from architecture.md § Smoke test**
        checkpoint: [name]
        subagent: test-capturer
        mode: smoke
        smoke-spec: [architecture.md § Smoke test]
        instrumented-enabled: true | false
        consumer-module: `:app`
        depends-on: CP-1/T-1, CP-1/T-2  [every Phase B task in this checkpoint that touches a type the smoke resolves]

### Phase C: Baseline lock (orchestrator-run, single task per relocation checkpoint)

- [ ] **CP-1/T-LOCK: Lock baseline.**
        run-by: orchestrator (NOT a subagent)
        action:
          1. Run test command from `spec.md` against the worktree. All baseline tests must be GREEN.
          2. `git add` everything in the worktree.
          3. `git commit -m "baseline: capture [scope]/[checkpoint] @ <SHA>"` where `<SHA>` = `git rev-parse HEAD` after step 2.
          4. Append `baseline-locked-sha: <SHA>` to `spec.md` and commit.
        post-condition: every file under `commonTest/` is now immutable per Constitution §8.

### Phase D: Migration (DAG-ordered; parallel within levels)

#### Level 0

- [ ] **CP-1/M-1: Migrate `[FileA].kt`**
        checkpoint: [name]
        subagent: migrator
        mode: migrate
        path: surgical | refactor
        refactor-entries: R-1, R-2  [only when path: refactor]
        source-staging: `shared/src/androidMain/kotlin/[package]/[FileA].kt`
        target: `shared/src/commonMain/kotlin/[package]/[FileA].kt`
        library-swaps: [from migration-guide.md]
        expect-actual: [from migration-guide.md]
        platform-apis: [from migration-guide.md]
        public-api: [verbatim from migration-guide.md]
        consumers: `[ConsumerA].kt`, `[ConsumerB].kt`
        test-command: [from spec.md]
        expected-tests: 5
        depends-on: CP-1/T-LOCK

- [ ] **CP-1/M-2: Migrate `[FileB].kt`**
        ... (parallel with M-1)

#### Level 1

- [ ] **CP-1/M-3: Migrate `[FileC].kt`**
        depends-on: CP-1/M-1

[After each level, the orchestrator runs the level-boundary check: full baseline test suite + per-target compile.]

#### Phase D-smoke: Re-run smoke test (single task per checkpoint, after all migrate tasks)

- [ ] **CP-1/SMOKE-RUN: Re-run JVM smoke test against migrated form**
        run-by: orchestrator (gradle invocation, not a subagent)
        jvm-command: `./gradlew :<consumer-module>:test --tests "<smoke-fqn>"` [from architecture.md § Smoke test]
        instrumented-command: `./gradlew :<consumer-module>:connectedDebugAndroidTest --tests "<fqn>"` [run only if `Instrumented smoke § Status: enabled`]
        depends-on: every Phase D task in this checkpoint

### Verify (CP-1)

`verify-passed: <ISO date>` once `completeness-verifier` returns `VERIFY_COMPLETE_PASS` for this checkpoint.

### PR (CP-1)

`pr: <URL>` once `gh pr create` returns. Recorded inline by pr-phase.

---

## CP-2: [next-checkpoint-name]

[same structure]

---

## Constitution check log

[Each command appends a one-line check at the bottom. Audit trail.]

- [DATE-TIME] specify-phase: PASS
- [DATE-TIME] architect-phase: PASS
- [DATE-TIME] plan-phase: PASS
- [DATE-TIME] tasks-phase: PASS
