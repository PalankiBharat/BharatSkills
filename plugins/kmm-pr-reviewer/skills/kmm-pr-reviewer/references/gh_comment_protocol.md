# gh Comment Protocol

> The exact procedure `50_comment_poster` follows to post a single
> GitHub review on the PR. One review = one API call, line-anchored
> inline comments + a summary body.

## Contents

- [Inputs](#inputs)
- [Output](#output)
- [Step 1 — Parse approved findings](#step-1--parse-approved-findings)
- [Step 2 — Build the review payload](#step-2--build-the-review-payload)
- [Step 3 — Resolve line anchors](#step-3--resolve-line-anchors)
- [Step 4 — Decide the review event](#step-4--decide-the-review-event)
- [Step 5 — POST the review](#step-5--post-the-review)
- [Step 6 — Record the result](#step-6--record-the-result)
- [Failure modes](#failure-modes)

## Inputs

From `state.json`:

- `pr_number`
- `repo_owner`
- `repo_name`
- `head_sha` — required by the GitHub API for inline comments to anchor correctly.

From `findings_pending_approval.md`:

- The user-edited markdown checklist. Only the bullets whose checkbox is `[x]` are considered approved.

## Output

`kmm_pr_review/<pr#>/posted_review.md`:

```markdown
# Posted review

- **Review URL:** <html_url returned by GitHub>
- **Review event:** REQUEST_CHANGES | COMMENT
- **Inline comments posted:** <count>
- **Summary-body bullets:** <count>
- **Approved findings dropped (no anchor):** <count>

## Payload sent

<the exact JSON payload passed to gh api, pretty-printed>

## GitHub response

<the JSON response from GitHub, pretty-printed>
```

## Step 1 — Parse approved findings

Read `findings_pending_approval.md`. For every line matching the regex `^- \[(x|X| )\] `:

- If `[x]` or `[X]` → ticked, include.
- If `[ ]` → unticked, skip.

For each ticked bullet, extract:

- Severity tag (the first bold token after the checkbox, e.g. `**BLOCKER**`).
- Category tag (the bold token after the `·`, e.g. `**MISSING_LOGIC**`).
- Path and line (the backtick-quoted `path:line` after the next `·`).
- Body (the indented blockquote content under the bullet — this is the proposed comment, possibly user-edited).

If the user replaced the body entirely, use the user's body verbatim. Do not "improve" it.

If the user removed the bullet entirely, the finding is dropped (it is no longer in the file).

If a bullet has `[x]` but a malformed body (no blockquote), emit a soft warning to the orchestrator's report but do not abort — fall back to using just the severity/category/path:line as the comment body.

## Step 2 — Build the review payload

The single API call is:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<pr_number>/reviews \
  --input -
```

The JSON body has shape:

```json
{
  "commit_id": "<head_sha>",
  "body": "<top-level summary body — see Step 3>",
  "event": "REQUEST_CHANGES" | "COMMENT",
  "comments": [
    {
      "path": "<repo-relative path>",
      "line": <int>,
      "side": "RIGHT",
      "body": "<finding body>"
    },
    ...
  ]
}
```

Every approved finding that has a stable `path:line` becomes one entry in `comments[]`. Findings without a usable line anchor (see Step 3) become bullet items in the top-level `body`.

## Step 3 — Resolve line anchors

A `path:line` from a finding is **postable inline** if and only if the line number falls within a hunk that the PR diff actually touched (added or modified line on the RIGHT side of the diff). Why: GitHub's `POST /pulls/<pr>/reviews` rejects inline comments anchored to lines outside the PR diff with a 422.

For each approved finding with a `path:line`:

1. Run `gh pr diff <pr> -- <path>` and parse the unified diff hunks for that file.
2. The line numbers attributable to the RIGHT side (head) are the headers `+<start>,<count>` of each hunk and the `+`-prefixed lines within. Build a set of postable line numbers per file.
3. If the finding's line is in the set → it goes to `comments[]`.
4. If the finding's line is NOT in the set (e.g., the finding cites a line on master that was deleted) → demote to the summary body. Prefix the summary bullet with the original `path:line` so the reader can navigate.

For findings citing master locations only (`MISSING_LOGIC` where the omitted line existed on master and is not in the head diff), there is by definition no head line to anchor to. Demote to summary body, citing both `master_path:line` (at `base_sha`) and the head file (no specific line).

## Step 4 — Decide the review event

```
event = "REQUEST_CHANGES" if any approved finding has severity == "BLOCKER" else "COMMENT"
```

The skill never posts `APPROVE`. Its job is to flag regressions, not to bless the PR. The author and a human reviewer are responsible for deciding when to approve.

## Step 5 — POST the review

Build the payload, write it to a temp file (or pipe via heredoc), then call:

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/<owner>/<repo>/pulls/<pr_number>/reviews \
  --input <payload-file>
```

The response is JSON with `id`, `node_id`, `user`, `body`, `state` (`COMMENTED` / `CHANGES_REQUESTED`), `html_url`, `submitted_at`. Capture `html_url` for the posted-review record.

## Step 6 — Record the result

Write `kmm_pr_review/<pr#>/posted_review.md` (see [Output](#output)). Update `state.json.status` to `complete` and `state.json.gates.gate_1_approval` to `posted_at_<iso-timestamp>` with the `html_url`.

## Failure modes

| Failure | Cause | Action |
|---|---|---|
| `gh: command not found` | gh CLI not installed | Emit `STATUS: BLOCKED`, write the would-be payload to `posted_review.md` so the user can post manually. |
| `HTTP 401` | gh auth missing or expired | Emit `STATUS: BLOCKED`, prompt user to run `gh auth login`. Payload preserved in `posted_review.md`. |
| `HTTP 403` (rate limit) | Too many requests | Emit `STATUS: BLOCKED` with retry-after time. Payload preserved. |
| `HTTP 404` | PR closed / repo renamed | Emit `STATUS: BLOCKED` with the API response. Payload preserved. |
| `HTTP 422` on `comments[i]` (line out of diff) | Anchor resolution missed a deleted line | Demote that comment to summary body, retry the POST without the offending entry, log the demotion. Do NOT silently drop. |
| Payload exceeds GitHub size limit (rare; ~64KB body) | Large finding list | Split into multiple reviews — first review carries the BLOCKERs and `event: REQUEST_CHANGES`; follow-up review(s) carry the rest as `event: COMMENT`. Document the split in `posted_review.md`. |

In every failure mode, `posted_review.md` is the durable record. Re-running the skill on the same PR after fixing the auth issue can re-attempt the POST from the saved payload.
