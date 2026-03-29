#!/usr/bin/env bash
# PostToolUse: reminds to update PROGRESS.md after edits

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

PLAN_DIR="$HOME/dev/gameplans/$(cat "$ACTIVE_FILE")"
[ -f "$PLAN_DIR/PROGRESS.md" ] && echo "[kmm-workflow] Update PROGRESS.md with what you just did."
