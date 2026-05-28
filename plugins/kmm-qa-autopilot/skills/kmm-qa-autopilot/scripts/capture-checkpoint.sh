#!/usr/bin/env bash
# capture-checkpoint.sh — snapshot ONE device at ONE checkpoint: a screenshot (evidence)
# plus the view hierarchy (the structural signal the parity verdict is built on).
#
# Call this TWICE per device ~2s apart at each checkpoint (e.g. prefix .s0 then .s1). The
# comparator uses the two same-device samples to auto-detect volatile fields (live prices,
# charts, clocks) — anything that changed on its own gets masked before comparing A vs B.
#
# Usage: capture-checkpoint.sh <serial> <out-prefix>
#   writes <out-prefix>.png and <out-prefix>.hierarchy.json
#
# Run scoped to a locked serial only (lock-a / lock-b). Never let it pick a device implicitly.

set -euo pipefail

SERIAL="${1:?usage: capture-checkpoint.sh <serial> <out-prefix>}"
OUT="${2:?missing out-prefix}"
mkdir -p "$(dirname "$OUT")"

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$ANDROID_HOME/platform-tools/adb"

# Screenshot via adb (reliable, no Maestro session needed). Kept as side-by-side evidence,
# never as the verdict — a live feed guarantees pixels differ between two devices.
"$ADB" -s "$SERIAL" exec-out screencap -p > "$OUT.png" 2>/dev/null || echo "⚠ screenshot failed on $SERIAL"

# View hierarchy: Maestro's accessibility tree (resource-ids = Compose testTags). This is the
# structural + value source the comparator diffs. Maestro's --device flag scopes it.
if command -v maestro >/dev/null; then
  if ! maestro --device "$SERIAL" hierarchy > "$OUT.hierarchy.json" 2>/dev/null; then
    echo "⚠ maestro hierarchy failed on $SERIAL — falling back to uiautomator dump"
    "$ADB" -s "$SERIAL" exec-out uiautomator dump /dev/tty > "$OUT.hierarchy.xml" 2>/dev/null || true
  fi
else
  echo "⚠ maestro not on PATH — using uiautomator dump (XML)"
  "$ADB" -s "$SERIAL" exec-out uiautomator dump /dev/tty > "$OUT.hierarchy.xml" 2>/dev/null || true
fi

echo "captured $SERIAL -> $OUT.{png,hierarchy.json}"
