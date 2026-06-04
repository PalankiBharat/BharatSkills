#!/usr/bin/env bash
# agent-pane.sh <role> — runs INSIDE a tmux pane. Launches a persistent, visible,
# interactive Claude as the role's persona agent. The orchestrator drives it by
# writing .harness/<role>/inbox.md and send-keys-ing a short nudge; the agent reads
# the inbox, works (visibly), then runs agent-done.sh. It NEVER exits between tasks.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROLE="${1:?role required}"
PERSONA="$(lead_persona "$ROLE" 2>/dev/null || echo "$ROLE")"
CLAUDE_BIN="${CLAUDE_BIN:-/opt/homebrew/bin/claude}"   # absolute — never the zsh shell-function

# Opt-in OS sandbox (same settings as the headless path).
SANDBOX_OPT=""
if [ "${HARNESS_SANDBOX:-0}" = "1" ] && [ -f "$HERE/../assets/sandbox-settings.json" ]; then
  SANDBOX_OPT="--settings $HERE/../assets/sandbox-settings.json"
fi

printf '\033[1;35m▌ %s\033[0m — waiting for the orchestrator. You can watch here; do not type.\n\n' "$PERSONA"
# Interactive Claude AS the persona agent (loads its system prompt + model), no prompts.
exec "$CLAUDE_BIN" --agent "$PERSONA" --permission-mode bypassPermissions $SANDBOX_OPT
