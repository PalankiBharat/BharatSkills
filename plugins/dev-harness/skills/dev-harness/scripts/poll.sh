#!/usr/bin/env bash
# poll.sh --role <name|role> [--wait-for <status>] [--timeout <sec>]
# Without --wait-for: print the role's status. With it: block (shell-native, no
# coreutils `timeout`) until that status appears or --timeout seconds elapse (exit 1).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"

TARGET="" WAIT="" TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --role) TARGET="$2"; shift 2 ;;
    --wait-for) WAIT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: poll.sh --role <r> [--wait-for <s>] [--timeout N]" >&2; exit 2; }
ROLE="$(resolve_role "$TARGET")" || { echo "unknown target: $TARGET" >&2; exit 2; }

[ -z "$WAIT" ] && { get_status "$ROOT" "$ROLE"; exit 0; }

deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -le "$deadline" ]; do
  [ "$(get_status "$ROOT" "$ROLE")" = "$WAIT" ] && exit 0
  sleep 1
done
exit 1
