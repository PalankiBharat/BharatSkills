# Phase: specify

Read by `/kmm` when state-detection routes to specify. Not user-invocable.

Read `constitution.md` first.

## Inputs

- `<scope-name>` — short slug (e.g., `auth-module`)
- Conversation context — the user's stated migration goal

## Steps

### 1. Parse the invocation for inferable answers (silent)

Extract from `/kmm <scope> <intent>` and surrounding conversation:
- **Concrete file paths** — listed in the intent? They're the in-scope list.
- **Negative scope hints** — "UI is out of scope", etc.
- **Feature / entry-point name** — anything that lets you trace files.
- **Base branch** — explicitly mentioned? Otherwise auto-detected in step 4.

If the invocation gives a concrete file list (3+ paths or a clearly-bounded directory), the goal-clarity gate is satisfied. Skip step 2.

### 2. Goal-clarity gate (only if intent is fuzzy)

Fire only if step 1 didn't produce a concrete file list. Ask one question at a time per `references/orchestration-protocol.md` § "User question style" — user-facing feature, then entry point — until you can enumerate files.

### 2.5. AndroidMain dep-direction check (silent — info only)

For each in-scope file, grep external imports. For every FQN that resolves to a project module, find the owning module:

```
grep -E "^import com\.<org>\." <in-scope-file>
grep -rln "^package com\.<org>\.<the-package>$" <repo>/<module>/src/main/...
```

If any import resolves to a module that **depends on `:shared`** (e.g., `:app`), surface as a non-blocking finding for `findings.md § Gotchas`:

> **AndroidMain staging will be infeasible for this migration.**
>
> `<file>:<line>` imports `<symbol>` from module `<module>` (which declares `implementation(project(":shared"))`). When the file is moved to `androidMain` for staging, that import cannot resolve.
>
> The fast-path's atomic-migrate flow handles this — T-1, T-LOCK, M-1 collapse into a single operation directly app→commonMain.

Don't prompt. The actual routing happens at end of specify via the trivial-heuristic.

### 2.6. Consumer-utility sniff (silent — surfaced only when migration may be a no-op)

After the in-scope file list is settled, do a fast read of public outputs and grep their consumers to confirm the migration's behaviour change will be observable.

1. List public API per file.
2. For each non-trivial public output, grep usage across consumers (direct reads + indirect reads via ViewModel state).
3. If a public output is computed but never read, surface as a non-blocking finding:

   > **Migration may be functionally invisible.**
   >
   > `<file>` exposes `<output>`, but no caller reads it. Searched: `<grep pattern>` across `<directories>`. The migration's behaviour-fix will be invisible at the UI/business layer until a separate fix wires the value through.
   >
   > Continue migrating, fix wiring first as a separate task, or descope?

4. One user question with three options + recommendation. Recommend `continue` if migration purpose is structural-only; recommend `fix wiring first` if the migration's whole point is the visible behaviour.
5. Record choice in `findings.md § Gotchas`.

Skip when the migration's purpose is explicitly structural-only.

### 3. Confirm in-scope files (only if step 1 inferred them by tracing)

If step 1 produced the file list directly from the invocation, do not re-ask.

If step 1 enumerated by tracing, present once for confirmation:

> Traced from `<entry-point>` → `<N>` files. Confirm or amend:
> ```
> 1. <path>
> 2. <path>
> ```
> [ok / amend / discuss]

### 4. Out-of-scope, targets, base branch — autodetect (silent in common case)

**Out-of-scope:**
- Use any negative hints from invocation directly.
- Default explicitly out-of-scope: consumer apps, UI files in same package, same-package files not in in-scope list. Record in `spec.md` automatically. Don't ask.

**Shared targets:**
- Auto-detect from `shared/build.gradle.kts`. Recommendation: all detected targets per Constitution §10.
- Ask only if build file is unusual.

**Base branch:**
- If exactly one of `main` / `master` exists on `origin`, use it. Silent.
- If both and HEAD is on one, use that. Silent.
- Otherwise ask.

**Gradle task names — live-source the canonical names:**

```
./gradlew :<consumer>:tasks --all 2>/dev/null | grep -E "^(test|compile|install)[A-Z]" | sort -u
./gradlew :shared:tasks --all 2>/dev/null | grep -E "^(test|compile)[A-Z]" | sort -u
```

