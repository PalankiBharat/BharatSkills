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
# Path-independent driver wrappers so the Orchestrator persona dispatches/polls with
# stable commands (`bash .harness/send <role> "<msg>"`, `bash .harness/poll <role> [--settle]`)
# without knowing the plugin's install path.
# HARNESS_ROOT is baked in so the scripts never depend on the caller's cwd (a `git
# rev-parse` fallback dies the moment the orchestrator runs them from elsewhere).
cat > "$ROOT/send" <<EOF
#!/usr/bin/env bash
exec env HARNESS_ROOT="$ROOT" bash "$HERE/send.sh" --role "\$1" --message "\$2"
EOF
chmod +x "$ROOT/send"
cat > "$ROOT/poll" <<EOF
#!/usr/bin/env bash
role="\$1"; shift
exec env HARNESS_ROOT="$ROOT" bash "$HERE/poll.sh" --role "\$role" "\$@"
EOF
chmod +x "$ROOT/poll"
# Render the structured needs-user questionnaire form: `bash .harness/ask <questions.json>`.
cat > "$ROOT/ask" <<EOF
#!/usr/bin/env bash
exec env HARNESS_ROOT="$ROOT" bash "$HERE/render-questions.sh" "\$@"
EOF
chmod +x "$ROOT/ask"
# Activity wrapper: `bash .harness/run <role> -- <cmd...>` runs a (possibly long) command and tees its
# combined output to .harness/<role>/activity.log. The log's MTIME is the "alive right now" signal the
# watchdog watches — so a 12-min gradle build reads as alive (the agent can't write a worklog line while
# blocked inside one tool call). Forwards the command's real exit code (pipefail + PIPESTATUS).
cat > "$ROOT/run" <<EOF
#!/usr/bin/env bash
set -o pipefail
role="\$1"; shift
[ "\${1:-}" = "--" ] && shift
log="$ROOT/\$role/activity.log"
[ -d "$ROOT/\$role" ] || { echo "unknown role: \$role" >&2; exit 2; }
"\$@" 2>&1 | tee -a "\$log"
exit "\${PIPESTATUS[0]}"
EOF
chmod +x "$ROOT/run"
# Gate-resume: `bash .harness/answer <role> "<verbatim user answers>"` re-dispatches the role to
# incorporate the answers ITSELF — so the Orchestrator routes the answers and never reconciles/analyzes.
cat > "$ROOT/answer" <<EOF
#!/usr/bin/env bash
role="\$1"; shift
msg="RESUME — the user answered the open questions. Incorporate their verbatim answers below into your work (revise the relevant artifact), resolve the gate, then signal done. Do not re-ask; do not wait for more input on these.

\$*"
exec env HARNESS_ROOT="$ROOT" bash "$HERE/send.sh" --role "\$role" --message "\$msg"
EOF
chmod +x "$ROOT/answer"
# Artifact gate: `bash .harness/require <file...>` exits non-zero if any is missing/empty. The
# Orchestrator runs it before accepting a role's `done` — a missing required output => re-dispatch.
cat > "$ROOT/require" <<'EOF'
#!/usr/bin/env bash
miss=0
for f in "$@"; do [ -s "$f" ] || { echo "MISSING/EMPTY: $f" >&2; miss=1; }; done
exit $miss
EOF
chmod +x "$ROOT/require"
# Resume after a session reset: `bash .harness/resume` restarts the orchestrator pane if it's alive.
cat > "$ROOT/resume" <<EOF
#!/usr/bin/env bash
exec env HARNESS_ROOT="$ROOT" bash "$HERE/harness-resume.sh" "\$@"
EOF
chmod +x "$ROOT/resume"
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

