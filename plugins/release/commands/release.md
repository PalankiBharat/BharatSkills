Create a release tag with consolidated release notes from changes since the last Android tag.

Use `$ARGUMENTS` to control behavior:
- No argument: Full release workflow (generate notes, approve, tag, push)
- `notes`: Only generate and display release notes without tagging
- `dry-run`: Show what would happen without creating or pushing anything

---

## Step 1: Setup — Create a temporary worktree from origin/master

```bash
git fetch origin --tags
```

Create a git worktree in a temp directory checked out to `origin/master`:

```bash
WORKTREE_DIR=$(mktemp -d)/sniper-release
git worktree add "$WORKTREE_DIR" origin/master --detach
```

All git commands in subsequent steps run inside `$WORKTREE_DIR`.

## Step 2: Find the last Android tag

Android tags follow the pattern `2.0.0.XX` (4-segment semver, 4th segment increments).
Filter out iOS tags (`iOS-*`) and any non-numeric tags.

```bash
LAST_TAG=$(git tag --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
```

Display: `Last release tag: $LAST_TAG`

## Step 3: Collect commits since last tag

Get all commits between `$LAST_TAG` and `HEAD` on master:

```bash
git log $LAST_TAG..HEAD --oneline --no-merges
git log $LAST_TAG..HEAD --oneline --merges
```

## Step 4: Categorize commits by branch type

Analyze each commit and its associated branch. Use merge commit messages (which contain branch names) and commit prefixes to categorize.

### Branch classification rules:

**Features** (consolidate all commits from the branch into ONE feature line):
- Branches starting with `feature/`
- Numbered branches like `001-`, `004-`, `015-`, `019-` (these are feature branches)
- Commit prefixes: `[Feature - ...]`

**Bug Fixes** (consolidate all commits from the branch into ONE bugfix line):
- Branches starting with `bugfix/`, `bug-fix/`, `bug/`, `hotfix/`
- Commit prefixes: `[Bugfix - ...]`, `[Hotfix - ...]`, `[Fix - ...]`

**Chores/Tech** (consolidate into ONE line each):
- Branches starting with `chore/`, `tech/`, `performance/`, `legacy-`
- Commit prefixes: `[Tech - ...]`

### Consolidation rules:
- Group all commits from the same branch together
- Write ONE human-readable summary line per branch describing the user-facing change
- For feature branches: describe WHAT the feature does, not implementation details
- For bugfix branches: describe WHAT was broken and that it's fixed
- Ignore internal commits (test scaffolding, SDK version bumps, debug scripts) — they get folded into their parent branch's summary
- If a branch has only chore/tooling commits with no user-facing impact, put it under "Internal" section

## Step 5: Format release notes

Format as:

```
## Release Notes — v{NEW_TAG}

### Features
- {One-line feature summary} (#{PR_number} if available)
- ...

### Bug Fixes  
- {One-line bugfix summary} (#{PR_number} if available)
- ...

### Internal
- {One-line chore/tech summary} (#{PR_number} if available)
- ...
```

Omit any section that has zero entries.

## Step 6: Present for approval

Display the formatted release notes to the user.

Calculate the new tag: increment the 4th segment of `$LAST_TAG` by 1.
Example: `2.0.0.89` -> `2.0.0.90`

Display: `New tag will be: $NEW_TAG`

If `$ARGUMENTS` is `notes` or `dry-run`, stop here. Clean up the worktree and exit.

**Ask the user to approve before proceeding.** Wait for explicit confirmation.

## Step 7: Create and push the tag

After approval, back in the ORIGINAL repo (not the worktree):

```bash
git tag -a $NEW_TAG -m "Release $NEW_TAG

{paste the full release notes here}"
git push origin $NEW_TAG
```

## Step 8: Cleanup

Remove the worktree:

```bash
git worktree remove "$WORKTREE_DIR" --force
```

Display: `Released $NEW_TAG and pushed to origin.`

---

## Error Handling

- If no Android tags exist, ask the user for the starting tag
- If there are no new commits since the last tag, inform the user and exit
- If `git push` fails, display the error and leave the local tag intact so the user can retry
- Always clean up the worktree, even on failure