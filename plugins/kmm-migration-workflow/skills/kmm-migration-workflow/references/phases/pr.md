# Phase: pr

Assembles the PR title and body for the active checkpoint, shows the user, opens the PR on confirmation.

When the migration is checkpointed (Constitution §13), this phase runs once per checkpoint.

Verify-phase must have returned `VERIFY_COMPLETE_PASS` for the active checkpoint. Every deviation scoped to this checkpoint must be `CLOSED`, `RATIFIED`, or `SUPERSEDED`.

Read `constitution.md` first.

## Inputs

- `spec.md`, `architecture.md`, `plan.md`, `migration-guide.md`, `migration-report.md`, `tasks.md`
- The worktree
- The active checkpoint name

## Steps

### 0. Auto-revert the `.broken`-rename sentinel (if present)

If specify-phase's master health sweep had to `.broken`-rename pre-existing-broken files for the local T-LOCK gate, a sentinel commit exists with message starting `chore(kmm-prelock): broken-rename`. The sentinel is not part of the migration's substance — auto-revert before opening the PR.

1. Find the sentinel: `git log --grep="^chore(kmm-prelock): broken-rename" --pretty=%H -n 1`
2. If none, skip.
3. Find renamed files: `git show --name-status <sentinel-sha> | grep -E "^R" | awk '{print $2, $3}'`
4. Revert each rename via `git mv` and emit a single revert commit:

```
chore(kmm): kmm-prelock-revert — restore .kt files to surface pre-existing breakage to reviewers

The .broken renames were a local workaround so :app:compileXxxUnitTestKotlin
could pass during T-LOCK. They are unrelated to this migration's substance.
The N pre-existing-broken test files are listed in the PR body under
"Pre-existing master breakage (NOT touched by this PR)".

D-1 closure: { type: "commit:present", message-fragment: "kmm-prelock-revert" }
```

5. Close D-1 in `migration-report.md`: `Closed-by: commit <sha-of-revert-commit>`.
6. Capture the list of `.broken`-renamed files for the PR body's "Pre-existing master breakage" section.

### 1. Verify pre-conditions

The active checkpoint is the lowest-numbered with all `[x]` tasks and no recorded PR URL. Pre-conditions:

- All tasks `[x]`.
- Last verify result was `VERIFY_COMPLETE_PASS`.
- All deviations attached to this checkpoint are non-`OPEN`.
- The branch is the checkpoint's branch (`feature/kmm-<scope>-<checkpoint>` for multi-PR, `feature/kmm-<scope>` for single-PR).
- Working tree clean (`git status` shows no uncommitted changes).

If any fails, list and stop.

### 1b. Branch policy

**Single checkpoint:** branch `feature/kmm-<scope>`. PR opens against base.

**Multi-checkpoint:** each checkpoint gets its own branch, stacked from the previous. CP-K's PR opens against CP-(K-1)'s branch (or against base after CP-(K-1) merges).

### 2. Assemble the PR draft

Scoped to the active checkpoint, not the whole migration.

**Title** (under 70 chars):
```
kmm(<checkpoint>): <one-line goal>
```

For single-checkpoint: `kmm: migrate <scope> to commonMain`.

