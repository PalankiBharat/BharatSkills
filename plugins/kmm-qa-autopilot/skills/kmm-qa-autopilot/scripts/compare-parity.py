#!/usr/bin/env python3
"""compare-parity.py — the hybrid parity oracle for one checkpoint.

Inputs are FOUR view-hierarchy captures: two per device, taken ~2s apart.
  A = master build, B = PR build.  a0/a1 = master samples, b0/b1 = PR samples.

Why two samples per device: this is a LIVE prod feed — prices, charts, clocks and P&L
change on their own every tick and will never match across two devices at the same instant.
A field that changes between a device's own two samples is VOLATILE and is masked before we
compare A vs B. That leaves the stable structure + computed values — which is exactly what a
business-logic (KMM) migration should preserve byte-for-byte, since it doesn't touch the UI.

Signal hierarchy:
  resource-id (= Compose testTag) presence + text  -> primary, hard signal
  untagged class structure                          -> soft hint only (noisier)

Verdicts (per checkpoint):
  EVICTION   ⚠  one device sits on an auth/login screen and the other doesn't (session got
                bumped — NOT a parity bug; re-login and re-run).  Takes precedence.
  DIVERGENCE 🔴 a non-volatile tagged element is missing/extra, or a stable value differs.
  DRIFT      🟡 only soft/structure hints or volatile-presence differences (timing/live data).
  PARITY     🟢 stable structure + values match once live fields are masked.

Usage:
  compare-parity.py --a0 a.s0.hierarchy.json --a1 a.s1.hierarchy.json \
                    --b0 b.s0.hierarchy.json --b1 b.s1.hierarchy.json \
                    [--checkpoint NAME] [--seed-mask price ltp pnl ...] [--out verdict.json]

Accepts Maestro hierarchy JSON or uiautomator XML (by file content/extension).
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET

# Seed patterns for known-volatile fields — belt-and-suspenders on top of auto-detection,
# in case the market is closed (static) and a field that is normally live didn't tick.
DEFAULT_SEED_MASK = [
    "price", "ltp", "pnl", "p_n_l", "pl_", "percent", "change", "ticker",
    "clock", "time", "timestamp", "chart", "canvas", "candle", "spark", "ohlc",
    "marquee", "live", "quote", "last_traded",
]

# A device showing any of these is on an auth/login surface — used for eviction detection.
AUTH_MARKERS = [
    "screen_otp", "otp_screen", "otp_text_field", "otp_continue_button", "resend_otp",
    "screen_pin", "screen_mobile_verification", "moble_number_screen", "phone_number",
    "phone_number_continue", "screen_intro", "login_trial_button", "trial_screen",
    "enter pin", "use otp", "verify otp", "enter otp", "login",
]


def _norm(s):
    return re.sub(r"\s+", " ", (s or "")).strip()


def _attr(attrs, *names):
    for n in names:
        if n in attrs and attrs[n] not in (None, ""):
            return attrs[n]
    return ""


def _walk_json(node, depth, out):
    if isinstance(node, list):
        for child in node:
            _walk_json(child, depth, out)
        return
    if not isinstance(node, dict):
        return
    attrs = node.get("attributes", node)  # maestro nests under "attributes"; tolerate flat
    rid = _norm(_attr(attrs, "resource-id", "resourceId", "resource_id"))
    text = _norm(_attr(attrs, "text", "accessibilityText", "hintText", "content-desc"))
    cls = _norm(_attr(attrs, "class", "className"))
    out.append({"rid": rid, "text": text, "cls": cls, "depth": depth})
    for child in node.get("children", []) or []:
        _walk_json(child, depth + 1, out)


def _walk_xml(elem, depth, out):
    a = elem.attrib
    rid = _norm(a.get("resource-id", ""))
    text = _norm(a.get("text", "") or a.get("content-desc", ""))
    cls = _norm(a.get("class", ""))
    if elem.tag == "node":
        out.append({"rid": rid, "text": text, "cls": cls, "depth": depth})
    for child in list(elem):
        _walk_xml(child, depth + 1, out)


def load_nodes(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read().strip()
    if not raw:
        return []
    out = []
    if raw[0] in "{[":
        _walk_json(json.loads(raw), 0, out)
    else:
        _walk_xml(ET.fromstring(raw), 0, out)
    return out


def rid_index(nodes):
    """{resource-id: sorted tuple of texts} — aggregates duplicates deterministically."""
    idx = {}
    for n in nodes:
        if n["rid"]:
            idx.setdefault(n["rid"], []).append(n["text"])
    return {k: tuple(sorted(v)) for k, v in idx.items()}


def class_multiset(nodes):
    from collections import Counter
    return Counter(n["cls"] for n in nodes if n["cls"])


def volatile_rids(s0, s1):
    """rids whose presence or text changed between a device's own two samples."""
    vol = set(s0.keys()) ^ set(s1.keys())  # appeared/disappeared on its own
    for rid in set(s0.keys()) & set(s1.keys()):
        if s0[rid] != s1[rid]:
            vol.add(rid)
    return vol


