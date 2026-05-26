#!/usr/bin/env python3
"""Pixel-diff a Figma design render against a live app screenshot.

Usage:
    compare-images.py <design.png> <app.png> <out-dir> [--threshold N] [--grid N]

Writes:
    <out-dir>/diff-overlay.png  app screenshot with differing pixels tinted red
    <out-dir>/diff-report.json  metrics for the model to interpret

The script only measures — it does not judge. qa-autopilot reads diff-report.json
plus diff-overlay.png and writes the human verdict (colour / thickness / spacing).

Requires: pillow, numpy.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

DIFF_TINT = np.array([255, 0, 0], dtype=np.uint8)


def load_rgb(path):
    if not os.path.exists(path):
        print(f"Image not found: {path}", file=sys.stderr)
        sys.exit(2)
    return Image.open(path).convert("RGB")


def aligned_arrays(design, app):
    """Resize the design to the app's pixel dimensions so coordinates map 1:1."""
    resized_design = design.resize(app.size, Image.LANCZOS)
    return np.asarray(resized_design, dtype=np.int16), np.asarray(app, dtype=np.int16)


def color_distance(design_pixels, app_pixels):
    """Euclidean RGB distance per pixel, range 0 (identical) .. 441 (black vs white)."""
    delta = design_pixels.astype(np.float32) - app_pixels.astype(np.float32)
    return np.sqrt(np.sum(delta ** 2, axis=2))


def aspect_ratio(size):
    width, height = size
    return round(width / height, 4) if height else 0.0


def grid_hotspots(diff_mask, cells):
    """Per-cell share of differing pixels, hottest first, so the model can localise."""
    height, width = diff_mask.shape
    rows, columns = min(cells, height), min(cells, width)
    row_edges = np.linspace(0, height, rows + 1, dtype=int)
    column_edges = np.linspace(0, width, columns + 1, dtype=int)
    hotspots = []
    for r in range(rows):
        for c in range(columns):
            cell = diff_mask[row_edges[r]:row_edges[r + 1], column_edges[c]:column_edges[c + 1]]
            if cell.size:
                hotspots.append({
                    "cell": f"row{r}_col{c}",
                    "region": {"x": int(column_edges[c]), "y": int(row_edges[r]),
                               "w": int(column_edges[c + 1] - column_edges[c]),
                               "h": int(row_edges[r + 1] - row_edges[r])},
                    "diff_pct": round(100.0 * float(cell.mean()), 2),
                })
    hotspots.sort(key=lambda h: h["diff_pct"], reverse=True)
    return hotspots[:12]


def differing_bounding_box(diff_mask):
    rows = np.any(diff_mask, axis=1)
    columns = np.any(diff_mask, axis=0)
    if not rows.any():
        return None
    top, bottom = np.where(rows)[0][[0, -1]]
    left, right = np.where(columns)[0][[0, -1]]
    return {"x": int(left), "y": int(top), "w": int(right - left + 1), "h": int(bottom - top + 1)}


def hex_of(rgb):
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def top_color_mismatches(design_pixels, app_pixels, diff_mask, limit=10):
    """Most frequent design->app colour swaps among differing pixels (quantised to /16)."""
    if not diff_mask.any():
        return []
    design_q = (design_pixels[diff_mask] // 16 * 16).astype(np.uint8)
    app_q = (app_pixels[diff_mask] // 16 * 16).astype(np.uint8)
    pairs = np.concatenate([design_q, app_q], axis=1)
    unique, counts = np.unique(pairs, axis=0, return_counts=True)
    ranking = np.argsort(counts)[::-1][:limit]
    return [{
        "design": hex_of(unique[i][:3]),
        "app": hex_of(unique[i][3:]),
        "pixels": int(counts[i]),
    } for i in ranking]


def write_overlay(app, diff_mask, output_path):
    canvas = np.asarray(app, dtype=np.uint8).copy()
    canvas[diff_mask] = DIFF_TINT
    Image.fromarray(canvas).save(output_path)


def parse_args():
    parser = argparse.ArgumentParser(description="Pixel-diff a Figma render against an app screenshot.")
    parser.add_argument("design", help="Figma design PNG")
    parser.add_argument("app", help="App screenshot PNG")
    parser.add_argument("out_dir", help="Directory for diff-overlay.png and diff-report.json")
    parser.add_argument("--threshold", type=float, default=24.0,
                        help="RGB distance above which a pixel counts as different (default 24)")
    parser.add_argument("--grid", type=int, default=16, help="Hotspot grid resolution (default 16)")
    return parser.parse_args()


def build_report(design, app, distances, diff_mask, threshold, design_pixels, app_pixels, grid):
    return {
        "design_size": list(design.size),
        "app_size": list(app.size),
        "aspect_ratio_match": aspect_ratio(design.size) == aspect_ratio(app.size),
        "threshold": threshold,
        "diff_pct": round(100.0 * float(diff_mask.mean()), 2),
        "mean_distance": round(float(distances.mean()), 2),
        "max_distance": round(float(distances.max()), 2),
        "differing_bounding_box": differing_bounding_box(diff_mask),
        "hotspots": grid_hotspots(diff_mask, grid),
        "top_color_mismatches": top_color_mismatches(design_pixels, app_pixels, diff_mask),
    }


def main():
    args = parse_args()
    design, app = load_rgb(args.design), load_rgb(args.app)
    design_pixels, app_pixels = aligned_arrays(design, app)
    distances = color_distance(design_pixels, app_pixels)
    diff_mask = distances > args.threshold

    os.makedirs(args.out_dir, exist_ok=True)
    write_overlay(app, diff_mask, os.path.join(args.out_dir, "diff-overlay.png"))

    report = build_report(design, app, distances, diff_mask, args.threshold,
                          design_pixels, app_pixels, args.grid)
    report_path = os.path.join(args.out_dir, "diff-report.json")
    with open(report_path, "w") as report_file:
        json.dump(report, report_file, indent=2)
    print(report_path)


if __name__ == "__main__":
    main()
