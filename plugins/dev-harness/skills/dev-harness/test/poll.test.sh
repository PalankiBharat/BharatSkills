#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

assert_eq "$("$HERE/../scripts/poll.sh" --role dev)" "idle"
set_status "$HARNESS_ROOT" dev done
assert_eq "$("$HERE/../scripts/poll.sh" --role dev)" "done"

# --wait-for matches immediately
"$HERE/../scripts/poll.sh" --role dev --wait-for done --timeout 1 || _FAIL "should match immediately"
# times out when status never reaches target
( "$HERE/../scripts/poll.sh" --role qa --wait-for done --timeout 1 ) && _FAIL "should time out (qa idle)"
echo OK
