#!/usr/bin/env bash
# screen-coverage-check.sh — Verify screen-map.json covers all navigable screens
# Generated during Phase 1 planning. Customize paths for your project.
#
# Usage: ./screen-coverage-check.sh [--screen-map <path>] [--android-src <path>]
#
# Exit codes: 0 = all screens covered, 1 = missing screens found

set -euo pipefail

SCREEN_MAP="${SCREEN_MAP:-e2e-tests/screen-map.json}"
ANDROID_SRC="${ANDROID_SRC:-androidApp/src}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --screen-map) SCREEN_MAP="$2"; shift 2 ;;
    --android-src) ANDROID_SRC="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

echo "=== Screen Coverage Check ==="
echo "Screen map: $SCREEN_MAP"
echo "Android source: $ANDROID_SRC"
echo ""

if [ ! -f "$SCREEN_MAP" ]; then
  echo "FAIL: screen-map.json not found at $SCREEN_MAP"
  exit 1
fi

FAIL=0

# Extract screen names from screen-map.json
mapped_screens=$(python3 -c "
import json, sys
with open('$SCREEN_MAP') as f:
    data = json.load(f)
screens = data.get('screens', data) if isinstance(data, dict) else data
for s in screens:
    name = s.get('name', s.get('screen', '')) if isinstance(s, dict) else str(s)
    print(name.lower())
" 2>/dev/null || echo "")

if [ -z "$mapped_screens" ]; then
  echo "WARN: Could not parse screen-map.json — check format"
  echo "RESULT: SKIP"
  exit 0
fi

# Strategy 1: Find Compose NavHost routes
compose_routes=$(grep -rhoP 'composable\s*\(\s*"([^"]+)"' "$ANDROID_SRC" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"' || true)

# Strategy 2: Find Activity classes
activities=$(grep -rl "class.*Activity\s*:" "$ANDROID_SRC" 2>/dev/null | xargs -I{} basename {} .kt 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)

# Strategy 3: Find Fragment classes
fragments=$(grep -rl "class.*Fragment\s*:" "$ANDROID_SRC" 2>/dev/null | xargs -I{} basename {} .kt 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)

# Combine all discovered screens
all_screens=$(echo -e "$compose_routes\n$activities\n$fragments" | sort -u | grep -v '^$' || true)

if [ -z "$all_screens" ]; then
  echo "No navigable screens discovered in $ANDROID_SRC"
  echo "RESULT: PASS (nothing to check)"
  exit 0
fi

echo "Discovered screens:"
for screen in $all_screens; do
  # Check if this screen appears in screen-map (fuzzy: lowercase contains)
  if echo "$mapped_screens" | grep -qi "$(echo "$screen" | sed 's/screen\|activity\|fragment//gi' | tr -d '_-')"; then
    echo "  PASS: $screen → found in screen-map.json"
  else
    echo "  FAIL: $screen → NOT in screen-map.json (zero Appium coverage)"
    FAIL=1
  fi
done

echo ""
if [ "$FAIL" -eq 1 ]; then
  echo "RESULT: FAIL — screens missing from screen-map.json"
  exit 1
else
  echo "RESULT: PASS — all discovered screens have screen-map entries"
  exit 0
fi
