#!/usr/bin/env bash
# Pre-flight environment gate for an autopilot phase. Exits 0 if the phase's
# device/iOS prerequisites are met, else non-zero with a reason on stdout that
# the orchestrator escalates to the human.
#
# Phase device/iOS needs (per design spec §5.2):
#   B  -> Android device (B.6b golden capture)
#   D  -> macOS + Xcode (iOS compile)            [no booted device required]
#   E  -> booted iOS simulator (iosSimulatorArm64Test)
#   I  -> Android device (+ optional iOS sim; + one-time manual prod login)
#   C, F, G, H -> nothing
set -euo pipefail
phase="${1:?usage: preflight.sh <PHASE_ID>}"

have_android_device() {
  command -v adb >/dev/null 2>&1 || return 1
  adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit found?0:1}'
}
have_xcode() { command -v xcrun >/dev/null 2>&1; }
have_booted_sim() {
  command -v xcrun >/dev/null 2>&1 || return 1
  xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)"
}

case "$phase" in
  B)
    have_android_device || { echo "Phase B needs a connected Android device/emulator for runtime golden capture (B.6b). Connect one (adb devices shows none)."; exit 1; } ;;
  D)
    have_xcode || { echo "Phase D needs macOS + Xcode for the iOS compile checks (xcrun not found)."; exit 1; } ;;
  E)
    have_booted_sim || { echo "Phase E needs a booted iOS simulator for iosSimulatorArm64Test. Boot one (xcrun simctl) first."; exit 1; } ;;
  I)
    have_android_device || { echo "Phase I needs a connected Android device for the parity A/B loop, plus a one-time manual prod login on it. Connect a device and confirm you can log in."; exit 1; } ;;
  C|F|G|H) : ;;  # no device prerequisites
  *) echo "preflight: unknown phase '$phase'"; exit 2 ;;
esac
exit 0
