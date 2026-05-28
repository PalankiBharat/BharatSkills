#!/usr/bin/env bash
# ensure-two-emulators.sh — guarantee TWO visible, physical-keyboard-enabled Android
# emulators and lock the parity run to them (A = master build, B = PR build).
#
# Parity needs two devices because master and the migrated PR build the SAME applicationId
# and cannot coexist on one device. A and B are interchangeable until builds are installed;
# the assignment here just gives the run two stable serials to scope every adb/maestro call.
#
# Policy (by running-emulator count):
#   0 running   -> create both AVDs (hw.keyboard=yes) if missing, boot both VISIBLE, lock A+B
#   1 running   -> lock it as A, boot a second VISIBLE one for B
#   2 running   -> lock both (A = lower serial, B = higher); never opens a third
#   3+ running  -> refuse and ask which two (or set KMM_PARITY_A / KMM_PARITY_B serials)
#
# Override: export KMM_PARITY_A=<serial> KMM_PARITY_B=<serial> to pick explicitly (any count).
#
# NEVER launches headless (-no-window) — the user must watch both runs and do the manual login.
# NEVER kills or touches an emulator it didn't boot.
#
# Writes serials to <run-dir>/locks/lock-a and lock-b. Every adb/maestro call MUST be scoped:
#   adb -s "$(cat <run-dir>/locks/lock-a)" ...
#   maestro --device "$(cat <run-dir>/locks/lock-a)" test <flow>
#
# Usage: ensure-two-emulators.sh <run-dir>

set -euo pipefail

RUN_DIR="${1:?usage: ensure-two-emulators.sh <run-dir>}"
LOCK_DIR="$RUN_DIR/locks"
mkdir -p "$LOCK_DIR"

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
EMULATOR="$ANDROID_HOME/emulator/emulator"
ADB="$ANDROID_HOME/platform-tools/adb"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
SYSTEM_IMAGE="system-images;android-34;google_apis_playstore;arm64-v8a"
DEVICE="pixel_4_xl"
AVD_A="kmm_parity_a"
AVD_B="kmm_parity_b"

running_serials() { "$ADB" devices | awk '/^emulator-[0-9]+\tdevice$/ { print $1 }' | sort; }

enable_hw_keyboard() {
  local cfg="$HOME/.android/avd/${1}.avd/config.ini"
  [ -f "$cfg" ] || return 0
  if grep -q '^hw.keyboard' "$cfg"; then
    sed -i '' 's/^hw.keyboard *=.*/hw.keyboard = yes/' "$cfg"
  else
    printf 'hw.keyboard = yes\n' >> "$cfg"
  fi
}

create_avd_if_missing() {
  "$EMULATOR" -list-avds | grep -qx "$1" || \
    echo "no" | "$AVDMANAGER" create avd -n "$1" -k "$SYSTEM_IMAGE" -d "$DEVICE" --force
  enable_hw_keyboard "$1"
}

serial_for_avd() {
  # Identify by the AVD a serial is running, so a concurrently-booting emulator is never grabbed.
  local s name
  for s in $(running_serials); do
    name="$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
    [ "$name" = "$1" ] && { echo "$s"; return 0; }
  done
}

wait_booted() {
  local s="$1"
  "$ADB" -s "$s" wait-for-device
  while [ "$("$ADB" -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do sleep 2; done
}

boot_visible() {
  # VISIBLE only. -no-snapshot-load for a clean start. Returns the serial once booted.
  local avd="$1"
  "$EMULATOR" -avd "$avd" -no-snapshot-load >/dev/null 2>&1 &
  local s="" i=0
  while [ "$i" -lt 90 ]; do
    s="$(serial_for_avd "$avd")"; [ -n "$s" ] && break
    sleep 2; i=$((i + 1))
  done
  [ -n "$s" ] || { echo "Emulator '$avd' did not appear after 180s" >&2; exit 1; }
  wait_booted "$s"
  echo "$s"
}

write_locks() {
  printf '%s' "$1" > "$LOCK_DIR/lock-a"
  printf '%s' "$2" > "$LOCK_DIR/lock-b"
  echo "Locked: A=$1 (master build)  B=$2 (PR build)"
  echo "  scope:  adb -s \"\$(cat $LOCK_DIR/lock-a)\" ...   /   maestro --device \"\$(cat $LOCK_DIR/lock-a)\" ..."
}

main() {
  # Explicit override wins regardless of count.
  if [ -n "${KMM_PARITY_A:-}" ] && [ -n "${KMM_PARITY_B:-}" ]; then
    write_locks "$KMM_PARITY_A" "$KMM_PARITY_B"; return
  fi

  local serials count
  serials="$(running_serials)"
  count="$(printf '%s\n' "$serials" | grep -c . || true)"

  case "$count" in
    0)
      echo "No emulator running — creating/booting two visible ones ($AVD_A, $AVD_B)..."
      create_avd_if_missing "$AVD_A"
      create_avd_if_missing "$AVD_B"
      local a b
      a="$(boot_visible "$AVD_A")"
      b="$(boot_visible "$AVD_B")"
      write_locks "$a" "$b" ;;
    1)
      echo "One emulator running ($serials) — using it as A, booting a second for B..."
      create_avd_if_missing "$AVD_B"
      local b; b="$(boot_visible "$AVD_B")"
      write_locks "$serials" "$b" ;;
    2)
      echo "Two emulators running — locking both:"; printf '  %s\n' $serials
      write_locks $serials ;;
    *)
      echo "More than two emulators are running:" >&2
      printf '  %s\n' $serials >&2
      echo "Refusing to guess. Leave only the intended two running, or set KMM_PARITY_A / KMM_PARITY_B." >&2
      exit 2 ;;
  esac
}

main "$@"
