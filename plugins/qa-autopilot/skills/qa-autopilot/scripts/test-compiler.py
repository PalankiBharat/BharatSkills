#!/usr/bin/env python3
"""
test-compiler.py — Compiles QA test cases into fast-runner scripts.

Takes test case definitions (JSON) + phone-driver memory (element coordinates)
and produces native shell scripts that run on-device without host round-trips.

Usage:
    python3 test-compiler.py compile <test_cases.json> <output_dir> [--memory <memory.json>] [--device-key <key>]
    python3 test-compiler.py resolve <element_name> [--memory <memory.json>] [--device-key <key>]
    python3 test-compiler.py plan <test_cases.json>   # Dry run — show what would be compiled

Test case JSON format:
{
  "app_package": "com.example.app",
  "app_activity": "com.example.app/.MainActivity",
  "test_cases": [
    {
      "id": "TC-ORD-001",
      "title": "Place order happy path",
      "priority": "P0",
      "precondition": "App on home screen",
      "steps": [
        {"action": "launch", "target": "com.example.app/.MainActivity"},
        {"action": "tap", "target": "Order Entry", "screen": "home"},
        {"action": "tap", "target": "Quantity", "screen": "order_entry"},
        {"action": "type", "text": "100"},
        {"action": "tap", "target": "Place Order", "screen": "order_entry"},
        {"action": "verify", "expect_text": "Order Placed", "timeout": 5}
      ],
      "cleanup": "back_to_home"
    }
  ]
}
"""

import json
import os
import sys
import re
from pathlib import Path

MEMORY_PATH = os.path.expanduser("~/.claude/phonedriver/memory.json")


def load_memory(memory_path=None):
    path = memory_path or MEMORY_PATH
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def resolve_element(memory, app_name, screen_name, element_text, device_key):
    """
    Look up element coordinates from phone-driver memory.
    Returns (x, y) tuple or None if not found.
    """
    apps = memory.get("apps", {})

    # Try exact app match first, then fuzzy
    app = None
    for name, data in apps.items():
        if name.lower() == app_name.lower():
            app = data
            break
        aliases = [a.lower() for a in data.get("aliases", [])]
        if app_name.lower() in aliases:
            app = data
            break

    if not app:
        return None

    screens = app.get("screens", {})
    screen = screens.get(screen_name, {})
    elements = screen.get("elements", {})

    # Normalize element text for lookup
    el_key = re.sub(r'[^a-zA-Z0-9_]', '_', element_text.lower().strip())[:40]

    for key, el_data in elements.items():
        if key == el_key or el_data.get("text", "").lower() == element_text.lower() \
                or el_data.get("content_desc", "").lower() == element_text.lower():
            bounds = el_data.get("bounds_by_device", {}).get(device_key)
            if bounds and len(bounds) == 4:
                cx = (bounds[0] + bounds[2]) // 2
                cy = (bounds[1] + bounds[3]) // 2
                return (cx, cy)

    # Try across all screens if specific screen not found
    if not screen.get("elements"):
        for scr_name, scr_data in screens.items():
            for key, el_data in scr_data.get("elements", {}).items():
                if key == el_key or el_data.get("text", "").lower() == element_text.lower():
                    bounds = el_data.get("bounds_by_device", {}).get(device_key)
                    if bounds and len(bounds) == 4:
                        cx = (bounds[0] + bounds[2]) // 2
                        cy = (bounds[1] + bounds[3]) // 2
                        return (cx, cy)

    return None


