#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

# writes inbox + flips status; --no-nudge skips tmux
"$HERE/../scripts/send.sh" --role dev --message "plan it" --no-nudge
assert_eq "$(cat "$HARNESS_ROOT/dev/inbox.md")" "plan it"
assert_eq "$(get_status "$HARNESS_ROOT" dev)" "working"

# persona target resolves to its role
"$HERE/../scripts/send.sh" --role rohit --message "test it" --no-nudge
assert_eq "$(get_status "$HARNESS_ROOT" qa)" "working"
assert_eq "$(cat "$HARNESS_ROOT/qa/inbox.md")" "test it"

# unknown target refused
( "$HERE/../scripts/send.sh" --role hacker --message x --no-nudge 2>/dev/null ) && _FAIL "unknown target refused"
echo OK
