# Phase 4 — Execute (the move loop)

Goal: every plan step done, journaled, and green. One kmm-migrator dispatch per step; the orchestrator only routes, verifies, and records.

## Loop, per step S<n>

1. Mark `in-progress` in state.json (atomic: write temp file, `mv` over). Journal `dispatch`.
2. Dispatch kmm-migrator with the standard brief (SKILL.md) + the verbatim step. The worker:
   - reads the Law, the step, relevant contract lines, and the profile's verification commands;
   - S0 only: writes baselines per Law Rule 9 (red-first where pinning new assertions, then green, then commit);
   - move steps: `git mv` first, then whitelist edits only, compile-test gates, one commit per coherent unit using the repo's KMM commit style — `[Kmm - <Feature>] - If applied, this commit will <effect>`;
   - appends journal events itself; returns the report contract.
3. **Verify the report**: SHAs exist on the branch; gates list shows the step's commands with green results (JUnit XML checked, not task output — profile gotcha); `git diff -M90% --name-status <step-base>..HEAD` shows `R` for every moved file (Rule 1 evidence); journal entries present.
4. `done` → next step. `blocked` → blocker protocol below.

## Fix-loop doctrine (when a step's gate goes red)

The worker invokes superpowers:systematic-debugging — root cause before any fix. After a FAILED fix attempt: the diagnosis is invalidated, not refined — re-investigate with a fresh lens treating the failed fix as data about what the root cause is NOT. Patch-chains (Fix N.1 on Fix N) are forbidden. Useful KMM-specific lenses: "does the sibling platform / an already-migrated feature implement this shape correctly — converge to it"; "is the cleanest KMM implementation different from the Android shape we're preserving — if so, STOP (behavior risk, G3)". Three failed dispatches on one step → G3 with the blocker file; never a fourth identical attempt.

## Standing constraints

- `:app` never stays red between steps — each step ends compiling with its tests green; there is no multi-step broken window.
- Touching `:shared` → `:shared:compileKotlinIosArm64` is part of that step's gate, and `:shared:compileTestKotlinIosSimulatorArm64` whenever the step moved or added commonTest code (test sources have their own Kotlin/Native portability failures — JVM-only idioms, illegal backtick names). The iOS klib keeps compiling all the way through, not just at phase 5.
- **One gradle build at a time, anywhere.** Never dispatch a second worker whose gates run gradle while another build is in flight (same or sibling worktree) — daemon/build-dir contention produces stuck workers and missing JUnit XML. This is the main reason execute steps run sequentially.
- **Every gradle invocation gets a watchdog.** This host has no coreutils `timeout` (profile gotcha): run via background task with a per-task ceiling (compile ~10m, unit tests ~20m, assemble ~30m), monitor the log, kill + record a blocker on breach. A silent hang is a `blocked` step, not a longer wait.
- **Rename-safe revert protocol.** Never `git checkout -- <path>` on a file that was `git mv`-ed this session — with a staged rename it restores the PRE-migration blob and destroys work. Revert = `git stash push` (snapshot first) or `git reset`/revert of whole commits, per the step's rollback line.
- Baselines are frozen (Law Rule 9). A step that "needs" a baseline edit is either mis-planned (back to phase 3 for that step) or a behavior change (G3) — record the exception either way in `blockers/`, append-only.
- Unrelated breakage discovered mid-step: quarantine + flag, never fix (Rules 3/9).
- Scope drift check on every report: files touched ⊆ files the step names. Anything extra → reject the report, re-dispatch with the violation named.

Journal `phase-done` when all steps are `done`; set phase 5.

Exit (run fresh, in order):
1. Rename-audit clean (`git diff -M90% --name-status <base>..HEAD` — every move shows `R`).
2. Full `:app` unit suite + `:shared` commonTest green.
3. **Cold iOS compile**: `./gradlew clean` scoped to `:shared` then `:shared:compileKotlinIosArm64` — a warm KSP/compile cache has masked expect/actual contract violations here before (`--rerun-tasks` is banned in this repo; clean-then-compile is the cold path).
4. **Framework-level smoke**: `pod install` in `Punch/` + `xcodebuild build` of the workspace. SKIE generates code at framework-link time — klib compile alone misses a class of SKIE errors, and standalone `linkPod*` is known-broken here (Finance.framework comes from pods), so the app build IS the link gate. Pre-existing link failures must be A/B-confirmed against the pre-migration commit before being declared out-of-scope.
