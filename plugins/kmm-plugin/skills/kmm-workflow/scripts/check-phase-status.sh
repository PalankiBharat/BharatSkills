#!/usr/bin/env bash
# Stop: warns if migration phases are incomplete

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

PLAN_DIR="$HOME/dev/gameplans/$(cat "$ACTIVE_FILE")"
[ ! -f "$PLAN_DIR/PROGRESS.md" ] && exit 0

TOTAL=$(grep -c '## Phase' "$PLAN_DIR/PROGRESS.md" 2>/dev/null || echo 0)
DONE=$(grep -c '\[x\] Checkpoint' "$PLAN_DIR/PROGRESS.md" 2>/dev/null || echo 0)

[ "$DONE" != "$TOTAL" ] && [ "$TOTAL" -gt 0 ] && echo "[kmm-workflow] In progress: $DONE/$TOTAL phases. Update PROGRESS.md before stopping."
exit 0
