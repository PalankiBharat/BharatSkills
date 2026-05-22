#!/bin/bash
# Compare Android heap dumps — convert .hprof → JVM format → per-class histogram → diff.
#
# Usage:
#   compare-heap-dumps.sh <pair-dir-A> [pair-dir-B] [--workspace DIR] [--top N]
#   compare-heap-dumps.sh <hprof-t0> <hprof-t5>                       [--workspace DIR] [--top N]
#   compare-heap-dumps.sh <a-t0> <a-t5> <b-t0> <b-t5>                 [--workspace DIR] [--top N] \
#                         [--label-a NAME --label-b NAME]
#
# When a "pair-dir" is passed, the script picks the first .hprof matching *t0min* as t0
# and the first matching *t5min* as t5 (the file-naming convention from the heap-dump-pair
# skill). Two pair-dirs → A/B comparison. One pair-dir → single-build growth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HPROF_CONV="${HPROF_CONV:-$HOME/Library/Android/sdk/platform-tools/hprof-conv}"
WORKSPACE=""
TOP=30
LABEL_A=""
LABEL_B=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --top)       TOP="$2"; shift 2 ;;
    --label-a)   LABEL_A="$2"; shift 2 ;;
    --label-b)   LABEL_B="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,12p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  echo "error: no inputs. Run with --help for usage." >&2
  exit 2
fi

if [[ ! -x "$HPROF_CONV" ]]; then
  echo "error: hprof-conv not found at $HPROF_CONV" >&2
  echo "  Set HPROF_CONV=/path/to/hprof-conv to override." >&2
  exit 2
fi

# Resolve a pair-dir into two hprof paths (t0, t5).
resolve_pair_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then echo "" "" ; return; fi
  local t0 t5
  t0=$(find "$dir" -maxdepth 1 -name '*t0min*.hprof' | sort | head -1)
  t5=$(find "$dir" -maxdepth 1 -name '*t5min*.hprof' | sort | head -1)
  echo "$t0" "$t5"
}

# Expand pair-dirs into hprof file arguments.
declare -a HPROFS=()
for arg in "${POSITIONAL[@]}"; do
  if [[ -d "$arg" ]]; then
    read -r t0 t5 <<<"$(resolve_pair_dir "$arg")"
    if [[ -z "$t0" || -z "$t5" ]]; then
      echo "error: $arg does not contain *t0min*.hprof and *t5min*.hprof" >&2
      exit 2
    fi
    HPROFS+=("$t0" "$t5")
    # If no explicit label given for this slot, derive from dir basename
    if [[ ${#HPROFS[@]} -eq 2 && -z "$LABEL_A" ]]; then
      LABEL_A=$(basename "$arg")
    elif [[ ${#HPROFS[@]} -eq 4 && -z "$LABEL_B" ]]; then
      LABEL_B=$(basename "$arg")
    fi
  elif [[ -f "$arg" ]]; then
    HPROFS+=("$arg")
  else
    echo "error: not a file or directory: $arg" >&2
    exit 2
  fi
done

case ${#HPROFS[@]} in
  2|4) ;;
  *)
    echo "error: expected 2 or 4 hprof files (got ${#HPROFS[@]})" >&2
    exit 2
    ;;
esac

[[ -z "$LABEL_A" ]] && LABEL_A="A"
[[ -z "$LABEL_B" ]] && LABEL_B="B"

if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="$(mktemp -d -t heap-compare-XXXXXX)"
fi
mkdir -p "$WORKSPACE"
echo "workspace: $WORKSPACE" >&2

# Convert Android hprof → JVM hprof (if needed). hprof-conv on a JVM-format file
# is a no-op-but-slow rewrite, so we still pass everything through it for
# consistency. Output filenames are stable so re-runs are cheap.
declare -a CONVERTED=()
declare -a HISTOGRAMS=()
i=0
for hprof in "${HPROFS[@]}"; do
  base=$(basename "${hprof%.hprof}")
  out="$WORKSPACE/${base}.jvm.hprof"
  hist="$WORKSPACE/${base}.histogram.csv"
  if [[ ! -f "$out" || "$hprof" -nt "$out" ]]; then
    echo "  converting: $base" >&2
    "$HPROF_CONV" "$hprof" "$out"
  fi
  if [[ ! -f "$hist" || "$out" -nt "$hist" ]]; then
    echo "  histogram:  $base" >&2
    python3 "$SCRIPT_DIR/hprof_histogram.py" "$out" "$hist"
  fi
  CONVERTED+=("$out")
  HISTOGRAMS+=("$hist")
  i=$((i+1))
done

# Run the diff.
BUCKET="$SCRIPT_DIR/buckets.json"

if [[ ${#HISTOGRAMS[@]} -eq 2 ]]; then
  python3 "$SCRIPT_DIR/diff_histograms.py" \
    --top "$TOP" \
    "${HISTOGRAMS[0]}" "${HISTOGRAMS[1]}"
else
  python3 "$SCRIPT_DIR/diff_histograms.py" \
    --top "$TOP" \
    --label-a "$LABEL_A" --label-b "$LABEL_B" \
    --bucket "$BUCKET" \
    "${HISTOGRAMS[0]}" "${HISTOGRAMS[1]}" "${HISTOGRAMS[2]}" "${HISTOGRAMS[3]}"
fi

echo
echo "histograms saved to: $WORKSPACE" >&2
