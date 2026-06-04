#!/usr/bin/env bash
# send.sh --role <name|role> --message <text> [--no-nudge]
# Orchestrator-only: write a role's inbox (temp-then-rename), flip status to working,
# then NUDGE the role's interactive-Claude pane (send-keys a short trigger to the recorded
# pane id) so the agent reads its inbox. The full instruction lives in the inbox FILE — only
# a one-line trigger goes through send-keys (no multiline/quoting hazards).
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

if [ "$NUDGE" -eq 1 ] && [ -n "${TMUX:-}" ] && [ -f "$ROOT/$ROLE/pane" ]; then
  PANE="$(cat "$ROOT/$ROLE/pane")"
  # Claude's TUI needs the text and a SEPARATE Enter (a combined "text" Enter leaves it
  # unsubmitted under bracketed-paste). Type the trigger literally, pause, then submit.
  tmux send-keys -t "$PANE" -l "Read .harness/$ROLE/inbox.md and do exactly that now; when finished run: bash .harness/done $ROLE" 2>/dev/null || true
  sleep 0.4
  tmux send-keys -t "$PANE" Enter 2>/dev/null || true
fi
