#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
mkdir -p "$tmp/orchestration"

# stub claude: pretends to be the worker — writes a COMPLETE status then exits 0
cat > "$tmp/claude" <<STUB
#!/usr/bin/env bash
echo "COMPLETE" > "$tmp/orchestration/phase-D.status"
exit 0
STUB
chmod +x "$tmp/claude"

# stub tmux: run the command synchronously in the foreground instead of a window
cat > "$tmp/tmux" <<'STUB'
#!/usr/bin/env bash
# only support: new-window -d -P -t <s> -n <n> -- <cmd...>  and  wait-for
case "$1" in
  new-window) shift; while [[ "$1" != "--" ]]; do shift; done; shift; "$@" ;;
  *) : ;;
esac
STUB
chmod +x "$tmp/tmux"

PATH="$tmp:$PATH" ORCH_DIR="$tmp/orchestration" \
  bash "$here/../run-phase-worker.sh" D > "$tmp/out.txt"
[[ "$(cat "$tmp/out.txt")" == "COMPLETE" ]] || { echo "FAIL: stdout must be EXACTLY 'COMPLETE', got:"; cat "$tmp/out.txt"; exit 1; }

# crash case: claude exits non-zero without writing a status → FAILED
cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
rm -f "$tmp/orchestration/phase-E.status"
PATH="$tmp:$PATH" ORCH_DIR="$tmp/orchestration" \
  bash "$here/../run-phase-worker.sh" E > "$tmp/out2.txt"
grep -q "^FAILED" "$tmp/out2.txt" || { echo "FAIL: expected FAILED on crash"; cat "$tmp/out2.txt"; exit 1; }
echo "ok"
