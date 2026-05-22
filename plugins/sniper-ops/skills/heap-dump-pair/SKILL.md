---
name: heap-dump-pair
description: >
  Capture a pair of Android heap dumps (.hprof) from a running app — a
  baseline now and a follow-up exactly 5 minutes later — so the user can
  diff them in Android Studio Profiler to spot leaks, growth, or steady-state
  retention. Use this skill whenever the user asks to "take a heap dump",
  "capture heap", "dump the heap", "memory snapshot", "hprof", "leak
  capture", "before/after heap", "5-minute heap dump", or any variant that
  means "give me two .hprof files from this app spaced 5 minutes apart so I
  can compare them." Interviews the user via AskUserQuestion options for
  device, app package, and save location — never asks for free text input
  unless presets don't fit (then uses the built-in "Other" escape hatch).
  Works for any Android app the user has installed; not sniper-specific
  despite living in the sniper-ops plugin.
---

# Heap Dump Pair Capture

## What this does

Captures two `.hprof` snapshots from a running Android app on a connected
adb device:

1. **t+0 (baseline)** — taken immediately.
2. **t+5min** — taken exactly 5 minutes after the baseline.

Both files are pulled to a user-chosen local directory and named so the
pair is obviously a pair (`<app>-vte-t0min-<timestamp>.hprof` /
`<app>-vte-t5min-<timestamp>.hprof`).

The pair lets the user diff retained objects in Android Studio Profiler
(Memory → Compare two heap dumps) to see what grew, what got freed, and
what's stuck.

## Why this skill instead of doing it freehand

`am dumpheap` is straightforward, but every invocation gets the same four
parameters wrong in different ways: which device when multiple are
connected, what the package's real applicationId is, where the .hprof
should land, and remembering to actually wait 5 real minutes between the
two dumps (not 30 seconds, not 8 minutes). This skill bakes those choices
into a short option-driven interview so the user clicks 3 times and walks
away — second dump shows up in the background.

## The flow

### 1. List adb devices

```bash
adb devices
```

If zero devices: tell the user, stop. If one device: skip the device
question, just use it. If multiple: present them as options.

### 2. Pick the device (only when 2+ connected)

Use `AskUserQuestion` with one option per `adb devices` entry. Label each
option with the serial **and** a hint (`emulator-5554`, `Pixel 8 (physical, USB)`,
etc.) so the user knows which is which. Don't ever fall back to free text
input here — the user said "interview with options", not "guess and ask
me to type the serial."

### 3. Pick the app package

The user might say "the sniper app" or "Instagram" or give a fully
qualified package name. Resolve as follows:

a. If the user already typed a package id (`com.foo.bar`), use it
   directly. Confirm it's installed:
   ```bash
   adb -s <device> shell pm list packages | grep -F <pkg>
   ```

b. Otherwise grep `pm list packages` for the hint they gave and present
   the top matches as options. Always include the **running** apps near
   the top — `adb -s <device> shell ps -A | awk '{print $NF}'` plus a
   filter to known third-party packages — because dumping a non-running
   process fails.

c. If the package list returns zero matches for the hint, ask the user to
   give a different hint via AskUserQuestion's "Other" — don't loop.

Once chosen, confirm a PID exists:

```bash
adb -s <device> shell pidof <pkg>
```

No PID → the app isn't running. Ask via AskUserQuestion whether to
launch it (`adb -s <device> shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`)
or pick a different package.

### 4. Pick the save location

Use `AskUserQuestion` with these presets (label them with the resolved
path so the user can see it):

- `~/dev/heap-dumps/<short-app-name>-latest/` (recommended for repeated
  runs against the same app — overwrites prior snapshots, which is
  usually what the user wants)
- `~/dev/heap-dumps/<short-app-name>-<YYYYMMDD-HHMM>/` (timestamped, keeps
  history)
