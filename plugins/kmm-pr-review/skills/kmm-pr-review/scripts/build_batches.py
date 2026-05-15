#!/usr/bin/env python3
"""
build_batches.py — Phase 3 prep for kmm-pr-review.

Groups Phase-2 cache-miss files into lane-specific batches so each specialist
agent reviews many files with a shared rule loadout. Used only when the
number of pending files exceeds the threshold (default 30); below that, the
orchestrator skips this script and dispatches per file using the original
single-file prompts.

Reads:
  - <state_dir>/plan.json
  - <repo_root>/<file>             # for token estimation on pending files

Writes:
  - <state_dir>/batches.json       # list of batches grouped by lane/tier/rules
  - <state_dir>/plan.json          # in place — stamps batch_id_<lane> per file

Grouping key (in priority order):
  (lane, swarm_tier, rules_hash, role, surface, package_root)

Per-tier caps (file count AND token budget; whichever triggers first):
  sonnet-1           correctness                   15 files / 100000 tokens
  sonnet-2           correctness, idiom            10 files /  90000 tokens
  sonnet-3-new       correctness, idiom             6 files /  80000 tokens
  sonnet-3-new       master-grounded-necessity      3 files /  70000 tokens
  sonnet-3-migration correctness, idiom             6 files /  80000 tokens
  sonnet-3-migration master-grounded-drift          2 files /  60000 tokens

haiku-1 (pure RELOCATIONs) is NOT batched here — verify_relocations.py
handles those entries deterministically in Phase 3a, before this script runs.

Usage: build_batches.py <state_dir>
"""

from __future__ import annotations
import hashlib
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

# (file_cap, token_cap) per (swarm_tier, lane)
# Note: haiku-1 / RELOCATION is no longer an LLM tier — scripts/verify_relocations.py
# handles those entries deterministically in Phase 3a, before this script runs.
CAPS: dict[tuple[str, str], tuple[int, int]] = {
    ("sonnet-1", "correctness"): (15, 100_000),
    ("sonnet-2", "correctness"): (10, 90_000),
    ("sonnet-2", "idiom"): (10, 90_000),
    ("sonnet-3-new", "correctness"): (6, 80_000),
    ("sonnet-3-new", "idiom"): (6, 80_000),
    ("sonnet-3-new", "master-grounded-necessity"): (3, 70_000),
    ("sonnet-3-migration", "correctness"): (6, 80_000),
    ("sonnet-3-migration", "idiom"): (6, 80_000),
    ("sonnet-3-migration", "master-grounded-drift"): (2, 60_000),
}

# Lanes each tier dispatches. haiku-1 omitted — handled by verify_relocations.py.
TIER_LANES: dict[str, list[str]] = {
    "sonnet-1": ["correctness"],
    "sonnet-2": ["correctness", "idiom"],
    "sonnet-3-new": ["correctness", "idiom", "master-grounded-necessity"],
    "sonnet-3-migration": ["correctness", "idiom", "master-grounded-drift"],
}

# Map lane → plan.json batch_id field
LANE_TO_FIELD = {
    "correctness": "batch_id_correctness",
    "idiom": "batch_id_idiom",
    "master-grounded-necessity": "batch_id_master",
    "master-grounded-drift": "batch_id_master",
}


def package_root(path: str, depth: int = 3) -> str:
    parts = Path(path).parts
    return "/".join(parts[:depth]) if parts else ""


def estimate_tokens(content: str | None) -> int:
    if not content:
        return 0
    return len(content) // 4


