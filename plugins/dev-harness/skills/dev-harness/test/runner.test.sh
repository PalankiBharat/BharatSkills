#!/usr/bin/env bash
# role-runner.sh processes ONE instruction with a stubbed claude (--once mode).
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

# success: stub claude streams one event + creates the EXPECTed artifact -> done
FAKE="$T/fake-claude.sh"
cat > "$FAKE" <<EOF
#!/usr/bin/env bash
echo '{"type":"stream_event","event":{"delta":{"type":"text_delta","text":"ok"}}}'
echo done > "$HARNESS_ROOT/artifacts/spec.md"
exit 0
EOF
chmod +x "$FAKE"
printf 'ANALYSE the story\nEXPECT: artifacts/spec.md\n' > "$HARNESS_ROOT/tech-lead/inbox.md"
printf 'also handle empty state\n' > "$HARNESS_ROOT/tech-lead/feedback.md"
set_status "$HARNESS_ROOT" tech-lead working
CLAUDE_BIN="$FAKE" bash "$HERE/../scripts/role-runner.sh" tech-lead --once

assert_eq "$(get_status "$HARNESS_ROOT" tech-lead)" "done"
assert_file "$HARNESS_ROOT/artifacts/spec.md"
assert_contains "$(cat "$HARNESS_ROOT/tech-lead/worklog.md")" "ANALYSE"
assert_eq "$(cat "$HARNESS_ROOT/tech-lead/feedback.md")" ""   # feedback consumed

# failure: stub exits non-zero -> blocked
FAIL="$T/fail.sh"; printf '#!/usr/bin/env bash\nexit 1\n' > "$FAIL"; chmod +x "$FAIL"
printf 'PLAN it\n' > "$HARNESS_ROOT/dev/inbox.md"
set_status "$HARNESS_ROOT" dev working
CLAUDE_BIN="$FAIL" bash "$HERE/../scripts/role-runner.sh" dev --once || true
assert_eq "$(get_status "$HARNESS_ROOT" dev)" "blocked"

# missing expected artifact despite exit 0 -> blocked (done-signal hardening)
NOART="$T/noart.sh"; printf '#!/usr/bin/env bash\necho "{}"\nexit 0\n' > "$NOART"; chmod +x "$NOART"
printf 'PREP\nEXPECT: artifacts/qa-scenarios.md\n' > "$HARNESS_ROOT/qa/inbox.md"
set_status "$HARNESS_ROOT" qa working
CLAUDE_BIN="$NOART" bash "$HERE/../scripts/role-runner.sh" qa --once || true
assert_eq "$(get_status "$HARNESS_ROOT" qa)" "blocked"
echo OK
