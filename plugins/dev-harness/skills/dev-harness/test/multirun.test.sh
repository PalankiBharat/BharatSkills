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

# --- isolation: two real runs in ONE repo each get their OWN worktree + .harness/ ---
# (regression for the collision where a second in-place run clobbered the first's branch/state)
INIT="$HERE/../scripts/harness-init.sh"
R="$(mktemp -d)"; ( cd "$R" && git init -q && git commit --allow-empty -qm base )
( cd "$R" && bash "$INIT" --story "first"  --slug run-a --no-tmux --no-emulator >/dev/null )
( cd "$R" && bash "$INIT" --story "second" --slug run-b --no-tmux --no-emulator >/dev/null )
# each run owns a separate worktree dir, each with its own state.json on its own slug
WA="$(ls -d "$R/.harness-worktrees/"run-a* 2>/dev/null)" || _FAIL "run-a worktree missing"
WB="$(ls -d "$R/.harness-worktrees/"run-b* 2>/dev/null)" || _FAIL "run-b worktree missing"
[ -n "$WA" ] && [ -n "$WB" ] && [ "$WA" != "$WB" ] || _FAIL "two runs must not share a worktree"
assert_dir "$WA/.harness"; assert_dir "$WB/.harness"
assert_eq "$(jq -r .slug "$WA/.harness/state.json")" "run-a"
assert_eq "$(jq -r .slug "$WB/.harness/state.json")" "run-b"
# the first run's state is intact after the second run (the bug clobbered it)
assert_eq "$(jq -r .branch "$WA/.harness/state.json")" "run-a"
# the main checkout was never switched off its base branch
assert_eq "$(cd "$R" && git branch --show-current)" "$(cd "$R" && git rev-parse --abbrev-ref HEAD)"
# two worktrees + the main checkout = 3 entries
assert_eq "$(cd "$R" && git worktree list | wc -l | tr -d ' ')" "3"

# same-slug back-to-back (same second) must still isolate — RUN_ID carries the PID, and a
# taken branch name falls back to the unique run-id, so neither run aborts or shares a tree
( cd "$R" && bash "$INIT" --story d1 --slug dup --no-tmux --no-emulator >/dev/null )
( cd "$R" && bash "$INIT" --story d2 --slug dup --no-tmux --no-emulator >/dev/null )
assert_eq "$(ls -d "$R/.harness-worktrees/"dup* | wc -l | tr -d ' ')" "2"
assert_eq "$(cd "$R" && git worktree list | wc -l | tr -d ' ')" "5"
echo OK
