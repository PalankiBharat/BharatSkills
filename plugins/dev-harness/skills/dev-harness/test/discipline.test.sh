#!/usr/bin/env bash
# Pass-B primitives: .harness/answer re-dispatches a role with the user's verbatim answers (so the
# orchestrator never analyzes), and .harness/require gates `done` on real artifacts existing.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; cd "$T"; git init -q; git commit --allow-empty -qm base; export DEV_HARNESS_HOME="$T/dh"
"$HERE/../scripts/harness-init.sh" --story "x" --slug t --no-tmux --no-branch --no-emulator >/dev/null

# --- answer: routes verbatim answers into the role inbox + flips it to working (no analysis) ---
assert_file "$T/.harness/answer"
bash "$T/.harness/answer" tech-lead "b1: Pine wins; c1: drop #id"
inbox="$(cat "$T/.harness/tech-lead/inbox.md")"
assert_contains "$inbox" "RESUME"
assert_contains "$inbox" "b1: Pine wins; c1: drop #id"
assert_eq "$(cat "$T/.harness/tech-lead/status")" "working"

# --- require: non-zero when a required artifact is missing/empty, zero when present ---
assert_file "$T/.harness/require"
( bash "$T/.harness/require" "$T/.harness/artifacts/feature-analysis.md" 2>/dev/null ) && _FAIL "missing file must fail require"
: > "$T/.harness/artifacts/feature-analysis.md"   # exists but EMPTY
( bash "$T/.harness/require" "$T/.harness/artifacts/feature-analysis.md" 2>/dev/null ) && _FAIL "empty file must fail require"
printf 'real analysis\n' > "$T/.harness/artifacts/feature-analysis.md"
bash "$T/.harness/require" "$T/.harness/artifacts/feature-analysis.md" || _FAIL "non-empty file must pass require"
# multiple files: fails if ANY missing
printf 'spec\n' > "$T/.harness/artifacts/spec.md"
bash "$T/.harness/require" "$T/.harness/artifacts/spec.md" "$T/.harness/artifacts/feature-analysis.md" || _FAIL "all-present must pass"
( bash "$T/.harness/require" "$T/.harness/artifacts/spec.md" "$T/.harness/artifacts/nope.md" 2>/dev/null ) && _FAIL "any-missing must fail"
echo OK
