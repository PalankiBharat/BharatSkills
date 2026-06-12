#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# stub tmux: log every invocation; report session-absent so the script creates it
cat > "$tmp/tmux" <<STUB
#!/usr/bin/env bash
echo "tmux \$*" >> "$tmp/tmux.log"
case "\$1" in
  has-session) exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$tmp/tmux"

PATH="$tmp:$PATH" KMM_AUTOPILOT_DRYRUN=1 \
  bash "$here/../kmm-autopilot.sh" funds-business-logic > "$tmp/out.txt" 2>&1

grep -q "new-session" "$tmp/tmux.log" || { echo "FAIL: should create a session"; cat "$tmp/tmux.log"; exit 1; }
grep -q "kmm-funds-business-logic" "$tmp/tmux.log" || { echo "FAIL: session name from arg"; cat "$tmp/tmux.log"; exit 1; }
grep -q "KMM_AUTOPILOT_ROLE=orchestrator" "$tmp/tmux.log" || { echo "FAIL: orchestrator role not set"; cat "$tmp/tmux.log"; exit 1; }

# --- reuse path: session already exists → must NOT create, but still send-keys ---
cat > "$tmp/tmux" <<STUB
#!/usr/bin/env bash
echo "tmux \$*" >> "$tmp/tmux2.log"
case "\$1" in
  has-session) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$tmp/tmux"
PATH="$tmp:$PATH" KMM_AUTOPILOT_DRYRUN=1 \
  bash "$here/../kmm-autopilot.sh" funds-business-logic > "$tmp/out2.txt" 2>&1
if grep -q "new-session" "$tmp/tmux2.log"; then echo "FAIL: must NOT create a session when one exists"; cat "$tmp/tmux2.log"; exit 1; fi
grep -q "send-keys" "$tmp/tmux2.log" || { echo "FAIL: should still send-keys to the existing session"; cat "$tmp/tmux2.log"; exit 1; }
echo "ok"
