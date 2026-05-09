# Phase: pr

Read by the `/kmm` orchestrator when state-detection routes to the **pr** phase. Assembles the PR title and body for the active checkpoint, shows the user, and on confirmation runs `gh pr create`.

When the migration is checkpointed (Constitution §13), this phase runs once per checkpoint — opening (and ideally landing) a small, reviewable PR before the next checkpoint starts. When the checkpoint plan is a single bundle, this runs once at the end.

The verify phase must have returned `VERIFY_COMPLETE_PASS` for the active checkpoint before this phase runs. If verification has not passed, route back to verify.

Every deviation in `migration-report.md` *that scopes to the active checkpoint* must be `CLOSED`, `RATIFIED`, or `SUPERSEDED` before opening the checkpoint's PR. Deviations attached to later checkpoints stay `OPEN` for now and are handled when those checkpoints reach their PR.

Read `skills/kmm-migration-workflow/constitution.md` first.

## Inputs

- `<repo>/kmm/<scope>/spec.md`
- `<repo>/kmm/<scope>/architecture.md`
- `<repo>/kmm/<scope>/plan.md`
- `<repo>/kmm/<scope>/migration-guide.md`
- `<repo>/kmm/<scope>/migration-report.md`
- `<repo>/kmm/<scope>/tasks.md`
- `<repo>/.worktrees/kmm-<scope>/`
- The active checkpoint name (the most recent checkpoint whose tasks are all `[x]` but no PR has been opened yet)

## What you do

### 1. Identify the active checkpoint and verify pre-conditions.

The active checkpoint is the lowest-numbered checkpoint with all `[x]` tasks and no recorded PR URL in `tasks.md`. Pre-conditions:

- All tasks for the active checkpoint are `[x]`.
- The verify-phase last result for this checkpoint was `VERIFY_COMPLETE_PASS`.
- All deviations attached to this checkpoint in `migration-report.md` are non-`OPEN`.
- The worktree's branch is on the checkpoint's branch (e.g., `feature/kmm-<scope>-<checkpoint>` for multi-PR, or `feature/kmm-<scope>` for single-PR).
- The worktree's working tree is clean (`git status` shows no uncommitted changes).

If any pre-condition fails, list them and stop.

### 1b. Branch policy for checkpointed migrations.

**Single checkpoint (default):** branch is `feature/kmm-<scope>`. PR opens against the base branch.

**Multi-checkpoint:** each checkpoint gets its own branch, stacked from the previous:
- CP-1: `feature/kmm-<scope>-<cp1-name>` from base branch.
- CP-2: `feature/kmm-<scope>-<cp2-name>` from CP-1's branch (or from base after CP-1 merges).
- etc.

The user picks the stacking strategy at architect-time (architecture.md → checkpoint plan section); default is "stack" (CP-K branches off CP-(K-1)). After CP-(K-1) merges to base, CP-K can be rebased onto base. The orchestrator records the strategy in `architecture.md` and honors it here.

### 2. Assemble the PR draft.

The draft is **scoped to the active checkpoint**, not the whole migration.

**Title** (under 70 chars):
```
kmm(<checkpoint>): <one-line goal of this checkpoint>
```

Example: `kmm(auth-relocation): move auth files into androidMain + capture baselines`

For single-checkpoint migrations, the title is `kmm: migrate <scope> to commonMain`.

