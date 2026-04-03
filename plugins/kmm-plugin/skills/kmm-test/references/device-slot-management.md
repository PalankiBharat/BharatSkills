# Device Slot Management

Protocol for managing dedicated Android emulators and iOS simulators across multiple git worktrees, so 3-4 concurrent KMM migration stories don't conflict with each other.

---

## Overview

Each worktree running a KMM migration story gets its own dedicated device slot: one Android emulator and one iOS simulator. Slots are tracked in a central config file. When a story starts, the agent allocates a slot (reusing an existing one if available, creating new devices otherwise). When the story completes, devices are deleted and the slot is released.

---

## Slot Configuration Format

Central config lives at `~/.claude/kmm-device-slots.json`.

```json
{
  "slots": [
    {
      "worktree": "/path/to/worktree",
      "android": { "avd_name": "kmm-<name>", "serial": "emulator-5554" },
      "ios": { "sim_name": "kmm-<name>", "udid": "A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6" },
      "port": 8091,
      "allocated_at": "2026-04-01T10:00:00Z",
      "last_used": "2026-04-03T14:30:00Z"
    }
  ],
  "android_image": "system-images;android-34;google_apis;arm64-v8a",
  "ios_device_type": "iPhone 16",
  "ios_runtime": "iOS-18-0"
}
```

### Field Definitions

| Field | Description |
|---|---|
| `worktree` | Absolute path to the git worktree. Used as the slot identity key. |
| `android.avd_name` | AVD name, prefixed with `kmm-` and the gameplan name. |
| `android.serial` | ADB serial of the running emulator (e.g. `emulator-5554`). Populated after boot. |
| `ios.sim_name` | Simulator display name in `xcrun simctl list`. |
| `ios.udid` | UUID assigned by `xcrun simctl create`. Populated at creation. |
| `port` | Fake server port allocated to this slot. |
| `allocated_at` | ISO-8601 timestamp when the slot was first created. |
| `last_used` | ISO-8601 timestamp, updated each time the slot is used. |
| `android_image` | System image used for all AVD creation. Global config, not per-slot. |
| `ios_device_type` | Device type used for all simulator creation. Global config. |
| `ios_runtime` | iOS runtime used for all simulator creation. Global config. |

---

## Allocation Protocol

Execute these steps in order at the start of every test session.

### Step 1 — Read or initialize the config

```bash
CONFIG="$HOME/.claude/kmm-device-slots.json"
if [ ! -f "$CONFIG" ]; then
  echo '{"slots":[],"android_image":"system-images;android-34;google_apis;arm64-v8a","ios_device_type":"iPhone 16","ios_runtime":"iOS-18-0"}' > "$CONFIG"
fi
```

### Step 2 — Look for an existing slot matching the current worktree

```bash
WORKTREE=$(git rev-parse --show-toplevel)
SLOT=$(python3 -c "
import json, sys
data = json.load(open('$CONFIG'))
for s in data['slots']:
    if s['worktree'] == '$WORKTREE':
        print(json.dumps(s))
        sys.exit(0)
")
```

- If a matching slot is found: proceed to Step 4 (verify devices booted).
- If no matching slot: proceed to Step 3 (create new slot).

### Step 3 — Create a new slot

Derive the gameplan name from the current branch or PLAN.md header:

```bash
GAMEPLAN_NAME=$(git branch --show-current | sed 's|.*/||' | cut -c1-20)
AVD_NAME="kmm-$GAMEPLAN_NAME"
SIM_NAME="kmm-$GAMEPLAN_NAME"
```

Create the Android AVD and iOS simulator (see Device Creation section below), allocate a port (see Port Allocation section), write the new slot to config:

```bash
python3 -c "
import json, datetime
data = json.load(open('$CONFIG'))
data['slots'].append({
    'worktree': '$WORKTREE',
    'android': {'avd_name': '$AVD_NAME', 'serial': '$ANDROID_SERIAL'},
    'ios': {'sim_name': '$SIM_NAME', 'udid': '$IOS_UDID'},
    'port': $FAKE_PORT,
    'allocated_at': datetime.datetime.utcnow().isoformat() + 'Z',
    'last_used': datetime.datetime.utcnow().isoformat() + 'Z'
})
json.dump(data, open('$CONFIG', 'w'), indent=2)
"
```

