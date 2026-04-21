#!/usr/bin/env bash
# flow-collector-check.sh — Deterministic ViewModel flow → iOS collector verification.
# Generated during Phase 1 planning. Customize SHARED_SRC, IOS_SRC, and VM_ACCESSOR.
#
# Usage: ./flow-collector-check.sh [--shared-src <path>] [--ios-src <path>] [--vm-accessor <pattern>]
#
# Exit codes: 0 = all flows have collectors, 1 = missing collectors found
#
# This version (v2) tightens both sides:
#   - VM detection: grep for "class <X> : BaseViewModel" OR "class <X>.*ViewModel" — covers
#     classes whose file names don't match "*ViewModel.kt" (e.g., AuthPresenter.kt)
#   - Flow extraction: requires explicit `val <name>: <State|Shared|Mutable><kind>Flow` — won't
#     match bare "Channel" in comments
#   - Collector check: requires the iOS file to contain <VM_ACCESSOR>\.<flow> in the context
#     of a `.task {` or `for await` block, not just any mention of the flow name

set -euo pipefail

SHARED_SRC="${SHARED_SRC:-shared/src/commonMain}"
IOS_SRC="${IOS_SRC:-iosApp/src}"
# Pattern used in Swift to access VM properties. Customize per project DI pattern.
# Examples: "viewModel", "vm", "presenter". Grep falls back across common accessors.
VM_ACCESSOR="${VM_ACCESSOR:-viewModel|vm|presenter}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shared-src) SHARED_SRC="$2"; shift 2 ;;
    --ios-src) IOS_SRC="$2"; shift 2 ;;
    --vm-accessor) VM_ACCESSOR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

FAIL=0

echo "=== Flow Collector Check (v2) ==="
echo "Shared source:  $SHARED_SRC"
echo "iOS source:     $IOS_SRC"
echo "VM accessor:    $VM_ACCESSOR"
echo ""

# Step 1: Find VM-like files in shared source — must declare a class that
# extends *ViewModel or is directly annotated as one. Not filename-based.
viewmodel_files=$(grep -rEl "class\s+\w+.*:\s*\w*ViewModel|class\s+\w+\s*:\s*BaseViewModel" "$SHARED_SRC" 2>/dev/null || true)

if [ -z "$viewmodel_files" ]; then
  echo "No ViewModel-like classes found in $SHARED_SRC — PASS (nothing to check)"
  exit 0
fi

for vm_file in $viewmodel_files; do
  vm_name=$(basename "$vm_file" .kt)
  echo "--- $vm_name ($vm_file) ---"

  # Step 2: Extract flow property names strictly.
  # Matches: val <name>: StateFlow<T>, val <name>: SharedFlow<T>, val <name>: MutableStateFlow<T>,
  #          val <name>: Channel<T>, protected val <name>: StateFlow<T>, etc.
  # Rejects: bare "Channel" in comments, standalone type names.
  flows=$(perl -ne '
    next if /^\s*\/\//;  # skip line comments
    next if /^\s*\*/;    # skip block comment lines
    if (/\b(?:val|var)\s+(\w+)\s*:\s*(?:Mutable)?(?:State|Shared)Flow\s*</ ||
        /\b(?:val|var)\s+(\w+)\s*:\s*Channel\s*</) {
      print "$1\n";
    }
  ' "$vm_file" 2>/dev/null || true)

  if [ -z "$flows" ]; then
    echo "  No reactive flows found — skip"
    continue
  fi

  # Step 3: For each flow, require the iOS source to have a structural
  # collector — `.task { for await ... in <accessor>.<flow>` or
  # `collectAsState()` on a <accessor>.<flow> receiver.
  for flow in $flows; do
    if grep -rEq "(?:$VM_ACCESSOR)\.$flow\b[^=]*(?:\.collect|for\s+await|collectAsState)" "$IOS_SRC" 2>/dev/null \
       || grep -rEq "for\s+await[^{]*in\s+(?:$VM_ACCESSOR)\.$flow\b" "$IOS_SRC" 2>/dev/null; then
      echo "  PASS: $vm_name.$flow"
    else
      # Fallback: property access with no structural collector is flagged as warning, not pass.
      if grep -rEq "(?:$VM_ACCESSOR)\.$flow\b" "$IOS_SRC" 2>/dev/null; then
        echo "  WARN: $vm_name.$flow — accessed but no .task { for await } / collectAsState found"
        FAIL=1
      else
        echo "  FAIL: $vm_name.$flow — no iOS collector found"
        FAIL=1
      fi
    fi
  done
done

echo ""
if [ "$FAIL" -eq 1 ]; then
  echo "RESULT: FAIL — missing or non-structural iOS collectors"
  exit 1
else
  echo "RESULT: PASS — all ViewModel flows have structural iOS collectors"
  exit 0
fi
