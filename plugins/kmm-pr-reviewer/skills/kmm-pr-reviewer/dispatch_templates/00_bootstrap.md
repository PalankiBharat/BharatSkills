---
name: 00_bootstrap
model: haiku
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(gh pr view *), Bash(gh pr diff *), Bash(gh api *), Bash(git rev-parse *), Bash(git fetch *), Bash(git ls-tree *), Bash(jq *), Write]
tool_denylist: [Edit, Bash(git commit *), Bash(git add *), Bash(git push *), Bash(git checkout *), Bash(git reset *), Bash(git rebase *), Bash(gh pr review *), Bash(gh pr comment *), Bash(gh pr close *), Bash(gh pr merge *)]
requires_success_criterion: true
---

# 00_bootstrap

## Role

Fetch PR metadata via `gh`, classify every changed path per the classification protocol, and write `state.json` + `pr_metadata.md`. Read-only operation; never posts, commits, or edits source.

## Must read

- `skills/kmm-pr-reviewer/review_laws.md`
- `skills/kmm-pr-reviewer/references/classification_protocol.md`
- `skills/kmm-pr-reviewer/references/subagent_status_contract.md`
- `skills/kmm-pr-reviewer/schemas/state_schema.md`

## Inputs

From the dispatch prompt:

- `pr_argument` — either a PR number (e.g. `154`) or a full PR URL.

## Procedure

1. **Parse the PR argument.** If the argument is a URL, extract `<owner>`, `<repo>`, and `<pr#>` from the URL. If it is an integer, fetch `<owner>` / `<repo>` from the current repo's `gh repo view --json owner,name`.
2. **Verify `gh` auth.** Run `gh auth status`. If unauthenticated, emit `STATUS: BLOCKED` immediately with the exact error — do not attempt any partial work.
3. **Fetch PR metadata.**
   ```bash
   gh pr view <pr#> --json number,url,baseRefName,headRefName,baseRefOid,headRefOid,headRepository,baseRepository,files,state,title,body
   ```
   - If `state != OPEN`, emit `STATUS: BLOCKED` (we don't review closed/merged PRs through this skill).
4. **Fetch the file list.** The `files` field contains `[{ path, additions, deletions, changeType }]`. Validate the count is non-zero — empty PR → `STATUS: BLOCKED`.
5. **Ensure the base ref is locally available.** Run `git fetch origin <base_branch>:<base_branch>` (silently — failures here are not fatal as long as `git rev-parse <base_sha>^{commit}` later succeeds). Then `git rev-parse <base_sha>^{commit}` and `git rev-parse <head_sha>^{commit}` — if either fails, emit `STATUS: BLOCKED` listing the missing SHA.
6. **Classify every path.** Apply `references/classification_protocol.md` step by step. For `migrated` candidates, run the paired-deletion heuristic and capture `paired_master_path`. Build the `files[]` array per the schema.
7. **Sanity-check counts.** `len(files[]) == len(gh_response.files[])` — if not, the classifier dropped a path; emit `STATUS: BLOCKED`.
8. **Write `pr_metadata.md`.** Format:
   ```markdown
   # PR <pr#> — <title>

   - **URL:** <url>
   - **Base:** <base_branch> @ <base_sha>
   - **Head:** <head_branch> @ <head_sha>
   - **State:** OPEN
   - **Total files:** <n>
   - **Classifications:** migrated=<n>, ios_port=<n>, nonmigrated=<n>, baseline=<n>, build_config=<n>
   - **iOS dispatch:** <yes|no>

   ## PR body (verbatim from gh pr view)

   <body>

   ## File list (raw from gh)

   | Path | Change type | +/- |
   |---|---|---|
   | ... | ... | +x / -y |
   ```
9. **Write `state.json`** per `schemas/state_schema.md`. Set `phase: 0`, `phase_substep: "bootstrap.complete"`, `status: "in_progress"`, every file's `review_status: "pending"`, `gates.gate_1_approval: null`, `last_dispatch: null`, `posted_review_url: null`.
10. **Report.**

## Report path

`kmm_pr_review/<pr#>/state.json` (the schema-conformant state file IS the report) plus `kmm_pr_review/<pr#>/pr_metadata.md` (human-readable summary).

The Bash output does not need to be in the report — the files ARE the report. The dispatch's textual reply is just the status header plus a one-line summary.

## Status

- `DONE` — both files written, all counts reconcile, all SHAs locally resolvable.
- `BLOCKED` — `gh` auth missing, network failure, PR not open, classifier lost a path, or `git rev-parse` failed for `base_sha`/`head_sha`.

## Notes

- Never run any `gh` write command (`gh pr review`, `gh pr comment`, `gh pr edit`, `gh pr close`, `gh pr merge`). The denylist enforces this.
- Never modify any source file. The denylist enforces this.
- The classification logic is mechanical — do not "interpret" classifications. Apply the protocol verbatim.