def batch_id(lane: str, tier: str, rules_hash: str, index: int) -> str:
    payload = f"{lane}|{tier}|{rules_hash}|{index}".encode()
    return hashlib.sha256(payload).hexdigest()[:12]


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: build_batches.py <state_dir>", file=sys.stderr)
        sys.exit(2)
    state_dir = Path(sys.argv[1])
    plan_path = state_dir / "plan.json"
    plan = json.loads(plan_path.read_text())

    ingest = json.loads((state_dir / "ingest.json").read_text())
    repo_root = Path(ingest["repo_root"])

    pending = [f for f in plan["files"] if f.get("status") == "pending"]

    # Bucket by (lane, swarm_tier, rules_hash, role, surface)
    buckets: dict[tuple[str, str, str, str, str], list[dict]] = defaultdict(list)
    for entry in pending:
        tier = entry["swarm_tier"]
        lanes = TIER_LANES.get(tier, [])
        if not lanes:
            continue
        # Estimate tokens for this file from disk content
        token_est = 0
        content_path = repo_root / entry["file"]
        if content_path.exists() and content_path.is_file():
            try:
                token_est = estimate_tokens(content_path.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                token_est = 0
        for lane in lanes:
            payload = {
                "file": entry["file"],
                "change_type": entry["change_type"],
                "content_hash": entry["content_hash"],
                "estimated_tokens": token_est,
            }
            if entry.get("old_file"):
                payload["old_file"] = entry["old_file"]
            if entry.get("is_migration_file"):
                payload["is_migration_file"] = True
            if entry.get("sibling_baselines"):
                payload["sibling_baselines"] = entry["sibling_baselines"]
            buckets[(lane, tier, entry["rules_hash"], entry["role"], entry["surface"])].append({
                "entry": entry,
                "payload": payload,
            })

    # Greedy fill into batches
    batches: list[dict] = []
    # Stable iteration order
    for key in sorted(buckets.keys()):
        lane, tier, rules_hash, role, surface = key
        cap = CAPS.get((tier, lane))
        if not cap:
            print(f"warn: no cap defined for tier={tier} lane={lane}; defaulting to (1, 0) per-file", file=sys.stderr)
            file_cap, token_cap = 1, 0
        else:
            file_cap, token_cap = cap
        # Sort bucket by (package_root, path) for attention coherence
        items = sorted(buckets[key], key=lambda x: (package_root(x["entry"]["file"]), x["entry"]["file"]))

        current: list[dict] = []
        current_tokens = 0
        index = 0

        def flush():
            nonlocal index, current, current_tokens
            if not current:
                return
            bid = batch_id(lane, tier, rules_hash, index)
            # Determine rules_to_load from the first entry (all share same rules_hash, so same loadout)
            first_entry = current[0]["entry"]
            batch_files = []
            for item in current:
                payload = item["payload"]
                batch_files.append(payload)
                # Stamp batch_id back into the plan entry
                field = LANE_TO_FIELD[lane]
                item["entry"][field] = bid
            batches.append({
                "batch_id": bid,
                "lane": lane,
                "swarm_tier": tier,
                "rules_hash": rules_hash,
                "role": role,
                "surface": surface,
                "package_root": package_root(current[0]["entry"]["file"]),
                "rules_to_load": first_entry["rules_to_load"],
                "files": batch_files,
                "file_count": len(batch_files),
                "estimated_content_tokens": current_tokens,
                "status": "pending",
            })
            index += 1
            current = []
            current_tokens = 0

        for item in items:
            item_tokens = item["payload"]["estimated_tokens"]
            # Check caps before adding
            would_exceed_files = len(current) + 1 > file_cap
            would_exceed_tokens = (token_cap > 0) and (current_tokens + item_tokens > token_cap) and current
            if would_exceed_files or would_exceed_tokens:
                flush()
            current.append(item)
            current_tokens += item_tokens
        flush()

    out = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "plan_file": str(plan_path),
        "batches": batches,
    }
    (state_dir / "batches.json").write_text(json.dumps(out, indent=2))

    # Write plan.json back with batch_id fields stamped in
    plan_path.write_text(json.dumps(plan, indent=2))

    # Summary
    print(json.dumps({
        "batches_file": str(state_dir / "batches.json"),
        "pending_files": len(pending),
        "batches_created": len(batches),
        "by_lane": {
            lane: sum(1 for b in batches if b["lane"] == lane)
            for lane in sorted({b["lane"] for b in batches})
        },
        "by_tier": {
            tier: sum(1 for b in batches if b["swarm_tier"] == tier)
            for tier in sorted({b["swarm_tier"] for b in batches})
        },
    }, indent=2))


if __name__ == "__main__":
    main()
