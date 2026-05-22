#!/usr/bin/env python3
"""
Diff per-class histograms produced by hprof_histogram.py.

Two modes — selected by argument count:

  growth mode (2 CSVs):
      diff_histograms.py <t0.csv> <t5.csv>
      Prints classes that grew (or shrank) the most between t0 and t5.

  compare mode (4 CSVs):
      diff_histograms.py --label-a NAME <a-t0.csv> <a-t5.csv> \\
                         --label-b NAME <b-t0.csv> <b-t5.csv>
      Prints A vs B comparison: per-class 5-min growth for each build,
      the extra-on-B delta, and the B/A ratio.

Flags:
  --top N            How many rows to show in each ranked table. Default 30.
  --bucket FILE      Optional JSON file with category → [class-prefix, ...]
                     buckets. The wrapper script passes the bundled
                     scripts/buckets.json by default.
"""

import argparse
import csv
import json
import os
import sys
from typing import Dict, Optional, Tuple


def load(path: str) -> Dict[str, Tuple[int, int]]:
    h: Dict[str, Tuple[int, int]] = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            h[row["class"]] = (int(row["instances"]), int(row["shallow_bytes"]))
    return h


def fmt_bytes(b: int) -> str:
    sign = "-" if b < 0 else " "
    b = abs(b)
    for unit in ("B  ", "KB ", "MB ", "GB "):
        if b < 1024:
            return f"{sign}{b:7.1f}{unit}"
        b /= 1024
    return f"{sign}{b:7.1f}TB "


def fmt_ratio(a: int, b: int) -> str:
    if b > 0:
        return f"{a/b:.2f}×"
    if a > 0:
        return f"+{a} (B=0)"
    return "—"


def print_growth(t0: str, t5: str, top: int) -> None:
    h0, h5 = load(t0), load(t5)
    classes = set(h0) | set(h5)
    rows = []
    for c in classes:
        d_obj = h5.get(c, (0, 0))[0] - h0.get(c, (0, 0))[0]
        d_sz = h5.get(c, (0, 0))[1] - h0.get(c, (0, 0))[1]
        rows.append((c, d_obj, d_sz, h5.get(c, (0, 0))[0], h5.get(c, (0, 0))[1]))
    rows.sort(key=lambda r: r[2], reverse=True)

    total_t0 = sum(v[1] for v in h0.values())
    total_t5 = sum(v[1] for v in h5.values())
    print(f"\n=== TOTAL HEAP ===")
    print(f"  t0: {total_t0:>14,} bytes  ({sum(v[0] for v in h0.values()):>12,} objs, {len(h0)} classes)")
    print(f"  t5: {total_t5:>14,} bytes  ({sum(v[0] for v in h5.values()):>12,} objs, {len(h5)} classes)")
    print(f"  Δ:  {total_t5 - total_t0:+14,} bytes")

    print(f"\n=== TOP {top}: GREW THE MOST (t5 - t0, by shallow bytes) ===")
    print(f"  {'class':<70} {'Δobjs':>12} {'Δbytes':>14} {'t5 objs':>10}")
    for r in rows[:top]:
        print(f"  {r[0][:70]:<70} {r[1]:>12,} {fmt_bytes(r[2]):>14} {r[3]:>10,}")

    print(f"\n=== TOP {top}: SHRANK THE MOST (t5 < t0) ===")
    for r in rows[-top:][::-1]:
        if r[2] >= 0:
            break
        print(f"  {r[0][:70]:<70} {r[1]:>12,} {fmt_bytes(r[2]):>14} {r[3]:>10,}")


