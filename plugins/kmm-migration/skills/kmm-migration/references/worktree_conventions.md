# Worktree Conventions

> The migration uses ONE worktree for the entire migration. Created at
> Phase 0 by `00_worktree_initializer`. Recorded in `state.json`. Every
> subsequent subagent operates inside it.

## Contents

- [Creation](#creation)
- [Path and branch naming](#path-and-branch-naming)
- [Verification at dispatch](#verification-at-dispatch)
- [Cleanup](#cleanup)

## Creation

Exactly once per migration, `00_worktree_initializer` invokes
`**REQUIRED SUB-SKILL:** superpowers:using-git-worktrees`. The initializer:

1. Verifies the target branch is clean (tests green on branch HEAD).
2. Creates the worktree.
3. Records `worktree_path` and `worktree_branch` in `kmm_migration/state.json`.

## Path and branch naming

- Path: `.worktrees/kmm-migrate-<feature>/` under the target repo (or
  follow the superpowers worktree skill's directory-selection priority).
- Branch: `kmm-migrate/<feature>`.

## Verification at dispatch

Every dispatch prompt begins with:

```
First action: run `pwd` and confirm it equals the worktree path recorded
in kmm_migration/state.json. If it does not, emit STATUS: BLOCKED with
reason WORKTREE_MISMATCH.
```

## Cleanup

- During an active migration: the worktree stays.
- After Phase 6 merge: the worktree is cleaned up only if the user
  explicitly says so. Default is to preserve for post-mortem.
