#!/usr/bin/env bash
# Contract for the merged team personas: one pane per role, no sub-workers.
#   tech-lead=manish · dev=bharat · qa=rohit · architect=mohit (+ orchestrator)
# Locks the strict rules that came out of live failures.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
AG="$HERE/../../../agents"

tools_line() { sed -n '1,8p' "$1" | grep -iE '^tools:'; }

# --- the team is exactly these five files; the retired personas are gone ---
for p in manish bharat rohit mohit orchestrator; do assert_file "$AG/$p.md"; done
for old in mohit-dev bharat-dev bharat-qa mohit-arch; do
  [ -f "$AG/$old.md" ] && _FAIL "retired persona file still present: $old.md"
done

# --- no role spawns sub-workers anymore: no Agent tool anywhere ---
for p in manish bharat rohit mohit orchestrator; do
  case "$(tools_line "$AG/$p.md")" in *Agent*) _FAIL "$p must not grant the Agent tool (no sub-workers)";; esac
done

# --- Bharat = the sole Dev: figma mandatory, never decides, plans+codes itself ---
assert_contains "$(cat "$AG/bharat.md")" "figma-to-compose"
assert_contains "$(cat "$AG/bharat.md")" "MANDATORY"
assert_contains "$(cat "$AG/bharat.md")" "do NOT make decisions"
assert_contains "$(cat "$AG/bharat.md")" "ask and stop"

# --- Rohit = the sole QA: real user + analyst, structured coverage, context hygiene, runs Maestro itself ---
assert_contains "$(cat "$AG/rohit.md")" "real-world user"
assert_contains "$(cat "$AG/rohit.md")" "qa-cases.md"
assert_contains "$(cat "$AG/rohit.md")" "never read screenshots"
for cat in "Invalid" "Boundary" "Interruption" "network"; do
  assert_contains "$(cat "$AG/rohit.md")" "$cat"
done

# --- Mohit = Architect: technical design + quality review, never UI ---
assert_contains "$(cat "$AG/mohit.md")" "never touch UI"

# --- HARD RULE on EVERY worker: missing input -> ask the user, never assume/fabricate ---
for p in manish bharat rohit mohit; do
  assert_contains "$(cat "$AG/$p.md")" "ASK — never assume"
done
# --- the orchestrator routes a blocked-with-question to the user, never answers it ---
assert_contains "$(cat "$AG/orchestrator.md")" "needs-user gate"

# --- Orchestrator: coverage gate + final regression + SWEEP + figma + dev-doubt = user gate ---
assert_contains "$(cat "$AG/orchestrator.md")" "Final QA regression"
assert_contains "$(cat "$AG/orchestrator.md")" "qa-cases.md"
assert_contains "$(cat "$AG/orchestrator.md")" "restart qa"
assert_contains "$(cat "$AG/orchestrator.md")" "SWEEP"
assert_contains "$(cat "$AG/orchestrator.md")" "figma-to-compose"
assert_contains "$(cat "$AG/orchestrator.md")" "user gate"

echo OK
