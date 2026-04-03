#!/usr/bin/env bash
# flow-collector-check.sh — Deterministic ViewModel flow → iOS collector verification
# Generated during Phase 1 planning. Customize SHARED_SRC and IOS_SRC for your project.
#
# Usage: ./flow-collector-check.sh [--shared-src <path>] [--ios-src <path>]
#
# Exit codes: 0 = all flows have collectors, 1 = missing collectors found

set -euo pipefail

# Defaults — overridden by Phase 1 generation or CLI args
SHARED_SRC="${SHARED_SRC:-shared/src/commonMain}"
IOS_SRC="${IOS_SRC:-iosApp/src}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shared-src) SHARED_SRC="$2"; shift 2 ;;
    --ios-src) IOS_SRC="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

FAIL=0

echo "=== Flow Collector Check ==="
echo "Shared source: $SHARED_SRC"
echo "iOS source:    $IOS_SRC"
echo ""

# Step 1: Find all ViewModel files in shared source
viewmodel_files=$(grep -rl "ViewModel\|StateFlow\|SharedFlow\|Channel<" "$SHARED_SRC" 2>/dev/null | grep -i "viewmodel\|vm" || true)

if [ -z "$viewmodel_files" ]; then
  echo "No ViewModel files found in $SHARED_SRC — PASS (nothing to check)"
  exit 0
fi

# Step 2: For each ViewModel, extract flow declarations
for vm_file in $viewmodel_files; do
  vm_name=$(basename "$vm_file" .kt)
  echo "--- $vm_name ($vm_file) ---"

  # Extract flow property names: val <name>: StateFlow/SharedFlow/Channel
  flows=$(grep -oP 'val\s+\K\w+(?=\s*:\s*(State|Shared|Mutable(State|Shared))Flow|Channel)' "$vm_file" 2>/dev/null || true)

  if [ -z "$flows" ]; then
    echo "  No reactive flows found — skip"
    continue
  fi

  # Step 3: For each flow, search iOS source for a collector
  for flow in $flows; do
    # Look for references to this flow name in iOS source (.swift files or CMP .kt files)
    collector=$(grep -rl "$flow" "$IOS_SRC" 2>/dev/null | head -1 || true)

    if [ -z "$collector" ]; then
      echo "  FAIL: $vm_name.$flow — no iOS collector found"
      FAIL=1
    else
      echo "  PASS: $vm_name.$flow → collected in $(basename "$collector")"
    fi
  done
done

echo ""
if [ "$FAIL" -eq 1 ]; then
  echo "RESULT: FAIL — missing iOS collectors detected"
  exit 1
else
  echo "RESULT: PASS — all ViewModel flows have iOS collectors"
  exit 0
fi
