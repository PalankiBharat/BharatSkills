#!/usr/bin/env bash
# ensure-emulator.sh — guarantee ONE visible, physical-keyboard-enabled Android
# emulator and lock qa-autopilot to it.
#
# Policy (standalone qa-autopilot):
#   0 running emulators  -> create the AVD (hw.keyboard=yes) if missing, boot VISIBLE, lock to it
#   1 running emulator   -> lock to that one (do NOT open a second)
#   2+ running emulators -> refuse and ask the user which serial to use (never guess)
#
# NEVER launches headless (-no-window) — the user must see the test run.
# NEVER kills or touches another emulator (no `adb emu kill`, no `adb kill-server`).
#
# Writes the locked serial to .maestro/.emulator-lock. Every adb/maestro command
# qa-autopilot runs MUST be scoped to it:
#   adb -s "$(cat .maestro/.emulator-lock)" ...
#   maestro test --device "$(cat .maestro/.emulator-lock)" <flow>
#
# Usage: ensure-emulator.sh [avd-name]   (avd-name used only when booting a new one; default: qa_autopilot)

set -eu

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
EMULATOR="$ANDROID_HOME/emulator/emulator"
ADB="$ANDROID_HOME/platform-tools/adb"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
LOCK_FILE=".maestro/.emulator-lock"
AVD_NAME="${1:-qa_autopilot}"
SYSTEM_IMAGE="system-images;android-34;google_apis_playstore;arm64-v8a"
DEVICE="pixel_4_xl"

running_serials() {
  "$ADB" devices | awk '/^emulator-[0-9]+\tdevice$/ { print $1 }'
}

write_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"
  printf '%s' "$1" > "$LOCK_FILE"
  echo "Locked qa-autopilot to $1  (scope every adb/maestro call with -s \"\$(cat $LOCK_FILE)\")"
}

enable_hw_keyboard() {
  cfg="$HOME/.android/avd/${1}.avd/config.ini"
  [ -f "$cfg" ] || return 0
  if grep -q '^hw.keyboard' "$cfg"; then
    sed -i '' 's/^hw.keyboard *=.*/hw.keyboard = yes/' "$cfg"
  else
    printf 'hw.keyboard = yes\n' >> "$cfg"
  fi
}

create_avd_if_missing() {
  if ! "$EMULATOR" -list-avds | grep -qx "$1"; then
    echo "no" | "$AVDMANAGER" create avd -n "$1" -k "$SYSTEM_IMAGE" -d "$DEVICE" --force
  fi
  enable_hw_keyboard "$1"
}

first_new_serial() {
  before="$1"
  for s in $(running_serials); do
    case " $before " in *" $s "*) ;; *) echo "$s"; return 0 ;; esac
  done
}

boot_visible() {
  before="$(running_serials | tr '\n' ' ')"
  # VISIBLE window only — never -no-window. -no-snapshot-load for a clean start.
  "$EMULATOR" -avd "$1" -no-snapshot-load >/dev/null 2>&1 &
  new=""
  i=0
  while [ "$i" -lt 60 ]; do
    new="$(first_new_serial "$before")"
    [ -n "$new" ] && break
    sleep 2
    i=$((i + 1))
  done
  [ -n "$new" ] || { echo "Emulator '$1' did not appear after 120s" >&2; exit 1; }
  "$ADB" -s "$new" wait-for-device
  while [ "$("$ADB" -s "$new" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
    sleep 2
  done
  echo "$new"
}

main() {
  serials="$(running_serials)"
  count="$(printf '%s\n' "$serials" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    echo "No emulator running — creating/booting a visible one ($AVD_NAME)..."
    create_avd_if_missing "$AVD_NAME"
    write_lock "$(boot_visible "$AVD_NAME")"
  elif [ "$count" -eq 1 ]; then
    echo "Reusing the single running emulator: $serials"
    write_lock "$serials"
  else
    echo "Multiple emulators are running:" >&2
    printf '  %s\n' $serials >&2
    echo "Refusing to guess. Leave only the intended one running, or tell qa-autopilot which serial to lock." >&2
    exit 2
  fi
}

main "$@"
