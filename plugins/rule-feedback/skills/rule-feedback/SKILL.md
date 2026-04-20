---
name: rule-feedback
description: End-of-session auditor that reviews the conversation for rule corrections, clarifications, and "always/never" directives the user gave Claude, then drafts GitHub Issues proposing amendments to CLAUDE.md, path-scoped rules, or the project constitution. The user reviews and approves each issue before it is created — nothing is written to rules and no issues are posted without explicit approval. Trigger on "rule feedback", "rule audit", "what did I miss", "review session", "session retro", "audit CLAUDE.md", "audit constitution", "feedback on rules", "raise rule issues", "/rule-feedback", or any request to close the loop between session corrections and durable rule updates. Skip silently if the session produced no rule-worthy corrections.
---

# Rule Feedback

Close the loop between "Claude missed a rule" and "CLAUDE.md / constitution / path-scoped rules get amended."

The skill scans the current conversation for correction signals, groups them into candidate amendments, presents them for review, and — with explicit approval — creates GitHub Issues that can be triaged and implemented later.

## Non-goals

- Does NOT auto-amend `CLAUDE.md`, `.claude/rules/*`, `.specify/memory/constitution.md`, or memory files.
- Does NOT create issues without explicit user approval per item.
- Does NOT nag on clean sessions — if nothing rule-worthy surfaced, say so and exit.

## Prerequisites

1. **GitHub CLI**: `gh auth status` must succeed.
2. **Target repo config**: `~/.claude-rule-feedback-config.json` with:
   ```json
   { "repo": "<owner>/<repo>" }
   ```
   If missing, ask the user for the repo once (e.g., `PunchHQ/sniper-v2-android`) and create the file.
3. **Labels**: ensure the target repo has these labels (create idempotently on first run):
   - `rule-feedback` — all issues raised by this skill
   - `claude-md` — candidate CLAUDE.md amendment
   - `constitution` — candidate constitution amendment (requires `/speckit.constitution` rerun)
   - `path-rule` — candidate amendment to a `.claude/rules/*.md` file
   - `memory-only` — capture in `memory/feedback_*.md`, not a rule change
   - `priority:P0`, `priority:P1`, `priority:P2`

   One-shot creation:
   ```bash
   for label in rule-feedback claude-md constitution path-rule memory-only; do
     gh label create "$label" --repo "$REPO" --color "0E8A16" --description "rule-feedback: $label" 2>/dev/null || true
   done
   for p in P0 P1 P2; do
     gh label create "priority:$p" --repo "$REPO" --color "D93F0B" 2>/dev/null || true
   done
   ```

## Workflow

Read each referenced file BEFORE executing the matching phase.

### Phase 0 — Pre-flight

1. Run `gh auth status`. If not authed, stop and tell the user.
2. Read `~/.claude-rule-feedback-config.json`. If missing, ask for `owner/repo` and write it.
3. Ensure the labels listed above exist on the target repo (idempotent `gh label create`, ignore errors if they already exist).

### Phase 1 — Detection

Read `references/detection-patterns.md` and follow its instructions.

Scan the current conversation for correction signals. Build a **candidate list** where each candidate has:
- The verbatim quote from the user (trimmed to relevant sentence).
- Claude's interpretation of what rule this relates to.
- A classification: `claude-md`, `constitution`, `path-rule`, or `memory-only`.
- A proposed title and priority.

If the candidate list is empty, say so plainly and exit. Do not invent candidates.

### Phase 2 — Review gate (mandatory)

Read `references/review-gate.md` and follow its instructions.

Present the candidates one at a time (not all at once — the user should make deliberate decisions). For each:
1. Show: quote, interpretation, classification, proposed title, draft body.
2. Ask: **approve / edit / drop**. If edit, accept revisions and re-show.
3. Record the decision.

After all candidates are reviewed, show a final confirmation list ("About to create N issues: …") before moving to Phase 3.

### Phase 3 — Issue creation

Read `references/issue-template.md` and follow its instructions for title/body formatting.

For each approved candidate:
```bash
gh issue create \
  --repo "$REPO" \
  --title "<title>" \
  --label "rule-feedback,<classification>,priority:<P>" \
  --body "<body from template>"
```

Collect the URLs and return them in a tidy list to the user. Example:
```
Created 3 issues:
- https://github.com/PunchHQ/sniper-v2-android/issues/331 [claude-md, P1] Clarify "fast and solid" timing budgets
- https://github.com/PunchHQ/sniper-v2-android/issues/332 [constitution, P2] Add amendment re: StrictMode in debug builds
- https://github.com/PunchHQ/sniper-v2-android/issues/333 [path-rule, P2] compose.md missing `rememberSaveable` guidance
```

## Key principles

1. **User approves every issue.** Pattern detection is fuzzy; false positives produce noise the user has to clean up. Review gate is non-negotiable.
2. **One candidate = one issue.** Do not bundle unrelated feedback into a single issue; traceability matters.
3. **Silent on clean sessions.** Perfect sessions get zero issues. No "looks good ⭐" issues.
4. **Actionable, not aspirational.** Every issue body must name the specific file + section to amend. Vague issues ("improve CLAUDE.md") are dropped during review.
5. **Do not amend rules directly.** Issues are the unit of change; a separate workflow (review, discuss, amend, commit) handles implementation.
