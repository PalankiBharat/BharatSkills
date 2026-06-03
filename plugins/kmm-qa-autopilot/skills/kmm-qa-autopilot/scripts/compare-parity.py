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
  INDETERMINATE ⚪ a declared --anchor proving the subject was reached is absent on BOTH devices
                — neither flow got there, so the comparison is vacuous (not parity). Fix the flow.
  DIVERGENCE 🔴 a non-volatile tagged element is missing/extra, or a stable value differs.
  DRIFT      🟡 only soft/structure hints or volatile-presence differences (timing/live data).
  PARITY     🟢 stable structure + values match once live fields are masked.

Usage:
  compare-parity.py --a0 a.s0.hierarchy.json --a1 a.s1.hierarchy.json \
                    --b0 b.s0.hierarchy.json --b1 b.s1.hierarchy.json \
                    [--checkpoint NAME] [--seed-mask price ltp pnl ...] [--anchor RID ...] \
                    [--out verdict.json]

Accepts Maestro hierarchy JSON or uiautomator XML (by file content/extension).
"""

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter

# Seed patterns for known-volatile fields — belt-and-suspenders on top of auto-detection,
# in case the market is closed (static) and a field that is normally live didn't tick.
DEFAULT_SEED_MASK = [
    "price", "ltp", "pnl", "p_n_l", "pl_", "percent", "change", "ticker",
    "clock", "time", "timestamp", "chart", "canvas", "candle", "spark", "ohlc",
    "marquee", "live", "quote", "last_traded",
    # chart-region render nodes: SciChart axis ticks/series/annotations re-render at a
    # sub-value offset and a device can diverge from ITSELF on relaunch (the visible price
    # is identical; the axis tick label rounds differently). Masking the region kills a
    # recurring false 🔴 on chart-bearing screens (see parity-comparison.md "relaunch trick").
    "axismodifier", "axis", "renderableseries", "adorner", "annotation",
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
    return Counter(n["cls"] for n in nodes if n["cls"])


def text_multiset(nodes):
    """Counter of visible non-empty text. The real signal on screens without testTags —
    e.g. reports, where the on-screen amounts ARE the migrated logic's output."""
    return Counter(n["text"] for n in nodes if n["text"])


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


