#!/usr/bin/env bash
# harness-resume.sh: with no run -> exit 2; with a run but no live orchestrator pane -> exit 3
# (tells the user to re-run /harness). The live-pane re-nudge path needs real tmux and is covered
# by the watchdog's send mechanism + live test.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
RS="$HERE/../scripts/harness-resume.sh"
assert_file "$RS"

# no run here -> exit 2
T="$(mktemp -d)"; cd "$T"; git init -q; git commit --allow-empty -qm base
rc=0; ( HARNESS_ROOT="$T/.harness" bash "$RS" >/dev/null 2>&1 ) || rc=$?
assert_eq "$rc" "2"

# a run exists but the orchestrator pane is dead/absent -> exit 3 (rebuild needed)
export DEV_HARNESS_HOME="$T/dh"
"$HERE/../scripts/harness-init.sh" --story x --slug t --no-tmux --no-branch --no-emulator >/dev/null
echo "%999" > "$T/.harness/orchestrator/pane"   # a pane id that doesn't exist
rc=0; ( HARNESS_ROOT="$T/.harness" bash "$RS" >/dev/null 2>&1 ) || rc=$?
assert_eq "$rc" "3"
echo OK
