#!/usr/bin/env bash
# Contract for figma-parity.sh: pure helpers + argument/dependency guards.
# Image operations need ImageMagick + network, so they're smoke (test/SMOKE.md);
# everything decidable without them is covered here.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
FP="$HERE/../scripts/figma-parity.sh"

# --- pure helper: rmse_pct parses `magick compare -metric RMSE` output ---
FP_LIB_ONLY=1 . "$FP"
assert_eq "$(rmse_pct '12345.6 (0.0188)')" "1.88"
assert_eq "$(rmse_pct '0 (0)')" "0.00"
assert_eq "$(rmse_pct '65535 (1)')" "100.00"

# --- usage guards: wrong/missing args fail fast with a usage line ---
( bash "$FP" 2>/dev/null ) && _FAIL "no command -> non-zero"
( bash "$FP" export onlyonearg 2>/dev/null ) && _FAIL "export with bad arity -> non-zero"
( bash "$FP" diff onlyonearg 2>/dev/null ) && _FAIL "diff with bad arity -> non-zero"

# --- export without FIGMA_TOKEN must say what is missing, never guess ---
out="$(env -u FIGMA_TOKEN bash "$FP" export key node /tmp/x.png 2>&1 || true)"
assert_contains "$out" "FIGMA_TOKEN"

# --- diff with a missing input names the missing file ---
out="$(bash "$FP" diff /nonexistent-a.png /nonexistent-b.png /tmp/fp-out 2>&1 || true)"
assert_contains "$out" "/nonexistent-a.png"

echo OK
