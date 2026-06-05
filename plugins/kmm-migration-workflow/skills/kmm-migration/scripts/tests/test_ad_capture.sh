#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
# stub agent-device: emits one interactive element line
cat > "$tmp/ad-stub" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  snapshot) echo '@e1 [text] "₹1,200.50"';;
  *) : ;;
esac
STUB
chmod +x "$tmp/ad-stub"
AD_BIN="$tmp/ad-stub" bash "$here/../ad-capture.sh" --device emu --journey holdings \
  --checkpoint c1 --anchor txt_total --out "$tmp/cp.json"
python3 - "$tmp/cp.json" <<'PY'
import json,sys
cp=json.load(open(sys.argv[1]))
assert cp["journey"]=="holdings" and cp["checkpoint"]=="c1" and cp["anchor"]=="txt_total"
assert isinstance(cp["elements"],list) and len(cp["elements"])>=1
print("ok")
PY
