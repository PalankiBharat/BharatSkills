#!/usr/bin/env bash
# watchdog.sh <root> <orchestrator-pane> — deterministic, FILE-BASED liveness for the harness.
#
# It never screen-scrapes to judge liveness (that proved fragile). A role's "alive" signal is the
# newest MTIME of files the harness owns: .harness/<role>/worklog.md (the agent appends a line per
# step) and .harness/<role>/activity.log (a long build/test tee'd via .harness/run). The only screen
# WRITES are nudges (send-keys) — never reads.
#
# Per `working` role:
#   - never woke (no activity since dispatch, past boot grace) -> ONE wake nudge.
#   - alive (recent activity)                                  -> stay quiet.
#   - stuck (working but no activity > STUCK)                  -> ONE gentle check-in;
#       still no activity after CHECKIN_GRACE                  -> ESCALATE to the user (via orchestrator).
# Plus: when the in_flight role SETTLES (done|blocked) -> wake the orchestrator. Self-reaps when the
# orchestrator pane disappears. Stops on <root>/.stop-watchdog.
#
# Test seams: WATCHDOG_INTERVAL, WATCHDOG_BOOT_GRACE, WATCHDOG_STUCK, WATCHDOG_CHECKIN_GRACE, and
# WATCHDOG_WAKE_CMD (called with a tagged message instead of tmux; also disables self-reap/skip-real-send).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"   # HARNESS_ROLES
ROOT="${1:?usage: watchdog.sh <root> <orchestrator-pane>}"
OPANE="${2:?orchestrator pane id}"
STATE="$ROOT/state.json"
INTERVAL="${WATCHDOG_INTERVAL:-15}"
BOOT_GRACE="${WATCHDOG_BOOT_GRACE:-30}"
# STUCK/CHECKIN_GRACE are deliberately LONG: real agents think/compute for 20-30 min in a single
# stretch (observed live). A false "stuck -> pause the run" is the costly outcome, so we only act
# after sustained silence across ALL liveness signals.
STUCK="${WATCHDOG_STUCK:-1800}"            # 30m of no activity before a gentle check-in
CHECKIN_GRACE="${WATCHDOG_CHECKIN_GRACE:-600}"   # +10m re-confirmed silence before escalating
PROJECTS_DIR="${WATCHDOG_PROJECTS_DIR:-$HOME/.claude/projects}"
# Periodic full-pane SWEEP: every SWEEP_INTERVAL, regardless of in_flight, report every
# role's status+activity and nudge the orchestrator to RECONCILE ALL panes. This is the
# safety net for a missed settle / a dropped poll — the orchestrator can otherwise sit
# polling one role while another already went done/blocked unnoticed.
SWEEP_INTERVAL="${WATCHDOG_SWEEP_INTERVAL:-300}"   # 5m

_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
_now()   { date +%s; }

# Newest activity mtime for a role across ALL signals the harness can see WITHOUT screen-scraping:
#   worklog.md   — per-step breadcrumb the agent appends
#   activity.log — a long build/test tee'd via .harness/run (alive during a 12-min gradle)
#   transcript   — the agent's own Claude session jsonl (advances during pure THINKING, no tool
#                  call needed); located via the session id the agent records in .harness/<role>/session.
# The transcript is what stops a long think from looking "stuck" — it's written by Claude Code
# itself, so it doesn't depend on the agent remembering to log.
last_activity() {
  local m w a t sid tx; m=0
  w="$(_mtime "$ROOT/$1/worklog.md")";  [ "$w" -gt "$m" ] && m="$w"
  a="$(_mtime "$ROOT/$1/activity.log")"; [ "$a" -gt "$m" ] && m="$a"
  sid="$(cat "$ROOT/$1/session" 2>/dev/null)"
  if [ -n "$sid" ]; then
    tx="$(ls "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | head -1)"
    [ -n "$tx" ] && { t="$(_mtime "$tx")"; [ "$t" -gt "$m" ] && m="$t"; }
  fi
  echo "$m"
}

# send a tagged message to a pane (or to the test hook). Text is tagged for testability.
send_pane() {  # <pane> <text>
  if [ -n "${WATCHDOG_WAKE_CMD:-}" ]; then "$WATCHDOG_WAKE_CMD" "$2"; return; fi
  tmux send-keys -t "$1" -l "$2" 2>/dev/null || true
  sleep 0.4
  tmux send-keys -t "$1" Enter 2>/dev/null || true
}
pane_of() { cat "$ROOT/$1/pane" 2>/dev/null; }

