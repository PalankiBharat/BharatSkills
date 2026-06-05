#!/usr/bin/env bash
# Contract for harness-init.sh (scriptable core) + its pure helpers in lib.sh.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"

# --- pure helper: pick_serial (parses `adb devices` output) ---
ONE='List of devices attached
emulator-5554	device
'
assert_eq "$(pick_serial "$ONE")" "emulator-5554"

NONE='List of devices attached
'
( pick_serial "$NONE" 2>/dev/null ) && _FAIL "no device -> non-zero"

TWO='List of devices attached
emulator-5554	device
emulator-5556	device
'
( pick_serial "$TWO" 2>/dev/null ) && _FAIL "two devices -> non-zero (needs --serial)"

OFFLINE='List of devices attached
emulator-5554	offline
'
( pick_serial "$OFFLINE" 2>/dev/null ) && _FAIL "offline device -> non-zero"

# --- pure helper: preflight_missing (reports tools not on PATH) ---
assert_eq "$(preflight_missing bash sh 2>/dev/null; echo "rc=$?")" "rc=0"
out="$(preflight_missing bash __no_such_tool_xyz__ 2>&1 || true)"
assert_contains "$out" "__no_such_tool_xyz__"

# --- the script: scriptable bootstrap (no tmux, no branch, no emulator) ---
T="$(mktemp -d)"; cd "$T"; export DEV_HARNESS_HOME="$T/dh"
git init -q && git commit --allow-empty -q -m base
"$HERE/../scripts/harness-init.sh" --story "Make it pop" --slug demo \
  --no-tmux --no-branch --no-emulator >/dev/null

for r in tech-lead dev qa architect; do assert_dir "$T/.harness/$r"; done
assert_dir  "$T/.harness/artifacts"
# the Orchestrator gets its own mailbox dir (it drives from a visible pane)
assert_dir  "$T/.harness/orchestrator"
assert_file "$T/.harness/orchestrator/inbox.md"
# path-independent driver wrappers so the orchestrator persona can dispatch/poll
assert_file "$T/.harness/send"
assert_file "$T/.harness/poll"
assert_file "$T/.harness/ask"
assert_file "$T/.harness/run"
assert_file "$T/.harness/dev/activity.log"
assert_file "$T/.harness/answer"
assert_file "$T/.harness/require"
assert_file "$T/.harness/resume"
bash "$T/.harness/send" dev "ANALYSE: do the thing"
assert_eq "$(cat "$T/.harness/dev/inbox.md")" "ANALYSE: do the thing"
assert_eq "$(cat "$T/.harness/dev/status")" "working"
assert_eq "$(bash "$T/.harness/poll" dev)" "working"
assert_contains "$(cat "$T/.harness/story.md")" "Make it pop"
assert_file "$T/.harness/log.md"
assert_file "$T/.harness/state.json"
assert_contains "$(cat "$T/.harness/state.json")" "demo"
# .harness/ must be gitignored (security rail)
assert_contains "$(cat "$T/.gitignore")" ".harness/"
# the run is registered in the cross-run registry (v2)
assert_contains "$(registry_list)" "demo"
# the completion sentinel exists and works
assert_file "$T/.harness/done"
bash "$T/.harness/done" tech-lead
assert_eq "$(cat "$T/.harness/tech-lead/status")" "done"
bash "$T/.harness/done" dev blocked
assert_eq "$(cat "$T/.harness/dev/status")" "blocked"

echo OK
