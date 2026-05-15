#!/usr/bin/env python3
"""
verify_plan_complete.py — Phase 5 of kmm-pr-review.

Reads plan.json. Exits 0 if every entry has status in {"done", "cache-hit"}.
Exits 1 (loud) if any entry is "pending", "in-progress", or "failed".

Usage: verify_plan_complete.py <state_dir>
"""

from __future__ import annotations
import json
import sys
from pathlib import Path

VALID_DONE = {"done", "cache-hit"}


def main():
    if len(sys.argv) != 2:
        print("usage: verify_plan_complete.py <state_dir>", file=sys.stderr)
        sys.exit(2)
    state_dir = Path(sys.argv[1])
    plan_path = state_dir / "plan.json"
    if not plan_path.exists():
        print(f"ERROR: plan.json not found at {plan_path}", file=sys.stderr)
        sys.exit(1)
    plan = json.loads(plan_path.read_text())
    incomplete = [f for f in plan["files"] if f.get("status") not in VALID_DONE]
    if incomplete:
        print(f"ERROR: {len(incomplete)} file(s) not reviewed:", file=sys.stderr)
        for f in incomplete:
            print(f"  - {f['file']}  status={f.get('status')}  tier={f.get('swarm_tier')}", file=sys.stderr)
        print(
            "\nThis is a contract failure. The skill must not produce a report when any planned file was skipped.",
            file=sys.stderr,
        )
        sys.exit(1)
    print(json.dumps({
        "ok": True,
        "files_total": len(plan["files"]),
        "done": sum(1 for f in plan["files"] if f["status"] == "done"),
        "cache_hit": sum(1 for f in plan["files"] if f["status"] == "cache-hit"),
    }, indent=2))


if __name__ == "__main__":
    main()
