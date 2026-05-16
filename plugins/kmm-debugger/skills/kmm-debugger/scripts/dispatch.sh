#!/usr/bin/env bash
# dispatch.sh — generate pre-filled subagent prompts for Phase 1 of kmm-debugger.
#
# Usage:
#   dispatch.sh ambiguous   "<bug-summary>" "<repo-path>" "<branch>" "<consumer-path>"
#   dispatch.sh unambiguous "<bug-summary>" "<repo-path>" "<branch>" "<consumer-path>"
#
# Output: prints subagent prompts to stdout, each separated by "=== DISPATCH N: <label> ===".
# - ambiguous   → 8 prompts (Forensic A/B, Reverse A/B, Archeology A/B, Ideal-Design A/B)
# - unambiguous → 2 prompts (Forensic A/B only)
#
# Each prompt has the mandatory bias-guard preamble inlined and the user-provided
# context substituted into the template placeholders. The parent agent copy-pastes
# each prompt body into an Agent tool call (subagent_type: general-purpose, model: opus,
# run_in_background: true), firing them all in a single message.
#
# Why this script exists:
# Assembling the templates from references/subagent-prompts.md each dispatch costs
# ~3500 tokens. Generating them via this script means the prompt bodies live on
# disk, not in the parent's context window.
#
# For the fix-didn't-fully-resolve loop, append the fresh-lens addendum from
# references/fix-loop-protocol.md step 3 to each prompt manually before dispatching.

set -euo pipefail