**Body**:
```markdown
## Summary

<one-paragraph plain-language summary: what this checkpoint accomplishes, why it's safe to merge in isolation>

Checkpoint: <K of N> — <name>
Baseline SHA: <baseline-locked-sha>
Declared shared targets: <list>

## Files in this checkpoint

- `<source>` → `<target>` — <relocation / swap / refactor / mixed>

Total: <N> files (this checkpoint), <T> files (whole migration)

## Refactors applied (this checkpoint)

- **R-N**: <title> — <clean-code violation>. Behaviour invariant pinned by `<test name>`.

If none: "None — this checkpoint is <relocation | swaps>."

## Library swaps (this checkpoint)

<table from findings.md, filtered to swaps applied here>

## ⚠️ Pre-existing master breakage (NOT touched by this PR)

<emit ONLY if step 0 reverted a sentinel. Otherwise omit.>

`<consumer>:compileXxxUnitTestKotlin` fails on master at the baseline SHA `<baseline-master-sha>` due to API drift in N unrelated test files. This PR's verification uses scope-focused commands, so this PR's CI does not depend on the broken test compile.

If your local / CI environment runs the full app unit test suite, you'll hit these failures. The project convention is to rename to `<name>.kt.broken`. The N files are:

<bulleted list>

These were temporarily `.broken`-renamed earlier on this branch and reverted before merge so this PR shows only the migration's substance.

## Deviations (this checkpoint)

- **D-N (<status>)**: <title>. <one-line root cause>. <one-line closure>.

If none: "None."

## Verification

- Per-target compile: <list and pass>
- Baseline tests: <count> green on <jvm/ios/etc.>
- Consumer compile: <list>
- Smoke (JVM): <test fqn> green
- Smoke (instrumented): <test fqn> green | n/a
- Verify result: VERIFY_COMPLETE_PASS

## Master-mergeable

This checkpoint compiles and passes tests independently. Does not depend on later checkpoints landing.

## Next checkpoints

- CP-<K+1>: <name> — <one-line goal>

If last: "None — this completes the `<scope>` migration."

## Test plan

- [ ] Pull the branch, run `<test command>` locally
- [ ] Confirm consumer apps build clean
- [ ] Skim `<repo>/kmm/<scope>/migration-report.md` deviations
- [ ] Skim relevant `migration-guide.md` entries

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Plain language in Summary (Constitution §15). Technical proper nouns appear in labelled sections.

### 3. Show the draft

Print the title and body in chat in a fenced markdown block:

> Draft PR ready. Reply "ok" to push and open the PR, "edit" to revise, or paste changes.

Apply edits if requested. Loop until user says go.

### 4. Push and open

When approved:

1. `git push -u origin <branch>`.
2. ```bash
   gh pr create --base <base> --title "<title>" --body "$(cat <<'EOF'
   <body>
   EOF
   )"
   ```
3. Capture the PR URL.
4. Record the PR URL inline in `tasks.md` next to the checkpoint header.

### 5. Constitution check

Touched: §3, §6, §13.

Checklist:
- `[ ]` Pre-conditions all green
- `[ ]` Draft assembled from on-disk artifacts (no chat-context inference)
- `[ ]` User approved the draft text
- `[ ]` Checkpoint branch pushed
- `[ ]` PR created and URL recorded

### 6. What's next

- **More checkpoints remain:** route back to implement-phase for `CP-(K+1)`. Print: `── implement (CP-<K+1>) ──`. The user can choose to merge first or stack.
- **Final checkpoint:** print summary and stop. Skill retrospective is opt-in via `/kmm-retro` — not auto-dispatched.

### 7. Final report (only on final checkpoint)

- Print every checkpoint PR URL in order.
- Summary: total files migrated, refactors applied, deviations (count by status), tests green.
- "Migration `<scope>` is open as `<N>` checkpoint PRs (URLs above). Worktree at `.worktrees/kmm-<scope>/` can stay until all PRs merge or be removed with `git worktree remove`. Run `/kmm-retro` if you want a skill retrospective."
- Offer on-device validation (one-line opt-in, same pattern as `/kmm-retro` — public action, never default): "Validate the migration on a device before merging? Run `/kmm-qa <scope>` — same no-silent-patches discipline as `/kmm`. [skip / `/kmm-qa <scope>`]"

## Failure modes

- **`gh` not authenticated** — surface error; tell the user `gh auth login`. Don't retry.
- **Branch already has a PR** — surface existing URL; ask whether to update (`gh pr edit`) or open new.
- **Push rejected** — upstream has new commits on base. Stop; never force-push.
- **An `OPEN` deviation appears mid-flow** — refuse. Tell the user to either CLOSE/RATIFY (with explicit approval recorded) or revisit the migration.
