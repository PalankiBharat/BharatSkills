---
name: install-staging
description: >
  Fast path for installing the sniper-v2-android StagingDebug build to a
  connected Android device via `scripts/install-staging.sh`. Use whenever
  the user asks to "install staging", "install stage", "install the staging
  build", "install on device for staging", "push staging to my phone",
  "build and install staging", or any variant that means "build the
  staging-flavor debug APK and put it on whatever device adb sees right
  now." Local-only — no commits, no push, no CI. The staging-flavor APK
  points at staging backends, NOT production.
---

# Install Staging Build

## What this does

Runs `bash scripts/install-staging.sh` in the sniper-v2-android
working directory. The script:

1. Runs `:app:objectboxPrepareBuild` without the configuration cache.
2. Runs `./gradlew installStagingDebug` with `-Pbuildkonfig.flavor=staging
   -Penvironment=staging`, config cache on, ObjectBox task excluded.
3. Installs the resulting APK to whatever device adb sees.

Output: a `StagingDebug` APK installed on the connected device. This
build points at staging backends (auth, trading, market data) — it
will NOT show production data, and orders placed in it are not real.

## Pre-flight

Same as install-prod: this is a local-only install. No CI involvement.

### 1. Confirm we're in the right repo

```bash
git rev-parse --show-toplevel
```

If it doesn't end in `sniper-v2-android`, stop and ask.

### 2. Confirm a device is connected

```bash
adb devices
```

Empty list → ask the user to connect a device / start an emulator
before retrying. Multiple devices → mention them so the user can pick
(or `export ANDROID_SERIAL=<id>`).

### 3. Run the install

```bash
bash scripts/install-staging.sh
```

`set -e` aborts on any failure. Typical install time: a few minutes
cold, faster incremental.

## What success looks like

The script prints `✅ StagingDebug installed successfully!` at the
end. The APK is on the device with the staging flavor configured.

## When this is the wrong skill

- The user wants to share staging with the team → `share-staging`,
  not this. CI builds and posts to Slack; this skill only installs
  locally.
- The user wants the prod flavor → `install-prod`.
- The user is confused about which flavor they want: staging is for
  pre-release testing against staging backends, prod is the same code
  path as the released app. If unclear, ask before running.

## Triggers

"install staging", "install stage", "install the staging build",
"push staging to phone", "install on device for staging", "install
stagingDebug", "build and install staging", "staging on emulator"