def print_compare(label_a: str, a0: str, a5: str,
                  label_b: str, b0: str, b5: str,
                  top: int, bucket_file: Optional[str]) -> None:
    ha0, ha5 = load(a0), load(a5)
    hb0, hb5 = load(b0), load(b5)

    print(f"\n=== TOTAL HEAP ===")
    for label, hh in [(f"{label_a}-t0", ha0), (f"{label_a}-t5", ha5),
                      (f"{label_b}-t0", hb0), (f"{label_b}-t5", hb5)]:
        total_b = sum(v[1] for v in hh.values())
        total_o = sum(v[0] for v in hh.values())
        print(f"  {label:<22s} {total_b:>14,} bytes  {total_o:>12,} objs  ({len(hh)} classes)")

    classes = set(ha0) | set(ha5) | set(hb0) | set(hb5)

    rows = []
    for c in classes:
        a_d_o = ha5.get(c, (0, 0))[0] - ha0.get(c, (0, 0))[0]
        a_d_b = ha5.get(c, (0, 0))[1] - ha0.get(c, (0, 0))[1]
        b_d_o = hb5.get(c, (0, 0))[0] - hb0.get(c, (0, 0))[0]
        b_d_b = hb5.get(c, (0, 0))[1] - hb0.get(c, (0, 0))[1]
        rows.append((c, a_d_o, a_d_b, b_d_o, b_d_b, b_d_o - a_d_o, b_d_b - a_d_b))

    rows.sort(key=lambda r: r[6], reverse=True)

    print(f"\n=== TOP {top}: CLASSES THAT GREW MORE ON {label_b.upper()} THAN ON {label_a.upper()} ===")
    print(f"  {'class':<70} {label_a+' Δobj':>10} {label_b+' Δobj':>10} {'ratio':>8} {'extra bytes':>14}")
    for r in rows[:top]:
        print(f"  {r[0][:70]:<70} {r[1]:>10,} {r[3]:>10,} {fmt_ratio(r[3], r[1]):>8} {fmt_bytes(r[6]):>14}")

    rows.sort(key=lambda r: r[6])
    print(f"\n=== TOP {top}: CLASSES THAT GREW MORE ON {label_a.upper()} THAN ON {label_b.upper()} ===")
    print(f"  {'class':<70} {label_a+' Δobj':>10} {label_b+' Δobj':>10} {'ratio':>8} {'extra bytes':>14}")
    for r in rows[:top]:
        if r[6] >= 0:
            break
        print(f"  {r[0][:70]:<70} {r[1]:>10,} {r[3]:>10,} {fmt_ratio(r[1], r[3]):>8} {fmt_bytes(-r[6]):>14}")

    if bucket_file and os.path.isfile(bucket_file):
        print_buckets(rows, label_a, label_b, bucket_file)


def print_buckets(rows, label_a: str, label_b: str, bucket_file: str) -> None:
    with open(bucket_file) as f:
        buckets = json.load(f)

    by_class = {r[0]: r for r in rows}
    print(f"\n=== CATEGORY BREAKDOWN ({label_a} vs {label_b}, 5-min growth) ===")
    for category, prefixes in buckets.items():
        matches = []
        for c, r in by_class.items():
            if any(c.startswith(p) for p in prefixes):
                if r[1] != 0 or r[3] != 0:
                    matches.append(r)
        if not matches:
            continue
        matches.sort(key=lambda r: -abs(r[6]))
        print(f"\n  -- {category} --")
        print(f"    {'class':<65} {label_a+' Δ':>10} {label_b+' Δ':>10} {'ratio':>8}")
        for r in matches[:15]:
            print(f"    {r[0][:65]:<65} {r[1]:>10,} {r[3]:>10,} {fmt_ratio(r[3], r[1]):>8}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("paths", nargs="+", help="histogram CSV paths")
    p.add_argument("--label-a", default="A", help="label for the first build (compare mode)")
    p.add_argument("--label-b", default="B", help="label for the second build (compare mode)")
    p.add_argument("--top", type=int, default=30, help="rows per ranked table")
    p.add_argument("--bucket", default=None, help="optional category bucket JSON file")
    args = p.parse_args()

    if len(args.paths) == 2:
        print_growth(args.paths[0], args.paths[1], args.top)
    elif len(args.paths) == 4:
        print_compare(args.label_a, args.paths[0], args.paths[1],
                      args.label_b, args.paths[2], args.paths[3],
                      args.top, args.bucket)
    else:
        sys.exit("usage: diff_histograms.py <t0.csv> <t5.csv>\n"
                 "   or: diff_histograms.py <a-t0.csv> <a-t5.csv> <b-t0.csv> <b-t5.csv>"
                 " [--label-a NAME --label-b NAME]")


if __name__ == "__main__":
    main()
