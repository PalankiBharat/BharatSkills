#!/usr/bin/env bash
# PreCompact: backs up plan files before compaction

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

ACTIVE_FILE="$HOME/dev/gameplans/.sessions/${SESSION_ID}.active"
[ ! -f "$ACTIVE_FILE" ] && exit 0

PLAN_DIR="$HOME/dev/gameplans/$(cat "$ACTIVE_FILE")"
[ ! -d "$PLAN_DIR" ] && exit 0

mkdir -p "$PLAN_DIR/backups"
TS=$(date +%s)
for f in PLAN.md PROGRESS.md findings.md migration-guide.md; do
  [ -f "$PLAN_DIR/$f" ] && cp "$PLAN_DIR/$f" "$PLAN_DIR/backups/${f%.md}_$TS.md"
done
echo "[kmm-workflow] CONTEXT COMPACTION IMMINENT."
echo "[kmm-workflow] BEFORE continuing: write your current state to $PLAN_DIR/HANDOFF.md"
echo "[kmm-workflow] Include: current task, what you just completed, next step, any pending decisions."
echo "[kmm-workflow] Then re-read PLAN.md + PROGRESS.md + HANDOFF.md to recover context."
