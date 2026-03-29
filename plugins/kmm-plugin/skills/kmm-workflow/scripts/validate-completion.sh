#!/usr/bin/env bash
# SubagentStop hook: ensures agents emit completion promises.
#
# The hook receives a JSON payload on stdin. We check the agent's output/summary
# text first. If no promise is found there, we fall back to the last few lines of
# PROGRESS.md. A warning is emitted only when NEITHER source contains a promise.
# The script always exits 0 — hooks must never block the session on validation.

# ---------------------------------------------------------------------------
# 1. Read the full hook payload from stdin
# ---------------------------------------------------------------------------
INPUT=$(cat)

# ---------------------------------------------------------------------------
# 2. Extract session_id — bail early if there's no active gameplan
# ---------------------------------------------------------------------------
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

PLAN_DIR="$HOME/dev/gameplans/$(cat "$ACTIVE_FILE")"
[ ! -d "$PLAN_DIR" ] && exit 0

# ---------------------------------------------------------------------------
# 3. Define the set of valid completion promise tokens
# ---------------------------------------------------------------------------
PROMISES="FILE_COMPLETE|FILE_BLOCKED|TDD_COMPLETE|TDD_BLOCKED|VERIFY_PASS|VERIFY_FAIL|DEBUG_COMPLETE|DEBUG_BLOCKED|UI_COMPLETE|UI_BLOCKED|AUDIT_COMPLETE|AUDIT_BLOCKED|REQUIRES_APPROVAL|PLAN_ANALYSIS"

# ---------------------------------------------------------------------------
# 4. Extract agent output text from the hook JSON payload.
#    The SubagentStop event may carry the summary in .output or .summary.
# ---------------------------------------------------------------------------
AGENT_OUTPUT=$(echo "$INPUT" | jq -r '(.output // .summary) // empty')

# If the agent output contains a promise token, we're done — all good.
if [ -n "$AGENT_OUTPUT" ] && echo "$AGENT_OUTPUT" | grep -qE "$PROMISES"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Fallback: check the last 5 lines of PROGRESS.md
# ---------------------------------------------------------------------------
if [ -f "$PLAN_DIR/PROGRESS.md" ]; then
    LAST_PROGRESS=$(tail -5 "$PLAN_DIR/PROGRESS.md" 2>/dev/null)
    echo "$LAST_PROGRESS" | grep -qE "$PROMISES" && exit 0
fi

# ---------------------------------------------------------------------------
# 6. Neither source contained a promise — emit a warning and exit cleanly
# ---------------------------------------------------------------------------
echo "[kmm-workflow] WARNING: Agent stopped without completion promise. Expected one of: $PROMISES"
exit 0
