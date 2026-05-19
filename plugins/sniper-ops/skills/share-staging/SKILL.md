---
name: share-staging
description: >
  Fast path for triggering a CircleCI staging build of sniper-v2-android via
  the `scripts/share_build_staging.sh` script. Use whenever the user asks to
  "share staging", "share a staging build", "fire a staging build", "trigger
  staging on circleci", "share apk staging", or any variant that means "I
  want CI to build this branch against the staging environment and post it
  to Slack." Same pre-flight as the prod variant — commit + push pending
  work first, because CircleCI builds the remote branch and unpushed work
  is silently absent from the build. Sister skill to share-prod; both
  defer to docs/claude/SHARE.md for the SDK-coupled workflow.
---

# Share Staging Build

## What this does

Triggers a CircleCI staging-flavor build of the current branch of
`sniper-v2-android` by running `bash scripts/share_build_staging.sh`.
The only difference from `share-prod` is the `action: "build_staging"`
parameter in the CircleCI API call — that swaps the build flavor to
`staging`. Otherwise the flow is identical.

## Why pre-flight matters

CircleCI builds the **remote** branch. Anything that lives only in the
working tree or in unpushed local commits is invisible to CI. Skipping
the pre-flight is the most common reason a "shared" build doesn't
contain the change the user just made — and the failure is silent (the
build succeeds, it just builds the wrong code).

## Pre-flight steps

Run these in order from the sniper-v2-android working directory.

### 1. Confirm we're in the right repo

```bash
git rev-parse --show-toplevel
```

If it doesn't end in `sniper-v2-android`, stop and ask the user where
they meant to run this.

### 2. Check working tree state

```bash
git status --porcelain
```

- **Empty** → clean, skip to step 4.
- **Non-empty** → uncommitted changes, go to step 3.

### 3. Commit uncommitted changes (only if needed)

Show the user the diff and ask if they want it committed before the
share. If yes:

- Stage relevant files by name.
- Write a one-line commit message describing the change.
- Commit with the standard `Co-Authored-By: Claude` trailer.

If the user says "share without these" — proceed, but warn explicitly
that those changes won't be in the build.

### 4. Check sync with origin

```bash
git fetch origin
git status -sb
```

- **Up to date** → skip to step 5.
- **Ahead** → `git push`.
- **Behind / diverged** → surface to the user, don't auto-resolve.

### 5. Verify Firebase release notes reflect this branch

The shared build will show up in Firebase App Distribution with the
release notes from `app/firebase/releasenotes.txt`. If those notes
are stale or from a different branch, QA reads the wrong story. Warn
the user before triggering.

**A. File exists.**

```bash
ls app/firebase/releasenotes.txt
```

Missing → warn, confirm before continuing.

**B. First line matches the current branch.**

```bash
head -1 app/firebase/releasenotes.txt
git branch --show-current
```

The first line should be `Branch: <current-branch>`. If it names a
different branch, the file is leftover from prior work — warn; the
convention (see `docs/claude/COMMIT.md`) is to clear and rewrite it
for the new branch on the first commit. Offer to invoke the
project's commit workflow before triggering.

**C. File hasn't fallen behind branch commits.**

```bash
git log --oneline --no-merges master..HEAD -- ':!app/firebase/releasenotes.txt'
git log --oneline -- app/firebase/releasenotes.txt | head -1
```

If the most recent non-release-notes commit on the branch sits after
the most recent commit that touched the release notes, the notes
are likely stale. Surface and ask whether to update first or proceed.

Action in all three cases: **warn, ask, do not block.** The user
decides whether stale notes matter for this share.

### 6. Trigger the build

```bash
bash scripts/share_build_staging.sh
```

The script reads `$CIRCLE_TOKEN` and `$SLACK_USER_ID` from the
environment. If either is missing it exits with a setup-guide link —
pass that link back to the user verbatim, don't try to set them.

Show the JSON pipeline-id response so the user has proof CI accepted
the request.

### 7. Tell the user what to expect

- Which branch will be built.
- Build is staging-flavored — points at staging backends, NOT prod.
- Roughly when the Slack DM will arrive.
- Further changes after this point won't be in *this* build.

## When staging vs prod

If the user just says "share build" without qualifier, treat it as
prod (that's the convention in `docs/claude/SHARE.md` and the project
CLAUDE.md). This skill is only for explicit staging requests:
"staging", "stage", "staging build", "staging apk".

## SDK-coupled awareness

Same as share-prod: if the local finance SDK is wired into
`settings.gradle` (`include ':finance'` uncommented), CI won't see
local SDK edits — it builds against the published artifact pinned by
`finance_chart_version`. The full SDK-coupled flow lives in
`docs/claude/SHARE.md` and is invoked deliberately, not as part of
this shortcut. If the local SDK is wired in, mention the foot-gun
once so the user can confirm before triggering.

## Triggers

"share staging", "share a staging build", "fire staging on ci",
"trigger staging build", "staging apk to slack", "share stage",
"staging share", "kick off staging build"
