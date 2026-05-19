---
name: install-prod
description: >
  Fast path for installing the sniper-v2-android ProductionDebug build to a
  connected Android device via `scripts/install-production.sh`. Use whenever
  the user asks to "install prod", "install production", "install on
  device", "build and install", "install the prod debug build", "install
  sniper", "push to my phone", or any variant that means "build the
  production-flavor debug APK and put it on whatever device adb sees right
  now." Local-only — no commits, no push, no CI. Just runs the Gradle
  install task. Sister skill to install-staging (which does the same for the
  staging flavor).
---

# Install Prod Build

## What this does

Runs `bash scripts/install-production.sh` in the sniper-v2-android
working directory. The script:

1. Runs the non-cacheable `:app:objectboxPrepareBuild` task without
   the configuration cache (ObjectBox's annotation processor isn't
   config-cache-safe in this project).
2. Runs `./gradlew installProductionDebug` with the configuration
   cache and `:app:objectboxPrepareBuild` excluded (since step 1
   already ran it).
3. Installs the resulting APK to whatever device adb sees.

Output: a `ProductionDebug` APK installed on the connected device,
ready to launch.

## Pre-flight

This is a local install — no CI, no remote, no commits. The only
thing that can go wrong before the script runs is missing
prerequisites:

### 1. Confirm we're in the right repo

```bash
git rev-parse --show-toplevel
```

If the path doesn't end in `sniper-v2-android`, stop and ask.

### 2. Confirm a device is connected

```bash
adb devices
```

If the list is empty (or shows only `* daemon ...` lines), tell the
user no device is connected and ask them to plug one in / start an
emulator before retrying. Don't run the script with no device — the
Gradle install will fail several minutes in after building the APK,
which wastes time.

If multiple devices are connected, mention which ones adb sees so the
user can pick. The install script doesn't disambiguate — it'll fail
with Gradle's "more than one device" error. The user may want to
`export ANDROID_SERIAL=<id>` first.

### 3. Run the install

```bash
bash scripts/install-production.sh
```

This takes a few minutes the first time, less on incremental builds.
The script uses `set -e` so any failure aborts loudly.

## What success looks like

The script prints `✅ ProductionDebug installed successfully!` at the
end. The APK is now on the device. The user can launch it from the
app drawer.

## When this is the wrong skill

- The user wants to share with the team → use `share-prod`, not this.
  This skill only installs locally.
- The user wants the staging flavor → use `install-staging`.
- The user has the local finance SDK wired in and is iterating on it
  → this skill still works; the local SDK is consumed via Gradle's
  `includeBuild`/`project(':finance')` so the install picks up local
  SDK edits automatically. No special handling needed for the
  install path (unlike the share path, which goes through CI).

## Triggers

"install prod", "install production", "install on device", "install
sniper", "install the prod debug build", "build and install", "push
to my phone", "install productionDebug", "install on emulator"
