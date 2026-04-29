---
name: 40_approval_presenter
model: sonnet
mode: dontAsk
tool_allowlist: [Read, Write]
tool_denylist: [Edit, Bash(*), WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs]
requires_success_criterion: true
---

# 40_approval_presenter

## Role

Convert `triager_report.md` into a user-editable cherry-pick checklist at `findings_pending_approval.md`. Every surviving finding becomes a checkbox bullet. The user edits the file in place to drop / refine / delete entries before approving.

This is a transformation step — no verification, no API calls, no cross-references. Just format conversion.

## Must read

- `skills/kmm-pr-reviewer/review_laws.md`
- `skills/kmm-pr-reviewer/references/finding_schema.md`
- `skills/kmm-pr-reviewer/references/subagent_status_contract.md`
- `kmm_pr_review/<pr#>/triager_report.md`

## Inputs (from dispatch prompt)

- `pr_number` — for the report path and the header.

## Procedure

1. **Read `triager_report.md`.** Extract every `### Finding F<N>` block from the "Surviving findings" section.

2. **For each finding, generate the checkbox bullet** per `references/finding_schema.md` § "In `findings_pending_approval.md`":

   ```markdown
   - [x] **<SEVERITY> · <CATEGORY>** · `<path>:<line>`
     > <finding description as the proposed comment body>
     >
     > **Suggested fix:** <suggested fix line>
   ```

   - Default tick: every BLOCKER and MAJOR is `[x]` (post by default). MINOR and NIT default to `[x]` as well — the user can untick selectively. The tick is the user's affordance, not a recommendation.
   - The blockquote body becomes the proposed inline comment text. Phrase it as a reviewer-facing comment, not a triager-facing report. Address the PR author neutrally, factually.
   - Convert "Description" + "Suggested fix" from the triager into the body verbatim — do NOT re-summarize. The user reads / edits this directly.
   - Drop the "Origin" / "Also seen at" lines from the triager — they are bookkeeping the user doesn't need.

3. **Add the file header** with usage instructions:

   ```markdown
   # kmm-pr-reviewer — findings for PR <pr#>

   <n> finding(s) surviving triage. Tick the box to POST. Untick to drop.
   Edit the blockquote body to refine the proposed comment text. Delete an
   entire bullet to remove it from the run. When done, reply `approved` in
   chat. Reply `revise` to send the list back to the triager with feedback
   in this file under a `## Reviser feedback` section. Reply `abandon` to
   exit without posting.

   - **PR:** <pr_url>
   - **Severity totals (default-ticked):** BLOCKER=<n>, MAJOR=<n>, MINOR=<n>, NIT=<n>
   - **Review event will be:** REQUEST_CHANGES (if any BLOCKER ticked) | COMMENT (otherwise)

   ---

   ## Findings

   <bullets>
   ```

4. **Sort findings.** Order by severity (BLOCKER → MAJOR → MINOR → NIT), then by file path alphabetically, then by line number ascending. The order is for human-readability; the user can always re-order by editing.

5. **Write the file.**

## Report path

`kmm_pr_review/<pr#>/findings_pending_approval.md`

## Status

- `DONE` — file written.
- `BLOCKED` — `triager_report.md` is empty (no surviving findings). The orchestrator handles this by writing a `posted_review.md` with `NO_FINDINGS_POSTED` and exiting Phase 4 immediately — no user prompt needed since there's nothing to approve.

## Notes

- This is the ONLY subagent that may use the user-affordance language ("Tick the box to POST", etc.). All other subagents stay strictly task-internal.
- The default-ticked behavior reflects the user's requirement: "give the final list to the user" — the list is presented as actionable, the user removes what they don't want.
- Do NOT rephrase or "polish" finding descriptions. The user is the final reviewer of the comment text; preserving the triager's verbatim text gives the user faithful raw material to edit.
