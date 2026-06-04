#!/usr/bin/env bash
# PreToolUse guard blocks destructive/forbidden shell ops (exit 2 = block).
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../scripts/guard.sh"

rc(){ ( set +e; printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$G" >/dev/null 2>&1; echo $? ); }

# blocked (exit 2)
assert_eq "$(rc 'git push --force origin feat/x')" "2"
assert_eq "$(rc 'git push -f origin feat/x')" "2"
assert_eq "$(rc 'git push origin master')" "2"
assert_eq "$(rc 'adb kill-server')" "2"
assert_eq "$(rc 'adb emu kill')" "2"
assert_eq "$(rc 'rm -rf /')" "2"

# allowed (exit 0)
assert_eq "$(rc 'git push --force-with-lease origin harness/demo-20260604')" "0"
assert_eq "$(rc 'git push origin harness/demo-20260604')" "0"
assert_eq "$(rc 'ls -la')" "0"
assert_eq "$(rc 'adb -s emulator-5554 shell input tap 1 2')" "0"
assert_eq "$(rc 'maestro --device emulator-5554 test flow.yaml')" "0"
echo OK
