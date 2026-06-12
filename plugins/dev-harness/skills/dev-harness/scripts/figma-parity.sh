#!/usr/bin/env bash
# figma-parity.sh — turn "does the UI match the Figma?" into a generated artifact.
#
#   figma-parity.sh export <file-key> <node-id> <out.png>
#       Renders the Figma frame to a PNG via the REST API. Needs FIGMA_TOKEN.
#   figma-parity.sh diff <design.png> <render.png> <out-dir>
#       Normalizes sizes, pixel-diffs design vs render, and writes
#       <out-dir>/parity-sheet.png (design | render | diff heatmap side by side).
#       Prints DIFF_PCT=<n> and SHEET=<path> for the caller to cite.
#
# The diff is RMSE-based: 0% = identical. Renders never byte-match a Figma export
# (font AA, shadows), so judge the SHEET with the DIFF_PCT as a guide — a low
# single-digit DIFF_PCT with a quiet heatmap is parity; hot spots are mistakes.
set -eu

die() { echo "$*" >&2; exit 2; }

# `magick compare -metric RMSE` reports "12345 (0.0188)"; the parenthesised value
# is normalized 0..1 — convert to a human percentage.
rmse_pct() { awk -F'[()]' '{printf "%.2f", $2 * 100}' <<<"$1"; }

figma_image_url() {  # <file-key> <node-id> -> short-lived URL of the rendered PNG
  curl -sf -H "X-Figma-Token: $FIGMA_TOKEN" \
    "https://api.figma.com/v1/images/$1?ids=$2&format=png&scale=1" \
    | jq -re '.images | to_entries[0].value // empty'
}

ensure_imagemagick() {
  command -v magick >/dev/null 2>&1 && return 0
  command -v brew >/dev/null 2>&1 || die "ImageMagick is required — install it first (https://imagemagick.org)"
  echo "installing ImageMagick via brew (one-time)…" >&2
  brew install imagemagick >/dev/null
}

cmd_export() {  # <file-key> <node-id> <out.png>
  [ $# -eq 3 ] || die "usage: figma-parity.sh export <file-key> <node-id> <out.png>"
  [ -n "${FIGMA_TOKEN:-}" ] || die "FIGMA_TOKEN is not set — ask the user for a Figma token; never skip the design source"
  local url; url="$(figma_image_url "$1" "$2")" || die "Figma render failed for $1/$2 (token expired? node wrong?)"
  curl -sf -o "$3" "$url" || die "could not download the rendered frame"
  echo "EXPORTED=$3"
}

cmd_diff() {  # <design.png> <render.png> <out-dir>
  [ $# -eq 3 ] || die "usage: figma-parity.sh diff <design.png> <render.png> <out-dir>"
  local design="$1" render="$2" out="$3"
  [ -s "$design" ] || die "missing design image: $design"
  [ -s "$render" ] || die "missing render image: $render"
  ensure_imagemagick
  mkdir -p "$out"
  local dims; dims="$(magick identify -format '%wx%h' "$render")"
  magick "$design" -resize "${dims}!" "$out/design-normalized.png"
  local metric
  metric="$(magick compare -metric RMSE "$out/design-normalized.png" "$render" "$out/diff-heatmap.png" 2>&1 >/dev/null || true)"
  magick montage "$out/design-normalized.png" "$render" "$out/diff-heatmap.png" \
    -tile 3x1 -geometry +6+6 -background '#1e1e1e' "$out/parity-sheet.png"
  cp "$render" "$out/render.png"                      # self-contained: the review page reads only this dir
  rmse_pct "$metric" > "$out/diff-pct.txt"
  echo "DIFF_PCT=$(cat "$out/diff-pct.txt")"
  echo "SHEET=$out/parity-sheet.png"
}

main() {
  case "${1:-}" in
    export) shift; cmd_export "$@" ;;
    diff)   shift; cmd_diff "$@" ;;
    *) die "usage: figma-parity.sh export|diff …" ;;
  esac
}

# Sourced by tests to reach the pure helpers without running main.
[ "${FP_LIB_ONLY:-0}" = "1" ] && return 0
main "$@"
