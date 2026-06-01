# Parity Report — Template

Save to the **persistent** run dir (survives any cleanup of the worktrees):
`$RUN_DIR/parity-report-pr<num>-<YYYY-MM-DD>.md`. Artifacts (screenshots, hierarchies,
per-checkpoint `verdict.json`) live under `$RUN_DIR/artifacts/<journey>/<checkpoint>/`.

Use this structure:

```markdown
# Parity Report — PR #<num> "<title>"

- **Candidate (B):** <branch> @ <pr-sha>
- **Baseline (A):** <baseline ref> @ <master-sha>   ← source of truth (pre-migration commit if the PR is merged)
- **Build variant:** ProductionRelease (R8-minified — the shipped artifact users run)
- **Verdict:** 🟢 PARITY HOLDS | 🟡 REVIEW DRIFT | 🔴 DIVERGENCE FOUND
- **Date:** <YYYY-MM-DD>   **Devices:** A=<serial> (master)  B=<serial> (PR)
- **Account / market:** <test acct?> / <market open|closed>

## Summary
<2–3 sentences: what the PR migrates, how many journeys were affected, the headline result.>

## Heatmap (what was tested)
| Journey | Risk | Mutating | Flow | Checkpoints | Result |
|---|---|---|---|---|---|
| Watchlist add/remove | 🟠 | no | maestro/... | 4 | 🟢 |
| Cancel normal order | 🔴 | YES (you confirmed) | order_modify_cancel/01 | 5 | 🔴 |
| Funds add | 🔴 | YES — **declined**, not tested | — | — | ⏭️ untested |

## Divergences (🔴)
For each confirmed divergence:
### <journey> / <checkpoint> — <presence|value> on `<resource-id>`
- **master (A):** `<value>`
- **PR (B):** `<value>`
- **Evidence:** artifacts/<journey>/<checkpoint>/{a.s0,b.s0}.png
- **Why it matters:** <what the user sees / which migrated symbol likely caused it>

## Drift (🟡 — live/timing-explainable)
<bullet list of checkpoints with only soft hints; one line each, why benign.>

## Evictions / re-runs
<any checkpoints that hit EVICTION and how they resolved after re-login.>

## Untested (gaps)
<affected journeys with no flow that couldn't be generated, and mutating journeys the user
declined — be explicit; "no exclusions" means gaps are named, not hidden.>

## Confidence / coverage (a 🟢 is only as good as what it exercised)
| Journey | Interactions exercised | Values compared | Masked | Signal | Verdict |
|---|---|---|---|---|---|
| <j> | open, date-range, scroll, expand, submit | <N> | <N> | text / tag | 🟢 |
Every confirmed false positive (scroll-offset, stateful server copy, eviction) is listed with HOW it
was confirmed — explained, never hidden. Documented exceptions that were not UI-reachable are named gaps.

## Masking note
Auto-masked volatile fields this run: <count typical per screen>. Seed mask used: <list>.
Server-state confirmation copy masked (stateful actions, if any): <phrases via --server-state-text>.
```

## Publishing to the PR (automatic — the PR is the deliverable, not a local .md)

The local report is the audit trail; the **PR is the deliverable surface**. Phase 6 publishes there
automatically (gated only by "is this a GitHub PR" — it always is, the single input is a PR link).
Don't wait to be asked (PR #420 left the body's QA table all `—` until prompted). Three steps:

1. **Fill the PR body's QA-table Result column in place** (the author's checklist rows — see the
   coverage union). Edit, don't rewrite the body:
   ```bash
   gh pr view "$PR_NUM" --json body -q .body > /tmp/pr-body.md
   # update each QA row's Result cell (🟢/🔴/🟡/⏭️ untested) + flip the QA section header to the verdict
   gh pr edit "$PR_NUM" --body-file /tmp/pr-body.md
   ```
2. **Flip the QA section header** to the overall verdict (🟢 PARITY HOLDS / 🔴 DIVERGENCE FOUND / 🟡 REVIEW DRIFT).
3. **Post the divergence writeup as a comment** (the per-🔴 detail + both values + the audit-subagent root cause):
   ```bash
   gh pr comment "$PR_NUM" --body-file "$RUN_DIR/parity-report-pr$PR_NUM-<date>.md"
   ```
Use `--body-file` (never inline `--body "$(…)"`) so the markdown table/emoji survive shell quoting.
A declined/untested row stays `⏭️ untested` in the table — published gaps, never silent passes.

## Retro
A session retro is saved to `$RUN_DIR/retro.md` (Phase 8) — friction + proposed skill improvements
from this run, for triage into the skill in a separate session.

## Verdict rules
- One confirmed 🔴 anywhere → overall **🔴 DIVERGENCE FOUND**. Don't average it away.
- Only 🟡 hints → **🟡 REVIEW DRIFT**.
- All 🟢 (and any mutating journeys were either tested-green or explicitly declined) → **🟢 PARITY HOLDS**.
- Be honest about untested journeys — a green verdict with three declined mutating journeys is "🟢 for what was tested," and the report must say so.