def compile_step(step, memory, app_name, device_key, step_idx):
    """Compile a single test step into fast-runner commands."""
    lines = []
    action = step.get("action", "")

    if action == "launch":
        target = step.get("target", "")
        # Check memory for launch intent
        if "/" in target:
            lines.append(f"launch {target}")
        else:
            apps = memory.get("apps", {})
            for name, data in apps.items():
                if name.lower() == target.lower() or target.lower() in [a.lower() for a in data.get("aliases", [])]:
                    activity = data.get("activity", "")
                    if activity:
                        lines.append(f"launch {activity}")
                        break
            else:
                lines.append(f"# UNRESOLVED: launch '{target}' — needs discovery")
                lines.append(f"log UNRESOLVED_LAUNCH_{step_idx}_{target}")
        lines.append("wait_idle 1500")

    elif action == "tap":
        target = step.get("target", "")
        screen = step.get("screen", "")
        coords = resolve_element(memory, app_name, screen, target, device_key)

        if coords:
            lines.append(f"tap {coords[0]} {coords[1]}")
            # Smart wait: short pause for UI to react, not a full 1.5s
            lines.append("wait_idle 500")
        else:
            # Fallback: can't resolve statically. Mark for runtime resolution.
            lines.append(f"# UNRESOLVED: tap '{target}' on screen '{screen}' — coordinate unknown")
            lines.append(f"log UNRESOLVED_TAP_{step_idx}_{target}")
            # The orchestrator will use phone-driver's tap-on for these

    elif action == "type":
        text = step.get("text", "")
        # Escape spaces for ADB input
        escaped = text.replace(" ", "%s")
        lines.append(f"text {escaped}")

    elif action == "key":
        keycode = step.get("keycode", step.get("key", ""))
        lines.append(f"key {keycode}")

    elif action == "back":
        lines.append("back")
        lines.append("wait_idle 500")

    elif action == "home":
        lines.append("home")

    elif action == "swipe":
        x1 = step.get("x1", 0)
        y1 = step.get("y1", 0)
        x2 = step.get("x2", 0)
        y2 = step.get("y2", 0)
        dur = step.get("duration", 300)
        lines.append(f"swipe {x1} {y1} {x2} {y2} {dur}")

    elif action == "scroll_down":
        # Generic scroll using screen center
        lines.append("swipe 540 1500 540 500 300")

    elif action == "scroll_up":
        lines.append("swipe 540 500 540 1500 300")

    elif action == "verify" or action == "checkpoint":
        checkpoint_id = step.get("checkpoint_id", f"step_{step_idx}")
        expect_text = step.get("expect_text", "")
        timeout = step.get("timeout", 5)

        if expect_text:
            lines.append(f"wait_text {expect_text} {timeout}")
        lines.append(f"checkpoint {checkpoint_id}")

    elif action == "wait":
        ms = step.get("ms", step.get("duration", 1000))
        lines.append(f"sleep {ms}")

    elif action == "clear":
        package = step.get("package", "")
        lines.append(f"clear {package}")
        lines.append("wait_idle 1000")

    elif action == "log":
        msg = step.get("message", "")
        lines.append(f"log {msg}")

    else:
        lines.append(f"# UNKNOWN action: {action}")
        lines.append(f"log UNKNOWN_{step_idx}_{action}")

    return lines


def compile_test_case(tc, memory, app_name, device_key):
    """Compile a full test case into a fast-runner script."""
    lines = []
    tc_id = tc.get("id", "unknown")

    lines.append(f"# Test case: {tc_id} — {tc.get('title', '')}")
    lines.append(f"# Priority: {tc.get('priority', 'P2')}")
    lines.append(f"log TC_START_{tc_id}")

    # Add start checkpoint
    lines.append(f"checkpoint {tc_id}_start")

    unresolved = []
    for idx, step in enumerate(tc.get("steps", [])):
        step_lines = compile_step(step, memory, app_name, device_key, idx)
        for line in step_lines:
            if "UNRESOLVED" in line:
                unresolved.append((idx, step))
            lines.append(line)

    # End checkpoint
    lines.append(f"checkpoint {tc_id}_end")
    lines.append(f"log TC_END_{tc_id}")

    # Cleanup
    cleanup = tc.get("cleanup", "")
    if cleanup == "back_to_home":
        lines.append("home")
        lines.append("wait_idle 500")
    elif cleanup == "force_stop":
        pkg = tc.get("app_package", "")
        if pkg:
            lines.append(f"clear {pkg}")

    return lines, unresolved


