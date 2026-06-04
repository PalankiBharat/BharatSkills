#!/usr/bin/env bash
# harness-allow.sh — pre-approve the harness's own scripts so the Orchestrator's
# send/poll/init/render/feedback/tmux calls don't prompt the user on every step.
# Adds Bash allow-rules to the project's .claude/settings.local.json (idempotent, gitignored).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=".claude/settings.local.json"
mkdir -p .claude
[ -f "$DEST" ] || echo '{}' > "$DEST"

rules="$(jq -n --arg h "$HERE" '[
  "Bash(\($h)/harness-init.sh:*)",
  "Bash(\($h)/send.sh:*)",
  "Bash(\($h)/poll.sh:*)",
  "Bash(\($h)/feedback.sh:*)",
  "Bash(\($h)/render-review.sh:*)",
  "Bash(\($h)/harness-allow.sh:*)",
  "Bash(tmux:*)"
]')"
jq --argjson add "$rules" '.permissions.allow = ((.permissions.allow // []) + $add | unique)' \
  "$DEST" > "$DEST.tmp" && mv "$DEST.tmp" "$DEST"
echo "pre-approved harness scripts in $DEST"
