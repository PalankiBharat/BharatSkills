---
name: setup-branch
description: >
  Create a new branch worktree with a dedicated tmux pane running Claude Code
  and a dedicated Android emulator for testing. Complete dev environment setup
  in one command.
---

# Setup Branch

## Overview

Sets up a complete isolated development environment for a new branch:
1. Creates a git worktree from the base repo
2. Opens a tmux split pane in that worktree
3. Launches Claude Code with dangerously skip permissions
4. Creates a dedicated Android emulator (AVD) named after the branch
5. Injects the emulator name into the Claude session so it knows which emulator to use

## Prerequisites

- Must be running inside a tmux session (check `$TMUX` env var)
- Must have a git repo to create worktrees from
- Android SDK installed at `~/Library/Android/sdk/`

## Triggers

"setup branch", "new branch", "create branch", "branch setup", "start branch"

## Arguments

The skill receives the branch name as an argument. If not provided, ask the user.

**Format:** `/setup-branch <branch-name> [base-branch]`

- `branch-name` (required): Name for the new branch (e.g., `fix/zoom-persist`)
- `base-branch` (optional): Branch to base from. Defaults to `master`.

## Execution Steps

### Step 1: Validate Environment

```bash
# Check tmux
if [ -z "$TMUX" ]; then
  echo "Not in tmux. Start tmux first."
  exit 1
fi
```

### Step 2: Determine Repo and Worktree Path

Find the main git repo. The worktree parent directory is the current working directory.

```bash
# Derive paths
BRANCH_NAME="<branch-name>"
SANITIZED_NAME=$(echo "$BRANCH_NAME" | tr '/' '-')
WORKTREE_PATH="$(pwd)/${SANITIZED_NAME}"

# Find the main repo to create worktree from
# Look for the bare repo or main repo that owns the worktrees
MAIN_REPO=$(git -C <any-existing-worktree> worktree list | head -1 | awk '{print $1}')
```

### Step 3: Create Git Worktree

```bash
git -C "$MAIN_REPO" worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" <base-branch>
```

If the branch already exists, use it without `-b`:
```bash
git -C "$MAIN_REPO" worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

### Step 4: Create Dedicated Android Emulator

```bash
AVD_NAME="$SANITIZED_NAME"
AVDMANAGER=~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager
SYSTEM_IMAGE="system-images;android-34;google_apis_playstore;arm64-v8a"
DEVICE="pixel_4_xl"

# Create AVD
echo "no" | $AVDMANAGER create avd \
  -n "$AVD_NAME" \
  -k "$SYSTEM_IMAGE" \
  -d "$DEVICE" \
  --force

# Enable physical keyboard input (default is 'no' which blocks host keyboard)
sed -i '' 's/hw.keyboard = no/hw.keyboard = yes/' ~/.android/avd/${AVD_NAME}.avd/config.ini
```

### Step 5: Open Tmux Split Pane with Claude

```bash
# Split pane and launch claude with dangerously skip permissions
# NOTE: Do NOT use -p flag — it causes the session to exit immediately.
# Instead, launch claude first, wait for it to initialize, then send the
# emulator context as the first message via tmux send-keys.
tmux split-window -h -c "$WORKTREE_PATH"

# Set ANDROID_HOME and PATH in the new pane shell before launching Claude
tmux send-keys -t <new-pane-index> "export ANDROID_HOME=~/Library/Android/sdk && export PATH=\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH" Enter

# Launch Claude
sleep 1
tmux send-keys -t <new-pane-index> "claude --dangerously-skip-permissions" Enter

# Re-tile for even layout
tmux select-layout tiled

# Wait for Claude to initialize, then send emulator context
sleep 8
tmux send-keys -t <new-pane-index> "You are working on branch: $BRANCH_NAME. For testing, ALWAYS use the dedicated emulator named '$AVD_NAME'. Verify with: emulator -list-avds. Launch with: emulator -avd $AVD_NAME -no-snapshot-load & Install with: adb -s emulator-<port> install <apk>. Do NOT use any other emulator." Enter
```

### Step 6: Confirm to User

After all steps complete, report:
- Worktree path
- Branch name
- AVD name
- Pane index
- How to switch to the pane

## Error Handling

- **Worktree path exists:** Ask user to pick a different name or clean up first
- **Branch already exists:** Offer to use existing branch (skip `-b` flag)
- **System image not installed:** Run `sdkmanager "system-images;android-34;google_apis_playstore;arm64-v8a"`
- **AVD already exists:** Use `--force` to overwrite, or skip creation

## Example

```
User: /setup-branch fix/zoom-persist
```

Result:
- Worktree at `./fix-zoom-persist/` based on `master`
- AVD named `fix-zoom-persist` (Pixel 4 XL, API 34)
- Tmux pane running Claude with skip permissions
- Claude knows to use `fix-zoom-persist` emulator for testing
