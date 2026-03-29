#!/usr/bin/env bash
# SubagentStop: ensures agents emit completion promises

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

PLAN_DIR="$HOME/dev/gameplans/$(cat "$ACTIVE_FILE")"
[ ! -d "$PLAN_DIR" ] && exit 0

[ ! -f "$PLAN_DIR/PROGRESS.md" ] && exit 0

LAST_OUTPUT=$(tail -5 "$PLAN_DIR/PROGRESS.md" 2>/dev/null)
PROMISES="FILE_COMPLETE|FILE_BLOCKED|TDD_COMPLETE|TDD_BLOCKED|VERIFY_PASS|VERIFY_FAIL|DEBUG_COMPLETE|DEBUG_BLOCKED|UI_COMPLETE|UI_BLOCKED|AUDIT_COMPLETE|AUDIT_BLOCKED|REQUIRES_APPROVAL|PLAN_ANALYSIS"

echo "$LAST_OUTPUT" | grep -qE "$PROMISES" && exit 0
echo "[kmm-workflow] WARNING: Agent stopped without completion promise. Expected: $PROMISES"
