#!/usr/bin/env bash
# Multi-run registry + heartbeat + stale detection + per-run lock.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export DEV_HARNESS_HOME="$T/dh"

# add + read
registry_add demo-1 /repo /wt1 harness/demo-1 harness-demo-1
assert_eq "$(registry_get demo-1 status)" "active"
assert_eq "$(registry_get demo-1 branch)" "harness/demo-1"
assert_eq "$(registry_get demo-1 worktree)" "/wt1"
assert_contains "$(registry_list)" "demo-1"

# update status
registry_set demo-1 status paused
assert_eq "$(registry_get demo-1 status)" "paused"

# heartbeat fresh -> not stale; old -> stale
heartbeat demo-1
( is_stale demo-1 120 ) && _FAIL "fresh heartbeat must not be stale"
registry_set demo-1 heartbeat 0
( is_stale demo-1 120 ) || _FAIL "old heartbeat must be stale"

# a second run coexists, first unchanged
registry_add demo-2 /repo /wt2 harness/demo-2 harness-demo-2
assert_contains "$(registry_list)" "demo-2"
assert_eq "$(registry_get demo-1 status)" "paused"

# per-run lock: acquire once; second acquire by a different owner is refused while held
assert_eq "$(run_lock_acquire demo-2 1111; echo $?)" "0"
assert_eq "$(run_lock_acquire demo-2 2222; echo $?)" "1"
run_lock_release demo-2 1111
assert_eq "$(run_lock_acquire demo-2 2222; echo $?)" "0"

# remove
registry_remove demo-1
case "$(registry_list)" in *demo-1*) _FAIL "demo-1 should be removed" ;; esac
assert_contains "$(registry_list)" "demo-2"
echo OK
