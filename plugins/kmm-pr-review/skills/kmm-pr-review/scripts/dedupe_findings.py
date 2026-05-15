#!/usr/bin/env python3
"""
dedupe_findings.py — merge multi-specialist findings.

Reads every findings/*.json under <state_dir>, groups by (rule_id, file, line) with overlapping
line ranges merged, and emits <state_dir>/findings.merged.json with one entry per group,
recording which specialists flagged it and the merged suggestion text.

Validates each finding against schemas/finding.schema.json (best-effort; invalid findings are dropped
with a stderr warning).

Usage: dedupe_findings.py <state_dir> <skill_dir>
"""

from __future__ import annotations
import json
import sys
from collections import defaultdict
from pathlib import Path

REQUIRED_FIELDS = {"rule_id", "file", "line", "severity", "why", "suggestion", "source", "attribution", "specialist"}


def validate(f: dict) -> bool:
    if not REQUIRED_FIELDS.issubset(f.keys()):
        return False
    if f["severity"] not in {"P0", "P1", "P2", "P3"}:
        return False
    if f["attribution"] not in {"pr-induced", "pre-existing", "unknown"}:
        return False
    if not isinstance(f["line"], int) or f["line"] < 1:
        return False
    if not f["source"]:
        return False
    return True


def overlaps(f1: dict, f2: dict) -> bool:
    if f1["file"] != f2["file"]:
        return False
    if f1["rule_id"] != f2["rule_id"]:
        return False
    a1, b1 = f1["line"], f1.get("line_end", f1["line"])
    a2, b2 = f2["line"], f2.get("line_end", f2["line"])
    return not (b1 < a2 or b2 < a1)


def confidence_rank(c: str) -> int:
    return {"high": 3, "medium": 2, "low": 1}.get(c, 0)


def merge_group(findings: list[dict]) -> dict:
    # Anchor: highest-confidence finding
    findings_sorted = sorted(findings, key=lambda x: (-confidence_rank(x.get("confidence", "low")), x["line"]))
    anchor = dict(findings_sorted[0])
    specialists = sorted({f["specialist"] for f in findings})
    anchor["specialists"] = specialists
    anchor["specialist_count"] = len(specialists)
    # Merge suggestion text if meaningfully different
    suggestions = {f["suggestion"].strip() for f in findings}
    if len(suggestions) > 1:
        anchor["suggestion"] = "\n\n— or —\n\n".join(sorted(suggestions))
    # Take the worst severity across the group
    worst_sev = min(f["severity"] for f in findings)  # P0 < P1 lexicographically
    anchor["severity"] = worst_sev
    # iOS_blocking is true if any finding in the group says so
    anchor["iOS_blocking"] = any(f.get("iOS_blocking") for f in findings)
    # Attribution: if any finding says "pr-induced", use that; else fall back to first non-unknown; else unknown
    attrs = [f["attribution"] for f in findings]
    if "pr-induced" in attrs:
        anchor["attribution"] = "pr-induced"
    elif "pre-existing" in attrs:
        anchor["attribution"] = "pre-existing"
    else:
        anchor["attribution"] = "unknown"
    # Confidence: highest among the group
    anchor["confidence"] = max((f.get("confidence", "low") for f in findings), key=confidence_rank)
    return anchor


def main():
    if len(sys.argv) != 3:
        print("usage: dedupe_findings.py <state_dir> <skill_dir>", file=sys.stderr)
        sys.exit(2)
    state_dir = Path(sys.argv[1])
    findings_dir = state_dir / "findings"
    if not findings_dir.exists():
        print(json.dumps({"merged": 0, "dropped": 0, "groups": []}))
        return

    all_findings = []
    dropped = 0
    for p in findings_dir.glob("*.json"):
        try:
            data = json.loads(p.read_text())
        except json.JSONDecodeError as exc:
            print(f"warn: {p}: invalid JSON ({exc})", file=sys.stderr)
            continue
        for f in data.get("findings", []):
            if validate(f):
                all_findings.append(f)
            else:
                dropped += 1
                print(f"warn: {p}: dropping malformed finding for rule {f.get('rule_id', '?')}", file=sys.stderr)

    # Group by (rule_id, file) then merge overlapping lines
    by_key: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for f in all_findings:
        by_key[(f["rule_id"], f["file"])].append(f)

    merged: list[dict] = []
    for (rule_id, file), group in by_key.items():
        group_sorted = sorted(group, key=lambda x: x["line"])
        clusters: list[list[dict]] = []
        for f in group_sorted:
            placed = False
            for cluster in clusters:
                if any(overlaps(f, g) for g in cluster):
                    cluster.append(f)
                    placed = True
                    break
            if not placed:
                clusters.append([f])
        for c in clusters:
            merged.append(merge_group(c))

    out = {
        "merged_count": len(merged),
        "dropped_count": dropped,
        "findings": merged,
    }
    (state_dir / "findings.merged.json").write_text(json.dumps(out, indent=2))
    print(json.dumps({
        "merged": len(merged),
        "dropped": dropped,
        "output": str(state_dir / "findings.merged.json"),
    }, indent=2))


if __name__ == "__main__":
    main()
