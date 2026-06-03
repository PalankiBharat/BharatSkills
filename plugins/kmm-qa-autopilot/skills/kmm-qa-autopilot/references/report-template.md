# Parity Report — Template

Save to the **persistent** run dir (survives any cleanup of the worktrees):
`$RUN_DIR/parity-report-pr<num>-<YYYY-MM-DD>.md`. Artifacts (screenshots, hierarchies,
per-checkpoint `verdict.json`) live under `$RUN_DIR/artifacts/<journey>/<checkpoint>/`.

Use this structure — **same compact shape for the local report AND the PR comment.** A reviewer
must see verdict + per-journey table + the one roll-up line **without expanding anything**; all
detail lives one click away in `<details>`.

```markdown
## <overall-emoji> Parity QA — PR #<num> "<title>"
master <sha> ⇄ pr <sha> · ProductionRelease · <YYYY-MM-DD> · acct <market>

| Journey | Verdict | Evidence |
|---|---|---|
| <journey> | 🟢 Parity | 14 elems · 6 values · 3 masked |
| <journey> | 🔴 Divergence | `txt_total` ₹1,200→₹1,020 |
| <journey> | ⚪ Indeterminate | anchor `widget_pnl` absent on both — flow didn't reach subject |
| <journey> | ⚠️ Eviction | session bumped — re-login & re-run |

**Verdict: <overall-emoji> <HEADLINE>** — 🔴 N · ⚪ N · ⚠️ N · 🟡 N · 🟢 N  (coverage: <mutating journeys tested/declined>)

<details><summary>Divergences & evidence</summary>

For each confirmed 🔴 — **<journey> / <checkpoint> — <presence|value> on `<resource-id>`**:
master (A) `<value>` ⇄ PR (B) `<value>` · artifacts/<journey>/<checkpoint>/{a.s0,b.s0}.png ·
why it matters: <what the user sees / which migrated symbol likely caused it> · root cause: <audit subagent>.
Evictions (⚠️) and how they resolved after re-login go here too.

</details>

<details><summary>Masking · coverage · untested</summary>

- **Masking:** auto-masked volatile fields <count typical per screen>; seed mask <list>;
  server-state copy masked (if any) <phrases via --server-state-text>.
- **Confidence per journey** (a 🟢 is only as good as what it exercised): <journey> — interactions
  exercised (open, date-range, scroll, expand, submit), <N> values compared, <N> masked, text/tag signal.
  Every confirmed false positive (scroll-offset, stateful server copy, eviction, absent anchor) listed with HOW it was confirmed.
- **Untested / declined:** affected journeys with no generatable flow + mutating journeys the user
  declined, each as `⏭️ untested` with a reason. "No exclusions" means gaps are named, not hidden;
  unreachable documented exceptions are named gaps.

</details>
```

(Full run metadata — baseline ref @ master-sha source of truth, candidate branch @ pr-sha,
device serials A/B, build-variant note — belongs in the local `.md` header; the compact comment's
title line carries the load-bearing bits.)

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
2. **Flip the QA section header** to the overall verdict (🟢 PARITY HOLDS / 🔴 DIVERGENCE FOUND / 🟡 REVIEW DRIFT / ⚪ INCONCLUSIVE).
3. **Post the compact report as a comment** (the shape above — verdict + per-journey table + roll-up
   line scannable, divergence/masking detail folded into `<details>`):
   ```bash
   gh pr comment "$PR_NUM" --body-file "$RUN_DIR/parity-report-pr$PR_NUM-<date>.md"
   ```
Use `--body-file` (never inline `--body "$(…)"`) so the markdown table/emoji survive shell quoting.
A declined/untested row stays `⏭️ untested` in the table — published gaps, never silent passes.

## Retro
A session retro is saved to `$RUN_DIR/retro.md` (Phase 8) — friction + proposed skill improvements
from this run, for triage into the skill in a separate session.

## Verdict rules (DIVERGENCE-dominant roll-up)
Per-checkpoint precedence is **⚠️ EVICTION > ⚪ INDETERMINATE > 🔴 DIVERGENCE > 🟡 DRIFT > 🟢 PARITY**,
but the overall headline is divergence-dominant — a single real 🔴 outranks any number of ⚪/⚠️:
- One confirmed 🔴 anywhere → overall **🔴 DIVERGENCE FOUND**. Don't average it away.
- Else any ⚪ INDETERMINATE or ⚠️ EVICTION → overall **⚪ INCONCLUSIVE** — list which journeys and why
  (anchor absent on both / session bumped); these need a re-run, they are NOT passes.
- Else only 🟡 hints → **🟡 REVIEW DRIFT**.
- Else all 🟢 (and any mutating journeys were either tested-green or explicitly declined) → **🟢 PARITY HOLDS**.
- ⚪ INDETERMINATE = a subject checkpoint's required anchor (resource-id/text proving the subject was
  reached) was absent on **both** devices → the comparison is vacuous (flow didn't reach the subject;
  matching-failure ≠ parity), exit code 3. Present on exactly one device is a normal presence 🔴.
- Be honest about untested journeys — a green verdict with three declined mutating journeys is "🟢 for what was tested," and the report must say so.
