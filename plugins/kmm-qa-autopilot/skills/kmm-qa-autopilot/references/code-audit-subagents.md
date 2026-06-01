# Code-Audit Subagents — confirm each finding is migration-induced

A 🔴 the comparator reports is an *observed behavioral difference*. Before it lands on the PR it
must be confirmed as **migration-induced** (vs pre-existing, server-state, env, or account-state) —
independently, not by the same main thread that ran the flows. This phase does that.

**Why a subagent, not inline.** Auditing root cause inline on the main thread bloats context with
file reads and biases toward whatever hypothesis the operator already formed mid-run (the PR #420
account-state detour is the cautionary tale — see the retro). A fresh subagent gets the evidence and
the diff with no prior, and returns an adversarial second opinion.

## When

After **all** journeys have run and every finding is **batched** (don't tunnel on the first 🔴 —
collect them all, then audit). One subagent **per confirmed/suspected issue**.

## Model tier — pick per issue

- **Sonnet** — small/localized: a missing slash in a URL, a renamed field, a dropped annotation, a
  one-line mapper change.
- **Opus** — large/complex or high-risk-surface: concurrency/threading, serialization-under-R8,
  cross-module DI scope, ordering/lifecycle, or anything on an auth/money path (where a "small" fix
  still warrants the deeper read). PR #420's biometric URL bug was a 1-line fix but sat on the
  login/auth path → Opus.

## Context to hand the subagent UPFRONT (all of it, for that one issue)

1. **Symptom** — master(A) vs PR(B) behavior, the checkpoint, and the comparator verdict (paste the
   `verdict.json` / the divergent rid or text + both values).
2. **The diff** — the exact changed files and `git diff <baseline-ref>...<pr-head>` for the relevant
   symbols (trace from the divergent screen back to the migrated code).
3. **Exception claims** — any relevant `.kmm/exceptions/*.md` (context only — see the independent-
   evidence rule; a doc never excuses a 🔴).
4. **Captured evidence** — screenshots, the malformed value, any `nslookup`/log output already in hand.
5. **The directive** — return: `is-migration-induced` (yes / no / uncertain), root cause, the
   offending lines (file:line), and a suggested fix.

## Output → report

Roll each subagent's verdict into the PR writeup. A confirmed migration-induced 🔴 is the headline,
quoted with both values + the offending lines + the suggested fix. An `uncertain` or `no` result is
reported honestly (pre-existing / env / inconclusive), never silently upgraded to a confirmed bug.
This is the independent, evidence-backed confirmation that makes the PR comment trustworthy.
