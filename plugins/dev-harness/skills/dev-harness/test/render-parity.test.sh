#!/usr/bin/env bash
# Contract for render-parity.sh: builds the per-screen review page from parity dirs,
# refuses to render an empty gate, and emits the parseable PARITY REVIEW machinery.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
RP="$HERE/../scripts/render-parity.sh"

T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"; mkdir -p "$HARNESS_ROOT"
PR="$T/parity"

# --- empty / missing parity root -> non-zero, helpful message ---
( bash "$RP" "$PR" --no-open 2>/dev/null ) && _FAIL "missing root -> non-zero"
mkdir -p "$PR/empty-screen"
out="$(bash "$RP" "$PR" --no-open 2>&1 || true)"
assert_contains "$out" "no parity screens"

# --- two complete screens -> one page with both, verdicts, pct, copy machinery ---
for s in chart-screen watchlist; do
  mkdir -p "$PR/$s"
  for f in design-normalized.png render.png diff-heatmap.png parity-sheet.png; do echo img > "$PR/$s/$f"; done
done
echo "1.88" > "$PR/chart-screen/diff-pct.txt"
PAGE="$(bash "$RP" "$PR" --no-open)"
assert_file "$PAGE"
html="$(cat "$PAGE")"
assert_contains "$html" 'data-screen="chart-screen"'
assert_contains "$html" 'data-screen="watchlist"'
assert_contains "$html" "DIFF 1.88%"
assert_contains "$html" "needs-changes"
assert_contains "$html" "PARITY REVIEW"
assert_contains "$html" "$PR/chart-screen/design-normalized.png"
assert_contains "$html" "$PR/chart-screen/render.png"

# --- a dir without a sheet is not a reviewable screen ---
grep -q 'data-screen="empty-screen"' "$PAGE" && _FAIL "incomplete screen must be excluded"

echo OK