### Step 4 — Verify devices are booted

**Android:**

```bash
ANDROID_SERIAL=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
for s in data['slots']:
    if s['worktree'] == '$WORKTREE':
        print(s['android']['serial'])
")
AVD_NAME=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
for s in data['slots']:
    if s['worktree'] == '$WORKTREE':
        print(s['android']['avd_name'])
")

# Check if the emulator is already running
if ! adb -s "$ANDROID_SERIAL" get-state 2>/dev/null | grep -q "device"; then
  emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim &
  adb -s "$ANDROID_SERIAL" wait-for-device
fi
```

**iOS:**

```bash
IOS_UDID=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
for s in data['slots']:
    if s['worktree'] == '$WORKTREE':
        print(s['ios']['udid'])
")

SIM_STATE=$(xcrun simctl list devices | grep "$IOS_UDID" | grep -o "(Booted)\|(Shutdown)")
if [ "$SIM_STATE" != "(Booted)" ]; then
  xcrun simctl boot "$IOS_UDID"
fi
```

### Step 5 — Export environment variables

```bash
export ANDROID_SERIAL="$ANDROID_SERIAL"
export IOS_UDID="$IOS_UDID"
export FAKE_PORT="$FAKE_PORT"
```

These are required by all subsequent Maestro invocations.

### Step 6 — Update `last_used`

```bash
python3 -c "
import json, datetime
data = json.load(open('$CONFIG'))
for s in data['slots']:
    if s['worktree'] == '$WORKTREE':
        s['last_used'] = datetime.datetime.utcnow().isoformat() + 'Z'
json.dump(data, open('$CONFIG', 'w'), indent=2)
"
```

---

## Device Creation

Do NOT use `maestro start-device` — it is too limited for this use case. Use `avdmanager` and `xcrun simctl` directly.

### Android AVD Creation

```bash
AVD_NAME="kmm-<gameplan-name>"

# Create the AVD
avdmanager create avd \
  -n "$AVD_NAME" \
  -k "system-images;android-34;google_apis;arm64-v8a" \
  --device "pixel_6" \
  --force

# Boot the emulator in the background
emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim &

# Wait for it to be ready
adb wait-for-device

# Capture its serial
ANDROID_SERIAL=$(adb devices | grep emulator | tail -1 | awk '{print $1}')
```

Notes:
- `--force` overwrites any AVD with the same name, ensuring idempotency.
- `-no-window -no-audio -no-boot-anim` reduces resource use in headless environments.
- `adb wait-for-device` blocks until the device is ready to accept commands.
- `tail -1` picks the most recently started emulator if multiple are running.

### iOS Simulator Creation

```bash
SIM_NAME="kmm-<gameplan-name>"

# Create the simulator and capture its UDID
IOS_UDID=$(xcrun simctl create "$SIM_NAME" "iPhone 16" "iOS-18-0")

# Boot it
xcrun simctl boot "$IOS_UDID"
```

Notes:
- `xcrun simctl create` prints the UDID to stdout. Capture it immediately.
- The simulator is not visible until `open -a Simulator` is run (not required for headless Maestro runs).
- `iOS-18-0` must match an installed runtime. Verify with `xcrun simctl list runtimes`.

---

## Dynamic Slot Creation

When all existing slots are occupied by other worktrees, create a new slot on the fly following Step 3 above. There is no hard cap on the number of concurrent slots.

**Resource warning:** If 4 or more slots are active simultaneously, log a warning before proceeding:

```
WARNING: 4+ concurrent device slots are active. Resource contention (CPU, RAM, disk I/O)
may slow emulators and cause flaky tests. Consider staggering test runs or closing idle slots.
```

The agent proceeds regardless — it is the user's responsibility to manage system resources.

---

## Port Allocation

