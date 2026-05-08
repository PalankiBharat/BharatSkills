<!-- TEMPLATE: generated to <repo>/kmm/<scope>/tasks.md by /kmm-tasks -->
<!-- Single source of truth for progress. Each task has a metadata block parsed by /kmm-implement. -->

# Tasks — [scope-name]

Checkbox states:
- `[ ]` pending
- `[x]` done
- `[!]` blocked on user input (REQUIRES_APPROVAL escalated)

---

## Phase A: Scaffold (sequential)

[one task per scaffolding interface from plan.md. zero tasks if plan needs no scaffolding.]

- [ ] **S-1: Create `[shared/src/commonMain/kotlin/[package]/[Interface].kt]`**
        subagent: migrator
        mode: scaffold
        interface-path: `shared/src/commonMain/kotlin/[package]/[Interface].kt`
        consumers-of-interface: `[FileA].kt`, `[FileB].kt`

---

## Phase B: Baseline capture (parallel across files)

[one task per in-scope file. all parallelizable; no `depends-on` between Phase B tasks.]

- [ ] **T-1: Capture baseline tests for `[FileA].kt`**
        subagent: test-capturer
        source: `app/src/main/java/[package]/[FileA].kt`
        target-staging: `shared/src/androidMain/kotlin/[package]/[FileA].kt`
        expected-tests: 5
        depends-on: `S-1`  [if test-capturer needs a scaffolding interface]
        consumers: `[ConsumerA].kt`, `[ConsumerB].kt`

- [ ] **T-2: Capture baseline tests for `[FileB].kt`**
        subagent: test-capturer
        source: `app/src/main/java/[package]/[FileB].kt`
        target-staging: `shared/src/androidMain/kotlin/[package]/[FileB].kt`
        expected-tests: 7
        depends-on: (none)
        consumers: `[ConsumerC].kt`

[... one task per in-scope file ...]

---

## Phase C: Baseline lock (orchestrator-run, single task)

- [ ] **T-LOCK: Lock baseline.**
        run-by: orchestrator (NOT a subagent)
        action:
          1. Run test command from `spec.md` against the worktree. All baseline tests must be GREEN.
          2. `git add` everything in the worktree.
          3. `git commit -m "baseline: capture [scope-name] @ <SHA>"` where `<SHA>` = `git rev-parse HEAD` after step 2.
          4. Append `baseline-locked-sha: <SHA>` to `spec.md` and commit.
        post-condition: every file under `commonTest/` is now immutable per Constitution §7.

---

## Phase D: Migration (DAG-ordered; parallel within levels)

[Files grouped by topological level. Level 0 has no in-scope deps; each later level depends only on earlier levels. Within a level, tasks parallelize.]

### Level 0

- [ ] **M-1: Migrate `[FileA].kt`**
        subagent: migrator
        mode: migrate
        source-staging: `shared/src/androidMain/kotlin/[package]/[FileA].kt`
        target: `shared/src/commonMain/kotlin/[package]/[FileA].kt`
        library-swaps: `[from migration-guide.md entry — exact list with versions]`
        expect-actual: `[from migration-guide.md entry]`
        platform-apis: `[from migration-guide.md entry]`
        public-api: `[verbatim from migration-guide.md entry]`
        consumers: `[ConsumerA].kt`, `[ConsumerB].kt`
        test-command: `[from spec.md]`
        expected-tests: 5
        depends-on: T-LOCK

- [ ] **M-2: Migrate `[FileB].kt`**
        ... (parallel with M-1)

### Level 1

- [ ] **M-3: Migrate `[FileC].kt`**
        depends-on: M-1
        ...

### Level 2

- [ ] **M-N: Migrate `[FileLast].kt`**
        depends-on: M-3, M-4
        ...

[After each level, the orchestrator runs the level-boundary check: full baseline test suite + per-target compile. Failures trigger refire of the responsible migrate task.]

---

## Phase E: Remediation (round N) — populated by /kmm-verify

[Empty initially. /kmm-verify on FAIL appends remediation tasks here. Each round increments N. The orchestrator runs them via /kmm-implement.]

[Example after a /kmm-verify FAIL:]

### Round 1

- [ ] **R-1: Remove residual `import retrofit2.Call` from `[file:line]` — Ktor swap incomplete**
        subagent: migrator
        target: `[file path]`
        violation: import retrofit2.Call still present at line 47
        depends-on: (none — direct fix)

---

## Strike counters (per task, mechanical retries)

[The orchestrator increments here when a mechanical failure refires. Reset on `[x]`. After 3 strikes, escalate to user.]

| Task | Strikes | Last failure |
|---|---|---|

---

## Constitution check log

[Each command appends a one-line constitution-check pass/fail at the bottom. Audit trail.]

- [DATE-TIME] /kmm-specify: PASS
- [DATE-TIME] /kmm-plan: PASS
- [DATE-TIME] /kmm-tasks: PASS
- ...
