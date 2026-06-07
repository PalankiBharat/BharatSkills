# Agent-device reference

Reference for the skill's use of the `agent-device` CLI to drive real devices during runtime-golden capture and parity QA. Loaded by Phase F (F.3 HTTP-parity checks) and Phase I (parity QA).

**Prerequisites:** Node 22+, Xcode (iOS simulator / device), Android SDK + ADB on `PATH`.

---

## Command surface

| Command | Purpose |
|---|---|
| `apps` | List installed apps on the scoped device |
| `open <bundle-id>` | Launch app by bundle/package ID |
| `snapshot -i` | Dump the current UI tree (accessibility snapshot) for programmatic inspection |
| `tap <ref>` | Tap a UI element by accessibility ref |
| `fill <ref> <text>` | Type text into a focused input element |
| `scroll <ref> <direction>` | Scroll a scrollable container |
| `assert <ref> <property> <value>` | Assert an element property (role, text, enabled state); non-zero exit on failure |
| `wait <ref> [timeout]` | Block until an element appears; default timeout 10 s |
| `screenshot [--out <path>]` | Capture the current screen to a file |
| `logs [--pid <pid>] [--since <ts>]` | Stream or dump device logs; scope to app PID when known |
| `network [--out <dir>]` | Capture in-flight HTTP traffic to `*.json` wire files |
| `<crash capture>` | Automatic: any unhandled exception / ANR / crash is appended to the session log |
| `record --out <path.ad>` | Record a user journey to a replayable `.ad` script |
| `replay <path.ad>` | Replay a previously recorded `.ad` script |
| `close` | Terminate the app foreground process |

---

## Subagent-mediation

Driving a device is inherently multi-step — each command produces a snapshot, log excerpt, or diff that the next step depends on. All agent-device work is therefore **dispatched to a subagent**; the main orchestrator context stays a terse dashboard. Verbose UI snapshots, logcat excerpts, and network dumps live in subagents and their output files — never inlined into the main context.

See SKILL.md §"Subagent-mediated execution" for the general pattern and subagent prompt discipline.

---

## `.ad` scripts

`.ad` scripts are **record-once / replay-many** journey programs.

- One `.ad` file per journey (e.g., `holdings-pnl.ad`, `order-placement.ad`).
- Stored in the session golden directory alongside `checkpoint.json` and wire files (see `runtime-golden.md` §Storage layout).
- Reused across all loop iterations within a session — the first iteration records, subsequent iterations replay.
- When the UI structure is unchanged between sessions, `.ad` scripts are reusable in future sessions without re-recording. A replay that fails an `assert` or `wait` step signals UI drift; re-record.

`scripts/ad-capture.sh --device <id> --journey <name> --checkpoint <name> --anchor <ref> --out <path>` wraps `agent-device snapshot -i` and emits the normalized checkpoint JSON next to the captured wires. The `.ad` journey itself is recorded separately via `agent-device record` per the deferred replay-mechanism research.

---

## Normalized checkpoint format

A checkpoint is a frozen snapshot of a journey state: the UI elements present at that anchor point plus the network calls that produced them.

```json
{
  "journey": "holdings-pnl",
  "checkpoint": "after-date-range-change",
  "anchor": "txt_total_pnl",
  "elements": [
    {"ref": "txt_total_pnl", "role": "text", "text": "₹1,200.50", "computed": true, "live": false},
    {"ref": "ticker_nifty", "role": "text", "text": "22,140.05", "computed": false, "live": true}
  ],
  "network": [
    {"method": "GET", "url": "https://…/holdings", "status": 200, "body_sha256": "…", "body_path": "wires/holdings.json"}
  ]
}
```

**`computed`** — the value is derived by migrated logic (P&L, totals, order values, derived prices). This is the headline parity signal; **never mask a `computed` field**.

**`live`** — the value is an externally-fed live feed not derived from migrated logic (raw streaming tick, chart axis). Maskable on the live A/B exception path; irrelevant on replay (inputs are frozen).

`scripts/ad-capture.sh` is the adapter that drives the device and writes this format to disk. `scripts/compare-golden.py` is the comparator that consumes it (exit 0 = PARITY, exit 1 = DIVERGENCE, exit 3 = INDETERMINATE).

---

## Scope every command

With two devices connected simultaneously (Android A / Android B, or Android / iOS), every `agent-device` and `adb` call **must be device-scoped** (e.g., `--device <serial>` / `adb -s <serial>`). An unscoped call is ambiguous when multiple devices are present and will target an arbitrary device, producing silently wrong results or command failures.
