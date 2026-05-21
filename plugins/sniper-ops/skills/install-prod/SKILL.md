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
  install task. After a successful install, auto-launches the app and
  starts a crash-only logcat (`*:E`) in the background scoped to the
  app's PID — quiet during normal use, loud on crashes. Sister skill to
  install-staging (which does the same for the staging flavor).
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
end. The APK is now on the device. This is the trigger for the
post-install steps below — don't report back to the user until those
have run too.

## After install — auto-launch + crash logcat

Once the success line is observed, do all of the following before
reporting back. The goal is: the app is running on the device and a
crash-focused logcat is streaming in the background.

### 1. Resolve the applicationId from Gradle's output

```bash
python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['applicationId'])" \
  app/build/outputs/apk/productionDebug/output-metadata.json
```

Gradle writes the resolved applicationId here on every build — this
survives any `applicationIdSuffix` change in `app/build.gradle.kts`,
which is the failure mode hardcoded package names would have. If the
file is missing (rare; clean-build edge case), skip steps 2–4 and
tell the user auto-launch + logcat couldn't run — they can launch the
app manually from the drawer.

### 2. Clear the logcat buffer

```bash
adb logcat -c
```

So the background stream only contains lines from this run, not the
previous session's noise.

### 3. Launch the app

```bash
adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1
```

`monkey` picks the LAUNCHER activity automatically, so the skill
doesn't need to know the main activity's class name.

### 4. Wait for the process, then tail crashes in background

Poll `adb shell pidof <applicationId>` up to ~5 seconds. Once it
returns a numeric PID, start the tail:

```bash
adb logcat --pid=<PID> -v threadtime '*:E'
```

**Run this Bash call with `run_in_background: true`.** Logcat is
long-lived by definition — without backgrounding, the turn blocks
indefinitely. Backgrounding makes new lines arrive as notifications
the user (and Claude on the next turn) can read.

If `pidof` never returns within ~5s, fall back to
`adb logcat -v threadtime '*:E'` (unscoped, still crash-only) in
background and tell the user that PID-filtering failed.

### 5. Tell the user what's running

One line, explicit about both the filter and how to widen it. Example:

> 📡 Tailing crashes from `<applicationId>` (pid `<PID>`) in
> background — drop `*:E` for the full app stream, `*:W` to include
> warnings, or drop `--pid` if you're chasing a native crash.

### Why crash-only as the default

`*:E` keeps the stream silent during normal use and loud when the app
crashes: `AndroidRuntime` FATAL EXCEPTION, ANRs, and other fatal
errors all log at error level. Native `libc` tombstones are emitted
under the crashing PID (which is dying) and can be missed by the
`--pid` filter — that's the one case where the user should drop the
PID filter.

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
