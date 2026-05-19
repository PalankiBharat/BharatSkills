---
name: share-prod
description: >
  Fast path for triggering a CircleCI production build of sniper-v2-android via
  the `scripts/share_build.sh` script and getting a Slack ping when it's done.
  Use whenever the user asks to "share build", "share prod", "share a prod
  build", "kick off CI", "trigger circleci", "fire a build", "share apk", or
  any variant that means "I want CI to build this branch and post it to
  Slack." Handles the pre-flight every time: commits + pushes pending work
  first, because CircleCI builds the remote branch — anything still local
  won't be in the build. Stays out of the SDK-coupled flow (see
  docs/claude/SHARE.md) which is a deeper workflow the user invokes
  separately when the local finance SDK is wired in.
---

# Share Prod Build

## What this does

Triggers a CircleCI production-flavor build of the current branch of
`sniper-v2-android` by running `bash scripts/share_build.sh`. The script
hits the CircleCI API; CircleCI checks out the current branch from
origin and builds it; on success a Slack DM lands with the APK link
addressed to `$SLACK_USER_ID`.

## Why pre-flight matters

CircleCI builds the **remote** branch. Anything that lives only in the
working tree or in unpushed local commits is invisible to CI. Skipping
the pre-flight is the most common reason a "shared" build doesn't
contain the change the user just made — and the failure is silent (the
build succeeds, it just builds the wrong code).

So before running the script, this skill makes sure the remote branch
actually reflects what the user wants to share.

## Pre-flight steps

Run these in order from the sniper-v2-android working directory. The
session's CWD is already the repo root; no `cd` needed.

### 1. Confirm we're in the right repo

```bash
git rev-parse --show-toplevel
```

If the path doesn't end in `sniper-v2-android` (or the user's expected
repo name), stop and ask the user where they meant to run this. The
`share_build.sh` script will fail loudly anyway if it's not in the
repo, but a clear question up front is friendlier.

### 2. Check working tree state

```bash
git status --porcelain
```

- **Empty output** → working tree clean. Skip to step 4.
- **Non-empty** → there are uncommitted changes. Go to step 3.

### 3. Commit uncommitted changes (only if needed)

Show the user the diff and ask if they want it committed before the
share. If yes:

- Stage the relevant files by name (not `git add -A` — too easy to
  pick up secrets or noise).
- Write a one-line commit message describing the change.
- Commit, including the standard `Co-Authored-By: Claude` trailer.

If the user says "no, share without these changes" — that's their
call, proceed but warn them explicitly that those changes won't be in
the build.

### 4. Check sync with origin

```bash
git fetch origin
git status -sb
```

- **Up to date with origin** → skip to step 5.
- **Ahead of origin by N commits** → `git push` first. Without this,
  CircleCI will build the older commit on the remote.
- **Behind origin** → tell the user; ask whether to pull first or
  proceed.
- **Diverged** → stop, surface the divergence, ask how to resolve.

### 5. Verify Firebase release notes reflect this branch

The shared build will show up in Firebase App Distribution with the
release notes from `app/firebase/releasenotes.txt`. If those notes
are from a different branch or are stale, the QA team will read the
wrong story about what changed. Warn the user before triggering so
they can fix it (or knowingly skip it).

Three checks, in order:

**A. File exists.**

```bash
ls app/firebase/releasenotes.txt
```

If missing → warn the user the build will go out with no release
notes and confirm before continuing.

**B. First line matches the current branch.**

```bash
head -1 app/firebase/releasenotes.txt
git branch --show-current
```

The first line should be `Branch: <current-branch>`. If it names a
different branch, the file is leftover from a prior branch's work
— warn the user; the convention (see `docs/claude/COMMIT.md`) is to
clear the file and rewrite it for the new branch on the first
commit. Offer to invoke the project's commit workflow (which
regenerates the notes) before triggering.

**C. File hasn't fallen behind branch commits.**

```bash
git log --oneline --no-merges master..HEAD -- ':!app/firebase/releasenotes.txt'
git log --oneline -- app/firebase/releasenotes.txt | head -1
```

If the most recent commit on the branch that *isn't* a release-notes
update sits after the most recent commit that touched the release
notes file, the notes are likely stale — recent changes haven't been
described. Surface that and ask the user whether to update notes
first or proceed anyway.

In all three cases the action is **warn, ask, do not block**. The
user is the one who knows whether the missing/stale notes matter for
this particular share.

### 6. Trigger the build

```bash
bash scripts/share_build.sh
```

The script reads `$CIRCLE_TOKEN` and `$SLACK_USER_ID` from the
environment. If either is missing it exits with a link to the setup
guide — pass that link back to the user verbatim, don't try to set
them yourself.

A successful trigger looks like a JSON response with a pipeline id.
Show that to the user so they have proof CI accepted the request.

### 7. Tell the user what to expect

After a successful trigger, the user typically wants to know:
- Which branch will be built (whatever `git symbolic-ref --short HEAD`
  returned at script time).
- Roughly when the Slack DM will land (CI build time, usually
  10–20 min for this app).
- That further changes after this point won't be in *this* build —
  they'd need another share.

## SDK-coupled awareness

If the local finance SDK is wired into this repo's `settings.gradle`
(`include ':finance'` uncommented), a plain CircleCI build won't see
local SDK edits — CI builds against whatever published artifact
`finance_chart_version` in `build.gradle` points at. That's a deeper
workflow that involves bumping an alpha tag, publishing the SDK to
Nexus, and switching the app's `build.gradle` over before triggering
CI. That flow lives in `docs/claude/SHARE.md` and is invoked by the
user as a deliberate multi-step process — not as part of this
shortcut.

This skill is for the standalone case. If the user runs this skill
with the local SDK wired in, mention the foot-gun once so they can
confirm they really want the standalone path before triggering.

## Triggers

"share build", "share prod", "share a prod build", "share production",
"kick off circleci", "trigger circleci", "fire a build", "share apk",
"build and share with team", "circleci share"
