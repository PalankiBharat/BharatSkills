# Fast Execution Mode

## The Problem

The phone-driver's `tap_on` function takes ~5.4s per tap:
- 2x `uiautomator dump` (before + after): ~3s total
- `sleep 1.5` hardcoded wait: 1.5s
- File pull/push overhead: ~0.6s
- Auto-memoization: ~0.3s

A 10-step test takes 54 seconds. A human does it in 8 seconds.

## The Solution: Compile, Don't Interpret

Instead of Claude thinking between every action, pre-compile the entire test into a native shell script that runs on-device.

### Architecture

```
Phase 1: COMPILE (Claude, once)           Phase 2: EXECUTE (device, fast)
┌──────────────────────────┐             ┌──────────────────────────┐
│ Test case definition     │             │ On-device shell script   │
│ + phone-driver memory    │──compile──▶ │ tap 540 188              │
│ (element coordinates)    │             │ text hello%sworld        │
│                          │             │ key KEYCODE_ENTER        │
│                          │             │ checkpoint step3         │
└──────────────────────────┘             └──────────────────────────┘
                                                    │
                                         ~50ms per action
                                         (vs ~5.4s current)
                                                    │
Phase 3: VERIFY (Claude, once)           ┌──────────▼───────────────┐
┌──────────────────────────┐             │ Results:                  │
│ Read checkpoint           │◀──pull───  │ - execution.log           │
│ screenshots + XML         │            │ - checkpoint screenshots  │
│ Determine PASS/FAIL       │            │ - checkpoint UI dumps     │
└──────────────────────────┘             └──────────────────────────┘
```

### Speed Comparison

| Scenario | Current (interpreted) | Fast (compiled) | Speedup |
|----------|----------------------|-----------------|---------|
| Single tap | 5.4s | 0.05s + 0.5s idle wait | ~10x |
| 10-step test | 54s + Claude round-trips | 2-3s execution + 1s checkpoints | ~20x |
| 20 test suite | ~20 minutes | ~2 minutes | ~10x |

## How to Use

### Step 1: Generate Test Case JSON

Claude analyzes the diff and generates `test_cases.json`:

```json
{
  "app_name": "MyTradingApp",
  "app_package": "com.example.trading",
  "app_activity": "com.example.trading/.MainActivity",
  "test_cases": [
    {
      "id": "TC-ORD-001",
      "title": "Place market order",
      "priority": "P0",
      "steps": [
        {"action": "launch", "target": "com.example.trading/.MainActivity"},
        {"action": "tap", "target": "Order Entry", "screen": "home"},
        {"action": "tap", "target": "Quantity", "screen": "order_entry"},
        {"action": "type", "text": "100"},
        {"action": "tap", "target": "Market", "screen": "order_entry"},
        {"action": "tap", "target": "Place Order", "screen": "order_entry"},
        {"action": "verify", "expect_text": "Order Placed", "timeout": 5, "checkpoint_id": "order_placed"}
      ],
      "cleanup": "back_to_home"
    }
  ]
}
```

### Step 2: Compile

```bash
python3 scripts/test-compiler.py compile test_cases.json compiled/ \
    --memory ~/.claude/phonedriver/memory.json \
    --device-key "Pixel_7__1080x2400"
```

This reads phone-driver's memory to resolve element names → coordinates.
Output: one `.sh` script per test case + `manifest.json`.

### Step 3: Execute

```bash
bash scripts/fast-test-orchestrator.sh compiled/
```

This pushes `fast-runner.sh` to the device, executes each test script natively, and pulls back results.

### Step 4: Verify

Claude reads the checkpoint screenshots and execution logs:

```bash
# View execution log
cat compiled/results/TC-ORD-001/execution.log

# View checkpoint screenshot (Claude reads the image)
open compiled/results/TC-ORD-001/ck_order_placed.png

# View checkpoint UI dump (for text verification)
cat compiled/results/TC-ORD-001/ck_order_placed.xml | grep "Order Placed"
```

## Handling Unresolved Steps

Not all elements can be resolved from memory. When the compiler encounters an unknown element:

1. It marks the step with `# UNRESOLVED` in the script
2. The manifest shows `unresolved_count > 0`
3. Two strategies:

**Strategy A: Discovery run first (recommended)**
Before compiling, do a single phone-driver discovery pass to learn the screens:
```
/phone-driver "Open MyTradingApp, navigate to each screen (Home, Order Entry, Watchlist, Settings), and snapshot each screen"
```
This populates memory. Then recompile — more steps will resolve.

**Strategy B: Hybrid execution**
For unresolved steps, the orchestrator falls back to phone-driver's `tap-on` (slow path).
The resolved steps still run fast. You get partial speedup.

## The Fast Runner Commands

Commands available inside compiled scripts:

| Command | Time | What it does |
|---------|------|-------------|
| `tap <x> <y>` | ~50ms | Direct input event |
| `text <content>` | ~50ms | Type text (spaces as `%s`) |
| `key <KEYCODE>` | ~50ms | Key press |
| `swipe <x1> <y1> <x2> <y2> <ms>` | ~duration | Swipe gesture |
| `launch <component>` | ~1.5s | Launch app + wait for idle |
| `wait_idle <ms>` | 50-800ms | Wait for animations via `dumpsys` (NOT `uiautomator`) |
| `wait_text <text> <timeout>` | 50ms-Ns | Poll for text using fast `dumpsys` then `uiautomator` fallback |
| `checkpoint <name>` | ~1.5s | Screenshot + UI dump (the ONLY slow operation) |
| `back` | ~50ms | Back button |
| `home` | ~50ms | Home button |
| `clear <package>` | ~500ms | Force stop + clear cache |
| `sleep <ms>` | exact | Forced wait |
| `log <message>` | ~1ms | Log to execution file |

### Key insight: `wait_idle` vs `sleep`

The current phone-driver uses `sleep 1.5` after every tap. That's wasted time when the UI settles in 200ms.

`wait_idle` uses `dumpsys window animator` to check if animations are running (~50ms per check). It returns as soon as the UI is idle, with a configurable max timeout. For most taps, the UI settles in 100-300ms, saving 1.2s per action.

### Key insight: `checkpoint` is the only slow operation

`uiautomator dump` takes 1-2s. In the current approach, it runs twice per tap (10 taps = 20 dumps).

In fast mode, checkpoints only run at verification points (typically 2-3 per test case). 10 taps with 2 checkpoints = 2 dumps instead of 20. That alone is a 10x reduction in dump time.

## Optimization Tips for Test Case Design

1. **Minimize checkpoints**: Only verify at critical moments (after the final action, not after every tap)
2. **Use `wait_text` before `checkpoint`**: Ensures the screen has settled before the expensive dump
3. **Group tests by screen**: Launch once, run all tests for that screen, then move on
4. **Use `clear` between test groups**: Fresh state prevents test pollution
5. **Prefer `back` over re-launching**: Navigating back is ~50ms, launching is ~1.5s
6. **Pre-discover all screens**: One phone-driver pass to populate memory before compilation

## Integration with QA Autopilot

The QA Autopilot skill uses fast execution by default when phone-driver is available:

1. Phase 2 (test generation) outputs `test_cases.json` alongside the human-readable test plan
2. Phase 3 (execution) calls the compiler → orchestrator → verify pipeline
3. For unresolved steps, it falls back to phone-driver's natural language mode
4. Phase 4 (report) combines fast-execution results with any fallback results