settle_last=""
sweep_last="$(_now)"   # first sweep one full interval after boot (panes are still starting)
while :; do
  sleep "$INTERVAL"
  [ -f "$ROOT/.stop-watchdog" ] && break
  # Self-reap when the orchestrator pane is gone (window closed/crash) — never poll forever.
  [ -z "${WATCHDOG_WAKE_CMD:-}" ] && { pane_alive "$OPANE" || break; }
  now="$(_now)"

  # ---- periodic SWEEP: reconcile ALL panes (runs before any early `continue` below) ----
  if [ $(( now - sweep_last )) -ge "$SWEEP_INTERVAL" ]; then
    sweep_last="$now"
    report=""
    for r in $HARNESS_ROLES; do
      st="?"; [ -f "$ROOT/$r/status" ] && st="$(tr -d '\n' < "$ROOT/$r/status")"
      report="$report$r=$st($(( now - $(last_activity "$r") ))s) "
    done
    printf '%s | SWEEP %s\n' "$(date -u +%FT%TZ)" "$report" >> "$ROOT/log.md"
    send_pane "$OPANE" "SWEEP Reconcile ALL panes now — re-read each role's status file (not memory): $report. Handle any done/blocked you haven't acted on; if you stopped polling, resume. Don't stop until the run is done, blocked, or needs the user."
  fi

  # ---- per-role liveness (independent of in_flight; the sole nudge path, also sandbox-safe) ----
  for r in $HARNESS_ROLES; do
    [ -f "$ROOT/$r/status" ] && [ "$(tr -d '\n' < "$ROOT/$r/status")" = "working" ] || continue
    smt="$(_mtime "$ROOT/$r/status")"        # dispatch time (send.sh wrote status=working)
    act="$(last_activity "$r")"
    p="$(pane_of "$r")"; [ -n "$p" ] || continue

    if [ "$act" -le "$smt" ]; then
      # never woke since dispatch. After boot grace, send ONE wake (marker prevents repeats per dispatch).
      [ $(( now - smt )) -lt "$BOOT_GRACE" ] && continue
      [ "$(_mtime "$ROOT/$r/.wd-wake")" -gt "$smt" ] && continue   # already woke this dispatch
      : > "$ROOT/$r/.wd-wake"
      send_pane "$p" "WAKE Read .harness/$r/inbox.md and do exactly that now; first append a 'started' line to .harness/$r/worklog.md; when finished run: bash .harness/done $r"
      continue
    fi

    # woke + progressing. Only act if it has gone silent for too long.
    [ $(( now - act )) -lt "$STUCK" ] && continue
    if [ "$(_mtime "$ROOT/$r/.wd-checkin")" -le "$act" ]; then
      : > "$ROOT/$r/.wd-checkin"
      send_pane "$p" "CHECKIN Status check: if you're still working, append one line to .harness/$r/worklog.md and continue. If you're done or blocked, run: bash .harness/done $r [blocked]"
      continue
    fi
    # checked-in already and STILL silent past the grace -> escalate to the user via the orchestrator.
    [ $(( now - $(_mtime "$ROOT/$r/.wd-checkin") )) -lt "$CHECKIN_GRACE" ] && continue
    [ "$(_mtime "$ROOT/$r/.wd-escalate")" -gt "$act" ] && continue
    : > "$ROOT/$r/.wd-escalate"
    printf '%s | WATCHDOG: %s stuck — no activity for >%ss, no response to check-in. Surface to user.\n' \
      "$(date -u +%FT%TZ)" "$r" "$STUCK" >> "$ROOT/log.md"
    send_pane "$OPANE" "ESCALATE The '$r' pane is STUCK — no activity for over $((STUCK/60))m and no response to a status check. Stop polling it; tell the user it needs attention (it may be rate-limited or hung), and pause the run."
  done

  # ---- settle wake: in_flight role done|blocked -> wake the orchestrator to advance ----
  [ -f "$STATE" ] || continue
  R="$(jq -r '.in_flight // empty' "$STATE" 2>/dev/null)" || continue
  [ -n "$R" ] || { settle_last=""; continue; }
  R="${R%%:*}"
  [ -f "$ROOT/$R/status" ] || continue
  S="$(tr -d '\n' < "$ROOT/$R/status")"
  case "$S" in done|blocked) ;; *) continue ;; esac
  key="$R:$S:$(_mtime "$ROOT/$R/status")"
  [ "$key" = "$settle_last" ] && continue
  settle_last="$key"
  send_pane "$OPANE" "SETTLE The '$R' pane settled with status '$S'. Continue driving now — verify its artifact, run the needs-user gate, then dispatch the next step or pause. Don't stop until the run is done, blocked, or needs the user."
done
