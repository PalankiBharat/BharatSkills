---
name: retro-triage
description: Triage a skill's session retro (retro.md / improvement backlog) into reviewed, version-bumped skill edits and a PR. Use whenever the user wants to fold a retro into a skill — "triage the retro for <skill>", "/retro-triage", "apply the retro to my skill", "turn retro.md into a PR", "work through the retro one by one", or hands you a retro file (path or pasted) plus the name of the skill they're working on. The retro is a list of CANDIDATE changes, not approved ones — this skill reads the whole target skill first, distills the retro into distinct candidates, gets the user's approval one-by-one (each with a recommended option + reasoning), reconciles candidates against the skill's own refuted/learned notes, then implements surgically in a worktree and ships a PR. Reach for it any time the input is "a retro + a skill to improve," even if the user doesn't say the word "triage."
---

# Retro Triage — fold a skill's retro into a reviewed PR

A retro (often `retro.md` or an `improvements.md` backlog) is what a self-improving skill emits after
a real run: friction, false positives, proposed changes — each **evidence-backed but unapproved**.
Your job is to turn that raw list into *reviewed, surgical* skill edits and a clean PR, without the
user having to babysit every keystroke. The retro is a set of **candidates, not decisions**.

## Inputs

- **The retro** — a file path (e.g. `~/.kmm-parity/pr-420/retro.md`) or pasted content.
- **The skill being improved** — its name or path. Find its source (e.g. `plugins/<p>/skills/<s>/`).

If either is missing, ask for it (via AskUserQuestion) before starting.

## Two rules that hold for the whole workflow

- **Every question goes through the AskUserQuestion tool**, never free text — and **always mark your
  recommended option** (put it first, label it `… (Recommended)`) **with a one-line reason and an
  explicit why-not for the alternatives.** The user is approving *your judgment*, so show it.
- **Don't bloat.** Prefer the leanest change that works — a surgical edit over a new paragraph, a
  reworded line over a new section. Length is a cost, not a feature.

## Phase 1 — Read the whole target skill FIRST

Read every file of the skill before touching anything: `SKILL.md`, all of `references/`, all of
`scripts/`, and `plugin.json`. This is non-negotiable because the next phases depend on it: you can't
tell a surgical edit from a needed rewrite, spot where a candidate *already* exists, or catch a
candidate that contradicts the skill's own "refuted/learned" notes, without the full picture. Skim-
reading here produces duplicated sections and re-introduced bugs later.

## Phase 2 — Distill the retro into a map of DISTINCT candidates

Read the retro and collapse it into a numbered list of **distinct** changes. Merge tightly-coupled
points into one candidate (e.g. "reproduce the bug" + "then audit it" are one protocol, not two);
split a bullet that secretly bundles two unrelated changes. Present a compact table and stop:

```
| # | Candidate (one line) | Retro source | My lean |
|---|---|---|---|
| 1 | Auto-post results to the PR | TOP #1 | ✅ strong |
| 2 | Coverage = checklist ∪ diff | TOP #2 | ✅ strong |
| 3 | Parallelize builds          | Speed  | ⚠️ contradicts a refuted note |
```

Keep candidate text to one line each — the detail comes out in the per-item question.

## Phase 3 — Approve one-by-one (the core loop)

Walk the candidates **one at a time** (or in small related batches) with AskUserQuestion. Never
bulk-approve. Each question carries: the observation + evidence from the retro, the concrete proposed
change, your recommended option (first, `(Recommended)`, with the reason), and a why-not for each
alternative. Offer real choices — typically *approve as-is / approve with a named tweak / skip* —
not just yes/no, so the user can steer the shape, not just the go/no-go.

**Reconcile against the skill's own history.** Before recommending, check each candidate against the
skill's "refuted / learned" or prior-improvements notes (you read them in Phase 1). If a candidate
re-proposes something the skill already measured-and-rejected, **say so in the question** and
recommend the reconciling option (e.g. "document the safe sub-win, don't re-introduce the refuted
approach") rather than silently shipping the conflict. Surfacing the tension is the value.

Track decisions as you go (a todo list works well) so nothing approved is dropped and nothing skipped
is silently implemented.

## Phase 4 — Implement in a worktree, surgically

Create a git worktree off the latest `master` before any edit — this work is multi-file, version-
bumped, and PR-bound, so it shouldn't touch the user's working checkout.

Then apply each approved change at the **right altitude**:
- **Surgical edit** where the structure already holds the idea — extend a list, reword a line, add a
  row to a table, change a default in a script.
- **Rewrite a block** only where appending would bury the point (e.g. a bullet list that's become a
  protocol → renumber it into ordered steps).
- **New reference/script file** only when inlining would bloat `SKILL.md` past its altitude — a
  detailed sub-procedure, a bundled helper several runs reinvented. Otherwise keep it in place.

Match the skill's existing voice and density. Fix obvious adjacent staleness you encounter (a comment
that now lies, a path that moved) — but stay within the approved scope; don't free-style new features.

## Phase 5 — Version, validate, ship

- **If the skill lives in a plugin/marketplace, bump every version location in lockstep** — for this
  repo that's `plugin.json`, the marketplace entry, the marketplace top-level `metadata.version`, and
  the README row. A drift between any of them ships a broken or invisible update. (Check the repo's
  own conventions doc — e.g. `CLAUDE.md` — for the exact list.) **Bump conservatively and by semver:**
  a **patch** (`x.y.Z`) for small content tweaks, a **minor** (`x.Y.0`) for new rules/features; reserve
  major for breaking workflow changes. A retro fold is almost always a patch or minor — don't over-bump.
- **Almost never edit the plugin/catalog descriptions.** The `plugin.json`, marketplace-entry, and
  README-row descriptions are tuned for skill triggering and catalog browse — a retro fold bumps the
  **version only**, it does NOT append a "what changed this version" clause to any description. (Piling
  recent-change bullets into a description is the failure mode — the description should read as *what the
  skill is*, not a changelog; the PR and retro are the changelog.) Only edit a description when the user
  **explicitly asks**, and then keep it concise — **what the skill does + how**, never a list of changes.
- **Validate** (`claude plugin validate .` here) and confirm it passes — quote the result, don't assume.
- **Review the diff**, then **commit on the worktree branch, push, and open a PR** with a concise body
  mapping each change back to its retro item. **Never push to `master` directly.**
- **Don't create memory entries** for the triage unless the user asks — the retro and the PR are the
  record.

## Common mistakes

| Mistake | Correct approach |
|---|---|
| Implementing the retro as-written | The retro is candidates, not decisions. Approve each one-by-one first. |
| Editing before reading the whole skill | Read every file in Phase 1 — else you duplicate sections or miss a contradiction. |
| Asking yes/no in plain text | Use AskUserQuestion, recommend an option with a reason, offer approve / tweak / skip. |
| Re-introducing a refuted idea because the retro proposed it | Cross-check the skill's refuted/learned notes; surface the conflict in the question. |
| Appending new sections for every change | Edit at the right altitude — surgical where it fits, rewrite where it reads better, new file only to avoid bloat. |
| Editing the user's working checkout | Worktree off master first; this is a PR-bound, version-bumped pass. |
| Bumping one version location and forgetting the rest | Bump all of them in lockstep, then validate. |
| Appending a "what changed" clause to the plugin/README description | Bump the version only; almost never touch descriptions. They're what-the-skill-is, not a changelog. |
| Over-bumping (minor/major for a tiny tweak) | Semver: patch for small tweaks, minor for new rules/features. A retro fold is usually a patch or minor. |
| Pushing to master / skipping the PR | Always a branch + PR with a body that maps changes to retro items. |
