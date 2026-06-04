#!/usr/bin/env bash
# role-runner passes the sandbox --settings only when HARNESS_SANDBOX=1.
. "$(dirname "$0")/_assert.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../scripts/lib.sh"
T="$(mktemp -d)"; export HARNESS_ROOT="$T/.harness"
harness_init_layout "$HARNESS_ROOT"

# stub claude records its args, emits one stream event, creates the EXPECTed artifact
STUB="$T/claude.sh"
cat > "$STUB" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$T/args.txt"
echo '{}'
echo done > "$HARNESS_ROOT/artifacts/spec.md"
exit 0
EOF
chmod +x "$STUB"

dispatch(){ printf 'ANALYSE\nEXPECT: artifacts/spec.md\n' > "$HARNESS_ROOT/tech-lead/inbox.md"; set_status "$HARNESS_ROOT" tech-lead working; }

# sandbox OFF -> no --settings
dispatch; CLAUDE_BIN="$STUB" bash "$HERE/../scripts/role-runner.sh" tech-lead --once
case "$(cat "$T/args.txt")" in *--settings*) _FAIL "sandbox OFF must not pass --settings" ;; esac

# sandbox ON -> --settings present
dispatch; HARNESS_SANDBOX=1 CLAUDE_BIN="$STUB" bash "$HERE/../scripts/role-runner.sh" tech-lead --once
assert_contains "$(cat "$T/args.txt")" "--settings"

# the shipped sandbox settings are valid JSON with sandbox.enabled
SB="$HERE/../assets/sandbox-settings.json"
assert_file "$SB"
python3 -c "import json,sys; d=json.load(open('$SB')); sys.exit(0 if d['sandbox']['enabled'] is True else 1)" || _FAIL "sandbox-settings.json must enable the sandbox"
echo OK
