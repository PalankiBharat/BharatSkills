#!/usr/bin/env bash
# PostToolUse: reminds to update PROGRESS.md after edits inside the gameplan's
# worktree or gameplan dir. Skips edits outside those paths and skips edits
# to PROGRESS.md itself (avoids a tail-chase).

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

GAMEPLAN_NAME=$(cat "$ACTIVE_FILE")
PLAN_DIR="$HOME/dev/gameplans/$GAMEPLAN_NAME"
[ ! -f "$PLAN_DIR/PROGRESS.md" ] && exit 0

# Extract the file path the tool touched.
TOUCHED_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[ -z "$TOUCHED_PATH" ] && exit 0

# Skip edits to PROGRESS.md itself.
case "$TOUCHED_PATH" in
  */PROGRESS.md) exit 0 ;;
esac

# Resolve worktree path if recorded in PLAN.md header (e.g., WORKTREE: /path).
WORKTREE_PATH=$(grep -m1 -E '^<!-- WORKTREE:' "$PLAN_DIR/PLAN.md" 2>/dev/null | sed -E 's/<!-- WORKTREE: *//; s/ *-->//')

# Only nag if the touched path is inside the gameplan dir or the worktree.
case "$TOUCHED_PATH" in
  "$PLAN_DIR"/*)
    echo "[kmm-workflow] Update PROGRESS.md with what you just did."
    ;;
  *)
    if [ -n "$WORKTREE_PATH" ]; then
      case "$TOUCHED_PATH" in
        "$WORKTREE_PATH"/*)
          echo "[kmm-workflow] Update PROGRESS.md with what you just did."
          ;;
      esac
    fi
    ;;
esac

exit 0