def anchor_present(nodes, rids, anchor):
    """True if anchor proves this device reached the subject — matches a resource-id (exact)
    or a visible text (exact, after _norm)."""
    if anchor in rids:
        return True
    return any(n["text"] == anchor for n in nodes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a0", required=True); ap.add_argument("--a1", required=True)
    ap.add_argument("--b0", required=True); ap.add_argument("--b1", required=True)
    ap.add_argument("--checkpoint", default="checkpoint")
    ap.add_argument("--seed-mask", nargs="*", default=DEFAULT_SEED_MASK)
    ap.add_argument("--server-state-text", nargs="*", default=[],
                    help="substrings of backend-driven confirmation copy to mask as account/"
                         "server-state-dependent (e.g. 'sent this report', 'you will receive'). "
                         "Same prod account on both devices means a stateful action's 2nd request "
                         "sees mutated server state — that copy is not a parity signal.")
    ap.add_argument("--mask-text", nargs="*", default=[],
                    help="substrings of visible text to mask as render/display noise rather than "
                         "migrated-logic output — e.g. chart-axis tick numbers that re-render at a "
                         "sub-value offset and differ across devices though the real value matches. "
                         "Distinct from --server-state-text (which is for backend confirmation copy); "
                         "use this for on-screen-render jitter that has no stable resource-id to seed-mask.")
    ap.add_argument("--anchor", nargs="*", default=[],
                    help="resource-ids or exact visible texts proving the subject was reached; if "
                         "declared and NONE appear on EITHER device, the checkpoint is INDETERMINATE "
                         "(the flow didn't reach the subject; comparison is vacuous).")
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

    # --- anchor gate: if declared anchors prove the subject was reached and NONE appear on
    #     EITHER device, neither flow got there and the comparison is vacuous (not parity). ---
    if args.anchor:
        on_a = any(anchor_present(a0n, set(a0), x) for x in args.anchor)
        on_b = any(anchor_present(b0n, set(b0), x) for x in args.anchor)
        if not (on_a or on_b):
            anchors = list(args.anchor)
            result = {
                "checkpoint": args.checkpoint, "verdict": "INDETERMINATE", "emoji": "⚪",
                "detail": f"anchor(s) {anchors} absent on both devices — neither flow reached the "
                          f"subject; this comparison is vacuous (not parity). Fix the flow to "
                          f"reach/scroll-to the subject, then re-run.",
                "divergences": [], "masked": [], "hints": [], "anchors": anchors,
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

    # visible-text comparison — the hard signal on untagged screens (reports etc.). A text whose
    # count changed between a device's own two samples is volatile (live) and is masked, exactly
    # like tagged fields. Remaining text-count differences are real value divergences.
    ta0, ta1 = text_multiset(a0n), text_multiset(a1n)
    tb0, tb1 = text_multiset(b0n), text_multiset(b1n)
    vol_text = {t for t in (set(ta0) | set(ta1)) if ta0.get(t, 0) != ta1.get(t, 0)}
    vol_text |= {t for t in (set(tb0) | set(tb1)) if tb0.get(t, 0) != tb1.get(t, 0)}
    for t in sorted((set(ta0) | set(tb0)) - vol_text):
        ca_, cb_ = ta0.get(t, 0), tb0.get(t, 0)
        if ca_ == cb_:
            continue
        if any(p.lower() in t.lower() for p in args.server_state_text):
            # Backend-driven confirmation copy on a stateful action (same account on both devices):
            # the 2nd request sees mutated server state, so this text is order/state-dependent,
            # not a build difference. Mask it instead of calling a 🔴. (See stateful-action note.)
            masked.append({"text": t, "reason": "server-state-text"})
            continue
        if any(p.lower() in t.lower() for p in args.mask_text):
            # Render/display noise with no stable id (e.g. a chart-axis tick number that rounds
            # differently per device while the real value matches) — masked, not a build 🔴.
            masked.append({"text": t, "reason": "mask-text"})
            continue
        if min(ca_, cb_) == 0:
            # Present on exactly ONE build → a real value/row difference (a unique row key like a
            # timestamp or amount appearing on one side only). This is the hard signal.
            divergences.append({"type": "text", "text": t, "master_count": ca_, "pr_count": cb_})
        else:
            # Count delta on a label present on BOTH builds → a repeated generic label (status,
            # "UPI", "Net Balance") whose visible count differs by a row at the scroll boundary.
            # That's render/scroll-offset jitter, not a data difference — soft hint, confirm
            # against the unique row values, never a hard 🔴 on its own.
            hints.append({"type": "text-count", "text": t, "master_count": ca_, "pr_count": cb_})
    masked_text = len(vol_text)

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
        "masked_volatile": len(vol), "masked_text": masked_text,
        "divergences": divergences, "masked": masked, "hints": hints,
    }
    emit(result, args.out)


def emit(result, out_path):
    line = f"{result['emoji']} {result['verdict']} @ {result['checkpoint']}"
    if result["verdict"] == "DIVERGENCE":
        labels = []
        for d in result["divergences"][:6]:
            labels.append(d.get("rid") or (("text:" + d.get("text", "?")[:24]) if d.get("type") == "text" else "?"))
        line += f" — {len(result['divergences'])} divergence(s): " + ", ".join(labels)
    elif result["verdict"] == "DRIFT":
        line += f" — {len(result['hints'])} structure hint(s) (live/timing-explainable)"
    elif result["verdict"] == "EVICTION":
        line += " — " + result["detail"]
    elif result["verdict"] == "INDETERMINATE":
        line += " — " + result["detail"]
    print(line)
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
    # exit code encodes the verdict so the SKILL can branch in bash if it wants
    sys.exit({"PARITY": 0, "DRIFT": 0, "DIVERGENCE": 1, "EVICTION": 2,
              "INDETERMINATE": 3}[result["verdict"]])


if __name__ == "__main__":
    main()
