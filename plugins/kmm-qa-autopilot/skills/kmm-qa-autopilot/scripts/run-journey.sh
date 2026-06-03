#!/usr/bin/env bash
# run-journey.sh — run every segment flow in a journey's flow dir, in sorted order, each as a
# parity checkpoint in lockstep on both devices. Thin loop over run-checkpoint.sh.
#
# Usage: run-journey.sh <run-dir> <journey> <flows-dir> [single|double]
#   runs <flows-dir>/*.yaml sorted; each becomes a checkpoint named by its file stem.
# Exit: 0 if all checkpoints PARITY/DRIFT; 1 = any DIVERGENCE; 2 = any EVICTION; 3 = any INDETERMINATE.
#   Worst-wins is NUMERIC, so an INDETERMINATE (3) checkpoint surfaces as the journey's coarse exit
#   even above a 🔴 (1) — the per-checkpoint report stays authoritative for a real divergence.
#
# Env (inherited by the child run-checkpoint.sh, no passthrough needed):
#   PARITY_PARALLEL=1  for a READ-ONLY journey only — runs both devices concurrently per checkpoint
#                      for ~2x speed. NEVER set for a mutating journey (shared prod account).
#   PARITY_ANCHOR      subject anchors, set PER-CHECKPOINT before each run-checkpoint.sh call (the
#                      anchor differs by screen); absent on both devices → INDETERMINATE for that cp.
#
# Note: this does not reset device state between segments — author the flows to run incrementally
# from the previous checkpoint's state, or relaunch+navigate at the start of each journey. For a
# clean base, force-stop + relaunch both devices before calling this (force-stop preserves login;
# never clearState). See references/maestro-parity.md.
set -uo pipefail
RUN_DIR="${1:?usage: run-journey.sh <run-dir> <journey> <flows-dir> [single|double]}"
J="${2:?missing journey}"; FDIR="${3:?missing flows-dir}"; MODE="${4:-double}"
SELF="$(cd "$(dirname "$0")" && pwd -P)"
worst=0
shopt -s nullglob
segs=("$FDIR"/*.yaml)
[ "${#segs[@]}" -gt 0 ] || { echo "no .yaml flows in $FDIR" >&2; exit 2; }
for seg in "${segs[@]}"; do
  name="$(basename "$seg" .yaml)"
  bash "$SELF/run-checkpoint.sh" "$RUN_DIR" "$J" "$name" "$seg" "$MODE"
  rc=$?
  [ "$rc" -gt "$worst" ] && worst=$rc
done
echo "journey '$J' complete — worst checkpoint verdict exit=$worst (0 ok, 1 divergence, 2 eviction, 3 indeterminate)"
exit "$worst"
