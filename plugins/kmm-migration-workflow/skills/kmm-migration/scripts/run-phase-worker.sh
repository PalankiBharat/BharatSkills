#!/usr/bin/env bash
# Spawn one headless KMM-migration phase worker in a fresh tmux window, wait for
# it to exit, then echo its status (COMPLETE | BLOCKED | FAILED).
#
# Worker invocation (locked in Task B1; CLI 2.1.168 has no --max-turns):
#   claude -p "<prompt>" --dangerously-skip-permissions --no-session-persistence
#
# Usage: run-phase-worker.sh <PHASE_ID>
# Env:   ORCH_DIR  = path to .../orchestration  (default: $PWD/.kmm-orch fallback)
#        TMUX_SESSION = tmux session name to create the window in (default: current)
set -euo pipefail

phase="${1:?usage: run-phase-worker.sh <PHASE_ID>}"
orch_dir="${ORCH_DIR:?ORCH_DIR must point at the orchestration/ dir}"
status_file="$orch_dir/phase-${phase}.status"
session="${TMUX_SESSION:-$(tmux display-message -p '#S' 2>/dev/null || echo kmm)}"
window="kmm-phase-${phase}"

rm -f "$status_file"

prompt="Resume this KMM migration. Per the AUTOPILOT WORKER MODE banner, run only the active phase to completion and write your orchestration status file."

# -d: don't switch focus; the worker runs to completion then the window's command
# exits. We block until the window is gone.
# || true: the test's tmux stub runs the worker synchronously and exits with the
# worker's code; real `tmux new-window -d` always returns 0 immediately (window
# creation, not process completion), so this suppression is a no-op in production.
tmux new-window -d -t "$session" -n "$window" -- \
  env KMM_AUTOPILOT_ROLE=worker KMM_AUTOPILOT_PHASE="$phase" \
  claude -p "$prompt" --dangerously-skip-permissions --no-session-persistence || true

# Wait for the worker window to disappear (process exited).
while tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null \
        | grep -qx "$window"; do
  sleep 2
done

if [[ -f "$status_file" ]]; then
  cat "$status_file"
else
  echo "FAILED: worker for phase ${phase} exited without writing ${status_file}"
fi
