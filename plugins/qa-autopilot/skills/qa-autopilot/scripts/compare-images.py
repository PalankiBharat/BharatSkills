#!/usr/bin/env python3
"""Measure how closely a built Android screen matches its Figma design.

This script does the DETERMINISTIC half of Figma parity: it aligns the two
images to one pixel grid and reports precise, perceptual colour numbers. The
holistic spatial read (layout, spacing, stroke thickness, missing elements) is
the model's job — it views the aligned images this script writes.

Usage:
    compare-images.py <design.png> <app.png> <out-dir>
        [--crop-top N] [--crop-bottom N] [--regions regions.json] [--inset F]

Always writes (to <out-dir>):
    design-aligned.png, app-aligned.png   the exact pixel grid being compared
    diff-overlay.png                       differing pixels tinted red (HINT only)
    diff-report.json                       global hint + per-region colour numbers

`--crop-top` / `--crop-bottom` strip the Android status / nav bars off the app
screenshot (look at it, then set the pixel counts) so the design and app content
occupy the same frame. After cropping, the design is resized to the app's exact
dimensions, so a region box addresses the same element in both images.

`--regions regions.json` is the precise path. Provide a JSON array of boxes in
ALIGNED-image pixel coordinates (post-crop, post-resize):
    [{"name": "primary_button", "x": 40, "y": 600, "w": 1000, "h": 130}, ...]
For each box the script reports median + dominant colour (design vs app) as hex,
the perceptual CIEDE2000 ΔE between them, and a luminance correlation.

ΔE reference: <1 imperceptible, 1-3 close, 3-5 noticeable drift, >5 clearly off.

Requires: pillow, numpy.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

DIFF_TINT = np.array([255, 0, 0], dtype=np.uint8)
D65_WHITE = (0.95047, 1.0, 1.08883)


def load_rgb(path):
    if not os.path.exists(path):
        print(f"Image not found: {path}", file=sys.stderr)
        sys.exit(2)
    return Image.open(path).convert("RGB")


def crop_chrome(app, crop_top, crop_bottom):
    width, height = app.size
    return app.crop((0, crop_top, width, height - crop_bottom))


def to_common_grid(design, cropped_app):
    """Resize the design onto the cropped app's exact pixel grid."""
    return design.resize(cropped_app.size, Image.LANCZOS), cropped_app


def srgb_channel_to_linear(channel):
    c = channel / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lab_pivot(ratio):
    return np.where(ratio > 0.008856, np.cbrt(ratio), 7.787 * ratio + 16.0 / 116.0)


def srgb_to_lab(rgb):
    """sRGB 0-255 (any array shape ...x3) to CIE-Lab, with gamma decode + D65."""
    linear = srgb_channel_to_linear(np.asarray(rgb, dtype=np.float64))
    r, g, b = linear[..., 0], linear[..., 1], linear[..., 2]
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
    fx, fy, fz = (lab_pivot(x / D65_WHITE[0]),
                  lab_pivot(y / D65_WHITE[1]),
                  lab_pivot(z / D65_WHITE[2]))
    return np.stack([116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)], axis=-1)


def ciede2000(lab1, lab2):
    """Perceptual colour difference (CIEDE2000) between two Lab triples."""
    l1, a1, b1 = lab1
    l2, a2, b2 = lab2
    c1, c2 = math.hypot(a1, b1), math.hypot(a2, b2)
    c_bar = (c1 + c2) / 2.0
    g = 0.5 * (1 - math.sqrt(c_bar ** 7 / (c_bar ** 7 + 25 ** 7))) if c_bar else 0.0
    a1p, a2p = (1 + g) * a1, (1 + g) * a2
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p, h2p = math.degrees(math.atan2(b1, a1p)) % 360, math.degrees(math.atan2(b2, a2p)) % 360

    dlp = l2 - l1
    dcp = c2p - c1p
    dhp = _hue_delta(h1p, h2p, c1p, c2p)
    dHp = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dhp) / 2.0)

    l_bar = (l1 + l2) / 2.0
    cp_bar = (c1p + c2p) / 2.0
    hp_bar = _hue_average(h1p, h2p, c1p, c2p)
    t = (1 - 0.17 * math.cos(math.radians(hp_bar - 30))
         + 0.24 * math.cos(math.radians(2 * hp_bar))
         + 0.32 * math.cos(math.radians(3 * hp_bar + 6))
         - 0.20 * math.cos(math.radians(4 * hp_bar - 63)))
    sl = 1 + (0.015 * (l_bar - 50) ** 2) / math.sqrt(20 + (l_bar - 50) ** 2)
    sc = 1 + 0.045 * cp_bar
    sh = 1 + 0.015 * cp_bar * t
    delta_theta = 30 * math.exp(-(((hp_bar - 275) / 25) ** 2))
    rc = 2 * math.sqrt(cp_bar ** 7 / (cp_bar ** 7 + 25 ** 7))
    rt = -rc * math.sin(math.radians(2 * delta_theta))
    return math.sqrt((dlp / sl) ** 2 + (dcp / sc) ** 2 + (dHp / sh) ** 2
                     + rt * (dcp / sc) * (dHp / sh))


