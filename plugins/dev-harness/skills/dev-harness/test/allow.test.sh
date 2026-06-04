#!/usr/bin/env bash
# harness-allow.sh pre-approves the harness scripts in .claude/settings.local.json (idempotent).
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; cd "$T"

bash "$HERE/../scripts/harness-allow.sh" >/dev/null
assert_file "$T/.claude/settings.local.json"
body="$(cat "$T/.claude/settings.local.json")"
assert_contains "$body" "send.sh"
assert_contains "$body" "poll.sh"
assert_contains "$body" "Bash(tmux:*)"
# valid JSON with a permissions.allow array
python3 -c "import json; d=json.load(open('$T/.claude/settings.local.json')); assert isinstance(d['permissions']['allow'], list) and d['permissions']['allow']"

# idempotent: second run keeps it valid and de-duplicated
bash "$HERE/../scripts/harness-allow.sh" >/dev/null
python3 -c "import json; a=json.load(open('$T/.claude/settings.local.json'))['permissions']['allow']; assert len(a)==len(set(a)), 'duplicate allow rules'"
echo OK
