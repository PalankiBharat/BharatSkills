# Phase: specify

Read by the `/kmm` orchestrator when state-detection routes to the **specify** phase. Not a user-invocable command — the user enters at `/kmm <scope> <intent>` and the router reads this file.

Read `skills/kmm-migration-workflow/constitution.md` first.

## Inputs

- `<scope-name>` — short slug (e.g., `auth-module`, `payments-data-layer`)
- Conversation context — the user's stated migration goal

## What you do

User-facing questions follow `references/orchestration-protocol.md` § "User question style": one question per turn, options + recommended + why, biased toward long-term canonical KMM. Do NOT bundle. Do NOT ask questions whose answers can be inferred from invocation context or from the codebase — comfort matters; every avoidable prompt is friction.

### 1. Parse the invocation for inferable answers (silent)

Before asking anything, extract from the user's `/kmm <scope> <intent>` invocation (and the surrounding conversation):

- **Concrete file paths** — listed in the intent? If yes, they're the in-scope list.
- **Negative scope hints** — "UI is out of scope", "consumers stay native", etc.
- **Feature / entry-point name** — anything that lets you trace files from a known entry.
- **Base branch** — explicitly mentioned? Otherwise auto-detected in step 4.

If the invocation already gives a concrete file list (3+ paths or a clearly-bounded directory), the goal-clarity gate is **satisfied**. Skip step 2.

### 2. Goal-clarity gate (CONDITIONAL — only if intent is fuzzy)

Fire only if step 1 did not produce a concrete file list. The gate is NOT mandatory; it exists for vague invocations like `/kmm auth-module` with no further detail.

If fired, ask one question at a time per the orchestration protocol — first the user-facing feature, then the entry point — until you can enumerate files by grepping from a known starting point.

If fired and the user immediately provides files in their reply, treat the gate as satisfied and proceed.

### 2.5. AndroidMain dep-direction check (silent — surfaced only when relevant)

For each in-scope file (or candidate file when scope is still being narrowed), grep the file's external imports. For every imported FQN that resolves to a project module (`com.<org>.<app>.<...>`), determine which gradle module owns it:

```
grep -E "^import com\.<org>\." <in-scope-file>
# For each matching FQN, find the module:
grep -rln "^package com\.<org>\.<the-package>$" <repo>/<module>/src/main/java/  <repo>/<module>/src/main/kotlin/
```

If any import resolves to a module that **depends on `:shared`** (e.g., `:app` in a typical setup), surface as a non-blocking finding to record in `findings.md § Gotchas`:

> **AndroidMain staging will be infeasible for this migration.**
>
> `<file>:<line>` imports `<symbol>` from module `<module>` (which declares `implementation(project(":shared"))`). When the file is moved to `shared/src/androidMain/...` for staging, that import cannot resolve — gradle's module dependency direction is `:<module> → :shared`, not the reverse.
>
> Recommendation: route this scope through the **fast-path's atomic-migrate** flow (Constitution §14). T-1, T-LOCK, and M-1 collapse into a single operation that goes directly `app → commonMain` with the swap and refactor applied. The `getIndianCalender`-style helper stays in its current module; the migrated file calls the multiplatform replacement instead.

Record the finding in `findings.md` under "Gotchas" with the file:line reference. Do NOT prompt the user — this is informational; the actual routing decision happens at end of specify-phase via the trivial-heuristic evaluation.

This check exists because the prior incident (sniper-v2-android GreetingUseCase, D-5) discovered this mid-flight after a failing `:shared:compileDebugKotlinAndroid`, costing ~10 minutes of redesign + a deviation-log entry. Catching it at specify-phase makes the redesign disappear.

### 3. Confirm in-scope files (CONDITIONAL — only if step 1 inferred them)

If step 1 produced the file list directly from the invocation, **do not re-ask**. Trust the user's explicit input. Move on.

If step 1 had to enumerate by tracing (because the user gave only an entry point, not files), present the enumerated list once for confirmation:

> Traced from `<entry-point>` → `<N>` files. Confirm or amend:
> ```
> 1. <path>
> 2. <path>
> ...
> ```
> [ok / amend / discuss]

### 4. Out-of-scope, targets, base branch — autodetect with sensible defaults (silent in the common case)

These three questions go silent unless detection is genuinely ambiguous.