def _hue_delta(h1p, h2p, c1p, c2p):
    if c1p * c2p == 0:
        return 0.0
    diff = h2p - h1p
    if diff > 180:
        return diff - 360
    if diff < -180:
        return diff + 360
    return diff


def _hue_average(h1p, h2p, c1p, c2p):
    if c1p * c2p == 0:
        return h1p + h2p
    if abs(h1p - h2p) <= 180:
        return (h1p + h2p) / 2.0
    return (h1p + h2p + 360) / 2.0 if (h1p + h2p) < 360 else (h1p + h2p - 360) / 2.0


def hex_of(rgb):
    return "#{:02X}{:02X}{:02X}".format(int(rgb[0]), int(rgb[1]), int(rgb[2]))


def inset_box(box, inset, bounds):
    """Shrink a box inward so region stats skip text/strokes at the edges."""
    x, y, w, h = box
    dx, dy = int(w * inset), int(h * inset)
    x0, y0 = max(0, x + dx), max(0, y + dy)
    x1, y1 = min(bounds[0], x + w - dx), min(bounds[1], y + h - dy)
    return x0, y0, max(x0 + 1, x1), max(y0 + 1, y1)


def region_colors(pixels):
    median = np.median(pixels.reshape(-1, 3), axis=0)
    quantized = (pixels.reshape(-1, 3) // 16 * 16).astype(np.uint8)
    values, counts = np.unique(quantized, axis=0, return_counts=True)
    top = int(np.argmax(counts))
    return {
        "median_hex": hex_of(median),
        "median_rgb": [int(v) for v in median],
        "dominant_hex": hex_of(values[top]),
        "dominant_pixels": int(counts[top]),
        "dominant_pct": round(100.0 * counts[top] / len(quantized), 1),
    }


def luminance_correlation(design_pixels, app_pixels):
    """Pearson r of luminance — a structural hint, not a colour judgement."""
    d = design_pixels.reshape(-1, 3).mean(axis=1)
    a = app_pixels.reshape(-1, 3).mean(axis=1)
    if d.std() == 0 or a.std() == 0:
        return None
    return round(float(np.corrcoef(d, a)[0, 1]), 3)


def verdict_hint(delta_e):
    if delta_e < 1:
        return "imperceptible"
    if delta_e < 3:
        return "close"
    if delta_e < 5:
        return "noticeable"
    return "clearly-off"


def sample_region(region, design_arr, app_arr, inset):
    bounds = (design_arr.shape[1], design_arr.shape[0])
    x0, y0, x1, y1 = inset_box((region["x"], region["y"], region["w"], region["h"]), inset, bounds)
    design_crop, app_crop = design_arr[y0:y1, x0:x1], app_arr[y0:y1, x0:x1]
    design = region_colors(design_crop)
    app = region_colors(app_crop)
    delta_median = ciede2000(srgb_to_lab(design["median_rgb"]), srgb_to_lab(app["median_rgb"]))
    return {
        "name": region.get("name", f"{x0},{y0}"),
        "box": [region["x"], region["y"], region["w"], region["h"]],
        "design": design,
        "app": app,
        "delta_e_2000": round(delta_median, 2),
        "verdict_hint": verdict_hint(delta_median),
        "luminance_correlation": luminance_correlation(design_crop, app_crop),
    }


def global_hint(design_arr, app_arr, threshold):
    distance = np.sqrt(np.sum((design_arr.astype(np.float32) - app_arr.astype(np.float32)) ** 2, axis=2))
    diff_mask = distance > threshold
    return diff_mask, {
        "diff_pct": round(100.0 * float(diff_mask.mean()), 2),
        "mean_rgb_distance": round(float(distance.mean()), 2),
        "note": "Alignment/anti-aliasing/mock-data sensitive. A HINT for where to look, NOT the verdict. Trust per-region delta_e_2000.",
    }


def write_overlay(app_arr, diff_mask, path):
    canvas = app_arr.copy()
    canvas[diff_mask] = DIFF_TINT
    Image.fromarray(canvas).save(path)


def blank_screen_check(app_arr):
    """Keyguard / system-credential screens screenshot as near-black. Detect so
    the skill refuses a parity verdict and falls back to the view hierarchy."""
    luminance = app_arr.mean(axis=2)
    mean, std = float(luminance.mean()), float(luminance.std())
    blank = mean < 8 and std < 3
    return {
        "mean_luminance": round(mean, 2),
        "luminance_std": round(std, 2),
        "app_screenshot_blank": blank,
        "note": ("Screenshot is near-black (keyguard / system-credential / full-screen "
                 "system prompt). Pixel parity is INVALID here — inspect the view hierarchy "
                 "(maestro hierarchy / inspect) instead.") if blank else "",
    }


def write_view_copy(image, path, view_width):
    """Downscaled copy for the model to open — full-res renders blow the image cap."""
    width, height = image.size
    if width <= view_width:
        image.save(path)
        return
    image.resize((view_width, round(height * view_width / width)), Image.LANCZOS).save(path)


def load_regions(path):
    if not path:
        return []
    with open(path) as regions_file:
        return json.load(regions_file)


def parse_args():
    parser = argparse.ArgumentParser(description="Measure Figma-vs-app visual parity.")
    parser.add_argument("design")
    parser.add_argument("app")
    parser.add_argument("out_dir")
    parser.add_argument("--crop-top", type=int, default=0, help="px to strip off the app's top (status bar)")
    parser.add_argument("--crop-bottom", type=int, default=0, help="px to strip off the app's bottom (nav bar)")
    parser.add_argument("--regions", help="JSON file of boxes in aligned-image coords")
    parser.add_argument("--inset", type=float, default=0.15, help="fraction to shrink each region before sampling")
    parser.add_argument("--threshold", type=float, default=24.0, help="RGB distance for the global hint overlay")
    parser.add_argument("--view-width", type=int, default=900, help="width of the downscaled *-view.png copies the model opens")
    return parser.parse_args()


def main():
    args = parse_args()
    design, app = load_rgb(args.design), load_rgb(args.app)
    design_img, app_img = to_common_grid(design, crop_chrome(app, args.crop_top, args.crop_bottom))

    os.makedirs(args.out_dir, exist_ok=True)
    design_img.save(os.path.join(args.out_dir, "design-aligned.png"))
    app_img.save(os.path.join(args.out_dir, "app-aligned.png"))
    write_view_copy(design_img, os.path.join(args.out_dir, "design-view.png"), args.view_width)
    write_view_copy(app_img, os.path.join(args.out_dir, "app-view.png"), args.view_width)

    design_arr, app_arr = np.asarray(design_img), np.asarray(app_img)
    diff_mask, hint = global_hint(design_arr, app_arr, args.threshold)
    write_overlay(app_arr, diff_mask, os.path.join(args.out_dir, "diff-overlay.png"))

    blank = blank_screen_check(app_arr)
    report = {
        "aligned_size": [design_arr.shape[1], design_arr.shape[0]],
        "crop": {"top": args.crop_top, "bottom": args.crop_bottom},
        "blank_screen_check": blank,
        "view_images": ["design-view.png", "app-view.png"],
        "global_hint": hint,
        "delta_e_reference": {"imperceptible": "<1", "close": "1-3", "noticeable": "3-5", "clearly_off": ">5"},
        "regions": [sample_region(r, design_arr, app_arr, args.inset) for r in load_regions(args.regions)],
    }
    report_path = os.path.join(args.out_dir, "diff-report.json")
    with open(report_path, "w") as report_file:
        json.dump(report, report_file, indent=2)
    if blank["app_screenshot_blank"]:
        print(f"WARNING: {blank['note']}", file=sys.stderr)
    print(report_path)


if __name__ == "__main__":
    main()