Fake server ports are drawn from the range 8089–8189. Find the first available port:

```bash
FAKE_PORT=$(python3 -c "
import socket
for p in range(8089, 8189):
    try:
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('', p))
        s.close()
        print(p)
        break
    except OSError:
        pass
")

if [ -z "$FAKE_PORT" ]; then
  echo "ERROR: No available port in range 8089-8189"
  exit 1
fi
```

Each slot owns one port. The port is recorded in the slot config and in the PLAN.md header so hooks can read it without parsing the full JSON.

---

## Concurrent Maestro Targeting

Each Maestro invocation must target a specific device using `--device`. This prevents Maestro from defaulting to a random connected device.

```bash
# Android — worktree 1
maestro test --device emulator-5554 flows/android/

# Android — worktree 2 (different slot)
maestro test --device emulator-5556 flows/android/

# iOS — any worktree
maestro test --device "$IOS_UDID" --platform ios flows/ios/
```

Multiple `maestro test` processes can run concurrently across different devices without conflict, as long as each invocation targets its own device serial/UDID.

---

## Cleanup

When a story or gameplan completes successfully (or is explicitly abandoned), release the slot:

### Delete devices

```bash
# Delete Android AVD
avdmanager delete avd -n "kmm-<gameplan-name>"

# Delete iOS simulator
xcrun simctl delete "$IOS_UDID"
```

### Remove slot from config

```bash
python3 -c "
import json
data = json.load(open('$HOME/.claude/kmm-device-slots.json'))
data['slots'] = [s for s in data['slots'] if s['worktree'] != '$WORKTREE']
json.dump(data, open('$HOME/.claude/kmm-device-slots.json', 'w'), indent=2)
"
```

Run cleanup only after all test artifacts (screenshots, reports) have been saved. If the worktree itself is being deleted, run cleanup first.

---

## PLAN.md Header Integration

Record the allocated device identifiers in the PLAN.md comment header so all hooks and agents in the worktree can read device config without loading the full JSON:

```
<!-- DEVICE: android=emulator-5558 | ios=A1B2C3D4-E5F6-G7H8-I9J0-K1L2M3N4O5P6 -->
<!-- PORTS: fake=8091 -->
```

### Reading the header in bash

```bash
PLAN="$(git rev-parse --show-toplevel)/PLAN.md"
ANDROID_SERIAL=$(grep "DEVICE:" "$PLAN" | sed 's/.*android=\([^ |]*\).*/\1/')
IOS_UDID=$(grep "DEVICE:" "$PLAN" | sed 's/.*ios=\([^>]*\).*/\1/' | tr -d ' ')
FAKE_PORT=$(grep "PORTS:" "$PLAN" | sed 's/.*fake=\([0-9]*\).*/\1/')
export ANDROID_SERIAL IOS_UDID FAKE_PORT
```

### Updating the header after slot allocation

Replace or insert the DEVICE and PORTS comment lines at the top of PLAN.md:

```bash
# Remove old device lines if present
sed -i '' '/<!-- DEVICE:/d' "$PLAN"
sed -i '' '/<!-- PORTS:/d' "$PLAN"

# Prepend new lines
HEADER="<!-- DEVICE: android=$ANDROID_SERIAL | ios=$IOS_UDID -->\n<!-- PORTS: fake=$FAKE_PORT -->"
printf "%s\n$(cat $PLAN)" "$HEADER" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
```

---

## Quick Reference

| Action | Command |
|---|---|
| List all slots | `python3 -c "import json; [print(s['worktree'], s['android']['serial'], s['ios']['udid']) for s in json.load(open('$HOME/.claude/kmm-device-slots.json'))['slots']]"` |
| List running emulators | `adb devices` |
| List simulators | `xcrun simctl list devices booted` |
| Kill an emulator | `adb -s emulator-5554 emu kill` |
| Shutdown a simulator | `xcrun simctl shutdown <UDID>` |
| Check available runtimes | `xcrun simctl list runtimes` |
| Check available AVD images | `sdkmanager --list \| grep system-images` |
