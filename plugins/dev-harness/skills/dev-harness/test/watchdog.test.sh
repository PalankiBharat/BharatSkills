#!/usr/bin/env bash
# File-based watchdog: wakes a never-woke role ONCE, stays quiet for an alive role, escalates a stuck
# role via check-in -> escalate, and wakes the orchestrator when the in_flight role settles.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../scripts/lib.sh"
WD="$HERE/../scripts/watchdog.sh"

# Build a fresh root with a fake wake-hook that logs tagged messages.
new_root() {
  local t; t="$(mktemp -d)"; ROOT="$t/.harness"; harness_init_layout "$ROOT"
  for r in $HARNESS_ROLES; do echo "%$r" > "$ROOT/$r/pane"; done
  WL="$t/wakes.txt"; : > "$WL"
  cat > "$t/wake.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$WL"
EOF
  chmod +x "$t/wake.sh"
  export WATCHDOG_WAKE_CMD="$t/wake.sh" WATCHDOG_INTERVAL=1 WATCHDOG_BOOT_GRACE=1 \
         WATCHDOG_STUCK=2 WATCHDOG_CHECKIN_GRACE=2
}
tag() { grep -c "^$1" "$WL"; }

# 1) NEVER WOKE -> exactly one WAKE (marker prevents repeats), no escalation yet
new_root
set_status "$ROOT" dev working          # status now; worklog/activity older -> no activity since dispatch
bash "$WD" "$ROOT" "%orch" & W=$!; sleep 4; touch "$ROOT/.stop-watchdog"; sleep 1; kill $W 2>/dev/null || true
assert_eq "$(tag WAKE)" "1"

# 2) ALIVE -> stay quiet (recent worklog activity after dispatch)
new_root
set_status "$ROOT" dev working
sleep 1; : > "$ROOT/dev/worklog.md"     # activity AFTER dispatch -> woke + alive
bash "$WD" "$ROOT" "%orch" & W=$!; sleep 2; touch "$ROOT/.stop-watchdog"; sleep 1; kill $W 2>/dev/null || true
assert_eq "$(tag WAKE)" "0"
assert_eq "$(tag CHECKIN)" "0"

# 3) STUCK -> CHECKIN then ESCALATE (woke, then silent past STUCK + CHECKIN_GRACE)
new_root
set_status "$ROOT" qa working
sleep 1; : > "$ROOT/qa/worklog.md"      # woke
bash "$WD" "$ROOT" "%orch" & W=$!; sleep 7; touch "$ROOT/.stop-watchdog"; sleep 1; kill $W 2>/dev/null || true
[ "$(tag CHECKIN)" -ge 1 ]  || _FAIL "stuck role must get a check-in"
[ "$(tag ESCALATE)" -ge 1 ] || _FAIL "still-silent role must escalate"

# 4) SETTLE -> wake the orchestrator once when in_flight role is done|blocked (suffix stripped)
new_root
printf '{"in_flight":"architect:REVIEW"}' > "$ROOT/state.json"
set_status "$ROOT" architect done
bash "$WD" "$ROOT" "%orch" & W=$!; sleep 3; touch "$ROOT/.stop-watchdog"; sleep 1; kill $W 2>/dev/null || true
[ "$(tag SETTLE)" -ge 1 ] || _FAIL "settle must wake the orchestrator"

# 5) LONG THINK -> transcript mtime keeps it ALIVE even with NO worklog/activity updates
new_root
proj="$(mktemp -d)"; mkdir -p "$proj/slug"; sid="sess-xyz"
export WATCHDOG_PROJECTS_DIR="$proj" WATCHDOG_STUCK=2 WATCHDOG_CHECKIN_GRACE=2
echo "$sid" > "$ROOT/qa/session"
set_status "$ROOT" qa working
: > "$proj/slug/$sid.jsonl"              # transcript fresh AFTER dispatch -> woke
bash "$WD" "$ROOT" "%orch" & W=$!
for i in 1 2 3 4 5 6; do sleep 1; : > "$proj/slug/$sid.jsonl"; done   # transcript keeps advancing
touch "$ROOT/.stop-watchdog"; sleep 1; kill $W 2>/dev/null || true
unset WATCHDOG_PROJECTS_DIR
assert_eq "$(tag WAKE)" "0"
assert_eq "$(tag CHECKIN)" "0"          # transcript activity => never "stuck" despite stale worklog
echo OK
