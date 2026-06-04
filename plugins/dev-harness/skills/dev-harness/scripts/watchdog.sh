#!/usr/bin/env bash
# watchdog.sh <root> <orchestrator-pane> — deterministic liveness for the Orchestrator.
#
# The Orchestrator is an LLM pane and may end its turn after a dispatch (prompt discipline
# alone is not enough — proven in live testing). This watchdog watches state.json's
# `in_flight` role; whenever that role SETTLES (done|blocked) it WAKES the Orchestrator so
# it advances. The Orchestrator still makes every decision — the watchdog only re-wakes it.
#
# It stands down (does nothing) whenever `in_flight` is null — that is how the Orchestrator
# signals an intentional pause (needs-user) or completion. Stops on <root>/.stop-watchdog.
#
# Test seams: WATCHDOG_INTERVAL (poll seconds), WATCHDOG_WAKE_CMD (called with the message
# instead of tmux send-keys — also disables the "busy" check).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"   # HARNESS_ROLES
ROOT="${1:?usage: watchdog.sh <root> <orchestrator-pane>}"
OPANE="${2:?orchestrator pane id}"
STATE="$ROOT/state.json"
INTERVAL="${WATCHDOG_INTERVAL:-12}"

_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

wake() {
  if [ -n "${WATCHDOG_WAKE_CMD:-}" ]; then "$WATCHDOG_WAKE_CMD" "$1"; return; fi
  tmux send-keys -t "$OPANE" -l "$1" 2>/dev/null || true
  sleep 0.4
  tmux send-keys -t "$OPANE" Enter 2>/dev/null || true
}

# Don't wake the Orchestrator while it is actively working (would land text mid-turn).
orch_busy() {
  [ -n "${WATCHDOG_WAKE_CMD:-}" ] && return 1
  tmux capture-pane -p -t "$OPANE" 2>/dev/null | grep -q 'esc to interrupt'
}

# A role that was dispatched (status=working) but never actually woke sits at an idle
# prompt — it shows NO active-work indicator. A working agent shows "esc to interrupt".
# So "needs a nudge" == working status AND not currently processing. (The context bar is
# NOT a reliable idle signal: a busy agent stays under 10% context, bar all-dashes, for a
# long time — keying on that re-nudges a working pane forever and corrupts the run.)
role_idle() {
  [ -n "${WATCHDOG_WAKE_CMD:-}" ] && return 1
  ! tmux capture-pane -p -t "$1" 2>/dev/null | grep -q 'esc to interrupt'
}
renudge_role() {  # <role> <pane>
  _dbg "renudge $1 -> $2"
  tmux send-keys -t "$2" -l "Read .harness/$1/inbox.md and do exactly that now; when finished run: bash .harness/done $1" 2>/dev/null || true
  sleep 0.4
  tmux send-keys -t "$2" Enter 2>/dev/null || true
}
_dbg() { [ -n "${WATCHDOG_DEBUG:-}" ] && printf '%s %s\n' "$(date +%H:%M:%S)" "$1" >> "$ROOT/watchdog.log" || true; }

last="" stale=0
while :; do
  sleep "$INTERVAL"
  [ -f "$ROOT/.stop-watchdog" ] && break
  # Self-reap: if the orchestrator pane is gone (window closed / crashed), exit — never
  # poll forever or stack a zombie per run. (Skipped in test mode, where OPANE is fake.)
  [ -z "${WATCHDOG_WAKE_CMD:-}" ] && { tmux display-message -p -t "$OPANE" '' >/dev/null 2>&1 || break; }

  # Universal role-wake: nudge ANY role that is `working` but whose pane never woke. This
  # is the sole nudge path under --sandbox (the orchestrator's own tmux call is blocked by
  # the sandbox), and a lost-nudge self-heal otherwise. Independent of in_flight. A per-role
  # cooldown (marker-file mtime; no bash-4 assoc arrays — macOS ships bash 3.2) avoids a
  # second nudge in the brief window before the work indicator appears.
  for r in $HARNESS_ROLES; do
    [ -f "$ROOT/$r/status" ] && [ "$(tr -d '\n' < "$ROOT/$r/status")" = "working" ] || continue
    p="$(cat "$ROOT/$r/pane" 2>/dev/null)"; [ -n "$p" ] || continue
    role_idle "$p" || { _dbg "scan: $r working, already busy"; continue; }
    mark="$ROOT/$r/.wd-last-nudge"
    [ -f "$mark" ] && [ $(( $(date +%s) - $(_mtime "$mark") )) -lt 20 ] && continue
    : > "$mark"
    renudge_role "$r" "$p"
  done

  [ -f "$STATE" ] || continue
  R="$(jq -r '.in_flight // empty' "$STATE" 2>/dev/null)" || continue
  [ -n "$R" ] || { last=""; stale=0; continue; }          # paused/complete -> stand down
  R="${R%%:*}"                                             # in_flight may be "role:STAGE"
  [ -f "$ROOT/$R/status" ] || continue
  S="$(tr -d '\n' < "$ROOT/$R/status")"

  case "$S" in done|blocked) ;; *) continue ;; esac        # working handled by the scan above

  key="$R:$S:$(_mtime "$ROOT/$R/status")"
  if [ "$key" = "$last" ]; then
    stale=$((stale + 1))
    [ "$stale" -lt 4 ] && continue                         # re-arm only if it stays stuck
  fi
  orch_busy && continue
  stale=0; last="$key"
  wake "System: the '$R' pane has settled with status '$S'. Continue driving NOW — verify its EXPECTed artifact, run the needs-user gate (read .harness/artifacts/open-questions.md), then dispatch the next step or pause for the user. Do not stop until the run is done, blocked, or needs the user."
done
