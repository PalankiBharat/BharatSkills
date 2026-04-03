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
      "ports": {
        "appium": 4723,
        "system_port": 8200,
        "mjpeg_port": 9100,
        "fake_server": 8091
      },
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
| `ports.appium` | Appium server port for this slot. Range: 4723–4730. |
| `ports.system_port` | UiAutomator2 systemPort for this slot. Range: 8200–8207. |
| `ports.mjpeg_port` | MJPEG server port for this slot. Range: 9100–9107. |
| `ports.fake_server` | Fake server port for this slot. Range: 8089–8189. |
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

Create the Android AVD and iOS simulator (see Device Creation section below), allocate ports (see Port Allocation section), write the new slot to config:

**File locking (mandatory):** All reads and writes to `kmm-device-slots.json` must be wrapped in a file lock to prevent race conditions when multiple gameplans allocate simultaneously:

```bash
(
  flock -n 200 || { echo "ERROR: Another gameplan is allocating a slot. Retry in a few seconds."; exit 1; }
  # ... read/write CONFIG here ...
) 200>"$CONFIG.lock"
```

Apply this lock pattern to Step 3 (create), Step 6 (update last_used), and Cleanup (remove slot).

```bash
python3 -c "
import json, datetime
data = json.load(open('$CONFIG'))
data['slots'].append({
    'worktree': '$WORKTREE',
    'android': {'avd_name': '$AVD_NAME', 'serial': '$ANDROID_SERIAL'},
    'ios': {'sim_name': '$SIM_NAME', 'udid': '$IOS_UDID'},
    'ports': {
        'appium': $APPIUM_PORT,
        'system_port': $SYSTEM_PORT,
        'mjpeg_port': $MJPEG_PORT,
        'fake_server': $FAKE_PORT
    },
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
export APPIUM_PORT="$APPIUM_PORT"
export SYSTEM_PORT="$SYSTEM_PORT"
export MJPEG_PORT="$MJPEG_PORT"
```

These are required by all subsequent Appium invocations.

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

Do NOT use any framework-managed device startup commands — they are too limited for this use case. Use `avdmanager` and `xcrun simctl` directly.

### Android AVD Creation

```bash
AVD_NAME="kmm-<gameplan-name>"

# Create the AVD
avdmanager create avd \
  -n "$AVD_NAME" \
  -k "system-images;android-34;google_apis;arm64-v8a" \
  --device "pixel_6" \
  --force

# Derive deterministic serial from allocated port
EMU_PORT=$((5554 + SLOT_INDEX * 2))
ANDROID_SERIAL="emulator-$EMU_PORT"

# Boot with explicit port (deterministic serial)
emulator -avd "$AVD_NAME" -port $EMU_PORT -no-window -no-audio -no-boot-anim &

# Wait for this specific device
adb -s "$ANDROID_SERIAL" wait-for-device
```

Notes:
- `--force` overwrites any AVD with the same name, ensuring idempotency.
- `-no-window -no-audio -no-boot-anim` reduces resource use in headless environments.
- Using `-port` flag ensures the serial is deterministic (`emulator-<port>`), preventing the `tail -1` race condition when multiple emulators boot simultaneously.

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
- The simulator is not visible until `open -a Simulator` is run (not required for headless Appium runs).
- `iOS-18-0` must match an installed runtime. Verify with `xcrun simctl list runtimes`.

---

## Stale Slot Cleanup

On every allocation (Step 2/3), check all existing slots for staleness:

```bash
python3 -c "
import json, datetime
data = json.load(open('$CONFIG'))
now = datetime.datetime.utcnow()
stale = []
for s in data['slots']:
    last = datetime.datetime.fromisoformat(s['last_used'].rstrip('Z'))
    if (now - last).total_seconds() > 86400:  # 24 hours
        stale.append(s)
for s in stale:
    print(f'WARNING: Stale slot for {s[\"worktree\"]} (last used {s[\"last_used\"]}). Freeing.')
    data['slots'].remove(s)
json.dump(data, open('$CONFIG', 'w'), indent=2)
"
```

Stale slots are freed automatically. Their devices (AVD/simulator) are also cleaned up:
- `avdmanager delete avd -n <avd_name>` for Android
- `xcrun simctl delete <udid>` for iOS

A slot is considered stale if `last_used` is older than 24 hours. This prevents crashed sessions from permanently consuming slots.

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

