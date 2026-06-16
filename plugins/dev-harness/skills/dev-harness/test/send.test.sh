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

# ledger: a dispatch writes a plain-language "→ role" line, EXPECT/file plumbing stripped,
# with the produced artifact kept as a "⇒ <basename>" suffix
"$HERE/../scripts/send.sh" --role dev \
  --message "build phase 1 — port the SDK locked-config, publish alpha. EXPECT: .harness/artifacts/dev-handoff.md" --no-nudge
LOG="$(cat "$HARNESS_ROOT/log.md")"
assert_contains "$LOG" "→ dev"
assert_contains "$LOG" "build phase 1 — port the SDK locked-config, publish alpha"
assert_contains "$LOG" "⇒ dev-handoff.md"
case "$LOG" in *EXPECT*|*.harness/artifacts*) _FAIL "ledger must strip EXPECT/file plumbing";; esac
echo OK
