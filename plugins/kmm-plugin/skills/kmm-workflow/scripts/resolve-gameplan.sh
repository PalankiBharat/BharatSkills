#!/usr/bin/env bash
# Reads hook input JSON from stdin, resolves active gameplan for this session.
# Usage: cat | resolve-gameplan.sh [plan-header|plan-path|full]

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

SESSIONS_DIR="$HOME/dev/gameplans/.sessions"
ACTIVE_FILE="$SESSIONS_DIR/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

GAMEPLAN_NAME=$(cat "$ACTIVE_FILE")
PLAN_DIR="$HOME/dev/gameplans/$GAMEPLAN_NAME"
[ ! -d "$PLAN_DIR" ] && exit 0

MODE="${1:-plan-header}"
case "$MODE" in
  plan-header)
    echo "[kmm-workflow] ACTIVE: $GAMEPLAN_NAME"
    head -15 "$PLAN_DIR/PLAN.md" 2>/dev/null
    echo ""
    echo "=== recent progress ==="
    tail -5 "$PLAN_DIR/PROGRESS.md" 2>/dev/null
    ;;
  plan-path)
    echo "$PLAN_DIR"
    ;;
  full)
    cat "$PLAN_DIR/PLAN.md" 2>/dev/null
    echo "---"
    cat "$PLAN_DIR/PROGRESS.md" 2>/dev/null
    ;;
esac
