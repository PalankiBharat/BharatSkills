# Phase 4 — Execute (the move loop)

Goal: every plan step done, journaled, and green. One kmm-migrator dispatch per step; the orchestrator only routes, verifies, and records.

## Loop, per step S<n>

1. Mark `in-progress` in state.json (atomic: write temp file, `mv` over). Journal `dispatch`.
2. Dispatch kmm-migrator with the standard brief (SKILL.md) + the verbatim step. Its method — baselines-first for S0, `git mv`-then-whitelist for moves, gates, commit style, journaling, report — lives in the agent file; don't re-spec it in the brief.
3. **Verify the report** — beyond SKILL.md's baseline (SHAs + journal exist): the gates list shows the step's commands green via JUnit XML, not task output (knowledge-base gotcha); `git diff -M90% --name-status <step-base>..HEAD` shows `R` for every moved file (Rule 1 evidence).
4. `done` → next step. `blocked` → blocker protocol below.

## Fix-loop doctrine (when a step's gate goes red)

The worker runs its own failure protocol (systematic-debugging, fresh lens after a failed fix, no patch-chains — agent file). Pass these KMM lenses into any re-dispatch: "does the sibling platform / an already-migrated feature implement this shape correctly — converge to it"; "is the cleanest KMM implementation different from the Android shape we're preserving — if so, STOP (behavior risk, G3)". Three failed dispatches on one step → G3 with the blocker file; never a fourth identical attempt.

## Standing constraints

- Steps touching `:shared` gate on all four compile targets — `:shared:compileDebugKotlinAndroid`, `:shared:compileKotlinMetadata`, `:shared:compileKotlinIosArm64`, `:app:compileProductionDebugKotlin` (the app compile catches cross-module call-site breaks pre-CI) — plus `:shared:compileTestKotlinIosSimulatorArm64` whenever the step moved or added commonTest code (test sources have their own Kotlin/Native portability failures). The iOS klib keeps compiling all the way through, not just at phase 5.
- **One gradle build at a time, anywhere.** Never dispatch a second worker whose gates run gradle while another build is in flight (same or sibling worktree) — daemon/build-dir contention produces stuck workers and missing JUnit XML. This is the main reason execute steps run sequentially.
- **Every gradle invocation gets a watchdog.** This host has no coreutils `timeout` (profile gotcha): run via background task with a per-task ceiling (compile ~10m, unit tests ~20m, assemble ~30m), monitor the log, kill + record a blocker on breach. A silent hang is a `blocked` step, not a longer wait.
- A step that "needs" a baseline edit (frozen, Law Rule 9) is either mis-planned (back to phase 3 for that step) or a behavior change (G3) — record the exception either way in `blockers/`, append-only.
- Scope drift check on every report: files touched ⊆ files the step names. Anything extra → reject the report, re-dispatch with the violation named.

Journal `phase-done` when all steps are `done`; set phase 5.

Exit (run fresh, in order):
1. Rename-audit clean (`git diff -M90% --name-status <base>..HEAD` — every move shows `R`).
2. Full `:app` unit suite + `:shared` commonTest green.
3. **Cold iOS compile**: `./gradlew clean` scoped to `:shared` then `:shared:compileKotlinIosArm64` — a warm KSP/compile cache has masked expect/actual contract violations here before (`--rerun-tasks` is banned in this repo; clean-then-compile is the cold path).
4. **Framework-level smoke**: `pod install` in `Punch/` + `xcodebuild build` of the workspace. SKIE generates code at framework-link time — klib compile alone misses a class of SKIE errors, and standalone `linkPod*` is known-broken here (Finance.framework comes from pods), so the app build IS the link gate. Pre-existing link failures must be A/B-confirmed against the pre-migration commit before being declared out-of-scope.
