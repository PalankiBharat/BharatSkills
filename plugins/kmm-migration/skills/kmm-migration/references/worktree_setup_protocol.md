# Worktree Setup Protocol

> Self-contained protocol for creating the single migration worktree at Phase 0.
> Invoked ONCE by `00_worktree_initializer`.

## Contents

- [Directory selection priority](#directory-selection-priority)
- [Branch naming](#branch-naming)
- [Setup sequence](#setup-sequence)
- [Baseline verification](#baseline-verification)

## Directory selection priority

Pick the worktree root directory in this order:

1. If `.worktrees/` exists at repo root, use `.worktrees/kmm-migrate-<feature>/`.
2. If `CLAUDE.md` specifies a worktree root, honor it.
3. Otherwise, ask the user ONE question: "Where should migration worktrees live?" Default: `.worktrees/kmm-migrate-<feature>/`.

Verify the chosen directory is in `.gitignore` OR is outside the repo tree. If neither, STOP and escalate — worktrees committed as subdirectories corrupt the parent repo.

## Branch naming

Branch name: `kmm-migrate/<feature>`. If a branch with that name exists, STOP and escalate with `NEEDS YOUR CALL` — do not reuse or overwrite.

## Setup sequence

```
git worktree add <worktree_path> -b <worktree_branch> <base_branch>
cd <worktree_path>
```

Record `worktree_path` and `worktree_branch` in `kmm_migration/state.json`.

## Baseline verification

Run the project's default test command (typically `./gradlew test` or equivalent per repo convention). All tests MUST pass on the branch head before migration begins. If any fails, STOP and escalate — a failing baseline means either the branch is broken or the test command is wrong; either blocks migration.
