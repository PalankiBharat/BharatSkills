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
#    SUCCESS tokens indicate work completed.
#    BLOCKED/FAIL tokens indicate the agent could not complete — these are
#    still valid promises (the agent communicated its status) but the
#    orchestrator should investigate.
# ---------------------------------------------------------------------------
SUCCESS_PROMISES="FILE_VERIFIED|TDD_COMPLETE|VERIFY_PASS|DEBUG_COMPLETE|UI_VERIFIED|AUDIT_COMPLETE|VERIFY_COMPLETE|PLAN_ANALYSIS|DONE|DONE_WITH_CONCERNS"
FAILURE_PROMISES="FILE_BLOCKED|TDD_BLOCKED|VERIFY_FAIL|DEBUG_BLOCKED|UI_BLOCKED|AUDIT_BLOCKED|VERIFY_BLOCKED|BLOCKED|NEEDS_CONTEXT"
PROMISES="$SUCCESS_PROMISES|$FAILURE_PROMISES"

# ---------------------------------------------------------------------------
# 4. Extract agent output text from the hook JSON payload.
#    The SubagentStop event may carry the summary in .output or .summary.
# ---------------------------------------------------------------------------
AGENT_OUTPUT=$(echo "$INPUT" | jq -r '(.output // .summary) // empty')

# Check for any valid promise token (success or failure).
if [ -n "$AGENT_OUTPUT" ]; then
    if echo "$AGENT_OUTPUT" | grep -qE "$FAILURE_PROMISES"; then
        echo "[kmm-workflow] NOTICE: Agent emitted a failure/blocked signal. Orchestrator should investigate."
        exit 0
    fi
    if echo "$AGENT_OUTPUT" | grep -qE "$SUCCESS_PROMISES"; then
        exit 0
    fi
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
