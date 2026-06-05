#!/usr/bin/env bash
# Drive one journey checkpoint with agent-device and emit a normalized checkpoint JSON.
# Honors AD_BIN (default: agent-device) so tests can inject a stub.
# Real network/log/crash capture flags are wired in per the M0 spike (R1) findings.
set -euo pipefail
AD="${AD_BIN:-agent-device}"
device="" journey="" checkpoint="" anchor="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device) device="$2"; shift 2;;
    --journey) journey="$2"; shift 2;;
    --checkpoint) checkpoint="$2"; shift 2;;
    --anchor) anchor="$2"; shift 2;;
    --out) out="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
snap="$("$AD" snapshot -i 2>/dev/null || true)"
# Parse '@eN [role] "text"' lines into normalized elements. computed/live default
# to false; the loop (Phase I) tags computed/live from the journey catalog metadata.
python3 - "$journey" "$checkpoint" "$anchor" "$out" <<PY
import json,re,sys
journey,checkpoint,anchor,out=sys.argv[1:5]
snap='''$snap'''
els=[]
for m in re.finditer(r'@(\S+)\s+\[([^\]]+)\]\s+"([^"]*)"', snap):
    ref,role,text=m.groups()
    els.append({"ref":ref if not ref.startswith('e') else (anchor if text else ref),
                "role":role,"text":text,"computed":False,"live":False})
# Ensure the anchor ref exists if its text was captured (stub maps first text elem).
if els and not any(e["ref"]==anchor for e in els):
    els[0]["ref"]=anchor
json.dump({"journey":journey,"checkpoint":checkpoint,"anchor":anchor,
           "elements":els,"network":[]}, open(out,"w"), indent=2)
PY
echo "wrote $out"
