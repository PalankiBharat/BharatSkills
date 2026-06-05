#!/usr/bin/env bash
# Contract for agent-pane.sh — the exact `claude` launch line per role. We stub CLAUDE_BIN
# with a recorder so no real Claude (and no tokens) are spawned; the recorder captures argv.
# This locks the model-pinning fix: deep panes get --model opus, build lanes (opusplan) get
# NO --model (switched post-boot), and HARNESS_MODEL[_ROLE] overrides win.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
PANE="$HERE/../scripts/agent-pane.sh"

T="$(mktemp -d)"
REC="$T/fakeclaude"
cat > "$REC" <<'SH'
#!/usr/bin/env bash
printf '%s ' "$@" > "$ARGV_OUT"
SH
chmod +x "$REC"

# launch <role> [env assignments...] -> the recorded argv string for that role.
launch() {
  _role="$1"; shift
  _out="$T/argv.$_role"
  env "$@" CLAUDE_BIN="$REC" ARGV_OUT="$_out" bash "$PANE" "$_role" >/dev/null 2>&1
  cat "$_out"
}

# --- every pane launches as its persona with bypass perms ---
assert_contains "$(launch orchestrator)" "--agent orchestrator"
assert_contains "$(launch tech-lead)"    "--agent manish"
assert_contains "$(launch dev)"          "--agent mohit-dev"
assert_contains "$(launch qa)"           "--agent rohit"
assert_contains "$(launch architect)"    "--agent mohit-arch"
assert_contains "$(launch dev)"          "--permission-mode bypassPermissions"

# --- deep panes are pinned to opus at launch ---
assert_contains "$(launch orchestrator)" "--model opus"
assert_contains "$(launch tech-lead)"    "--model opus"
assert_contains "$(launch architect)"    "--model opus"

# --- build lanes default to opusplan, which is NOT a launch flag -> no --model ---
case "$(launch dev)" in *"--model"*) _FAIL "dev (opusplan) must not pass --model at launch";; esac
case "$(launch qa)"  in *"--model"*) _FAIL "qa (opusplan) must not pass --model at launch";; esac

# --- per-role override turns a build lane into a real launch-flag model ---
assert_contains "$(launch dev HARNESS_MODEL_DEV=sonnet)" "--model sonnet"
# --- global override applies to a deep pane too ---
assert_contains "$(launch architect HARNESS_MODEL=haiku)" "--model haiku"
# --- per-role key beats the global default ---
assert_contains "$(launch qa HARNESS_MODEL=opus HARNESS_MODEL_QA=sonnet)" "--model sonnet"

rm -rf "$T"
echo OK
