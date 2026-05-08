---
description: Assemble PR title and body from spec.md, plan.md, migration-guide.md, migration-report.md, tasks.md. Show user. On confirmation, run gh pr create.
---

# /kmm-pr

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md` first.

`/kmm-verify` must have returned `VERIFY_COMPLETE_PASS` before this command runs. If verification has not passed, refuse and tell the user to run `/kmm-verify` first.

Every deviation in `migration-report.md` must be `CLOSED`, `RATIFIED`, or `SUPERSEDED` — no `OPEN` deviations may ship. If any are `OPEN`, list them and refuse.

## Inputs

- `<repo>/kmm/<scope>/spec.md`
- `<repo>/kmm/<scope>/plan.md`
- `<repo>/kmm/<scope>/migration-guide.md`
- `<repo>/kmm/<scope>/migration-report.md`
- `<repo>/kmm/<scope>/tasks.md`
- `<repo>/.worktrees/kmm-<scope>/`

## What you do

### 1. Verify pre-conditions.

- `tasks.md` has zero unchecked tasks.
- `/kmm-verify` last result was `VERIFY_COMPLETE_PASS` — find this in the most recent `tasks.md` commit log or the `migration-report.md`.
- All deviations in `migration-report.md` are non-`OPEN`.
- The worktree's branch is `feature/kmm-<scope>` (or whatever the user named at `/kmm-specify`).
- The worktree's working tree is clean (`git status` shows no uncommitted changes).

If any pre-condition fails, list them and stop.

### 2. Assemble the PR draft.

Use this structure:

**Title** (under 70 chars):
```
kmm: migrate <scope> to commonMain
```
or, if `spec.md` declared a more specific user-facing goal, derive from there.

**Body**:
```markdown
## Summary

<one-paragraph summary derived from spec.md's user goal and plan.md's context>

Baseline SHA: <baseline-locked-sha from spec.md>
Declared shared targets: <list from spec.md>

## Files migrated

<one bullet per file from migration-guide.md, format:>
- `<source path>` → `<target path>` — <one-line classification + key swaps>

Total: <N> files

## Library swaps

<table from findings.md "Library Versions" — library | from | to | source>

## Deviations

<for each entry in migration-report.md:>
- **D-N (<status>)**: <title>. <one-line root cause>. <one-line closure>.

If no deviations: "None."

## Verification

- Per-target compile: <list of targets and pass>
- Baseline tests: <count> green on <jvm/ios/etc.>
- Consumer compile: <list>
- `/kmm-verify` result: VERIFY_COMPLETE_PASS

## Test plan

- [ ] Reviewer: pull the branch, run `<test command from spec.md>` locally
- [ ] Reviewer: confirm consumer apps build clean against the migrated module
- [ ] Reviewer: skim `<repo>/kmm/<scope>/migration-report.md` deviations
- [ ] Reviewer: skim `<repo>/kmm/<scope>/migration-guide.md` for any file you have history with

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

The footer uses the standard "Generated with Claude Code" line — only because this PR was assembled by the orchestrator from on-disk artifacts. The footer is acceptable here because it is metadata, not migration code.

### 3. Show the draft to the user.

Print the full title and body in chat, in a fenced markdown block. Tell the user:

> Draft PR ready. Reply "ok" to push and open the PR, "edit" to revise the body, or paste the changes you want.

Wait for the user to respond. Apply edits if requested. Loop until the user says go.

### 4. Push and open the PR.

When the user approves:

1. Push the branch: `git push -u origin feature/kmm-<scope>`
2. Run:
   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )"
   ```
   Use a heredoc to preserve formatting.
3. Capture the PR URL `gh pr create` returns.

### 5. Constitution check.

- Touched: §2 (no silent decisions — user approved the draft), §5 (PR scope matches spec scope), deviations governance (no `OPEN` deviations shipping).
- Pass/fail:
  - `[ ]` Pre-conditions all green
  - `[ ]` Draft assembled from on-disk artifacts (no chat-context inference)
  - `[ ]` User approved the draft text
  - `[ ]` Branch pushed
  - `[ ]` PR created
- On fail: STOP. Report which checks failed.

### 6. Skill retrospective (auto-trigger).

Dispatch the `skill-retrospector` subagent (read-only, sonnet) with the scope's artifact paths. The subagent reads migration-report.md / tasks.md / spec.md and produces a project-agnostic markdown block on what worked / where the skill drifted / what could still improve.

Write the result to `<repo>/kmm/<scope>/skill-retro.md` and print it to the chat (so the user can copy it into an issue on the skill repo without re-fetching).

This is automatic — no user prompt. The cost (one read-only sonnet dispatch) is small relative to the value of capturing skill-improvement signals while context is fresh.

### 7. Final report.

- Print the PR URL.
- Summary: files migrated, deviations (count by status), tests green.
- Print the skill retrospective block (verbatim from `skill-retro.md`) under a clearly-marked section.
- Tell the user: "Migration `<scope>` is open as <URL>. Skill retrospective at `kmm/<scope>/skill-retro.md` — copy into an issue on the skill repo or apply directly to skill files. Worktree at `.worktrees/kmm-<scope>/` can stay until merged or be removed with `git worktree remove`."

## What you do NOT do

- Do not run `gh pr create` without user confirmation. The skill never silently opens PRs.
- Do not edit the migrated code. The PR ships exactly what `/kmm-verify` validated.
- Do not push to `main`/`master`. The branch is always `feature/kmm-<scope>`. If the user asks to push to main, refuse — that is destructive and outside the migration workflow.

## Failure modes

- **`gh` is not authenticated** — surface the error, tell the user to run `gh auth login`. Do not retry.
- **Branch already has a PR** — `gh pr create` will say so. Surface the existing PR URL; ask the user whether to update it (`gh pr edit`) or open a new one.
- **Push rejected** — likely upstream has new commits on `main`/`master`. Stop and tell the user; never force-push.
- **An `OPEN` deviation appears mid-flow** — refuse. Tell the user to either `CLOSE`/`RATIFY` it (with explicit approval recorded in `migration-report.md`) or revisit the migration.
