#!/usr/bin/env bash
# build-and-install.sh — build the ProductionRelease APK (default) from ONE worktree and
# install it to ONE locked emulator. Run once per build (master -> A, pr -> B).
#
# Mirrors the repo's working install sequence (see sniper-ops install-prod):
#   1. :app:objectboxPrepareBuild WITHOUT the configuration cache (ObjectBox's annotation
#      processor isn't config-cache-safe in this project).
#   2. install<Variant> WITH config cache, objectbox + lint excluded.
# Scoped to the target serial via ANDROID_SERIAL so the two builds land on the right devices.
# --build-cache is on so the second build reuses the first where possible.
#
# Clean slate: before installing, the known package is UNINSTALLED on the target serial
# (best-effort, ignored if absent). master and the PR build the SAME package
# (com.marketpulse.sniper.vte) and live on separate emulators — a stale prior-run APK left on a
# device makes post-install presence checks ambiguous, so we wipe first. This runs in Phase 0,
# BEFORE the Phase 1 manual login, so no session/OTP is ever burned by it.
#
# Usage: build-and-install.sh <worktree-dir> <serial> <label>
#   PARITY_VARIANT (env) selects the Gradle variant; DEFAULT ProductionRelease — the shipped
#   artifact users actually run (minified + shrunk by R8 + signed). This matters: ProductionDebug
#   is the canary / non-R8 build, so it can HIDE R8-only regressions — most dangerously serialization
#   (a Gson->kotlinx.serialization migration can be green on debug yet broken under R8). Override to
#   ProductionDebug only if you knowingly want a fast non-R8 build. Both builds MUST use the same variant.
# Prints: APP_ID=<resolved applicationId>   (also echoes a testTagsAsResourceId warning if off)

set -euo pipefail

WT="${1:?usage: build-and-install.sh <worktree-dir> <serial> <label>}"
SERIAL="${2:?missing serial}"
LABEL="${3:-build}"
WT="$(cd "$WT" && pwd -P)"
VARIANT="${PARITY_VARIANT:-ProductionRelease}"
# Derive flavor + buildType to LOCATE the APK metadata. AGP places it under either
# apk/<flavor>/<buildType>/ (this project's release) or apk/<flavorBuildType>/ (debug),
# depending on version — so glob for both rather than assuming one layout.
BT="$(printf '%s' "$VARIANT" | grep -oiE 'release$|debug$' | tr 'A-Z' 'a-z')"
FLAVOR="$(printf '%s' "$VARIANT" | sed -E 's/(Release|Debug)$//' | tr 'A-Z' 'a-z')"

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$ANDROID_HOME/platform-tools/adb"
export ANDROID_SERIAL="$SERIAL"

echo "[$LABEL] building $VARIANT in $WT -> $SERIAL"
cd "$WT"

# testTagsAsResourceId gate: Maestro id: selectors only resolve when Compose testTags are
# exposed as Android resource-ids. If this is off, parity capture silently degrades to text.
if grep -rqs "testTagsAsResourceId" app/src/main 2>/dev/null; then
  echo "[$LABEL] testTagsAsResourceId present ✔"
else
  echo "[$LABEL] ⚠ testTagsAsResourceId not found under app/src/main — id: selectors may not resolve; parity will fall back to text/structure only."
fi

# Clean slate — uninstall any prior build of this package on the target device before install.
# Best-effort: a fresh device (nothing installed) returns non-zero, which we ignore. Override the
# package with PARITY_APP_ID if a flavor adds an applicationIdSuffix. Runs in Phase 0, before the
# Phase 1 manual login, so it never wipes a session you logged into.
UNINSTALL_PKG="${PARITY_APP_ID:-com.marketpulse.sniper.vte}"
echo "[$LABEL] uninstalling any prior $UNINSTALL_PKG on $SERIAL (clean slate)..."
"$ADB" -s "$SERIAL" uninstall "$UNINSTALL_PKG" >/dev/null 2>&1 || echo "[$LABEL]   (none installed — ok)"

# Step 1 — ObjectBox prepare, no config cache.
./gradlew :app:objectboxPrepareBuild --no-configuration-cache --build-cache

# Step 2 — install, reusing step 1, skipping lint.
./gradlew "install$VARIANT" -x :app:objectboxPrepareBuild -x lint --build-cache

# Resolve the applicationId Gradle actually produced (survives any applicationIdSuffix drift).
META="$(find app/build/outputs/apk -path "*${FLAVOR}*${BT}*" -name output-metadata.json 2>/dev/null | head -1)"
if [ -f "$META" ]; then
  APP_ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["applicationId"])' "$META")"
else
  APP_ID="com.marketpulse.sniper.vte"
  echo "[$LABEL] ⚠ $META missing — falling back to $APP_ID"
fi

# Confirm it actually installed on the locked device.
if "$ADB" -s "$SERIAL" shell pm list packages | grep -qx "package:$APP_ID"; then
  echo "[$LABEL] ✅ $APP_ID installed on $SERIAL"
else
  echo "[$LABEL] ❌ $APP_ID not found on $SERIAL after install" >&2
  exit 1
fi

echo "APP_ID=$APP_ID"
