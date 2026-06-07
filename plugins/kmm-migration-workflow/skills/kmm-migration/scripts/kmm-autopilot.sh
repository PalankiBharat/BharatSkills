#!/usr/bin/env bash
# Bootstrap an autopilot KMM migration: create/attach a tmux session and launch
# the orchestrator (interactive claude, role=orchestrator). The orchestrator runs
# Phases 0+A with you, then drives B->I via run-phase-worker.sh.
#
# Usage: kmm-autopilot.sh <feature>-<depth>
#   e.g. kmm-autopilot.sh funds-business-logic
# Env:  KMM_AUTOPILOT_DRYRUN=1  -> print/stub actions, don't exec claude
set -euo pipefail
suffix="${1:?usage: kmm-autopilot.sh <feature>-<depth>}"
session="kmm-${suffix}"

if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -n orchestrator -c "$PWD"
fi

launch="env KMM_AUTOPILOT_ROLE=orchestrator claude"
prompt="Start the KMM migration autopilot for ${suffix}. Per the AUTOPILOT ORCHESTRATOR MODE banner, run Phases 0 and A with me, then drive B through I as headless workers."

if [[ "${KMM_AUTOPILOT_DRYRUN:-0}" == "1" ]]; then
  echo "[dryrun] would run in $session: $launch  (prompt: $prompt)"
  # still touch the session window so a dryrun is observable
  tmux send-keys -t "$session:orchestrator" "$launch" C-m 2>/dev/null || true
  exit 0
fi

# Send the launch command into the orchestrator window, then attach.
tmux send-keys -t "$session:orchestrator" "$launch $(printf '%q' "$prompt")" C-m
echo "Orchestrator launching in tmux session '$session'. Attaching..."
exec tmux attach -t "$session"
