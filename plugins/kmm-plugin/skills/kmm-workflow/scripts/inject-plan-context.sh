#!/usr/bin/env bash
# UserPromptSubmit: injects plan context for active session gameplan

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

SESSIONS_DIR="$HOME/dev/gameplans/.sessions"
ACTIVE_FILE="$SESSIONS_DIR/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

GAMEPLAN_NAME=$(cat "$ACTIVE_FILE")
PLAN_DIR="$HOME/dev/gameplans/$GAMEPLAN_NAME"
[ ! -f "$PLAN_DIR/PLAN.md" ] && exit 0

echo "[kmm-workflow] ACTIVE: $GAMEPLAN_NAME"
head -15 "$PLAN_DIR/PLAN.md"
echo ""
echo "=== recent progress ==="
tail -15 "$PLAN_DIR/PROGRESS.md" 2>/dev/null