def matches_seed(rid, seed):
    low = rid.lower()
    return any(p in low for p in seed)


def is_auth_surface(nodes):
    hay = " ".join((n["rid"] + " " + n["text"]).lower() for n in nodes)
    hits = [m for m in AUTH_MARKERS if m in hay]
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a0", required=True); ap.add_argument("--a1", required=True)
    ap.add_argument("--b0", required=True); ap.add_argument("--b1", required=True)
    ap.add_argument("--checkpoint", default="checkpoint")
    ap.add_argument("--seed-mask", nargs="*", default=DEFAULT_SEED_MASK)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    a0n, a1n = load_nodes(args.a0), load_nodes(args.a1)
    b0n, b1n = load_nodes(args.b0), load_nodes(args.b1)
    a0, a1 = rid_index(a0n), rid_index(a1n)
    b0, b1 = rid_index(b0n), rid_index(b1n)

    # --- eviction first: it invalidates any divergence reading ---
    auth_a, auth_b = is_auth_surface(a0n), is_auth_surface(b0n)
    if bool(auth_a) != bool(auth_b):
        evicted = "master(A)" if auth_a else "PR(B)"
        result = {
            "checkpoint": args.checkpoint, "verdict": "EVICTION", "emoji": "⚠️",
            "detail": f"{evicted} is on an auth/login surface (markers: {auth_a or auth_b}); "
                      f"the other device is not. A session was likely bumped — re-login on both "
                      f"and re-run. This is not a parity result.",
            "divergences": [], "masked": [], "hints": [],
        }
        emit(result, args.out)
        return

    # --- auto-detected volatile set (+ seed) ---
    vol = volatile_rids(a0, a1) | volatile_rids(b0, b1)
    seed_hits = {rid for rid in set(a0) | set(b0) if matches_seed(rid, args.seed_mask)}
    vol |= seed_hits

    ids_a, ids_b = set(a0), set(b0)
    divergences, masked, hints = [], [], []

    # presence divergence on tagged, non-volatile elements
    for rid in sorted((ids_a ^ ids_b) - vol):
        where = "master only" if rid in ids_a else "PR only"
        divergences.append({"type": "presence", "rid": rid, "detail": f"present on {where}"})
    # presence differences that ARE volatile -> soft drift, not a hard call
    for rid in sorted((ids_a ^ ids_b) & vol):
        masked.append({"rid": rid, "reason": "volatile-presence"})

    # value divergence on shared, non-volatile elements
    for rid in sorted((ids_a & ids_b) - vol):
        if a0[rid] != b0[rid]:
            divergences.append({
                "type": "value", "rid": rid,
                "master": list(a0[rid]), "pr": list(b0[rid]),
            })
    for rid in sorted((ids_a & ids_b) & vol):
        masked.append({"rid": rid, "reason": "volatile-value"})

    # untagged structure: soft hint only
    ca, cb = class_multiset(a0n), class_multiset(b0n)
    for cls in sorted(set(ca) | set(cb)):
        if ca.get(cls, 0) != cb.get(cls, 0):
            hints.append({"class": cls, "master_count": ca.get(cls, 0), "pr_count": cb.get(cls, 0)})

    if divergences:
        verdict, emoji = "DIVERGENCE", "🔴"
    elif hints:
        verdict, emoji = "DRIFT", "🟡"
    else:
        verdict, emoji = "PARITY", "🟢"

    result = {
        "checkpoint": args.checkpoint, "verdict": verdict, "emoji": emoji,
        "tagged_master": len(ids_a), "tagged_pr": len(ids_b),
        "masked_volatile": len(vol),
        "divergences": divergences, "masked": masked, "hints": hints,
    }
    emit(result, args.out)


def emit(result, out_path):
    line = f"{result['emoji']} {result['verdict']} @ {result['checkpoint']}"
    if result["verdict"] == "DIVERGENCE":
        line += f" — {len(result['divergences'])} divergence(s): " + \
                ", ".join(d["rid"] for d in result["divergences"][:6])
    elif result["verdict"] == "DRIFT":
        line += f" — {len(result['hints'])} structure hint(s) (live/timing-explainable)"
    elif result["verdict"] == "EVICTION":
        line += " — " + result["detail"]
    print(line)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
    # exit code encodes the verdict so the SKILL can branch in bash if it wants
    sys.exit({"PARITY": 0, "DRIFT": 0, "DIVERGENCE": 1, "EVICTION": 2}[result["verdict"]])


if __name__ == "__main__":
    main()
