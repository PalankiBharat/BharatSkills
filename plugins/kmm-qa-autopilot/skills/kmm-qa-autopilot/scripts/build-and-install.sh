#!/usr/bin/env bash
# build-and-install.sh — build the ProductionDebug APK from ONE worktree and install it
# to ONE locked emulator. Run once per build (master -> A, pr -> B).
#
# Mirrors the repo's working install sequence (see sniper-ops install-prod):
#   1. :app:objectboxPrepareBuild WITHOUT the configuration cache (ObjectBox's annotation
#      processor isn't config-cache-safe in this project).
#   2. installProductionDebug WITH config cache, objectbox + lint excluded.
# Scoped to the target serial via ANDROID_SERIAL so the two builds land on the right devices.
# --build-cache is on so the second build reuses the first where possible.
#
# Why ProductionDebug: real prod backend, debuggable, signed with the release-dev keystore.
# Both master and the PR produce the same package (com.marketpulse.sniper.vte) — that's why
# they need separate emulators.
#
# Usage: build-and-install.sh <worktree-dir> <serial> <label>
# Prints: APP_ID=<resolved applicationId>   (also echoes a testTagsAsResourceId warning if off)

set -euo pipefail

WT="${1:?usage: build-and-install.sh <worktree-dir> <serial> <label>}"
SERIAL="${2:?missing serial}"
LABEL="${3:-build}"
WT="$(cd "$WT" && pwd -P)"

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$ANDROID_HOME/platform-tools/adb"
export ANDROID_SERIAL="$SERIAL"

echo "[$LABEL] building ProductionDebug in $WT -> $SERIAL"
cd "$WT"

# testTagsAsResourceId gate: Maestro id: selectors only resolve when Compose testTags are
# exposed as Android resource-ids. If this is off, parity capture silently degrades to text.
if grep -rqs "testTagsAsResourceId" app/src/main 2>/dev/null; then
  echo "[$LABEL] testTagsAsResourceId present ✔"
else
  echo "[$LABEL] ⚠ testTagsAsResourceId not found under app/src/main — id: selectors may not resolve; parity will fall back to text/structure only."
fi

# Step 1 — ObjectBox prepare, no config cache.
./gradlew :app:objectboxPrepareBuild --no-configuration-cache --build-cache

# Step 2 — install, reusing step 1, skipping lint.
./gradlew installProductionDebug -x :app:objectboxPrepareBuild -x lint --build-cache

# Resolve the applicationId Gradle actually produced (survives any applicationIdSuffix drift).
META="app/build/outputs/apk/productionDebug/output-metadata.json"
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
