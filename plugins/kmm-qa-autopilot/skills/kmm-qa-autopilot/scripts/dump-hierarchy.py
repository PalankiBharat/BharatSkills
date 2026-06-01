#!/usr/bin/env python3
"""dump-hierarchy.py — print a filtered, readable view of a device's Maestro view hierarchy.

Use this for LIVE selector discovery during flow authoring instead of hand-rolled
`python3 -c '...'` one-liners — those repeatedly break on backslashes in f-strings and
quoting under zsh. This is the committed, quoting-safe equivalent.

It does NOT capture a checkpoint (that's capture-checkpoint.sh, which also keeps screenshots
and is what the verdict is built on). This is a read-only inspection aid: "what's on screen
right now, and what can I select?"

Usage:
  dump-hierarchy.py <serial> [--filter text|id|clickable|all] [--grep SUBSTR]
    <serial>        the locked device (cat $RUN_DIR/locks/lock-a etc.)
    --filter all    every node (default)
    --filter id     only nodes with a resource-id (= Compose testTag) — for id: selectors
    --filter text   only nodes with visible text — for text: selectors on untagged screens
    --filter clickable  only clickable nodes — find the tappable target
    --grep SUBSTR   keep only rows whose id+text+class contains SUBSTR (case-insensitive)

Prints one node per line: <rid> | "<text>" | <class> [clickable]. Reads the hierarchy via
`maestro --device <serial> hierarchy` (the same source compare-parity.py consumes).
"""

import argparse
import json
import re
import subprocess
import sys


def _norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip()


def _attr(attrs, *names):
    for n in names:
        if n in attrs and attrs[n] not in (None, ""):
            return attrs[n]
    return ""


def walk(node, out):
    if isinstance(node, list):
        for child in node:
            walk(child, out)
        return
    if not isinstance(node, dict):
        return
    attrs = node.get("attributes", node)  # maestro nests under "attributes"; tolerate flat
    out.append({
        "rid": _norm(_attr(attrs, "resource-id", "resourceId", "resource_id")),
        "text": _norm(_attr(attrs, "text", "accessibilityText", "hintText", "content-desc")),
        "cls": _norm(_attr(attrs, "class", "className")),
        "clickable": str(_attr(attrs, "clickable")).lower() == "true",
    })
    for child in node.get("children", []) or []:
        walk(child, out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("serial")
    ap.add_argument("--filter", choices=["text", "id", "clickable", "all"], default="all")
    ap.add_argument("--grep", default="")
    args = ap.parse_args()

    try:
        raw = subprocess.run(
            ["maestro", "--device", args.serial, "hierarchy"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"maestro hierarchy failed on {args.serial}: {e}", file=sys.stderr)
        sys.exit(1)
    if not raw:
        print("(empty hierarchy)", file=sys.stderr)
        sys.exit(1)

    nodes = []
    walk(json.loads(raw), nodes)

    g = args.grep.lower()
    shown = 0
    for n in nodes:
        if args.filter == "id" and not n["rid"]:
            continue
        if args.filter == "text" and not n["text"]:
            continue
        if args.filter == "clickable" and not n["clickable"]:
            continue
        if g and g not in (n["rid"] + " " + n["text"] + " " + n["cls"]).lower():
            continue
        rid = n["rid"] or "-"
        txt = f'"{n["text"]}"' if n["text"] else "-"
        flag = " [clickable]" if n["clickable"] else ""
        print(f"{rid} | {txt} | {n['cls']}{flag}")
        shown += 1
    print(f"\n{shown}/{len(nodes)} nodes (filter={args.filter}"
          + (f", grep={args.grep!r}" if args.grep else "") + ")", file=sys.stderr)


if __name__ == "__main__":
    main()
