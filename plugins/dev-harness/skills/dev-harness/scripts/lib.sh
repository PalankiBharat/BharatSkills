#!/usr/bin/env bash
# lib.sh — shared notepad helpers for the harness. Sourced, never run directly.
# A run's state lives under HARNESS_ROOT (".../.harness"). Four roles; personas
# resolve to role keys for routing. Functions are small and side-effect-explicit.

HARNESS_ROLES="tech-lead dev qa architect"

_valid_role() {
  case " $HARNESS_ROLES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# resolve_role <name-or-role> -> role key on stdout; non-zero if unknown/ambiguous.
resolve_role() {
  local key; key="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$key" in
    tech-lead|dev|qa|architect) printf '%s' "$key" ;;
    manish)                     printf 'tech-lead' ;;
    mohit-dev|bharat-dev)       printf 'dev' ;;
    rohit|bharat-qa)            printf 'qa' ;;
    mohit-arch)                 printf 'architect' ;;
    *) echo "unresolved role/name: $1" >&2; return 3 ;;
  esac
}

harness_init_layout() {
  local root="$1" r
  mkdir -p "$root/artifacts"
  for r in $HARNESS_ROLES; do
    mkdir -p "$root/$r"
    : > "$root/$r/inbox.md"
    : > "$root/$r/outbox.md"
    : > "$root/$r/feedback.md"
    : > "$root/$r/worklog.md"
    printf 'idle\n' > "$root/$r/status"
  done
  : > "$root/story.md"
  : > "$root/log.md"
}

set_status() {
  local root="$1" role="$2" value="$3"
  _valid_role "$role" || { echo "unknown role: $role" >&2; return 2; }
  printf '%s\n' "$value" > "$root/$role/status"
}

get_status() {
  local root="$1" role="$2"
  _valid_role "$role" || { echo "unknown role: $role" >&2; return 2; }
  tr -d '\n' < "$root/$role/status"
}

# pick_serial <adb-devices-output> -> the single online serial on stdout.
# Returns 2 if none online, 3 if more than one (caller must pass --serial).
pick_serial() {
  local serials n
  serials="$(printf '%s\n' "$1" | awk '$2=="device"{print $1}')"
  n="$(printf '%s' "$serials" | grep -c .)"
  [ "$n" -eq 0 ] && { echo "no online emulator/device" >&2; return 2; }
  [ "$n" -gt 1 ] && { echo "multiple devices online; pass --serial" >&2; return 3; }
  printf '%s' "$serials"
}

# lead_persona <role> -> the opus lead agent name for that pane.
lead_persona() {
  case "$1" in
    tech-lead) echo manish ;;
    dev)       echo mohit-dev ;;
    qa)        echo rohit ;;
    architect) echo mohit-arch ;;
    *) return 1 ;;
  esac
}

# _strip_frontmatter <file> -> the file body with leading YAML frontmatter removed.
_strip_frontmatter() {
  awk 'BEGIN{f=0} /^---[[:space:]]*$/{f++; next} f>=2{print}' "$1"
}

# redact_secrets — filter stdin->stdout, masking common secret/token shapes.
# Security rail: applied before any artifact (feedback, worklog, log, PR body) is written.
redact_secrets() {
  sed -E \
    -e 's/ghp_[A-Za-z0-9]{20,}/***REDACTED***/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/***REDACTED***/g' \
    -e 's/gho_[A-Za-z0-9]{20,}/***REDACTED***/g' \
    -e 's/sk-[A-Za-z0-9]{20,}/***REDACTED***/g' \
    -e 's/AKIA[0-9A-Z]{16}/***REDACTED***/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/***REDACTED***/g'
}

# preflight_missing <tool...> -> prints any tools not on PATH; non-zero if any missing.
preflight_missing() {
  local t missing=""
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  [ -z "$missing" ] && return 0
  printf '%s\n' "${missing# }"
  return 1
}

# ---- multi-run (v2): cross-run registry + heartbeat + per-run lock ----
_dh_home()       { echo "${DEV_HARNESS_HOME:-$HOME/.dev-harness}"; }
registry_path()  { echo "$(_dh_home)/registry.json"; }
_registry_init() { local rp; rp="$(registry_path)"; mkdir -p "$(dirname "$rp")"; [ -f "$rp" ] || echo '{"runs":{}}' > "$rp"; }
_registry_write(){ local rp="$1"; mv "$rp.tmp" "$rp"; }   # paired with jq > "$rp.tmp"

registry_add() {   # <run-id> <repo> <worktree> <branch> <session>
  _registry_init; local rp; rp="$(registry_path)"
  jq --arg id "$1" --arg repo "$2" --arg wt "$3" --arg br "$4" --arg ses "$5" --argjson hb "$(date +%s)" \
    '.runs[$id]={repo:$repo,worktree:$wt,branch:$br,session:$ses,status:"active",heartbeat:$hb}' \
    "$rp" > "$rp.tmp" && _registry_write "$rp"
}
registry_set() {   # <run-id> <key> <value>
  _registry_init; local rp; rp="$(registry_path)"
  jq --arg id "$1" --arg k "$2" --arg v "$3" '.runs[$id][$k]=$v' "$rp" > "$rp.tmp" && _registry_write "$rp"
}
registry_get()    { jq -r --arg id "$1" --arg k "$2" '.runs[$id][$k] // empty' "$(registry_path)" 2>/dev/null; }
registry_list()   { jq -r '.runs | keys[]' "$(registry_path)" 2>/dev/null || true; }
registry_remove() { local rp; rp="$(registry_path)"; jq --arg id "$1" 'del(.runs[$id])' "$rp" > "$rp.tmp" && _registry_write "$rp"; }
heartbeat()       { _registry_init; local rp; rp="$(registry_path)"; jq --arg id "$1" --argjson hb "$(date +%s)" '.runs[$id].heartbeat=$hb' "$rp" > "$rp.tmp" && _registry_write "$rp"; }

is_stale() {       # <run-id> [max-age-sec] -> 0 (stale) if heartbeat older than max-age (default 120)
  local hb age; hb="$(registry_get "$1" heartbeat)"
  [ -n "$hb" ] || return 0
  age=$(( $(date +%s) - hb )); [ "$age" -ge "${2:-120}" ]
}

run_lock_acquire() {   # <run-id> <owner-pid> -> 0 acquired (or already ours), 1 held by another
  local lf; lf="$(_dh_home)/locks/$1"; mkdir -p "$(dirname "$lf")"
  if [ -f "$lf" ]; then [ "$(cat "$lf")" = "$2" ] && return 0; return 1; fi
  printf '%s' "$2" > "$lf"
}
run_lock_release() {   # <run-id> <owner-pid> -> release only if we own it
  local lf; lf="$(_dh_home)/locks/$1"
  [ -f "$lf" ] && [ "$(cat "$lf")" = "$2" ] && rm -f "$lf"
  return 0
}
