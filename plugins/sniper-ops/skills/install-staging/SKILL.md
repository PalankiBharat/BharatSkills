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
  points at staging backends, NOT production. After a successful install,
  auto-launches the app and starts a crash-only logcat (`*:E`) in the
  background scoped to the app's PID — quiet during normal use, loud on
  crashes.
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
This is the trigger for the post-install steps below — don't report
back to the user until those have run too.

## After install — auto-launch + crash logcat

Once the success line is observed, do all of the following before
reporting back. The goal is: the staging app is running on the device
and a crash-focused logcat is streaming in the background.

### 1. Resolve the applicationId from Gradle's output

```bash
python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['applicationId'])" \
  app/build/outputs/apk/stagingDebug/output-metadata.json
```

Gradle writes the resolved applicationId here on every build — this
survives `applicationIdSuffix` differences between staging and prod
(staging usually has a `.staging` suffix, sometimes also `.debug`),
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
