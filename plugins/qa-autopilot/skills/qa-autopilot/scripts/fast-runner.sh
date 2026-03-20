#!/system/bin/sh
# fast-runner.sh — Pushed to device, runs natively at ADB speed
# No host round-trips per command. Only checkpoints pull data back.
# Usage: pushed via adb, then: adb shell sh /data/local/tmp/pd_fast.sh <script_file>
#
# Script format (one command per line):
#   tap <x> <y>
#   text <content>          (spaces as %s)
#   key <KEYCODE>
#   swipe <x1> <y1> <x2> <y2> <ms>
#   launch <component>
#   wait_idle <ms>          (wait for window transitions to settle)
#   wait_text <text> <timeout_s>  (poll until text appears)
#   checkpoint <name>       (UI dump + screenshot for verification)
#   sleep <ms>
#   back
#   home
#   clear <package>         (force-stop + clear cache)
#   log <message>

SCRIPT_FILE="$1"
RESULT_DIR="/data/local/tmp/pd_results"
LOG_FILE="$RESULT_DIR/execution.log"

mkdir -p "$RESULT_DIR"
echo "FAST_RUNNER_START $(date +%s%3N)" > "$LOG_FILE"

# Fast idle check using dumpsys window (50ms vs 2s for uiautomator)
wait_idle() {
    local max_ms="${1:-800}"
    local waited=0
    local step=50
    # Wait for animations to complete by checking window transition state
    while [ "$waited" -lt "$max_ms" ]; do
        local animating=$(dumpsys window animator 2>/dev/null | grep -c "animating=true" || echo "0")
        if [ "$animating" = "0" ]; then
            break
        fi
        sleep 0.05
        waited=$((waited + step))
    done
}

# Lightweight text check using dumpsys activity (much faster than uiautomator dump)
has_text() {
    local target="$1"
    # Quick check via accessibility or dumpsys
    dumpsys activity top 2>/dev/null | grep -qi "$target" 2>/dev/null
    return $?
}

checkpoint() {
    local name="$1"
    local ts=$(date +%s%3N)
    echo "CHECKPOINT $name $ts" >> "$LOG_FILE"
    # Take screenshot
    screencap -p "$RESULT_DIR/ck_${name}.png" 2>/dev/null
    # UI dump for verification
    uiautomator dump "$RESULT_DIR/ck_${name}.xml" 2>/dev/null
    echo "CHECKPOINT_DONE $name $(date +%s%3N)" >> "$LOG_FILE"
}

# Read and execute each line
line_num=0
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    case "$line" in
        ""|\#*) continue ;;
    esac

    line_num=$((line_num + 1))
    cmd=$(echo "$line" | awk '{print $1}')
    ts_start=$(date +%s%3N)

    case "$cmd" in
        tap)
            x=$(echo "$line" | awk '{print $2}')
            y=$(echo "$line" | awk '{print $3}')
            input tap "$x" "$y"
            echo "OK tap $x $y $ts_start" >> "$LOG_FILE"
            ;;
        text)
            content=$(echo "$line" | cut -d' ' -f2-)
            input text "$content"
            echo "OK text $ts_start" >> "$LOG_FILE"
            ;;
        key)
            keycode=$(echo "$line" | awk '{print $2}')
            input keyevent "$keycode"
            echo "OK key $keycode $ts_start" >> "$LOG_FILE"
            ;;
        swipe)
            x1=$(echo "$line" | awk '{print $2}')
            y1=$(echo "$line" | awk '{print $3}')
            x2=$(echo "$line" | awk '{print $4}')
            y2=$(echo "$line" | awk '{print $5}')
            dur=$(echo "$line" | awk '{print $6}')
            input swipe "$x1" "$y1" "$x2" "$y2" "${dur:-300}"
            echo "OK swipe $ts_start" >> "$LOG_FILE"
            ;;
        launch)
            component=$(echo "$line" | cut -d' ' -f2-)
            am start -n "$component" 2>/dev/null
            wait_idle 1500
            echo "OK launch $component $ts_start" >> "$LOG_FILE"
            ;;
        intent)
            action=$(echo "$line" | cut -d' ' -f2-)
            am start -a "$action" 2>/dev/null
            wait_idle 1500
            echo "OK intent $action $ts_start" >> "$LOG_FILE"
            ;;
        wait_idle)
            ms=$(echo "$line" | awk '{print $2}')
            wait_idle "${ms:-800}"
            echo "OK wait_idle $ts_start" >> "$LOG_FILE"
            ;;
        wait_text)
            target=$(echo "$line" | awk '{print $2}')
            timeout_s=$(echo "$line" | awk '{print $3}')
            timeout_s="${timeout_s:-10}"
            elapsed=0
            found=0
            while [ "$elapsed" -lt "$timeout_s" ]; do
                # Fast path: check via dumpsys first (50ms)
                if has_text "$target"; then
                    found=1
                    break
                fi
                # Slow path fallback: quick XML grep on device (no pull)
                uiautomator dump /data/local/tmp/pd_waitcheck.xml 2>/dev/null
                if grep -q "$target" /data/local/tmp/pd_waitcheck.xml 2>/dev/null; then
                    found=1
                    rm -f /data/local/tmp/pd_waitcheck.xml
                    break
                fi
                rm -f /data/local/tmp/pd_waitcheck.xml
                sleep 1
                elapsed=$((elapsed + 1))
            done
            if [ "$found" = "1" ]; then
                echo "OK wait_text '$target' found@${elapsed}s $ts_start" >> "$LOG_FILE"
            else
                echo "TIMEOUT wait_text '$target' after ${timeout_s}s $ts_start" >> "$LOG_FILE"
            fi
            ;;
        checkpoint)
            name=$(echo "$line" | awk '{print $2}')
            checkpoint "$name"
            ;;
        sleep)
            ms=$(echo "$line" | awk '{print $2}')
            # Convert ms to seconds for shell sleep
            if [ "$ms" -ge 1000 ] 2>/dev/null; then
                secs=$((ms / 1000))
                sleep "$secs"
            else
                # For sub-second, use fractional
                sleep "0.${ms}"
            fi
            echo "OK sleep ${ms}ms $ts_start" >> "$LOG_FILE"
            ;;
        back)
            input keyevent KEYCODE_BACK
            echo "OK back $ts_start" >> "$LOG_FILE"
            ;;
        home)
            input keyevent KEYCODE_HOME
            echo "OK home $ts_start" >> "$LOG_FILE"
            ;;
        clear)
            package=$(echo "$line" | awk '{print $2}')
            am force-stop "$package" 2>/dev/null
            pm clear --cache-only "$package" 2>/dev/null
            echo "OK clear $package $ts_start" >> "$LOG_FILE"
            ;;
        log)
            msg=$(echo "$line" | cut -d' ' -f2-)
            echo "LOG $msg $ts_start" >> "$LOG_FILE"
            ;;
        *)
            echo "UNKNOWN $cmd $ts_start" >> "$LOG_FILE"
            ;;
    esac
done < "$SCRIPT_FILE"

echo "FAST_RUNNER_END $(date +%s%3N)" >> "$LOG_FILE"
echo "DONE"
