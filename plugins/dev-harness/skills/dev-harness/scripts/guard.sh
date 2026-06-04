#!/usr/bin/env bash
# guard.sh — PreToolUse hook. Blocks destructive/forbidden shell ops regardless of
# the model (bash-enforced security rail). Exit 2 = deny the tool call.
set -eu
cmd="$(cat | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0
deny() { echo "BLOCKED by dev-harness guard: $1" >&2; exit 2; }

# Plain force-push is banned (--force-with-lease on the run's own branch is allowed).
printf '%s\n' "$cmd" | grep -Eq 'git[[:space:]]+push.*(--force([[:space:]]|$|=)|[[:space:]]-f([[:space:]]|$))' \
  && { printf '%s\n' "$cmd" | grep -Eq -- '--force-with-lease' || deny "force-push (use --force-with-lease on the run's own branch only)"; }
# Pushing to master/main is banned.
printf '%s\n' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]]+origin)?[[:space:]]+(master|main)([[:space:]]|$)' \
  && deny "push to master/main"
# Global/destructive device ops.
printf '%s\n' "$cmd" | grep -Eq 'adb[[:space:]]+(kill-server|emu[[:space:]]+kill|reboot)' \
  && deny "global adb op (scope to the locked serial with adb -s)"
# Catastrophic filesystem op.
printf '%s\n' "$cmd" | grep -Eq 'rm[[:space:]]+-rf[[:space:]]+/([[:space:]]|$)' \
  && deny "rm -rf /"
exit 0
