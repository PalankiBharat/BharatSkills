#!/usr/bin/env bash
# send.sh --role <name|role> --message <text> [--no-nudge]
# Orchestrator-only: write a role's inbox (temp-then-rename) THEN flip status to
# working, then nudge its tmux pane. Inbox is written before status so the supervisor
# never reads a half-written handoff.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"

TARGET="" MSG="" NUDGE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --role) TARGET="$2"; shift 2 ;;
    --message) MSG="$2"; shift 2 ;;
    --no-nudge) NUDGE=0; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] && [ -n "$MSG" ] || { echo "usage: send.sh --role <r> --message <m> [--no-nudge]" >&2; exit 2; }

ROLE="$(resolve_role "$TARGET")" || { echo "unknown target: $TARGET" >&2; exit 2; }
[ -d "$ROOT/$ROLE" ] || { echo "no $ROOT/$ROLE (run harness-init first)" >&2; exit 3; }

printf '%s' "$MSG" > "$ROOT/$ROLE/inbox.md.tmp"
mv "$ROOT/$ROLE/inbox.md.tmp" "$ROOT/$ROLE/inbox.md"
set_status "$ROOT" "$ROLE" working

if [ "$NUDGE" -eq 1 ] && [ -n "${TMUX:-}" ]; then
  tmux send-keys -t "harness" "" Enter 2>/dev/null || true
fi
