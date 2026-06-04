#!/usr/bin/env bash
# .harness/run <role> -- <cmd> tees combined output to .harness/<role>/activity.log (the watchdog's
# "alive during a long build" signal) and forwards the command's real exit code.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; cd "$T"; git init -q; git commit --allow-empty -qm base; export DEV_HARNESS_HOME="$T/dh"
"$HERE/../scripts/harness-init.sh" --story "x" --slug t --no-tmux --no-branch --no-emulator >/dev/null

assert_file "$T/.harness/run"
assert_file "$T/.harness/dev/activity.log"

# output is tee'd to the role's activity.log
bash "$T/.harness/run" dev -- printf 'hello-build\n' >/dev/null
assert_contains "$(cat "$T/.harness/dev/activity.log")" "hello-build"

# activity.log MTIME advances when a command runs (the liveness signal)
before="$(stat -f %m "$T/.harness/dev/activity.log" 2>/dev/null || stat -c %Y "$T/.harness/dev/activity.log")"
sleep 1
bash "$T/.harness/run" dev -- printf 'more\n' >/dev/null
after="$(stat -f %m "$T/.harness/dev/activity.log" 2>/dev/null || stat -c %Y "$T/.harness/dev/activity.log")"
[ "$after" -gt "$before" ] || _FAIL "activity.log mtime must advance on run"

# the command's REAL exit code is forwarded (not tee's)
bash "$T/.harness/run" dev -- false && _FAIL "should forward non-zero exit"
bash "$T/.harness/run" dev -- true  || _FAIL "should forward zero exit"

# unknown role rejected
( bash "$T/.harness/run" nobody -- true 2>/dev/null ) && _FAIL "unknown role must fail"
echo OK
