#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# stub adb: no devices
cat > "$tmp/adb" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "devices" ]] && { echo "List of devices attached"; echo ""; }
STUB
chmod +x "$tmp/adb"

# Phase C needs no device → ready regardless
PATH="$tmp:$PATH" bash "$here/../preflight.sh" C; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: C should be ready"; exit 1; }

# Phase B needs a device → not ready (no adb device) → non-zero + reason
set +e
PATH="$tmp:$PATH" bash "$here/../preflight.sh" B > "$tmp/b.txt" 2>&1; rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: B should be blocked with no device"; exit 1; }
grep -qi "device" "$tmp/b.txt" || { echo "FAIL: reason should mention device"; exit 1; }

# stub adb: one device present
cat > "$tmp/adb" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "devices" ]] && { echo "List of devices attached"; echo "emulator-5554	device"; }
STUB
chmod +x "$tmp/adb"
PATH="$tmp:$PATH" bash "$here/../preflight.sh" B; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: B ready with a device"; exit 1; }

# --- iOS phases: stub xcrun (simctl reports a booted sim) ---
cat > "$tmp/xcrun" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "simctl list devices" ]]; then
  echo "== Devices =="
  echo "    iPhone 15 (1234-UUID) (Booted)"
fi
exit 0
STUB
chmod +x "$tmp/xcrun"

# D ready when xcrun is present
PATH="$tmp:$PATH" bash "$here/../preflight.sh" D; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: D should be ready with xcrun"; exit 1; }

# E ready when a booted sim is present
PATH="$tmp:$PATH" bash "$here/../preflight.sh" E; rc=$?
[[ $rc -eq 0 ]] || { echo "FAIL: E should be ready with booted sim"; exit 1; }

# E blocked when no booted sim
cat > "$tmp/xcrun" <<'STUB'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "simctl list devices" ]] && echo "== Devices =="
exit 0
STUB
chmod +x "$tmp/xcrun"
set +e
PATH="$tmp:$PATH" bash "$here/../preflight.sh" E > "$tmp/e.txt" 2>&1; rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "FAIL: E should be blocked with no booted sim"; exit 1; }
grep -qi "simulator" "$tmp/e.txt" || { echo "FAIL: E reason should mention simulator"; exit 1; }

# unknown phase → exit 2
set +e
PATH="$tmp:$PATH" bash "$here/../preflight.sh" Z > "$tmp/z.txt" 2>&1; rc=$?
set -e
[[ $rc -eq 2 ]] || { echo "FAIL: unknown phase should exit 2, got $rc"; exit 1; }
echo "ok"
