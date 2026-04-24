#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
ok() { printf "✓ %s\n" "$1"; }
fail() { printf "✗ %s\n" "$1"; exit 1; }

# Structural
[[ -d skills/kmm-migration ]] || fail "directory missing"
[[ -f skills/kmm-migration/SKILL.md ]] || fail "SKILL.md missing"
lines=$(wc -l < skills/kmm-migration/SKILL.md)
(( lines <= 500 )) || fail "SKILL.md over 500 lines: $lines"
ok "structural"

# No @-force-loads
if grep -rE '@[a-z_/]+\.md' skills/kmm-migration/ >/dev/null; then
  fail "@-forceload reference found"
fi
ok "no @-forceloads"

# No hedging verbs in laws
for v in " consider " " try to " " should probably " " preferably "; do
  if grep -riq "$v" skills/kmm-migration/migration_laws.md skills/kmm-migration/dispatch_templates/; then
    fail "hedging verb found: $v"
  fi
done
ok "no hedging"

# References have TOCs when >100 lines
for f in skills/kmm-migration/references/*.md; do
  n=$(wc -l < "$f")
  if (( n > 100 )); then
    grep -q "^## Contents" "$f" || fail "missing Contents TOC in $f"
  fi
done
ok "TOCs present"

# Reference-to-reference links (one-level-deep)
# Allowed target roots: spec path in design doc, migration_laws, skill.md
for f in skills/kmm-migration/references/*.md; do
  if grep -oE 'skills/kmm-migration/references/[a-z_]+\.md' "$f" | grep -v "$(basename "$f")" >/dev/null; then
    fail "reference $f links to another reference (violates one-level-deep)"
  fi
done
ok "one-level-deep references"

printf "\n== authoring checklist ALL PASS ==\n"
