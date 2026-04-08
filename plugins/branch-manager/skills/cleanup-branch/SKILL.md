---
name: cleanup-branch
description: >
  Clean up a branch development environment: remove git worktree, close tmux pane,
  delete dedicated Android emulator, and optionally delete the remote branch.
  Shows interactive selection from active worktrees/panes.
---

# Cleanup Branch

## Overview

Tears down a complete branch development environment:
1. Shows a list of active worktrees and tmux panes for selection
2. Resets any uncommitted changes in the worktree
3. Closes the tmux pane running in that worktree
4. Removes the git worktree
5. Deletes the dedicated Android emulator (AVD)
6. Optionally deletes the local and remote branch

## Prerequisites

- Must be running inside a tmux session
- NEVER close the current pane (pane 1 / the orchestrator pane)

## Triggers

"cleanup branch", "clean branch", "remove branch", "delete branch", "teardown branch", "close branch"

## Arguments

**Format:** `/cleanup-branch [branch-or-worktree-name]`

If no argument is provided, show the interactive selection.

## Execution Steps

### Step 1: Gather Active Worktrees and Panes

```bash
# List all tmux panes with their paths
tmux list-panes -F "#{pane_index} #{pane_current_path} #{pane_current_command}"

# List all git worktrees
git worktree list
```

Cross-reference panes with worktrees to build a selection list.

### Step 2: Present Selection to User

Display a numbered list combining worktree and pane info:

```
Active branch environments:

  1. fix-indicator-performance (pane 3)
     Branch: fix/indicator-performance
     Path: /path/to/punch-work-tree/indicator-performance

  2. integration-tests (pane 4)
     Branch: tech/integration-tests
     Path: /path/to/punch-work-tree/integration-tests

Which environment(s) to clean up? (number, comma-separated, or "all")
```

If an argument was provided, skip selection and match by name.

### Step 3: Confirm Destructive Action

Before proceeding, show what will be deleted and ask for confirmation:

```
Will clean up:
  - Close tmux pane 3
  - Reset and remove worktree: ./indicator-performance/
  - Delete AVD: fix-indicator-performance
  - Local branch: fix/indicator-performance (will NOT delete remote)

Proceed? (y/n)
```

### Step 4: Close Tmux Pane

```bash
PANE_INDEX=<target-pane>

# NEVER close pane 1 (current/orchestrator pane)
if [ "$PANE_INDEX" = "1" ]; then
  echo "Cannot close the orchestrator pane!"
  exit 1
fi

tmux kill-pane -t "$PANE_INDEX"
```

### Step 5: Reset and Remove Worktree

```bash
WORKTREE_PATH="<path>"

# Reset any changes
git -C "$WORKTREE_PATH" checkout -- . 2>/dev/null
git -C "$WORKTREE_PATH" clean -fd 2>/dev/null

# Remove worktree
git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" --force
```

### Step 6: Delete Android Emulator

```bash
SANITIZED_NAME=$(echo "$BRANCH_NAME" | tr '/' '-')
AVDMANAGER=~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager

# Kill emulator if running
adb devices | grep "emulator" | while read line; do
  EMU=$(echo $line | awk '{print $1}')
  EMU_AVD=$(adb -s "$EMU" emu avd name 2>/dev/null | head -1)
  if [ "$EMU_AVD" = "$SANITIZED_NAME" ]; then
    adb -s "$EMU" emu kill 2>/dev/null
  fi
done

# Delete AVD
$AVDMANAGER delete avd -n "$SANITIZED_NAME" 2>/dev/null
```

### Step 7: Optionally Delete Branch

Ask the user:
```
Delete local branch 'fix/indicator-performance'? (y/n)
Delete remote branch 'origin/fix/indicator-performance'? (y/n)
```

```bash
# Local
git -C "$MAIN_REPO" branch -D "$BRANCH_NAME"

# Remote (only if user confirms)
git -C "$MAIN_REPO" push origin --delete "$BRANCH_NAME"
```

### Step 8: Re-tile Remaining Panes

```bash
tmux select-layout tiled
```

### Step 9: Report

Confirm what was cleaned up:
- Pane closed
- Worktree removed
- AVD deleted
- Branch deleted (if applicable)

## Batch Cleanup

If user selects "all" or multiple items, iterate through each one. Always confirm before batch deletion.

## Safety Rules

- **NEVER** close pane 1 (the orchestrator/current pane)
- **NEVER** delete `master` or `production` branches
- **NEVER** delete a worktree with unpushed commits without warning the user
- Always check for unpushed commits before removing:
  ```bash
  UNPUSHED=$(git -C "$WORKTREE_PATH" log @{u}..HEAD --oneline 2>/dev/null)
  if [ -n "$UNPUSHED" ]; then
    echo "WARNING: This worktree has unpushed commits:"
    echo "$UNPUSHED"
    echo "Proceed anyway? (y/n)"
  fi
  ```

## Example

```
User: /cleanup-branch

Claude shows:
  Active branch environments:
    1. fix-indicator-performance (pane 3)
    2. integration-tests (pane 4)

  Which to clean up?

User: 1

Claude:
  Will clean up:
    - Close tmux pane 3
    - Remove worktree: ./indicator-performance/
    - Delete AVD: fix-indicator-performance
    - Branch: fix/indicator-performance

  Proceed? (y/n)

User: y

Claude: Done. Cleaned up fix-indicator-performance environment.
```
