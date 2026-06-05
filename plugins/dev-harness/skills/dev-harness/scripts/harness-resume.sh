#!/usr/bin/env bash
# harness-resume.sh — resume a run after a session/context reset ("continue").
# Durable state (.harness/ files + git + PR) survives; the transient tmux panes + watchdog may not.
# If this run's Orchestrator pane is still alive, just RESTART it (re-nudge to continue from
# state.json) and respawn the watchdog — the simple, common case. If the pane is gone, tell the user
# to re-run /harness from inside tmux to rebuild the panes (durable state stays intact).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)/.harness}"
[ -f "$ROOT/state.json" ] || { echo "no run here ($ROOT/state.json missing) — run /harness first." >&2; exit 2; }

OP="$(cat "$ROOT/orchestrator/pane" 2>/dev/null || true)"
if pane_alive "$OP"; then
  pkill -f "watchdog.sh $ROOT " 2>/dev/null || true        # respawn a fresh watchdog
  rm -f "$ROOT/.stop-watchdog"
  nohup bash "$HERE/watchdog.sh" "$ROOT" "$OP" >"$ROOT/watchdog.log" 2>&1 &
  tmux send-keys -t "$OP" -l "continue — re-read .harness/state.json and resume driving from the in-flight stage." 2>/dev/null || true
  sleep 0.4; tmux send-keys -t "$OP" Enter 2>/dev/null || true
  echo "resumed: restarted orchestrator pane $OP + watchdog (run $(jq -r '.run_id // "?"' "$ROOT/state.json" 2>/dev/null))"
  exit 0
fi

echo "run found but its tmux window/Orchestrator pane is gone — re-run /harness from inside tmux to rebuild the panes; .harness/ + git state are intact." >&2
exit 3
