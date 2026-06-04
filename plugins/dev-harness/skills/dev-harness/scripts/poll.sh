#!/usr/bin/env bash
# poll.sh --role <name|role> [--wait-for <status> | --settle] [--timeout <sec>]
#   no mode      : print the role's current status (exit 0).
#   --wait-for S : block (shell-native, no coreutils `timeout`) until status == S.
#   --settle     : block until status is terminal (done|blocked); print which.
# On timeout EITHER blocking mode prints `still-working` and exits 0 — the Orchestrator
# loops on that word instead of treating a non-zero exit as a failure. Default timeout
# 240s stays under the Bash-tool cap so the driver's poll call always returns cleanly.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"

TARGET="" WAIT="" SETTLE=0 TIMEOUT=240
while [ $# -gt 0 ]; do
  case "$1" in
    --role) TARGET="$2"; shift 2 ;;
    --wait-for) WAIT="$2"; shift 2 ;;
    --settle) SETTLE=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: poll.sh --role <r> [--wait-for <s>|--settle] [--timeout N]" >&2; exit 2; }
ROLE="$(resolve_role "$TARGET")" || { echo "unknown target: $TARGET" >&2; exit 2; }

[ -z "$WAIT" ] && [ "$SETTLE" -eq 0 ] && { get_status "$ROOT" "$ROLE"; exit 0; }

# Print the status and succeed once the wait condition is met; else non-zero.
_reached() {
  local s; s="$(get_status "$ROOT" "$ROLE")"
  if [ "$SETTLE" -eq 1 ]; then
    case "$s" in done|blocked) printf '%s' "$s"; return 0 ;; esac
  elif [ "$s" = "$WAIT" ]; then
    printf '%s' "$s"; return 0
  fi
  return 1
}

deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -le "$deadline" ]; do
  _reached && exit 0
  sleep 1
done
printf 'still-working'
exit 0