# Pre-accept Claude's folder-trust for this repo so panes don't stall at the trust dialog
# (fresh/worktree dirs always show it; under --sandbox a stuck role pane can't be nudged out).
# Idempotent + atomic; no-op if jq or ~/.claude.json is absent.
trust_workdir() {
  local cj="$HOME/.claude.json" d="$1" tmp
  { [ -f "$cj" ] && command -v jq >/dev/null; } || return 0
  tmp="$(mktemp)" || return 0
  if jq --arg d "$d" '.projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted:true, hasCompletedProjectOnboarding:true})' "$cj" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$cj"
  else
    rm -f "$tmp"
  fi
}
if [ "$DO_TMUX" -eq 1 ]; then
  # Must be INSIDE tmux — never create a detached session you can't see.
  [ -n "${TMUX:-}" ] || {
    echo "dev-harness needs a tmux session. Start one (\`tmux\`) and run /harness from inside it." >&2
    exit 6; }
  trust_workdir "$PWD"; trust_workdir "$(pwd -P)"
  SBX=""; [ "$DO_SANDBOX" -eq 1 ] && SBX="HARNESS_SANDBOX=1 "
  # A NEW window in the CURRENT session, named after the branch. Pane 0 = live log.
  tmux new-window -n "$WIN" -c "$PWD" "exec tail -f '$ROOT/log.md'" \
    || { echo "could not open the harness window (terminal too small?)" >&2; exit 7; }
  # The Orchestrator pane — the visible, persistent driver (claude --agent orchestrator).
  # It replaces the old invisible main-session driver, so it can never "kill itself".
  opid="$(tmux split-window -t "$WIN" -c "$PWD" -P -F '#{pane_id}' "${SBX}exec bash '$HERE/agent-pane.sh' orchestrator" 2>/dev/null)" \
    || { echo "could not split the harness window for the orchestrator (terminal too small for 6 panes?)" >&2; exit 7; }
  printf '%s\n' "$opid" > "$ROOT/orchestrator/pane"
  tmux select-layout -t "$WIN" tiled >/dev/null 2>&1 || true
  # One pane per agent — a visible interactive Claude as that persona. Record each pane id.
  for r in tech-lead dev qa architect; do
    pid="$(tmux split-window -t "$WIN" -c "$PWD" -P -F '#{pane_id}' "${SBX}exec bash '$HERE/agent-pane.sh' $r" 2>/dev/null)" \
      || { echo "could not split the harness window for '$r' (terminal too small for 6 panes?)" >&2; exit 7; }
    printf '%s\n' "$pid" > "$ROOT/$r/pane"
    tmux select-layout -t "$WIN" tiled >/dev/null 2>&1 || true
  done
  tmux select-layout -t "$WIN" tiled >/dev/null 2>&1 || true

  # Per-pane model switch for /model-only modes (e.g. opusplan): these can't be a launch
  # flag, so once the pane's Claude has booted we send `/model <mode>` the same way we nudge
  # (literal text, pause, separate Enter). Launch-flag models were already set in agent-pane.
  ( sleep 8
    for r in orchestrator tech-lead dev qa architect; do
      m="$(role_model "$r" 2>/dev/null || echo opus)"
      is_launch_model "$m" && continue
      pane="$(cat "$ROOT/$r/pane" 2>/dev/null)"; [ -n "$pane" ] || continue
      tmux send-keys -t "$pane" -l "/model $m" 2>/dev/null || true; sleep 0.5
      tmux send-keys -t "$pane" Enter 2>/dev/null || true
    done
  ) >/dev/null 2>&1 &

  # Self-start the driver: write its standing order, let Claude boot, then nudge it.
  # From here the main session is LAUNCHER-ONLY — it must not also drive state.json.
  printf 'BEGIN. Drive the run for the story in .harness/story.md.\nDispatch the Tech Lead first, then loop: poll, advance on settle, pause for the user only at needs-user gates. Stay in your turn until the run is done, blocked, or needs the user.\n' \
    > "$ROOT/orchestrator/inbox.md"
  NUDGE="Read .harness/orchestrator/inbox.md and begin driving the run now."
  ( # Heavy envs can take 10-20s for `claude` to boot. Nudge, then re-nudge on a long
    # gap ONLY while it still hasn't dispatched (tech-lead inbox empty) — so a run already
    # underway is never interrupted, but a missed-nudge idle start self-heals.
    sleep 6
    tmux send-keys -t "$opid" -l "$NUDGE" 2>/dev/null || true; sleep 0.4
    tmux send-keys -t "$opid" Enter 2>/dev/null || true
    for _ in 1 2 3 4; do
      sleep 30
      [ -s "$ROOT/tech-lead/inbox.md" ] && break
      tmux send-keys -t "$opid" -l "$NUDGE" 2>/dev/null || true; sleep 0.4
      tmux send-keys -t "$opid" Enter 2>/dev/null || true
    done
  ) >/dev/null 2>&1 &
  # Liveness watchdog — re-wakes the Orchestrator whenever the in-flight role settles, so
  # the run advances even if the LLM ended its turn. Backgrounded; retires on .stop-watchdog,
  # and self-reaps when its orchestrator pane disappears. Kill any stale one for this run first.
  pkill -f "watchdog.sh $ROOT " 2>/dev/null || true
  rm -f "$ROOT/.stop-watchdog"
  nohup bash "$HERE/watchdog.sh" "$ROOT" "$opid" >"$ROOT/watchdog.log" 2>&1 &
fi

echo "$ROOT"
