#!/usr/bin/env python3
"""Compare a candidate (migrated) checkpoint against the frozen golden checkpoint.

Trading-app rule: a `computed` element (value the migrated logic produces) must
match EXACTLY and is NEVER masked. A `live` element (externally-fed feed not
derived from migrated logic) is ignored. The checkpoint `anchor` must be present
on BOTH sides or the comparison is vacuous.

Verdicts / exit codes:
  PARITY        0   all computed elements match, anchor present both sides
  DIVERGENCE    1   a computed element differs
  INDETERMINATE 3   anchor absent on golden or candidate (vacuous comparison)
"""
import json, sys

def load(p): return json.load(open(p, encoding="utf-8"))
def by_ref(cp): return {e["ref"]: e for e in cp.get("elements", [])}

def main(argv):
    if len(argv) != 3:
        print("usage: compare-golden.py <golden.json> <candidate.json>"); return 64
    g, c = load(argv[1]), load(argv[2])
    anchor = g.get("anchor")
    gmap, cmap = by_ref(g), by_ref(c)
    if anchor not in gmap or anchor not in cmap:
        side = "golden" if anchor not in gmap else "candidate"
        print(f"⚪ INDETERMINATE — anchor '{anchor}' absent on {side}; comparison vacuous")
        return 3
    diffs = []
    for ref, ge in gmap.items():
        if not ge.get("computed") or ge.get("live"):
            continue  # never compare a live/non-computed field
        ce = cmap.get(ref)
        if ce is None:
            diffs.append(f"{ref}: missing on candidate (golden '{ge['text']}')")
        elif ce.get("text") != ge.get("text"):
            diffs.append(f"{ref}: golden '{ge['text']}' ⇄ candidate '{ce['text']}'")
    if diffs:
        print("🔴 DIVERGENCE — " + "; ".join(diffs))
        return 1
    print("🟢 PARITY — all computed values match (anchor reached on both)")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
