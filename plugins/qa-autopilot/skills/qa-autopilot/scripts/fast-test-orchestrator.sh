#!/bin/bash
# fast-test-orchestrator.sh — Host-side orchestrator for fast QA execution
#
# Workflow:
#   1. Push fast-runner.sh to device
#   2. For each compiled test script:
#      a. Push script to device
#      b. Run on device (no host round-trips during execution)
#      c. Pull results (log + checkpoint screenshots + checkpoint XML)
#   3. Output structured results for Claude to verify
#
# Usage:
#   bash fast-test-orchestrator.sh <compiled_dir> [--serial <device_id>]
#
# Expects:
#   <compiled_dir>/manifest.json
#   <compiled_dir>/TC-*.sh (compiled test scripts)

set -euo pipefail

COMPILED_DIR="${1:?Usage: fast-test-orchestrator.sh <compiled_dir> [--serial <device_id>]}"
SERIAL_FLAG=""
RESULTS_DIR="${COMPILED_DIR}/results"
DEVICE_TMP="/data/local/tmp"
DEVICE_RESULTS="$DEVICE_TMP/pd_results"

# Parse optional serial
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --serial) SERIAL_FLAG="-s $2"; shift 2 ;;
        *) shift ;;
    esac
done

# Resolve ADB
if [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
    ADB="$HOME/Library/Android/sdk/platform-tools/adb"
elif command -v adb &>/dev/null; then
    ADB="$(command -v adb)"
else
    echo "ERROR: adb not found"
    exit 1
fi

adb_do() {
    $ADB $SERIAL_FLAG "$@"
}

# Verify device
echo "=== Fast Test Orchestrator ==="
device_check=$(adb_do devices 2>/dev/null | grep -w "device" | grep -v "List" | head -1)
if [ -z "$device_check" ]; then
    echo "ERROR: No device connected"
    exit 1
fi
echo "Device: $(adb_do shell getprop ro.product.model 2>/dev/null | tr -d '\r')"

# Verify manifest
MANIFEST="$COMPILED_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: No manifest.json in $COMPILED_DIR"
    exit 1
fi

# Read manifest
TOTAL_TESTS=$(python3 -c "import json; print(len(json.load(open('$MANIFEST'))['test_cases']))")
echo "Test cases: $TOTAL_TESTS"
echo ""

# Step 1: Push fast-runner to device
RUNNER_SCRIPT="$(dirname "$0")/fast-runner.sh"
if [ ! -f "$RUNNER_SCRIPT" ]; then
    echo "ERROR: fast-runner.sh not found at $RUNNER_SCRIPT"
    exit 1
fi

adb_do push "$RUNNER_SCRIPT" "$DEVICE_TMP/pd_fast_runner.sh" > /dev/null 2>&1
adb_do shell chmod +x "$DEVICE_TMP/pd_fast_runner.sh"
echo "Pushed fast-runner to device"

# Step 2: Create local results dir
mkdir -p "$RESULTS_DIR"

# Step 3: Execute each test case
PASS=0
FAIL=0
BLOCKED=0
TOTAL_TIME_MS=0

# Get test case list from manifest
python3 -c "
import json
m = json.load(open('$MANIFEST'))
for tc in m['test_cases']:
    print(f\"{tc['id']}|{tc['priority']}|{tc['script']}|{tc['fully_compiled']}|{tc['title']}\")
" | while IFS='|' read -r TC_ID PRIORITY SCRIPT COMPILED TITLE; do

    echo "--- [$PRIORITY] $TC_ID: $TITLE ---"

    SCRIPT_PATH="$COMPILED_DIR/$SCRIPT"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "  BLOCKED: Script not found"
        echo "$TC_ID|BLOCKED|Script not found|0" >> "$RESULTS_DIR/summary.txt"
        continue
    fi

    # Check for unresolved steps
    UNRESOLVED=$(grep -c "UNRESOLVED" "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$UNRESOLVED" -gt 0 ]; then
        echo "  WARNING: $UNRESOLVED unresolved steps (will need phone-driver fallback)"
    fi

    # Clean previous results on device
    adb_do shell "rm -rf $DEVICE_RESULTS; mkdir -p $DEVICE_RESULTS" 2>/dev/null

    # Push test script
    adb_do push "$SCRIPT_PATH" "$DEVICE_TMP/pd_current_test.sh" > /dev/null 2>&1

    # Execute!
    START_MS=$(date +%s%3N)
    RESULT=$(adb_do shell "sh $DEVICE_TMP/pd_fast_runner.sh $DEVICE_TMP/pd_current_test.sh" 2>&1)
    END_MS=$(date +%s%3N)
    DURATION=$((END_MS - START_MS))

    echo "  Executed in ${DURATION}ms"

    # Pull results
    TC_RESULTS="$RESULTS_DIR/$TC_ID"
    mkdir -p "$TC_RESULTS"

    # Pull execution log
    adb_do pull "$DEVICE_RESULTS/execution.log" "$TC_RESULTS/execution.log" > /dev/null 2>&1 || true

    # Pull checkpoint screenshots and XML
    CHECKPOINT_FILES=$(adb_do shell "ls $DEVICE_RESULTS/ck_*.png $DEVICE_RESULTS/ck_*.xml 2>/dev/null" 2>/dev/null | tr -d '\r' || true)
    if [ -n "$CHECKPOINT_FILES" ]; then
        for f in $CHECKPOINT_FILES; do
            fname=$(basename "$f")
            adb_do pull "$f" "$TC_RESULTS/$fname" > /dev/null 2>&1 || true
        done
        CHECKPOINT_COUNT=$(echo "$CHECKPOINT_FILES" | grep -c "\.png$" || echo "0")
        echo "  Pulled $CHECKPOINT_COUNT checkpoint(s)"
    fi

    # Check for errors in execution log
    if [ -f "$TC_RESULTS/execution.log" ]; then
        TIMEOUTS=$(grep -c "^TIMEOUT" "$TC_RESULTS/execution.log" 2>/dev/null || echo "0")
        UNKNOWNS=$(grep -c "^UNKNOWN" "$TC_RESULTS/execution.log" 2>/dev/null || echo "0")
        ERRORS=$((TIMEOUTS + UNKNOWNS))

        if [ "$ERRORS" -gt 0 ]; then
            echo "  Issues: $TIMEOUTS timeouts, $UNKNOWNS unknown commands"
            STATUS="NEEDS_VERIFICATION"
        else
            STATUS="EXECUTED"
        fi
    else
        STATUS="NO_LOG"
    fi

    echo "$TC_ID|$STATUS|${DURATION}ms|$UNRESOLVED" >> "$RESULTS_DIR/summary.txt"
    echo "  Status: $STATUS"
    echo ""
done

# Step 4: Generate results summary
echo "=== Execution Complete ==="
echo ""
echo "Results directory: $RESULTS_DIR"
echo ""

if [ -f "$RESULTS_DIR/summary.txt" ]; then
    echo "Summary:"
    echo "  Executed: $(grep -c "EXECUTED" "$RESULTS_DIR/summary.txt" 2>/dev/null || echo 0)"
    echo "  Needs verification: $(grep -c "NEEDS_VERIFICATION" "$RESULTS_DIR/summary.txt" 2>/dev/null || echo 0)"
    echo "  Blocked: $(grep -c "BLOCKED" "$RESULTS_DIR/summary.txt" 2>/dev/null || echo 0)"
fi

echo ""
echo "Next: Claude reads checkpoint screenshots and execution logs to determine PASS/FAIL"
echo "Checkpoint files are in: $RESULTS_DIR/<TC_ID>/ck_*.png"
