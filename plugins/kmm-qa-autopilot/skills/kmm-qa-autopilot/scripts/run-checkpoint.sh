#!/usr/bin/env bash
# run-checkpoint.sh — run ONE parity checkpoint end-to-end: drive the SAME Maestro flow on both
# locked devices, capture per-device samples, and compare into a verdict. This is the proven
# per-checkpoint unit behind Phase 4/5, so the orchestrator does NOT hand-issue every
# maestro + capture-checkpoint + compare-parity call (which is slow and error-prone).
#
# Usage: run-checkpoint.sh <run-dir> <journey> <checkpoint> <flow.yaml> [single|double]
#   <run-dir>      run's persistent dir (must contain locks/lock-a, locks/lock-b from Phase 0)
#   single|double  samples per device (default double; use single ONLY on proven-static screens,
#                  i.e. a prior checkpoint reported masked_volatile/masked_text = 0)
#
# Writes <run-dir>/artifacts/<journey>/<checkpoint>/{a,b}.s0[,.s1].{png,hierarchy.json} + verdict.json
# Exit code mirrors compare-parity.py: 0 = PARITY/DRIFT, 1 = DIVERGENCE, 2 = EVICTION.
#
# SCROLL/paging (#7): a scrolling flow MUST scroll to a deterministic anchor (list bottom /
# scrollUntilVisible) before this captures — comparing an arbitrary mid-scroll offset across two
# devices yields a FALSE presence 🔴. On a boundary-only presence diff, converge (scroll both to the
# bottom) and re-run this checkpoint before trusting the 🔴.
# STATEFUL actions (#9): for submit/send/download/email on a SHARED account the 2nd device hits
# mutated server state and gets different confirmation copy — do NOT diff the post-action server
# message; capture/compare the pre-submit state and only assert the action fired.
set -uo pipefail
RUN_DIR="${1:?usage: run-checkpoint.sh <run-dir> <journey> <checkpoint> <flow.yaml> [single|double]}"
J="${2:?missing journey}"; CP="${3:?missing checkpoint}"; FLOW="${4:?missing flow.yaml}"; MODE="${5:-double}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"   # .../skills/kmm-qa-autopilot
A="$(cat "$RUN_DIR/locks/lock-a")"; B="$(cat "$RUN_DIR/locks/lock-b")"
OUT="$RUN_DIR/artifacts/$J/$CP"; mkdir -p "$OUT"
echo "[$J/$CP] flow=$(basename "$FLOW") mode=$MODE  A=$A B=$B"
maestro --device "$A" test "$FLOW" >"$OUT/a.maestro.log" 2>&1; ra=$?
maestro --device "$B" test "$FLOW" >"$OUT/b.maestro.log" 2>&1; rb=$?
echo "  maestro exit: A=$ra B=$rb"
[ "$ra" -ne 0 ] && { echo "  ! A flow non-zero (tail):"; tail -3 "$OUT/a.maestro.log"; }
[ "$rb" -ne 0 ] && { echo "  ! B flow non-zero (tail):"; tail -3 "$OUT/b.maestro.log"; }
cap() { bash "$SKILL_DIR/scripts/capture-checkpoint.sh" "$1" "$2" >/dev/null 2>&1; }
cap "$A" "$OUT/a.s0"; cap "$B" "$OUT/b.s0"
if [ "$MODE" = "double" ]; then
  sleep 2; cap "$A" "$OUT/a.s1"; cap "$B" "$OUT/b.s1"
else
  cp "$OUT/a.s0.hierarchy.json" "$OUT/a.s1.hierarchy.json" 2>/dev/null
  cp "$OUT/b.s0.hierarchy.json" "$OUT/b.s1.hierarchy.json" 2>/dev/null
fi
python3 "$SKILL_DIR/scripts/compare-parity.py" \
  --a0 "$OUT/a.s0.hierarchy.json" --a1 "$OUT/a.s1.hierarchy.json" \
  --b0 "$OUT/b.s0.hierarchy.json" --b1 "$OUT/b.s1.hierarchy.json" \
  --checkpoint "$J/$CP" --out "$OUT/verdict.json"
