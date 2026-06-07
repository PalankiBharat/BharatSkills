#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"; export DEV_HARNESS_HOME="$T/dhhome"
harness_init_layout "$HARNESS_ROOT"
FB="$HERE/../scripts/feedback.sh"

# task lane by persona -> the persona's role feedback file
"$FB" task bharat "handle the empty-cart case"
assert_contains "$(cat "$HARNESS_ROOT/dev/feedback.md")" "empty-cart"

# task lane by role key
"$FB" task qa "also test landscape"
assert_contains "$(cat "$HARNESS_ROOT/qa/feedback.md")" "landscape"

# skill lane -> durable cross-run store (not a role file)
"$FB" skill qa-autopilot "keeps using text selectors instead of testTag"
assert_contains "$(cat "$DEV_HARNESS_HOME/skill-feedback/qa-autopilot.md")" "text selectors"

# secret redaction (security rail): tokens never written verbatim
"$FB" task dev "my key is ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789xx"
body="$(cat "$HARNESS_ROOT/dev/feedback.md")"
assert_contains "$body" "REDACTED"
case "$body" in *ghp_ABCDEFGHIJKLMNOPQRST*) _FAIL "secret leaked into feedback" ;; esac

# unknown task target refused
( "$FB" task hacker "x" 2>/dev/null ) && _FAIL "unknown target refused"
echo OK
