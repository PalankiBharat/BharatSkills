#!/usr/bin/env bash
# harness-init.sh — bootstrap a harness run.
#   harness-init.sh --story "<text>" --slug <slug> [--serial <s>]
#                   [--no-branch] [--no-tmux] [--no-emulator]
# Builds the .harness/ notepad, the run's state.json, gitignores .harness/, captures
# a booted emulator serial, and (live) creates the feature branch + 5-pane tmux window.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
CLAUDE_BIN="${CLAUDE_BIN:-/opt/homebrew/bin/claude}"   # never the zsh shell-function

STORY="" SLUG="" SERIAL="" DO_BRANCH=1 DO_TMUX=1 DO_EMU=1 DO_SANDBOX=0 DO_WORKTREE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --no-branch) DO_BRANCH=0; shift ;;
    --no-tmux) DO_TMUX=0; shift ;;
    --no-emulator) DO_EMU=0; shift ;;
    --sandbox) DO_SANDBOX=1; shift ;;
    --worktree) DO_WORKTREE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORY" ] && [ -n "$SLUG" ] || { echo "usage: harness-init.sh --story <s> --slug <slug>" >&2; exit 2; }
[ -d .git ] || { echo "run from a git repo root" >&2; exit 2; }

DATE="$(date +%Y%m%d)"; RUN_ID="$SLUG-$(date +%Y%m%d-%H%M%S)"; BRANCH="harness/$SLUG-$DATE"
WIN="harness-$SLUG-$DATE"   # tmux window name carries the branch identity

# Preflight only the tools the requested live features actually need.
preflight() {
  local need="git jq"
  [ "$DO_TMUX" -eq 1 ] && need="$need tmux $CLAUDE_BIN"
  [ "$DO_EMU" -eq 1 ] && need="$need adb maestro"
  local missing; missing="$(preflight_missing $need)" || {
    echo "PREFLIGHT FAILED — install/PATH these first: $missing" >&2; exit 5; }
}
preflight

if [ "$DO_WORKTREE" -eq 1 ]; then
  WORKTREE_DIR="$PWD/.harness-worktrees/$RUN_ID"
  git worktree add -b "$BRANCH" "$WORKTREE_DIR" 2>/dev/null || git worktree add "$WORKTREE_DIR"
  cd "$WORKTREE_DIR"
elif [ "$DO_BRANCH" -eq 1 ]; then
  git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
fi
ROOT="$PWD/.harness"

harness_init_layout "$ROOT"
# Completion sentinel an agent runs as its last action: `bash .harness/done <role> [done|blocked]`.
cat > "$ROOT/done" <<'DONE'
#!/usr/bin/env bash
set -eu
ROLE="${1:?usage: done <role> [done|blocked]}"; STATE="${2:-done}"
HR="$(cd "$(dirname "$0")" && pwd)"
case "$STATE" in done|blocked) ;; *) echo "state must be done|blocked" >&2; exit 2 ;; esac
printf '%s\n' "$STATE" > "$HR/$ROLE/status"
printf '%s [%s] sentinel: %s\n' "$(date +%H:%M:%S)" "$ROLE" "$STATE" >> "$HR/$ROLE/worklog.md"
DONE
chmod +x "$ROOT/done"
printf '%s\n' "$STORY" > "$ROOT/story.md"
printf '# Orchestrator ledger\n\n- init  run=%s  branch=%s\n' "$RUN_ID" "$BRANCH" > "$ROOT/log.md"
printf '{"run_id":"%s","slug":"%s","branch":"%s","stage":"init","phase":null,"in_flight":null,"heartbeat":"%s"}\n' \
  "$RUN_ID" "$SLUG" "$BRANCH" "$(date -u +%FT%TZ)" > "$ROOT/state.json"

registry_add "$RUN_ID" "$PWD" "$PWD" "$BRANCH" "$WIN"   # cross-run registry (v2)

grep -q '^\.harness/$' .gitignore 2>/dev/null || printf '\n.harness/\n' >> .gitignore
grep -q '^\.harness-worktrees/$' .gitignore 2>/dev/null || printf '.harness-worktrees/\n' >> .gitignore

if [ "$DO_EMU" -eq 1 ]; then
  if [ -z "$SERIAL" ]; then SERIAL="$(pick_serial "$(adb devices)")"; fi
  printf '%s\n' "$SERIAL" > "$ROOT/qa/emulator.lock"
fi

if [ "$DO_TMUX" -eq 1 ]; then
  # Must be INSIDE tmux — never create a detached session you can't see.
  [ -n "${TMUX:-}" ] || {
    echo "dev-harness needs a tmux session. Start one (\`tmux\`) and run /harness from inside it." >&2
    exit 6; }
  SBX=""; [ "$DO_SANDBOX" -eq 1 ] && SBX="HARNESS_SANDBOX=1 "
  # A NEW window in the CURRENT session, named after the branch. Pane 0 = live log.
  tmux new-window -n "$WIN" -c "$PWD" "exec tail -f '$ROOT/log.md'" \
    || { echo "could not open the harness window (terminal too small?)" >&2; exit 7; }
  # One pane per agent — a visible interactive Claude as that persona. Record each pane id.
  for r in tech-lead dev qa architect; do
    pid="$(tmux split-window -t "$WIN" -c "$PWD" -P -F '#{pane_id}' "${SBX}exec bash '$HERE/agent-pane.sh' $r" 2>/dev/null)" \
      || { echo "could not split the harness window for '$r' (terminal too small for 5 panes?)" >&2; exit 7; }
    printf '%s\n' "$pid" > "$ROOT/$r/pane"
    tmux select-layout -t "$WIN" tiled >/dev/null 2>&1 || true
  done
  tmux select-layout -t "$WIN" tiled >/dev/null 2>&1 || true
fi

echo "$ROOT"
