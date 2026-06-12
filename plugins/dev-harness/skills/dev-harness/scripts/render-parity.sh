#!/usr/bin/env bash
# render-parity.sh <parity-root> [--no-open]
# The Figma-parity human gate: one page for every screen under <parity-root>
# (each dir = design-normalized.png + render.png + diff-heatmap.png + diff-pct.txt).
# Design LEFT, render RIGHT, heatmap below, a verdict (approve | needs-changes)
# and a comment box per screen. Copy reply emits a parseable PARITY REVIEW block:
#   PARITY REVIEW
#   [screen-a] approve
#   [screen-b] needs-changes: header spacing is wrong
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"
THEME="$HERE/../assets/theme.css"

PROOT="${1:?usage: render-parity.sh <parity-root> [--no-open]}"; OPEN=1
[ "${2:-}" = "--no-open" ] && OPEN=0
[ -d "$PROOT" ] || { echo "no parity root: $PROOT" >&2; exit 2; }

screen_dirs() { for d in "$PROOT"/*/; do [ -s "$d/parity-sheet.png" ] && echo "$d"; done; }
[ -n "$(screen_dirs)" ] || { echo "no parity screens under $PROOT (run figma-parity diff first)" >&2; exit 2; }

abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$PWD" "$(basename "$1")"); }

screen_section() {  # <dir> — one reviewable screen row
  local dir="$1" name pct
  name="$(basename "$dir")"
  pct="$(cat "$dir/diff-pct.txt" 2>/dev/null || echo '?')"
  printf '<section class="screen" data-screen="%s">' "$name"
  printf '<h2>%s <span class="pct">DIFF %s%%</span></h2>' "$name" "$pct"
  printf '<div class="pair"><figure><img src="%s"><figcaption>Figma design</figcaption></figure>' "$(abs "$dir/design-normalized.png")"
  printf '<figure><img src="%s"><figcaption>Built render</figcaption></figure></div>' "$(abs "$dir/render.png")"
  printf '<details><summary>diff heatmap</summary><img class="heat" src="%s"></details>' "$(abs "$dir/diff-heatmap.png")"
  printf '<div class="verdict"><label><input type="radio" name="v-%s" value="approve" checked> approve</label>' "$name"
  printf '<label><input type="radio" name="v-%s" value="needs-changes"> needs changes</label></div>' "$name"
  printf '<textarea placeholder="comments for this screen (what is wrong, what to fix)…"></textarea></section>'
}

mkdir -p "$ROOT/review"
OUT="$ROOT/review/parity-$(date +%Y%m%d-%H%M%S).html"
{
  printf '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '<title>dev-harness — Figma parity review</title><style>%s' "$(cat "$THEME" 2>/dev/null || true)"
  printf '.screen{margin:28px 0;padding:18px;border:1px solid #333;border-radius:12px}'
  printf '.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}.pair img{width:100%%;border-radius:8px}'
  printf 'figcaption{text-align:center;opacity:.7;margin-top:4px}.pct{font-size:.7em;opacity:.8;margin-left:8px}'
  printf '.heat{max-width:50%%;margin-top:8px}.verdict{margin:10px 0}.verdict label{margin-right:18px}'
  printf 'textarea{width:100%%;min-height:60px}</style></head><body><div class="wrap">'
  printf '<header><h1>dev<span class="dot">·</span>harness</h1><span class="kind">Figma parity review</span></header>'
  printf '<p>Design left, render right. Approve each screen or mark <b>needs changes</b> with a comment, then Copy reply and paste it back.</p>'
  screen_dirs | while read -r d; do screen_section "$d"; done
  printf '<div class="actions"><button onclick="cp()">📋 Copy reply</button><span id="s"></span></div><pre id="pv" hidden></pre></div>'
  printf '<script>function cp(){var out=["PARITY REVIEW"];'
  printf 'document.querySelectorAll("[data-screen]").forEach(function(sc){var n=sc.dataset.screen;'
  printf 'var v=sc.querySelector("input:checked").value;var c=sc.querySelector("textarea").value.trim();'
  printf 'out.push("["+n+"] "+v+(c?": "+c:""))});var t=out.join("\\n");'
  printf 'navigator.clipboard.writeText(t).then(function(){f("✓ copied — paste to Claude")},function(){'
  printf 'var p=document.getElementById("pv");p.hidden=false;p.textContent=t;var r=document.createRange();'
  printf 'r.selectNodeContents(p);var s=getSelection();s.removeAllRanges();s.addRange(r);f("press ⌘C")})}'
  printf 'function f(m){document.getElementById("s").textContent=m}</script></body></html>'
} > "$OUT"

if [ "$OPEN" -eq 1 ] && command -v open >/dev/null 2>&1; then open "$OUT" || true; fi
echo "$OUT"
