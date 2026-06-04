#!/usr/bin/env bash
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

printf '# Phase plan\n- P1 UI\n- P2 logic\nNeeds <review> & sign-off\n' > "$T/payload.md"
out="$("$HERE/../scripts/render-review.sh" plan "$T/payload.md" --no-open)"

assert_file "$out"
html="$(cat "$out")"
assert_contains "$html" "P1 UI"
assert_contains "$html" "Copy"                 # copy-back button present
assert_contains "$html" "dev-harness"          # branded header
assert_contains "$html" "plan"                 # kind shown
# HTML-escaping: raw angle brackets must not leak as live tags
case "$html" in *"<review>"*) _FAIL "payload not HTML-escaped" ;; esac
assert_contains "$html" "&lt;review&gt;"
# written under the run's review/ dir
case "$out" in *"/.harness/review/"*) ;; *) _FAIL "not under .harness/review/" ;; esac
echo OK