**Out-of-scope:**
- Use any negative hints from the invocation ("UI is out of scope") directly.
- If the user explicitly listed in-scope files, default explicitly out-of-scope to: consumer apps (only imports may update), UI files in the same package as in-scope files, and same-package files not in the in-scope list. Record this in `spec.md` automatically.
- Do **not** ask. The user already declared scope by listing files.

**Shared targets:**
- Auto-detect from `shared/build.gradle.kts`. The recommendation is "all detected targets" per Constitution §10.
- Ask only if the build file is unusual (e.g., declares targets without source sets, or has `expect/actual`-only platforms). Otherwise record the full set silently.

**Base branch:**
- If exactly one of `main` / `master` exists on `origin`, use it. Silent.
- If both exist and HEAD is currently on one of them, use that. Silent.
- If both exist and HEAD is elsewhere, ask one question with two options.
- Otherwise (no `main`/`master`) ask with detected candidates.

For each silent autodetection, print a one-line summary so the user can see what was picked: `Targets: commonMain, androidMain, iosArm64, iosX64. Base branch: main.`

### 5. Create the worktree

- Path: `<repo>/.worktrees/kmm-<scope-name>/`
- Branch: `feature/kmm-<scope-name>` from the base branch picked in step 5
- Run: `git worktree add .worktrees/kmm-<scope-name> <base-branch> -b feature/kmm-<scope-name>`
- Copy `local.properties` if it exists at repo root.
- Record the worktree path in `spec.md`.
- All subsequent commands operate against the worktree, not the main repo working tree.

### 6. Record baseline master SHA

Capture `git rev-parse <base-branch>` — record in `spec.md`. This is the SHA the baseline is anchored to per Constitution §7.

### 7. Master-baseline health sweep (scope-aware)

Pre-existing master-state breakage outside the scope, if not surfaced now, will surface later at T-LOCK or `/kmm-verify` and force mid-flight policy application — much more disruptive than handling it up front. The sweep's depth is calibrated to the migration's scope per Constitution §14 (Proportionality).

**Sweep matrix:**

| Scope size | Per-target compile | Test source-set compile | Full unit test runtime suite |
|---|---|---|---|
| ≤3 in-scope files (trivial heuristic candidate) | mandatory | mandatory | **opt-in** (default skipped) |
| >3 in-scope files OR any HIGH-risk refactor surfaced upstream | mandatory | mandatory | mandatory |

**Why opt-in for trivial scopes:** `/kmm-verify` runs scope-focused tests via `--tests <fqn>`, never the full suite. Pre-existing runtime failures unrelated to the in-scope file therefore cannot block verify on a trivial migration. The full-suite runtime sweep at specify-phase exists to surface failures that *would* block multi-file migrations whose verify-phase touches a wider blast radius. For a 1-file extract+swap migration the full suite is paid time without proportional value (sniper-v2-android GreetingUseCase, D-2: ~5 min wall-clock killed mid-flight as scope-disproportionate).

**Test-source-set compile is always mandatory.** If `:<consumer>:compileXxxUnitTestKotlin` fails on master, T-LOCK will fail regardless of scope size; the broken-file inventory is needed at specify time.

**Two failure classes need different treatment:**

- **Runtime test failures** (test compiled, executed, asserted false) → `@Ignore` annotation on the failing test methods, with cross-reference to the deviation entry. The test file otherwise stays untouched.
- **Compile-only failures** (test source set or production source set fails to compile on a target) → `@Ignore` does NOT help (it skips runtime, not compilation). Rename the offending file to `<original>.broken` per the project convention. Files like `*.kt.broken` are excluded from compilation by Kotlin's source-set glob. Verify the project already uses this convention by greppping for `*.broken` in test directories before applying.

**Subsequent test runs** (during `implement-phase` and `/kmm-verify`) use scope-focused commands only — `--tests <fqn>` for the migration's own baseline tests. The full sweep, when run, is a one-shot at `specify-phase` to inventory pre-existing failures; running it on every subsequent step would be expensive and irrelevant.

After the sweep, present the combined patch to the user (one approval covers all):

