#!/usr/bin/env bash
# Spawn one headless KMM-migration phase worker in a fresh tmux window, wait for
# it to exit, then echo its status (COMPLETE | BLOCKED | FAILED).
#
# Worker invocation (locked in Task B1; CLI 2.1.168 has no --max-turns):
#   claude -p "<prompt>" --dangerously-skip-permissions --no-session-persistence
#
# Usage: run-phase-worker.sh <PHASE_ID>
# Env:   ORCH_DIR (optional) — orchestration dir. When unset, it is auto-derived
#          from the kmm/<suffix> branch as
#          <repo>/.kmm/migrations/kmm/<suffix>/orchestration. It is passed to the
#          worker as KMM_ORCH_DIR (absolute) so the worker writes its status to the
#          exact same path this script polls — CWD-independent.
#        TMUX_SESSION (optional) — session to create the window in (default: current).
set -euo pipefail

phase="${1:?usage: run-phase-worker.sh <PHASE_ID>}"

if [[ -n "${ORCH_DIR:-}" ]]; then
  orch_dir="$ORCH_DIR"
  repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
else
  repo_root="$(git rev-parse --show-toplevel)"
  branch="$(git -C "$repo_root" branch --show-current)"
  suffix="${branch#kmm/}"
  orch_dir="$repo_root/.kmm/migrations/kmm/$suffix/orchestration"
fi
mkdir -p "$orch_dir"

status_file="$orch_dir/phase-${phase}.status"
session="${TMUX_SESSION:-$(tmux display-message -p '#S' 2>/dev/null || echo kmm)}"
window="kmm-phase-${phase}"

rm -f "$status_file"

prompt="Resume this KMM migration. Per the AUTOPILOT WORKER MODE banner, run only the active phase to completion and write your orchestration status file."

# -d: don't switch focus. -c "$repo_root": the worker's CWD is the repo root (gradle
# and git operate from there). KMM_ORCH_DIR (absolute) tells the worker exactly where
# to write its status / decision files — the same dir this script polls below.
# || true: in tests the tmux stub runs the worker synchronously and exits with the
# worker's code; real `tmux new-window -d` always returns 0 immediately (window
# creation, not process completion), so this suppression is a no-op in production.
tmux new-window -d -c "$repo_root" -t "$session" -n "$window" -- \
  env KMM_AUTOPILOT_ROLE=worker KMM_AUTOPILOT_PHASE="$phase" KMM_ORCH_DIR="$orch_dir" \
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
