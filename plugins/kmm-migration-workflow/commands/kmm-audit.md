---
description: Read-only audit of any KMM migration PR — whether it was made with this skill or not. Reviews every changed line against the constitution and clean-code rules. Returns a table of issues. On user approval, posts selected issues as inline GitHub comments. Distinct from /kmm-verify (which is a completeness check on migrations done with this skill).
argument-hint: "<pr-number-or-url> | <branch-name>"
---

# /kmm-audit

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` and `references/orchestration-protocol.md` first.

Audit mode is **read-only by default**. The skill's principles apply equally to migrations done with this skill and migrations done by hand.

This is **not** the verify phase. Verify checks completeness of a skill-made migration; audit checks principle adherence of any migration with no skill artifacts to cross-reference.

## When to invoke

- A teammate's PR that migrates files into commonMain.
- A PR opened months ago wanted a second look.
- A PR opened **with** this skill the user wants a fresh principle-pass on (audit and verify are not redundant — different lenses).

## Inputs

- `<pr>` — GitHub PR number, URL, or local branch name.
- The constitution (always loaded).

## Steps

### 1. Resolve the PR and gather context

For a GitHub PR:
- `gh pr view <pr> --json number,title,body,baseRefName,headRefName,files,headRepository`
- `gh pr diff <pr>` → unified diff
- `gh pr view <pr> --json commits` → commit list

For a local branch:
- `git diff <base>...<branch>` (ask once if base is unclear)
- `git log <base>..<branch>`

Write the diff to `<repo>/.kmm-audit/<pr-or-branch>/diff.patch` and metadata to `metadata.json` so the auditor can read without re-fetching.

### 2. Check whether the PR was made with this skill

If `<pr>`'s repo contains `kmm/<scope>/` whose `spec.md` references the same baseline SHA the PR diff is built on, this is a skill-made migration. Tell the user:

> This PR was made with `kmm-migration-workflow`. Audit will still run (different lens than verify), but you may want `/kmm-verify` for completeness. Continue with audit? [y / cancel]

Default is to continue.

If no skill artifacts present, audit is the only relevant lens.

### 3. Dispatch `pr-auditor`

```
Dispatch: agents/pr-auditor.md
Task: Audit the KMM migration PR for principle violations.
      Diff: <repo>/.kmm-audit/<pr-or-branch>/diff.patch
      Metadata: <repo>/.kmm-audit/<pr-or-branch>/metadata.json
Model: sonnet
Mode: read-only
```

The auditor walks the diff and applies the constitution + clean-code rules from §7. Returns `AUDIT_REPORT` with one row per finding.

### 4. Receive the report

Markdown table with columns: # | File | Line | Severity | Principle | Observed | Should be.

Severity:
- **HIGH** — constitution violation, public API drift, behaviour drift. Blocks merge in the auditor's view.
- **MEDIUM** — clean-code violation creating lasting tech debt.
- **LOW** — minor observation.
- **NIT** — style nitpick.

### 5. Present and ask the user what to do

> Audit found `<N>` issues: HIGH=`<H>` MEDIUM=`<M>` LOW=`<L>` NIT=`<I>`.
>
> A) Post all HIGH as inline comments (recommended for HIGH — they affect mergeability)
> B) Post selected issues — give comma-separated issue numbers from the table
> C) Just print the report — don't post (default for read-only audit)
> D) Discuss — drill into a specific finding
>
> Reply: A / B / C / D

Default is C. Posting is a public action; never default it.

### 6. On A or B — post inline comments

For each selected issue:

- Compose comment body:
  ```
  **[`<principle>`]** <observed>

  <should-be recommendation>

  _— audited via /kmm-audit (kmm-migration-workflow)_
  ```

- Use `gh api repos/<owner>/<repo>/pulls/<pr>/comments -F path=<file> -F line=<line> -F body=<body>` for inline comments. Use `gh pr review <pr> --comment ...` for general comments (cross-cutting findings).

- Throttle: post one, capture response, post the next. Don't batch via shell loop (`gh` rate-limits).

After posting, print summary:
```
Posted <N> comments on PR <url>:
  - <file>:<line> — <one-line>
```

### 7. On C — print and exit

Audit report preserved at `<repo>/.kmm-audit/<pr-or-branch>/audit-report.md`. Print path and exit.

### 8. Constitution check

Touched: §3 (no silent decisions), §4 (live-sourced reasoning — every finding cites a principle), §12 (audit report is the audit's documentation).

Checklist:
- `[ ]` Diff fully read by the auditor
- `[ ]` Every finding cites a principle or section
- `[ ]` No comments posted without user approval

## What you MUST NOT do

- Do not modify the audited PR's code.
- Do not post comments without explicit user opt-in.
- Do not invent findings.
- Do not run `/kmm-verify` — verify is for skill-made migrations.
- Do not push branches or create PRs.

## Failure modes

- **`gh` not authenticated** — surface error; tell user `gh auth login`. Don't retry.
- **PR not found** — surface; offer retry with different identifier.
- **Auditor returns malformed `AUDIT_REPORT`** — escalate to user with output.
- **Diff is enormous (>5000 lines)** — print warning, ask whether to proceed or scope to a subset of files.
- **Merge conflicts with base** — diff may be ambiguous. Surface; user picks head-only or rebased state.
