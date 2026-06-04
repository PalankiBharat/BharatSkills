#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

# no mode -> current status
assert_eq "$("$HERE/../scripts/poll.sh" --role dev)" "idle"
set_status "$HARNESS_ROOT" dev done
assert_eq "$("$HERE/../scripts/poll.sh" --role dev)" "done"

# --wait-for matches immediately and prints the status
assert_eq "$("$HERE/../scripts/poll.sh" --role dev --wait-for done --timeout 1)" "done"

# timeout NEVER errors — it prints `still-working` (exit 0) so the orchestrator loops
out="$("$HERE/../scripts/poll.sh" --role qa --wait-for done --timeout 1)"; rc=$?
assert_eq "$out" "still-working"
assert_eq "$rc" "0"

# --settle returns on ANY terminal status (done OR blocked), not just `done`
set_status "$HARNESS_ROOT" architect blocked
assert_eq "$("$HERE/../scripts/poll.sh" --role architect --settle --timeout 1)" "blocked"
assert_eq "$("$HERE/../scripts/poll.sh" --role dev --settle --timeout 1)" "done"
echo OK