if [[ $# -lt 5 ]]; then
  cat >&2 <<USAGE
Usage: $(basename "$0") <ambiguous|unambiguous> "<bug-summary>" "<repo-path>" "<branch>" "<consumer-path>"

Example:
  $(basename "$0") ambiguous \\
    "UniqueViolationException on scrip dedup in prod" \\
    "/Users/me/dev/sesame-sdk" \\
    "kmm-migration" \\
    "/Users/me/dev/sesame-consumer"
USAGE
  exit 1
fi

MODE="$1"
BUG_SUMMARY="$2"
REPO_PATH="$3"
BRANCH="$4"
CONSUMER_PATH="$5"

if [[ "$MODE" != "ambiguous" && "$MODE" != "unambiguous" ]]; then
  echo "Error: mode must be 'ambiguous' or 'unambiguous', got '$MODE'" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Mandatory bias-guard preamble (kept in sync with references/subagent-prompts.md)
# -----------------------------------------------------------------------------
read -r -d '' BIAS_GUARD <<'EOF' || true
**Bias guard.** Do NOT treat the existing implementation, prior diagnoses, or prior fix attempts as correct. The parent agent has biases toward (a) defending the current code as roughly right and (b) proposing minimal patches over root-cause fixes — your job is to investigate with a fresh lens. If your reading suggests the existing implementation is wrong, or that a deletion is the right shape, or that the proper fix is much larger than a patch, say so plainly. Do not soften findings to align with prior work or to reduce blast radius.

If the parent agent told you "the bug is X" or "the previous fix tried Y", treat those as hypotheses to test, not anchors to defend.
EOF

# -----------------------------------------------------------------------------
# Helper to emit a single dispatch
# -----------------------------------------------------------------------------
emit() {
  local label="$1"
  local body="$2"
  printf '=== DISPATCH %d: %s ===\n%s\n\n' "$DISPATCH_NUM" "$label" "$body"
  DISPATCH_NUM=$((DISPATCH_NUM + 1))
}

# -----------------------------------------------------------------------------
# Templates (truncated; for the full versions see references/subagent-prompts.md)
# These bodies match the template structures defined there. Keep in sync.
# -----------------------------------------------------------------------------

template_forensic() {
  cat <<EOF
**Read-only investigation, no code edits.**

$BIAS_GUARD

Identify the proximate cause of the user-reported regression in our KMM-migrated SDK, with file:line precision.

## Context

Repo: $REPO_PATH
Migration branch: $BRANCH
Consumer path: $CONSUMER_PATH

## The bug to investigate

$BUG_SUMMARY

## What I need from you

1. **Locate the proximate cause.** Trace from the user-visible symptom backward to the specific commonMain / androidMain / iosMain code that's misbehaving. Cite file:line.
2. **Identify the migration-introduced surface area.** What in the failing code path is new since the migration vs. pre-existing on master? Use \`git diff master..$BRANCH -- <suspected paths>\` to be precise.
3. **Cross-check against the catalog.** Does this map to one of the 7 common KMM migration pitfalls (commonMain BuildConfig, Room KMP suspend DAO race, ObjectBox→Room refetch, init-time scope leak, transitive dep drift, multi-flavor publish, latent invariant in annotation-driven schema)?
4. **Note adjacent suspect areas.** Brief flag for code that could exhibit a similar bug under different conditions.

## Output

Under ~700 words. Structure:
- **Proximate cause** — file:line, brief description
- **Migration delta in this code path** — what's new vs. pre-existing
- **Catalog pitfall match** — none / pitfall N + how it fits
- **Adjacent suspects** — (optional) brief list

File:line refs required. No code edits. Treat any stated hypothesis as something to test, not confirm.
EOF
}

template_reverse() {
  cat <<EOF
**Read-only investigation, no code edits.**

$BIAS_GUARD

Your job is to argue *against* the hypothesis that the SDK is broken. Build the strongest steelman case you can for one of: backend contract violation, consumer misuse, infrastructure regression, recent non-migration commit, or cross-platform asymmetry where the sibling platform is the correct one.

## Context

Repo: $REPO_PATH
Migration branch: $BRANCH
Consumer path: $CONSUMER_PATH

## The bug

$BUG_SUMMARY

The current SDK-is-broken hypothesis is the default frame. Your job is to push back on that.

## What I need from you

For each alternative locus, build a steelman argument and cite evidence:

1. **Backend contract violation.** What contract does the SDK encode via annotations, schemas, expect/actual, non-nullable types? Has the BE recently violated that contract? If the exception type is contract-violation-shaped (\`UniqueViolationException\`, \`MissingFieldException\`), this locus deserves the highest priority. See Pitfall #7.

2. **Consumer misuse.** Wrong threading, wrong lifecycle, wrong ordering, stale cached SDK instance, missing required \`initialize()\` call, double-initialization?

3. **Infrastructure regression.** Has Gradle, AGP, Kotlin, Xcode, OkHttp, Ktor, CDN, or platform component changed recently? Other apps seeing similar symptoms?

4. **Recent non-migration commit.** \`git log --since="30 days ago" --not $BRANCH~50\` — is there a more recent commit that's the real cause?

5. **Cross-platform asymmetry.** Does the sibling platform (iOS / Android) handle this differently? If yes, which is the deviant — and why? Often the sibling has implemented the correct shape; the deviant is the bug.

For each: cite evidence. If evidence is thin, say so — don't fabricate a case.

## Output

Under ~700 words. One section per alternative locus, with **Steelman argument** (2-3 sentences), **Evidence** (file:line / SHAs / log timestamps), **Confidence** (high / medium / low / thin).

End with a **Confidence ranking**: which locus has the strongest non-SDK case? What would confirm/refute it?

Be combative. Make the SDK-is-broken frame defend itself.
EOF
}

template_archeology() {
  cat <<EOF
**Read-only investigation, no code edits.**

$BIAS_GUARD

Mine the original KMM migration PR for the design rationale behind decisions now manifesting as regressions. Treat findings as context, NOT constraint.

## Context

Repo: $REPO_PATH ; migration branch: $BRANCH ; \`gh\` works from there.

## The bug

$BUG_SUMMARY

## What I need from you

For the regression area:

1. **Design intent.** What was the migration author trying to do? Cite PR body, design docs, commit messages, review-thread comments. Quote verbatim where load-bearing.
2. **Explicitly accepted trade-offs.** "Known trade-offs" / "Limitations" sections; commits that say "we accept X because Y".
3. **Reviewer pushback that was resolved.** Was the issue flagged? What was the resolution?
4. **Open follow-ups in the PR.** "TODO post-merge" / "before release" / "revisit when X".
5. **Reviewer identities + count.** Single-author / zero-review PRs have lower confidence — surface that signal.
6. **Validation status.** Merged? Last validated alpha behind current head?

## Tool guidance

- \`gh pr view <NUM> --repo <ORG>/<REPO> --comments\`
- \`gh api repos/<ORG>/<REPO>/pulls/<NUM>/reviews\`
- \`gh api repos/<ORG>/<REPO>/pulls/<NUM>/comments --paginate\`
- Don't use \`gh pr diff\` (fails on >300 files).
- Watch GitHub secondary rate limits.

## Output

Under ~800 words. One section per area covered.

**Critical: treat findings as context, NOT constraint.** If the author accepted a trade-off that's now causing user pain, the right fix is what's right for KMM — not preserving the trade-off.
EOF
}

template_ideal_design() {
  cat <<EOF
**Read-only investigation, no code edits.**

$BIAS_GUARD

Ignore the current implementation. Propose what the right design would look like if you were building this area today, from scratch, with full KMM knowledge — explicitly NOT trying to minimize divergence from current code.

## Context

Repo: $REPO_PATH
Migration branch: $BRANCH

## The bug surfacing in this area

$BUG_SUMMARY

## What I need from you

Without reading the current implementation in detail:

1. **What is the actual need?** Domain terms, not implementation terms.
2. **What's the canonical KMM way to satisfy that need?** \`expect/actual\`, AGP \`BuildConfig\`, Room KMP suspend DAOs, business-key upserts, etc.
3. **What's the minimal data model?** Entities, fields, invariants. Which invariants are load-bearing on remote contracts vs. local guarantees?
4. **What's the minimal API surface?** Public functions, signatures, threading.
5. **What's the minimal lifecycle?** Init, hot path, cleanup.
6. **Cross-platform parity check.** Does iOS / Android already have a version of this? If yes, what shape does it use? Often the sibling has solved it better — converge there.

## What NOT to do

- Do NOT propose patches to current implementation.
- Do NOT defend the current implementation.
- Do NOT engage with PR archeology (other subagents' job).
- Do NOT propose new architecture for newness — if the simplest shape is "delete the new machinery", say so.
- Do NOT soften the design to "stay close to current code".

## Output

Under ~600 words:
- **Need** (1 paragraph)
- **Right shape** (numbered list — data model, API, lifecycle, cross-platform)
- **Comparison to current** (1 paragraph — divergences and which look load-bearing on the bug)
- **Deletion candidates** (bulleted list — current code that wouldn't exist in the right shape)
- **Clean-fix size estimate** (LOC delta + risk: small / medium / large)
EOF
}

# -----------------------------------------------------------------------------
# Emit dispatches
# -----------------------------------------------------------------------------
DISPATCH_NUM=1

if [[ "$MODE" == "ambiguous" ]]; then
  emit "Forensic A"          "$(template_forensic)"
  emit "Forensic B"          "$(template_forensic)"
  emit "Reverse A"           "$(template_reverse)"
  emit "Reverse B"           "$(template_reverse)"
  emit "PR Archeology A"     "$(template_archeology)"
  emit "PR Archeology B"     "$(template_archeology)"
  emit "Ideal-Design A"      "$(template_ideal_design)"
  emit "Ideal-Design B"      "$(template_ideal_design)"
else
  emit "Forensic A"          "$(template_forensic)"
  emit "Forensic B"          "$(template_forensic)"
fi

cat <<'FOOTER'
=== DISPATCH SUMMARY ===
Spawn each prompt above as a separate Agent tool call in a single message.
Recommended: subagent_type=general-purpose, model=opus, run_in_background=true.

After all return, synthesize per references/subagent-prompts.md "Consensus dispatch" section:
  1. Within each A/B pair, check agreement first.
  2. Then synthesize across angles.
  3. Single-source claims → flag as not-corroborated, verify by hand.
  4. Do NOT collapse disagreements into a clean narrative — surface them to the user.
FOOTER
