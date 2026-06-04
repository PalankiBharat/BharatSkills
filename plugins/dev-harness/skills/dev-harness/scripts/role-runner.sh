#!/usr/bin/env bash
# role-runner.sh <role> [--once] — the per-pane supervisor loop.
# Waits for status=working, runs ONE headless claude on (job-sheet + inbox + feedback),
# streams the live work to the pane via a broadened jq filter, then sets status from the
# result: done = exit 0 AND (no EXPECT, or the EXPECTed artifact exists); else blocked.
# pipefail is load-bearing: without it, jq's exit (0) would mask a failed claude worker.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROLE="${1:?role required}"; shift || true
ONCE=0; [ "${1:-}" = "--once" ] && ONCE=1
CLAUDE_BIN="${CLAUDE_BIN:-/opt/homebrew/bin/claude}"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"
PERSONA="$(lead_persona "$ROLE" 2>/dev/null || echo "$ROLE")"
AGENT_FILE="${ROLE_AGENT:-$HERE/../../../agents/$PERSONA.md}"

# Opt-in OS sandbox (HARNESS_SANDBOX=1): a filesystem+network blast-wall around the
# worker, the doc-blessed alternative to bypass-only. Falls back gracefully if absent.
# Do NOT also set CLAUDE_CODE_SUBPROCESS_ENV_SCRUB — Claude Code forces permission mode to
# "default" when it's set, which deadlocks a headless worker (no human to approve the Write).
# Credentials are still protected by the sandbox's denyRead (~/.aws, ~/.ssh, ~/.config/gh…).
SANDBOX_OPT=""
if [ "${HARNESS_SANDBOX:-0}" = "1" ] && [ -f "$HERE/../assets/sandbox-settings.json" ]; then
  SANDBOX_OPT="--settings $HERE/../assets/sandbox-settings.json"
fi

# Broadened streaming filter (proven in the Task 1 spike): think + tool + text.
FILTER='select(.type=="stream_event") | .event as $e |
  if   $e.type=="content_block_start" and $e.content_block.type=="tool_use" then "\n  🔧 "+$e.content_block.name+" "
  elif $e.type=="content_block_start" and $e.content_block.type=="thinking" then "\n  💭 "
  elif $e.type=="content_block_start" and $e.content_block.type=="text" then "\n  🗨  "
  elif $e.delta.type=="thinking_delta"   then $e.delta.thinking
  elif $e.delta.type=="text_delta"       then $e.delta.text
  elif $e.delta.type=="input_json_delta" then $e.delta.partial_json
  else "" end'

_log() { printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "$ROLE" "$1" >> "$ROOT/$ROLE/worklog.md"; }

_artifact_present() {   # $1 = EXPECT path (relative to .harness or cwd)
  [ -z "$1" ] && return 0
  [ -f "$ROOT/$1" ] || [ -f "$1" ]
}

run_once() {
  local inbox feedback sys firstline expect prompt
  inbox="$(cat "$ROOT/$ROLE/inbox.md")"
  feedback="$(cat "$ROOT/$ROLE/feedback.md" 2>/dev/null || true)"
  sys="$(_strip_frontmatter "$AGENT_FILE" 2>/dev/null || true)"   # the lead agent IS the system prompt
  firstline="$(printf '%s' "$inbox" | head -1)"
  expect="$(printf '%s\n' "$inbox" | sed -n 's/^EXPECT: *//p' | head -1)"
  _log "start: $firstline"

  prompt="INSTRUCTION:
$inbox"
  [ -n "$feedback" ] && prompt="$prompt

USER FEEDBACK (fold into this work):
$feedback"

  if "$CLAUDE_BIN" -p "$prompt" --model opus --append-system-prompt "$sys" $SANDBOX_OPT \
       --permission-mode bypassPermissions \
       --output-format stream-json --verbose --include-partial-messages < /dev/null \
       | jq -rj "$FILTER" \
     && _artifact_present "$expect"; then
    set_status "$ROOT" "$ROLE" done
  else
    set_status "$ROOT" "$ROLE" blocked
  fi
  : > "$ROOT/$ROLE/feedback.md"            # feedback consumed
  _log "finish: status=$(get_status "$ROOT" "$ROLE")"
}

while true; do
  [ "$(get_status "$ROOT" "$ROLE")" = "working" ] && run_once
  [ "$ONCE" -eq 1 ] && break
  sleep 1
done