**Body**:
```markdown
## Summary

<one-paragraph summary derived from architecture.md's checkpoint entry: what this checkpoint accomplishes, why it's safe to merge in isolation>

Checkpoint: <K of N> — <name>
Baseline SHA: <baseline-locked-sha from spec.md>
Declared shared targets: <list from spec.md>

## Files in this checkpoint

<one bullet per file in this checkpoint, format:>
- `<source path>` → `<target path>` — <one-line: relocation / swap / refactor / mixed>

Total: <N> files (this checkpoint), <T> files (whole migration)

## Refactors applied (this checkpoint)

<for each Refactor entry from architecture.md applied in this checkpoint:>
- **R-N**: <title> — <clean-code violation>. Behaviour invariant pinned by `<test name>`.

If no refactors in this checkpoint: "None — this checkpoint is <relocation | swaps>."

## Library swaps (this checkpoint)

<table from findings.md "Library Versions" — library | from | to | source — filtered to swaps applied here>

## Deviations (this checkpoint)

<for each entry in migration-report.md scoped to this checkpoint:>
- **D-N (<status>)**: <title>. <one-line root cause>. <one-line closure>.

If no deviations: "None."

## Verification

- Per-target compile: <list of targets and pass>
- Baseline tests: <count> green on <jvm/ios/etc.>
- Consumer compile: <list>
- Verify result: VERIFY_COMPLETE_PASS

## Master-mergeable

This checkpoint compiles and passes tests independently. It does not depend on later checkpoints landing.

## Next checkpoints

<if more checkpoints follow:>
- CP-<K+1>: <name> — <one-line goal>
- ...

<if this is the last:>
- None — this completes the `<scope>` migration.

## Test plan

- [ ] Reviewer: pull the branch, run `<test command from spec.md>` locally
- [ ] Reviewer: confirm consumer apps build clean against the migrated module
- [ ] Reviewer: skim `<repo>/kmm/<scope>/migration-report.md` deviations for this checkpoint
- [ ] Reviewer: skim the relevant `<repo>/kmm/<scope>/migration-guide.md` entries

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

The footer uses the standard "Generated with Claude Code" line — only because this PR was assembled by the orchestrator from on-disk artifacts. The footer is acceptable here because it is metadata, not migration code.

### 3. Show the draft to the user.

Print the full title and body in chat, in a fenced markdown block. Tell the user:

> Draft PR ready. Reply "ok" to push and open the PR, "edit" to revise the body, or paste the changes you want.

Wait for the user to respond. Apply edits if requested. Loop until the user says go.

### 4. Push and open the PR.

When the user approves:

1. Push the checkpoint's branch: `git push -u origin <branch>` (the branch determined in Step 1b).
2. Run:
   ```bash
   gh pr create --base <base> --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )"
   ```
   `<base>` is the prior checkpoint's branch (for stacked checkpoints) or `main`/`master` (for the first checkpoint, or for non-checkpointed migrations). Use a heredoc to preserve formatting.
3. Capture the PR URL `gh pr create` returns.
4. Record the PR URL inline in `tasks.md` next to the checkpoint header so the orchestrator's state-detection knows this checkpoint is done.

### 5. Constitution check.

- Touched: §3 (no silent decisions — user approved the draft), §6 (PR scope matches checkpoint scope), §13 (per-checkpoint PR), deviations governance (no `OPEN` deviations for this checkpoint shipping).
- Pass/fail:
  - `[ ]` Pre-conditions all green
  - `[ ]` Draft assembled from on-disk artifacts (no chat-context inference)
  - `[ ]` User approved the draft text
  - `[ ]` Checkpoint branch pushed
  - `[ ]` PR created and URL recorded
- On fail: STOP. Report which checks failed.

### 6. Decide what's next.

- **More checkpoints remain:** route the orchestrator back to the **implement** phase for the next checkpoint. Print: `── implement (CP-<K+1>) ──`. The user can choose to merge the just-opened PR before the next checkpoint starts running, or stack the next branch on the current. Either way, implementation continues.
- **This was the final checkpoint:** advance to the skill retrospective (Step 7).

### 7. Skill retrospective (auto-trigger, only on final checkpoint).

Dispatch the `skill-retrospector` subagent (read-only, sonnet) with the scope's artifact paths. The subagent reads migration-report.md / tasks.md / spec.md / architecture.md and produces a project-agnostic markdown block on what worked / where the skill drifted / what could still improve.

Write the result to `<repo>/kmm/<scope>/skill-retro.md` and print it to the chat (so the user can copy it into an issue on the skill repo without re-fetching).

This is automatic — no user prompt. The cost (one read-only sonnet dispatch) is small relative to the value of capturing skill-improvement signals while context is fresh.

### 8. Final report (only on final checkpoint).

- Print every checkpoint PR URL in order.
- Summary: total files migrated, refactors applied, deviations (count by status), tests green.
- Print the skill retrospective block (verbatim from `skill-retro.md`) under a clearly-marked section.
- Tell the user: "Migration `<scope>` is open as `<N>` checkpoint PRs (URLs above). Skill retrospective at `kmm/<scope>/skill-retro.md`. Worktree at `.worktrees/kmm-<scope>/` can stay until all PRs merge or be removed with `git worktree remove`."

## What you do NOT do

- Do not run `gh pr create` without user confirmation. The skill never silently opens PRs.
- Do not edit the migrated code. The PR ships exactly what verify-phase validated.
- Do not push to `main`/`master`. Always push to a feature branch. If the user asks to push to main, refuse — that is destructive and outside the migration workflow.
- Do not bundle multiple checkpoints into one PR. The whole point of Constitution §13 is one checkpoint per PR.

## Failure modes

- **`gh` is not authenticated** — surface the error, tell the user to run `gh auth login`. Do not retry.
- **Branch already has a PR** — `gh pr create` will say so. Surface the existing PR URL; ask the user whether to update it (`gh pr edit`) or open a new one.
- **Push rejected** — likely upstream has new commits on the base branch. Stop and tell the user; never force-push.
- **An `OPEN` deviation for this checkpoint appears mid-flow** — refuse. Tell the user to either `CLOSE`/`RATIFY` it (with explicit approval recorded in `migration-report.md`) or revisit the migration.
- **A checkpoint depends on a not-yet-merged earlier checkpoint, but the user wanted unstacked branches** — the orchestrator records the dependency in the PR body and lets `gh` open the PR against the prior branch (stacked). The user can still merge in order; stacked PRs land cleanly when the base branch updates.
