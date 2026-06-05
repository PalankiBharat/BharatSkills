#!/usr/bin/env bash
# Contract for the lead personas — the regression that made juniors never spawn:
# a lead told to dispatch its junior but whose tools: frontmatter never granted the
# Agent tool. Lock the scoped grant so execution always delegates to the sonnet junior.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
AG="$HERE/../../../agents"

tools_line() { sed -n '1,8p' "$1" | grep -iE '^tools:'; }

# --- the leads MUST grant the scoped Agent spawn tool for their own junior ---
assert_contains "$(tools_line "$AG/mohit-dev.md")" "Agent(dev-harness:bharat-dev)"
assert_contains "$(tools_line "$AG/rohit.md")"     "Agent(dev-harness:bharat-qa)"

# --- the juniors are leaf workers: they never spawn (no Agent tool) ---
case "$(tools_line "$AG/bharat-dev.md")" in *Agent*) _FAIL "bharat-dev must not grant Agent (leaf worker)";; esac
case "$(tools_line "$AG/bharat-qa.md")"  in *Agent*) _FAIL "bharat-qa must not grant Agent (leaf worker)";;  esac

# --- the personas state the delegation as a hard rule, not a preference ---
assert_contains "$(cat "$AG/mohit-dev.md")" "never type app code"
assert_contains "$(cat "$AG/mohit-dev.md")" "process failure"
assert_contains "$(cat "$AG/rohit.md")"     "never write or run test code"
assert_contains "$(cat "$AG/rohit.md")"     "process failure"

echo OK
