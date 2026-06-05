#!/usr/bin/env bash
# Contract for lib.sh — the shared-notepad helpers (roles, layout, status, name->role).
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"

ROLES="tech-lead dev qa architect"
T="$(mktemp -d)"; ROOT="$T/.harness"

# --- layout ---
harness_init_layout "$ROOT"
for r in $ROLES; do
  assert_dir  "$ROOT/$r"
  assert_file "$ROOT/$r/inbox.md"
  assert_file "$ROOT/$r/outbox.md"
  assert_file "$ROOT/$r/feedback.md"
  assert_file "$ROOT/$r/worklog.md"
  assert_file "$ROOT/$r/status"
  assert_eq "$(get_status "$ROOT" "$r")" "idle"
done
assert_dir  "$ROOT/artifacts"
assert_file "$ROOT/story.md"
assert_file "$ROOT/log.md"

# --- status get/set ---
set_status "$ROOT" dev working
assert_eq "$(get_status "$ROOT" dev)" "working"

# --- unknown role is rejected (non-zero, no write) ---
( set_status "$ROOT" hacker working 2>/dev/null ) && _FAIL "should refuse unknown role"

# --- name -> role resolution (personas AND role keys) ---
assert_eq "$(resolve_role manish)"    "tech-lead"
assert_eq "$(resolve_role Manish)"    "tech-lead"   # case-insensitive
assert_eq "$(resolve_role mohit-dev)" "dev"
assert_eq "$(resolve_role bharat-dev)" "dev"
assert_eq "$(resolve_role rohit)"     "qa"
assert_eq "$(resolve_role bharat-qa)" "qa"
assert_eq "$(resolve_role mohit-arch)" "architect"
assert_eq "$(resolve_role dev)"       "dev"         # a role key resolves to itself
assert_eq "$(resolve_role architect)" "architect"

# --- ambiguous first name (Mohit = Dev or Arch) is refused ---
( resolve_role mohit 2>/dev/null ) && _FAIL "ambiguous 'mohit' should be refused"
# --- unknown name is refused ---
( resolve_role nobody 2>/dev/null ) && _FAIL "unknown name should be refused"

# --- role_model: per-role defaults (deep panes opus, build lanes opusplan) ---
assert_eq "$(role_model orchestrator)" "opus"
assert_eq "$(role_model tech-lead)"    "opus"
assert_eq "$(role_model architect)"    "opus"
assert_eq "$(role_model dev)"          "opusplan"
assert_eq "$(role_model qa)"           "opusplan"

# --- role_model: per-role env override wins (hyphen role -> underscored env key) ---
assert_eq "$(HARNESS_MODEL_DEV=sonnet role_model dev)"            "sonnet"
assert_eq "$(HARNESS_MODEL_TECH_LEAD=haiku role_model tech-lead)" "haiku"
# --- role_model: global override applies when no per-role key ---
assert_eq "$(HARNESS_MODEL=opus role_model dev)"                  "opus"
# --- role_model: per-role key beats the global default ---
assert_eq "$(HARNESS_MODEL=opus HARNESS_MODEL_QA=sonnet role_model qa)" "sonnet"

# --- is_launch_model: aliases + full ids are launch-flag; /model modes are not ---
for m in opus sonnet haiku claude-opus-4-8; do
  is_launch_model "$m" || _FAIL "$m should be a launch-flag model"
done
is_launch_model opusplan && _FAIL "opusplan must NOT be a launch-flag model"

echo OK