- `$PWD/heap-dumps/` (drop them in the current project)
- `/tmp/heap-dumps-<short-app-name>/` (scratch — auto-cleaned by the OS
  on reboot; good for one-off captures the user doesn't want to keep)

The user can pick "Other" and type a custom absolute path. Treat any
non-absolute reply as relative to `$PWD` and tell the user the resolved
path before continuing.

Create the directory with `mkdir -p` before either dump runs — failing at
`adb pull` time because the dir doesn't exist is a frustrating way to
lose a 30-second baseline.

### 5. Capture baseline (t+0)

```bash
DEVICE=<chosen device serial>
PKG=<chosen package>
DEST=<chosen local dir>
TS1=$(date +%Y%m%d-%H%M%S)
REMOTE1=/data/local/tmp/${PKG##*.}-t0-${TS1}.hprof
LOCAL1="$DEST/${PKG##*.}-t0min-${TS1}.hprof"
PID=$(adb -s "$DEVICE" shell pidof "$PKG" | tr -d '\r\n')
echo "Baseline dump, PID=$PID -> $LOCAL1"
adb -s "$DEVICE" shell am dumpheap "$PKG" "$REMOTE1"
sleep 3
adb -s "$DEVICE" pull "$REMOTE1" "$LOCAL1"
adb -s "$DEVICE" shell rm "$REMOTE1"
```

The `sleep 3` is a small buffer; `am dumpheap` already prints "Waiting
for dump to finish..." and blocks until the heap is written, but on slow
devices the file size sometimes lags by a hair. Don't shorten it — a
zero-byte pull is worse than waiting an extra second.

Tell the user the baseline file path and size **before** scheduling the
follow-up, so they have proof one dump landed even if the second somehow
fails.

### 6. Schedule t+5min in the background

Compute the wall-clock target as `baseline_timestamp + 5 minutes` so the
gap is exactly 5 real minutes regardless of how long the baseline pull
took.

Run the second dump in a backgrounded Bash command (`run_in_background:
true`). The command sleeps until the target, then runs the same dump
sequence with a `-t5min-` filename suffix. Verify the PID hasn't changed
(`adb shell pidof <pkg>`) — if it has, the app restarted and the pair is
not comparable; warn the user clearly in the final report.

While the background job is sleeping, return control to the user — don't
hold the conversation hostage for 5 minutes. The harness notifies you
when the background command finishes; report results then.

### 7. Final report

When the second dump lands, post a single message containing:

- Both file paths, with sizes.
- The 5-minute delta in MB (positive = heap grew).
- A flag if the PID changed between dumps (pair invalid).
- A one-line hint: "Compare in Android Studio Profiler: open the t0 file,
  then File → Open the t5 file, then Memory tab → 'Compare two heap
  dumps' to see per-class deltas."

Don't oversell what the delta means. A +50MB delta during idle could be
caching working as designed, or a leak, or a GC that hasn't fired yet —
the diff in the profiler is what tells you which. State the delta, point
at the comparison tool, stop.

## Things to NOT do

- **Don't dump a non-running PID.** `am dumpheap` on a stopped app
  silently produces an empty file. Verify `pidof` returns something
  before each dump.
- **Don't sleep less than 5 real minutes.** The "5-minute" gap is the
  whole point — it lets short-lived allocations (network buffers, image
  decode scratch, animation state) age out so the diff highlights real
  retention, not transient noise.
- **Don't dump both files into `/tmp` and forget to pull.** `am dumpheap`
  writes to the device, not the host. Always `adb pull` + `adb shell rm`
  to clean up `/data/local/tmp/` so the device doesn't accumulate
  hundreds of MB of stale dumps.
- **Don't ask the user to type the device serial or package id as free
  text** unless presets genuinely don't fit — the user explicitly wants
  an options-driven interview. `AskUserQuestion`'s built-in "Other"
  escape hatch handles the rare custom-path case.
- **Don't claim the pair is meaningful if the PID changed.** A process
  restart between dumps means you're comparing two different program
  instances; the diff is noise. Flag it loudly.

## Example dialogue

> **User:** can you take a heap dump pair of the sniper app
>
> *(skill lists devices, finds 2 connected; asks via AskUserQuestion which one)*
>
> **User:** *(picks Pixel 8)*
>
> *(skill greps `pm list packages` for "sniper", finds com.marketpulse.sniper.vte;
>  asks via AskUserQuestion to confirm vs other matches)*
>
> **User:** *(picks com.marketpulse.sniper.vte)*
>
> *(skill asks via AskUserQuestion for save location with 3 presets)*
>
> **User:** *(picks ~/dev/heap-dumps/sniper-latest/)*
>
> *(skill captures baseline, posts "baseline: 166MB at /Users/.../t0min-...hprof",
>  schedules t+5min in background, returns control)*
>
> *(5 min later, background job completes)*
>
> *(skill posts: "t5: 220MB. delta: +54MB. PID unchanged (30569). Compare in
>  Android Studio Profiler: ...")*

## Why the file naming matters

`<app>-vte-t0min-<ts>.hprof` and `<app>-vte-t5min-<ts>.hprof` is the
convention so:

- A `ls` of the save dir immediately shows which file is which side of
  the pair.
- The shared timestamp prefix (or near-prefix) makes it obvious they're
  a pair, not two unrelated dumps.
- The `vte` segment is the flavor/variant hint — keep it when you can
  resolve the build flavor from the applicationId; drop it if you can't.

If the user picks a save dir that already contains a pair, **don't
silently overwrite** — append a `-2` suffix to the dir
(`...-latest-2/`) and tell the user. The earlier captures are usually
the baseline they want to compare *against*, not throw away.
