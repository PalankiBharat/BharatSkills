#!/usr/bin/env bash
# watchdog wakes the orchestrator on a role settle, and stands down while working / paused.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; ROOT="$T/.harness"; harness_init_layout "$ROOT"

WAKELOG="$T/wakes.txt"; : > "$WAKELOG"
cat > "$T/wake.sh" <<EOF
#!/usr/bin/env bash
printf 'wake\n' >> "$WAKELOG"
EOF
chmod +x "$T/wake.sh"
count() { wc -l < "$WAKELOG" | tr -d ' '; }

export WATCHDOG_INTERVAL=1 WATCHDOG_WAKE_CMD="$T/wake.sh"

# in_flight carries a "role:STAGE" suffix (as the orchestrator writes it); still WORKING -> no wake
printf '{"in_flight":"tech-lead:ANALYSE"}' > "$ROOT/state.json"
set_status "$ROOT" tech-lead working
bash "$HERE/../scripts/watchdog.sh" "$ROOT" "%0" & WPID=$!
sleep 3
assert_eq "$(count)" "0"

# settles done (in_flight still suffixed) -> watchdog strips suffix and wakes
set_status "$ROOT" tech-lead done
sleep 3
[ "$(count)" -ge 1 ] || _FAIL "watchdog must wake on settle (got $(count))"

# orchestrator pauses (in_flight null) -> stands down, no further wakes
printf '{"in_flight":null}' > "$ROOT/state.json"
before="$(count)"; sleep 3
assert_eq "$(count)" "$before"

touch "$ROOT/.stop-watchdog"; sleep 2; kill $WPID 2>/dev/null || true
echo OK