Each slot gets four dedicated ports. Ports are assigned sequentially based on slot index (slot 0 gets the base port, slot 1 gets base+1, etc.):

| Port type | Range | Slot 1 | Slot 2 |
|---|---|---|---|
| Appium server | 4723–4730 | 4723 | 4724 |
| UiAutomator2 systemPort | 8200–8207 | 8200 | 8201 |
| MJPEG server | 9100–9107 | 9100 | 9101 |
| Fake server | 8089–8189 | first free | first free |

Allocate all four ports when creating a new slot:

```bash
# Appium, system, and MJPEG ports — sequential by slot count
SLOT_INDEX=$(python3 -c "
import json
data = json.load(open('$CONFIG'))
print(len(data['slots']))
")
APPIUM_PORT=$((4723 + SLOT_INDEX))
SYSTEM_PORT=$((8200 + SLOT_INDEX))
MJPEG_PORT=$((9100 + SLOT_INDEX))

# Fake server port — first available in range
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

All four ports are recorded in the slot config and in the PLAN.md header so hooks can read them without parsing the full JSON.

---

## Concurrent Appium Targeting

Each Appium server runs on its own port, bound to one device. This prevents any cross-worktree conflicts.

```bash
# Worktree 1: Appium server on port 4723, targeting emulator-5554
appium --port 4723 --base-path /wd/hub &
python3 e2e-tests/appium_driver.py --appium-port 4723 --device emulator-5554 --system-port 8200 ...

# Worktree 2: Appium server on port 4724, targeting emulator-5556
appium --port 4724 --base-path /wd/hub &
python3 e2e-tests/appium_driver.py --appium-port 4724 --device emulator-5556 --system-port 8201 ...
```

Each Appium server runs on its own port. No conflicts. Fully parallel.

---

## Appium Server Lifecycle

Start the Appium server for this slot before running tests, and stop it when done:

```bash
# Start Appium server for this slot (background)
appium --port $APPIUM_PORT --base-path /wd/hub \
  --allow-insecure chromedriver_autodownload &
APPIUM_PID=$!

# Verify server is ready
sleep 3
curl -s http://localhost:$APPIUM_PORT/wd/hub/status | grep -q '"ready":true'

# Stop when done
kill $APPIUM_PID
```

---

## Cleanup

When a story or gameplan completes successfully (or is explicitly abandoned), release the slot:

### Kill stale Appium server

```bash
# Kill stale Appium server on this slot's port
lsof -ti:$APPIUM_PORT | xargs kill -9 2>/dev/null
```

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
<!-- PORTS: fake=8091 | appium=4723 | system=8200 | mjpeg=9100 -->
```

### Reading the header in bash

```bash
PLAN="$(git rev-parse --show-toplevel)/PLAN.md"
ANDROID_SERIAL=$(grep "DEVICE:" "$PLAN" | sed 's/.*android=\([^ |]*\).*/\1/')
IOS_UDID=$(grep "DEVICE:" "$PLAN" | sed 's/.*ios=\([^>]*\).*/\1/' | tr -d ' ')
FAKE_PORT=$(grep "PORTS:" "$PLAN" | sed 's/.*fake=\([0-9]*\).*/\1/')
APPIUM_PORT=$(grep "PORTS:" "$PLAN" | sed 's/.*appium=\([0-9]*\).*/\1/')
SYSTEM_PORT=$(grep "PORTS:" "$PLAN" | sed 's/.*system=\([0-9]*\).*/\1/')
MJPEG_PORT=$(grep "PORTS:" "$PLAN" | sed 's/.*mjpeg=\([0-9]*\).*/\1/')
export ANDROID_SERIAL IOS_UDID FAKE_PORT APPIUM_PORT SYSTEM_PORT MJPEG_PORT
```

### Updating the header after slot allocation

Replace or insert the DEVICE and PORTS comment lines at the top of PLAN.md:

```bash
# Remove old device lines if present
sed -i '' '/<!-- DEVICE:/d' "$PLAN"
sed -i '' '/<!-- PORTS:/d' "$PLAN"

# Prepend new lines
HEADER="<!-- DEVICE: android=$ANDROID_SERIAL | ios=$IOS_UDID -->\n<!-- PORTS: fake=$FAKE_PORT | appium=$APPIUM_PORT | system=$SYSTEM_PORT | mjpeg=$MJPEG_PORT -->"
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