def compile_all(test_cases_path, output_dir, memory_path=None, device_key=None):
    """Compile all test cases from JSON into fast-runner scripts."""
    with open(test_cases_path) as f:
        data = json.load(f)

    memory = load_memory(memory_path)
    app_name = data.get("app_name", "")
    app_package = data.get("app_package", "")
    app_activity = data.get("app_activity", "")
    dev_key = device_key or ""

    os.makedirs(output_dir, exist_ok=True)

    manifest = {
        "app_package": app_package,
        "app_activity": app_activity,
        "device_key": dev_key,
        "test_cases": [],
        "total_unresolved": 0,
    }

    all_unresolved = []

    for tc in data.get("test_cases", []):
        tc_id = tc.get("id", "unknown")
        lines, unresolved = compile_test_case(tc, memory, app_name, dev_key)

        # Write the script
        script_path = os.path.join(output_dir, f"{tc_id}.sh")
        with open(script_path, "w") as f:
            f.write("\n".join(lines) + "\n")

        manifest["test_cases"].append({
            "id": tc_id,
            "title": tc.get("title", ""),
            "priority": tc.get("priority", "P2"),
            "script": f"{tc_id}.sh",
            "unresolved_count": len(unresolved),
            "fully_compiled": len(unresolved) == 0,
        })

        all_unresolved.extend([(tc_id, u) for u in unresolved])
        manifest["total_unresolved"] += len(unresolved)

    # Write manifest
    manifest_path = os.path.join(output_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    # Summary
    total = len(manifest["test_cases"])
    fully_compiled = sum(1 for tc in manifest["test_cases"] if tc["fully_compiled"])
    partial = total - fully_compiled

    print(f"COMPILED: {total} test cases → {output_dir}")
    print(f"  Fully compiled (fast path): {fully_compiled}")
    print(f"  Partially compiled (need runtime resolution): {partial}")
    print(f"  Total unresolved steps: {manifest['total_unresolved']}")

    if all_unresolved:
        print("\nUnresolved steps (will fall back to phone-driver tap-on):")
        for tc_id, (step_idx, step) in all_unresolved:
            print(f"  {tc_id} step {step_idx}: {step.get('action')} '{step.get('target', '')}'")

    return manifest


def resolve_cmd(element_name, memory_path=None, device_key=None):
    """Resolve a single element to coordinates."""
    memory = load_memory(memory_path)
    # Search across all apps and screens
    for app_name, app_data in memory.get("apps", {}).items():
        for screen_name, screen_data in app_data.get("screens", {}).items():
            coords = resolve_element(memory, app_name, screen_name, element_name, device_key or "")
            if coords:
                print(f"RESOLVED: '{element_name}' → ({coords[0]}, {coords[1]}) in {app_name}/{screen_name}")
                return
    print(f"NOT_FOUND: '{element_name}' not in memory")


def plan_cmd(test_cases_path):
    """Dry run — show what would be compiled without writing files."""
    with open(test_cases_path) as f:
        data = json.load(f)

    print(f"Test plan for: {data.get('app_name', 'unknown')}")
    print(f"Total test cases: {len(data.get('test_cases', []))}")
    print()

    for tc in data.get("test_cases", []):
        print(f"  [{tc.get('priority', '??')}] {tc.get('id', '?')}: {tc.get('title', '')}")
        for idx, step in enumerate(tc.get("steps", [])):
            action = step.get("action", "?")
            target = step.get("target", step.get("text", step.get("expect_text", "")))
            print(f"    {idx+1}. {action} → {target}")
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 test-compiler.py compile <test_cases.json> <output_dir> [--memory <path>] [--device-key <key>]")
        print("  python3 test-compiler.py resolve <element_name> [--memory <path>] [--device-key <key>]")
        print("  python3 test-compiler.py plan <test_cases.json>")
        sys.exit(1)

    cmd = sys.argv[1]
    memory_path = None
    device_key = None

    # Parse optional flags
    args = sys.argv[2:]
    positional = []
    i = 0
    while i < len(args):
        if args[i] == "--memory" and i + 1 < len(args):
            memory_path = args[i + 1]
            i += 2
        elif args[i] == "--device-key" and i + 1 < len(args):
            device_key = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1

    if cmd == "compile":
        if len(positional) < 2:
            print("Usage: compile <test_cases.json> <output_dir>")
            sys.exit(1)
        compile_all(positional[0], positional[1], memory_path, device_key)

    elif cmd == "resolve":
        if len(positional) < 1:
            print("Usage: resolve <element_name>")
            sys.exit(1)
        resolve_cmd(positional[0], memory_path, device_key)

    elif cmd == "plan":
        if len(positional) < 1:
            print("Usage: plan <test_cases.json>")
            sys.exit(1)
        plan_cmd(positional[0])

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
