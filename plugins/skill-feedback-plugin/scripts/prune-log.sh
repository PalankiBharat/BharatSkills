#!/usr/bin/env bash
# prune-log.sh — Enforces a 7-day rolling window on the skill session log.

set -euo pipefail

LOG_FILE="$HOME/.skill-session-log.jsonl"

[ ! -f "$LOG_FILE" ] && echo "No session log found." && exit 0

CUTOFF=$(date -u -d "7 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
         date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

[ -z "$CUTOFF" ] && echo "Warning: Could not calculate cutoff date." && exit 0

BEFORE=$(wc -l < "$LOG_FILE")
TEMP_FILE=$(mktemp)
jq -c --arg cutoff "$CUTOFF" 'select(.timestamp >= $cutoff)' "$LOG_FILE" > "$TEMP_FILE" 2>/dev/null || true
mv "$TEMP_FILE" "$LOG_FILE"
AFTER=$(wc -l < "$LOG_FILE")
PRUNED=$((BEFORE - AFTER))

[ "$PRUNED" -gt 0 ] && echo "Pruned $PRUNED entries. Remaining: $AFTER." || echo "All $AFTER entries within 7-day window."
