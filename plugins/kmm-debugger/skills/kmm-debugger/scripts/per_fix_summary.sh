#!/usr/bin/env bash
# per_fix_summary.sh — print the Per-fix shipped summary template skeleton.
#
# Usage:
#   per_fix_summary.sh <fix-num> "<one-line symptom>" <commit-sha>
#
# Example:
#   per_fix_summary.sh 3 "scrip dedup UniqueViolationException in prod" abc1234
#
# Output: prints the Problem / Solution / Pros / Cons template with the fix
# number, symptom, and commit SHA pre-filled. The parent fills in the four
# sections before reporting the fix to the user.
#
# Why this script exists:
# Keeps the template structure in one place. Ensures the parent doesn't drop the
# Cons section — which is the most important, because it surfaces hotfix / patch
# instincts that should be caught by Doctrine 3 before they ship.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  cat >&2 <<USAGE
Usage: $(basename "$0") <fix-num> "<one-line symptom>" <commit-sha>

Example:
  $(basename "$0") 3 "scrip dedup UniqueViolationException in prod" abc1234
USAGE
  exit 1
fi

FIX_NUM="$1"
SYMPTOM="$2"
SHA="$3"

cat <<EOF
### Fix $FIX_NUM — $SYMPTOM

**Problem.** [Proximate cause with file:line. Root cause location: SDK / upstream / consumer / infra. If Q0 (is this even our bug?) was yes, name the upstream contract that was violated.]

**Solution.** Commit \`$SHA\`. [What changed. Why this is the clean long-term shape — or, if it's a hotfix per Doctrine 3, name that explicitly here and link the tracking issue + deadline for the clean follow-up.]

**Pros.** [What makes this the right shape vs. alternatives. Examples: converges to sibling-platform's shape; deletes vestigial machinery; addresses root cause at the right layer (not a layer above); preserves the early-warning signal for future contract drift.]

**Cons / risks / gaps.** [Ruthless. What this doesn't cover. What's deferred. What the user needs to validate. If Q0 was yes: upstream escalation status. If this is a hotfix: what specifically defers to the clean follow-up. If you can't name a single con, you haven't thought hard enough — keep thinking.]

---
EOF

cat >&2 <<'NOTES'

Notes:
- The Cons section is the most important. It catches when you've defaulted to a patch instead of a clean fix.
- If you wrote a hotfix, name it as such in Solution AND link the tracking issue. "Clean up later" without a tracked issue is debt that compounds.
- If the symptom persists after this fix ships, do NOT write Fix N+1 as a patch on this fix. See references/fix-loop-protocol.md.
NOTES
