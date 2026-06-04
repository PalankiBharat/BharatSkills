#!/usr/bin/env bash
# render-review.sh <kind> <payload-file> [--no-open]
# Wrap a markdown/text payload in the themed shell -> .harness/review/<kind>-<ts>.html,
# print the path, open it (unless --no-open / no `open`). Payload is redacted + HTML-escaped.
# kinds: story | plan | questionnaire | verdict | summary
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"
THEME="$HERE/../assets/theme.css"

KIND="${1:?kind}"; PAYLOAD="${2:?payload file}"; OPEN=1
[ "${3:-}" = "--no-open" ] && OPEN=0
[ -f "$PAYLOAD" ] || { echo "no payload: $PAYLOAD" >&2; exit 2; }

mkdir -p "$ROOT/review"
OUT="$ROOT/review/$KIND-$(date +%Y%m%d-%H%M%S).html"

_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
CSS="$(cat "$THEME" 2>/dev/null || true)"
BODY="$(redact_secrets < "$PAYLOAD" | _esc)"

{
  printf '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '<title>dev-harness — %s review</title><style>%s</style></head><body>' "$KIND" "$CSS"
  printf '<div class="wrap"><header><h1>dev<span class="dot">·</span>harness</h1><span class="kind">%s review</span></header>' "$KIND"
  printf '<pre class="payload">%s</pre>' "$BODY"
  printf '<section class="review"><label>Your comments / answers</label>'
  printf '<textarea id="note" placeholder="Type here, then Copy reply…"></textarea>'
  printf '<div class="actions"><button onclick="cp()">📋 Copy reply</button><span id="s"></span></div></section>'
  printf '<pre id="pv" hidden></pre></div>'
  printf '<script>function cp(){var t=document.getElementById("note").value;'
  printf 'navigator.clipboard.writeText(t).then(function(){f("✓ copied — paste to Claude")},function(){'
  printf 'var p=document.getElementById("pv");p.hidden=false;p.textContent=t;var r=document.createRange();'
  printf 'r.selectNodeContents(p);var s=getSelection();s.removeAllRanges();s.addRange(r);f("press ⌘C")})}'
  printf 'function f(m){document.getElementById("s").textContent=m}</script></body></html>'
} > "$OUT"

if [ "$OPEN" -eq 1 ] && command -v open >/dev/null 2>&1; then open "$OUT" || true; fi
echo "$OUT"