Pick the production-flavor debug variant as canonical:
- Tests: `testProductionDebugUnitTest` over alternatives. If only `testDebugUnitTest` (no flavors), use it.
- Production-source compile: `compileProductionDebugKotlin` or `compileDebugKotlin`.
- Test-source compile: `compileProductionDebugUnitTestKotlin` or `compileDebugUnitTestKotlin`.
- Shared per-target compile: derived from declared shared targets.

If `CLAUDE.md`'s anchored test name doesn't exist as a discovered task, surface a non-blocking warning:
> ⚠ `CLAUDE.md` lists `<anchored-name>`, but it's ambiguous (flavors detected). Using `<canonical-name>` instead.

Record resolved names in `findings.md § Verification command provenance`.

Print one-line summary per silent autodetection: `Targets: commonMain, androidMain, iosArm64, iosX64. Base branch: main. Test command: ./gradlew :app:testProductionDebugUnitTest.`

### 5. Create the worktree

- Path: `<repo>/.worktrees/kmm-<scope-name>/`
- Branch: `feature/kmm-<scope-name>` from base branch
- `git worktree add .worktrees/kmm-<scope-name> <base-branch> -b feature/kmm-<scope-name>`
- Copy `local.properties` if present at repo root.
- Record worktree path in `spec.md`.

All subsequent commands operate against the worktree.

### 6. Record baseline master SHA

`git rev-parse <base-branch>` → `spec.md`. The SHA the baseline is anchored to per Constitution §8.

### 7. Master-baseline health sweep (compile-only mandatory; runtime opt-in)

| Component | Always | Trivial scope (≤3 files) | Larger scope |
|---|---|---|---|
| Per-target compile | mandatory | mandatory | mandatory |
| Test source-set compile | mandatory | mandatory | mandatory |
| Full unit test runtime | opt-in | default skipped | opt-in (recommended for >10 files) |

**Why runtime is opt-in:** `/kmm-verify` runs scope-focused tests via `--tests <fqn>`. Pre-existing runtime failures unrelated to in-scope files cannot block verify. Running the full suite at specify-phase is paid time without proportional value for trivial scopes.

**Failure handling:**
- **Runtime failures** (test compiled, asserted false): `@Ignore` on failing methods; cross-reference deviation.
- **Compile-only failures**: rename to `<original>.broken` per project convention. Verify the project already uses `*.broken` by grepping before applying.

Combined approval prompt:

> Master health sweep:
>   Runtime failures (out of scope): `<N>` tests in `<files>` — propose `@Ignore`
>   Compile-only failures (out of scope): `<M>` files (`<paths>`) — propose `.broken` rename
> Total: `<N+M>` files touched outside scope. All logged as deviation D-1 (RATIFIED, pre-existing).
>
> Approve? [y / n / discuss]

On `y`: apply as a sentinel commit `chore(kmm-prelock): broken-rename — DO NOT MERGE; auto-reverted at pr-phase`. Log `D-1` with `Closure: { type: "commit:present", message-fragment: "kmm-prelock-revert" }`. The pr-phase auto-reverts before opening the PR.

### 8. Write `spec.md`

Use `templates/spec.md`. Fields: scope name, base branch, baseline SHA, worktree path, in-scope file list (exact paths), explicitly out-of-scope, declared shared targets, declared consumer targets, the user's stated goal **in their words**, the test command. Commit `spec.md` and the directory.

### 9. Constitution check

Touched: §1, §2, §6, §8.

Pass/fail checklist:
- `[ ]` Goal clarified — concrete entry point and feature boundary
- `[ ]` Scope file list declared and confirmed
- `[ ]` Out-of-scope list declared
- `[ ]` Shared targets declared
- `[ ]` Base branch declared
- `[ ]` Worktree created
- `[ ]` `local.properties` copied (if present)
- `[ ]` Baseline master SHA recorded
- `[ ]` Existing tests run; failures outside scope addressed (D-1 logged or zero)
- `[ ]` `spec.md` written and committed

On fail: STOP. Report which checks failed.

### 10. Auto-advance

Print `── architect ──` and the router advances to architect-phase. In `--step` mode, stop and print: "Spec written and committed. Re-run `/kmm` to advance."

## Failure modes

- **Worktree exists** — read its `spec.md`. Same scope: ask resume / restart / discuss. Different scope: abort with path conflict.
- **Base branch not found** — surface available branches as options.
- **User cannot articulate scope** — keep pushing back per Constitution §1, §6. One targeted question at a time. Never advance into worktree creation on a fuzzy scope.
- **Test command unknown** — ask with options derived from `gradle :tasks --all`.
