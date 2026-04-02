---
name: issue-resolver
description: >
  Automated issue resolution pipeline. Use when the user asks to "fix issues",
  "resolve open issues", "solve issues and raise PR", "check issues for <skill/project>",
  "fix GitHub issues", or any request to batch-resolve open issues from a GitHub repo
  and raise a PR with the fixes. Handles the full cycle: fetch → plan → fix → PR → self-review → fix gaps.
argument-hint: "[skill-name or label filter]"
---

# Issue Resolver

Automated pipeline that resolves open GitHub issues, raises a PR, self-reviews for gaps, and fixes them.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- Git repo with a remote (the skill reads issues from the remote's repo)

## On Invocation

Ask the user:
1. **Scope** — which issues to resolve? Options:
   - A specific skill/label (e.g., `skill:kmm-workflow`)
   - All open issues
   - Specific issue numbers (e.g., `#24, #28, #33`)
2. **Branch strategy** — create a new branch or use an existing one?

If the user provides a skill name or label as an argument, skip question 1 and use that as the filter.

## Pipeline

Execute these phases in order. Do NOT skip phases.

```
Phase 1: FETCH → Phase 2: PLAN → Phase 3: FIX → Phase 4: PR → Phase 5: REVIEW → Phase 6: FIX GAPS → Done
```

---

### Phase 1: FETCH

Gather all issues to resolve.

1. Run `gh issue list --state open --json number,title,labels,body` (add `--label <label>` if user specified a filter)
2. Read each issue body fully — issues contain specific file paths, code snippets, and suggested changes
3. Present a summary table to the user:

```
Found N open issues:

| # | Title | Priority | Key changes |
|---|-------|----------|-------------|
| 24 | Runtime bugs at checkpoints | P1 | auditor audit step, stub scan |
| 28 | onClick handlers unwired | P1 | ui-migrator onClick audit |
...

Proceed with all N? Or pick specific ones?
```

4. Wait for user confirmation before proceeding

---

### Phase 2: PLAN

Analyze all issues and identify the full set of changes needed.

1. **Map issues to files** — for each issue, identify every file that needs modification. Issues often contain exact file paths and suggested content.
2. **Detect overlaps** — multiple issues may touch the same file. Group changes by file to avoid conflicts.
3. **Identify new files** — some issues require creating new reference files, scripts, or templates.
4. **Version bump** — check if the target has a `plugin.json`, `marketplace.json`, or version in `README.md`. Plan the version bump.
5. **Present the plan** — show the user which files will be modified/created and which issues each change addresses. Wait for approval.

**Planning rules:**
- Read every file you plan to modify BEFORE proposing changes
- Never propose changes to files you haven't read
- Cross-reference issues — later issues may depend on or extend earlier ones
- If an issue's suggested change conflicts with another issue, flag it to the user

---

### Phase 3: FIX

Implement all changes.

1. **Create branch** — `git checkout -b fix/<scope>-open-issues` (e.g., `fix/kmm-workflow-open-issues`)
2. **Parallelize independent work** — use subagents for:
   - New files (no conflicts possible)
   - Files only touched by one issue
3. **Serialize shared files** — files touched by multiple issues must be edited sequentially
4. **Version bump** — update `plugin.json`, `marketplace.json`, `README.md` as needed. **Keep descriptions concise (2-3 lines max).** The description should reflect what the plugin does as a whole, NOT enumerate every change being merged. Do not append new learnings/features to the description string — rewrite it if needed to stay concise.
5. **Commit** — one commit covering all issue fixes. Message format:
   ```
   fix: resolve N open <scope> issues — <brief summary>

   Addresses #X, #Y, #Z.
   <one-line summary per issue>
   ```
6. **Push** — `git push -u origin <branch>`

**Execution rules:**
- Use `mode: "bypassPermissions"` on all subagents
- Maximize parallelism — launch independent agents concurrently
- Every issue's changes must be fully implemented. No partial fixes, no deferrals.
- If an issue requires research (web search, Context7), do it during this phase

---

### Phase 4: PR

Create the pull request.

1. Run `git diff <base-branch>...HEAD --stat` to confirm all changes
2. Create PR with `gh pr create`:
   - Title: `fix: resolve N open <scope> issues (vX.Y.Z)` (under 70 chars)
   - Body format:

```markdown
## Summary
<1-2 sentence overview>

### Issues resolved
| Issue | Title | What was done |
|-------|-------|---------------|
| #N | <title> | <one-line summary> |

### Files changed
- **New:** <list new files with one-line descriptions>
- **Modified:** <list modified files with one-line descriptions>

### Version
<old> → <new>

Closes #X, closes #Y, closes #Z

## Test plan
- [ ] <verification items>

Generated with [Claude Code](https://claude.com/claude-code)
```

3. Return the PR URL

---

### Phase 5: REVIEW

Self-review the PR for issues and gaps. This is the critical quality gate.

1. **Dispatch review agents in parallel** — one per logical area:
   - Each agent reads the FULL current state of its assigned files (not just the diff)
   - Checks for: inconsistencies, contradictions between files, broken cross-references, factual errors, renumbering gaps, duplicate content, logical ordering problems, format inconsistencies
2. **Compile findings** — collect all issues from all review agents
3. **Classify by severity:**
   - **HIGH** — will cause incorrect behavior, factual errors, contradictions between files, broken workflows
   - **MEDIUM** — gaps, missing cross-references, inconsistent formatting, unclear instructions
4. **Present findings** to the user:

```
Review found N issues:

### HIGH (N)
| # | File | Issue |
|---|------|-------|
| 1 | migrator.md | Step ordering causes duplicate class errors |

### MEDIUM (N)
| # | File | Issue |
|---|------|-------|
| 7 | SKILL.md | Workflow diagram missing Phase 1 |

Fix all HIGH + MEDIUM?
```

5. Wait for user confirmation

**Review rules:**
- Review agents must read COMPLETE files, not just diffs
- Cross-file consistency is the highest priority — the same concept described in two files must not contradict
- Check that every reference to a file path, task number, or section name is still valid after changes
- Check factual claims against live sources (web search) if they involve library versions or API availability
- Do NOT skip this phase. Ever.

---

### Phase 6: FIX GAPS

Fix all issues found during review.

1. **Dispatch fix agents** — parallelize where possible (same rules as Phase 3)
2. **Commit** — separate commit for review fixes:
   ```
   fix: resolve N review issues — <brief categories>
   ```
3. **Push** and update PR description to include the review fixes section
4. If the fixes were substantial (>5 HIGH issues), run a **mini-review** (Phase 5 again, scoped to only the files changed in Phase 6). Otherwise, skip.

---

## Rules

- **All decisions through the user.** Present findings, propose approach, wait for confirmation at each phase boundary.
- **Read before writing.** Never modify a file you haven't read in this session.
- **Maximize parallelism.** Independent agents run concurrently. Use `mode: "bypassPermissions"` on all subagents.
- **No partial fixes.** Every issue must be fully resolved or explicitly flagged as blocked with rationale.
- **Version bump on every PR.** If the target has versioned metadata, bump it.
- **Self-review is mandatory.** Phase 5 is never skipped. The review catches issues that the initial fix misses — this has been validated empirically.
- **Factual claims require live verification.** If any change involves library versions, API availability, or platform support — verify via web search + Context7 before writing. Training data is not reliable for fast-moving ecosystems.