> Master health sweep:
>   Runtime failures (out of scope): `<N>` tests in `<comma-separated files>` — propose `@Ignore`
>   Compile-only failures (out of scope): `<M>` files (`<comma-separated paths>`) — propose `.broken` rename
> Total: `<N+M>` files touched outside scope. All logged as deviation D-1 (RATIFIED, pre-existing).
>
> Approve? [y / n / discuss]

Do not show diffs by default — these are mechanical patches following the project's policy. User picks `discuss` if they want per-file review.

- On `y`: apply the combined patch as a **sentinel commit** with the message prefix `chore(kmm-prelock): broken-rename — DO NOT MERGE; auto-reverted at pr-phase`. The sentinel is **not** part of the migration's substance; it exists so T-LOCK's compile gate passes locally. Log a single deviation `D-1` in `migration-report.md` with `Closure: { type: "commit:present", message-fragment: "kmm-prelock-revert" }` (RATIFIED — pre-existing breakage; closure path is "owners of the affected files fix in separate PRs"; the sentinel itself is auto-reverted at pr-phase before the PR opens, so reviewers never see rename noise in the diff). The pr-phase reads this deviation and emits the revert commit + populates the PR body's "Pre-existing master breakage (NOT touched by this PR)" section listing the broken files.
- On `discuss`: enumerate each item with file path and failure mode, then re-ask with `y / n`.
- On `n`: abort `specify-phase`. The user must fix master or revise scope before re-running.

### 8. Write `spec.md`

- Use `templates/spec.md` as the structure.
- Fields: scope name, base branch, baseline SHA, worktree path, in-scope file list (exact paths), explicitly out-of-scope file list, declared shared targets, declared consumer targets, the user's stated migration goal **in their words**, the test command used to verify the baseline.
- The "Goal" field captures the user's actual sentence(s), not a paraphrase. The orchestrator's job at goal-clarity (step 1) was to make the user's own words concrete enough — those words go in.
- Commit `spec.md` and the directory `<repo>/kmm/<scope-name>/` to the feature branch.

### 9. Constitution check

- List every principle this command touched: §1 (understand before acting — goal-clarity gate, file enumeration from entry point), §2 (no assumptions when stuck — every user question used the options + recommended + why shape), §5 (scope declared, no silent expansion), §7 (baseline SHA recorded).
- Pass/fail: pass if every checklist item below is `[x]`:
  - `[ ]` Goal clarified — concrete entry point and feature boundary identified
  - `[ ]` Scope file list declared and confirmed by user
  - `[ ]` Out-of-scope list declared
  - `[ ]` Shared targets declared
  - `[ ]` Base branch declared
  - `[ ]` Worktree created
  - `[ ]` `local.properties` copied (if present)
  - `[ ]` Baseline master SHA recorded
  - `[ ]` Existing tests run; failures outside scope addressed (deviation D-1 logged or zero failures)
  - `[ ]` `spec.md` written and committed
- On fail: STOP. Do not advance. Report which checks failed.

### 10. Auto-advance to architect phase

After the constitution-check passes, the router auto-advances to the **architect** phase (Constitution §1 — architecture before code). Print a one-line transition banner: `── architect ──`.

In `--step` mode, stop here and print: "Spec written and committed. Re-run `/kmm` to advance to the architect phase."

## What you do NOT do

- Do not design the target architecture. That is the architect phase (Constitution §1).
- Do not draft the migration plan. That is the plan phase.
- Do not generate tasks. That is the tasks phase.
- Do not modify any in-scope file. The scope is declared but no file moves yet.
- Do not write code. This phase writes only `spec.md` and (if approved) the `@Ignore` patch.

## Failure modes

- **Worktree already exists** — read its `spec.md`. If the existing one is for the same scope, ask the user (one question, options): A) resume the existing one / B) restart fresh (deletes the worktree) / C) discuss. If for a different scope, abort with the path conflict and tell the user.
- **Base branch not found** — surface available branches as options in the step 5 question; do not guess.
- **User cannot articulate scope at the goal-clarity gate** — keep pushing back per the protocol. Constitution §1 + §5 require a concrete scope; this is not negotiable. Targeted follow-ups, one at a time, until you can produce a list of file paths the user agrees to. Never advance into worktree creation on a fuzzy scope — every downstream command's correctness depends on this list.
- **The test command is unknown** — ask the user as a single question with options (the most likely candidates, derived from `gradle :tasks --all`), with a `discuss` affordance.
