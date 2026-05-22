# Phase G — PR Creation

**Purpose.** Produce a PR ready for review. **PR body is about WHAT, not HOW.** Migration workflow internals stay in the session folder; PR communicates user-visible changes only.

**Inputs:** all prior session files complete (especially `validation.md` and `heatmap.md`), `project.md`.

---

## Sub-phases

### G.1 — PR body composition (Sonnet)

**Exception provenance check (mandatory pre-step).** Before listing any migration exceptions in the body, the G.1 subagent runs `git log <base-branch>..HEAD --grep '<exception-id>' --oneline` for every candidate exception under `.kmm/exceptions/`. The base branch is read from `project.md.git.base_branch` if present; else detected via `git symbolic-ref refs/remotes/origin/HEAD`. If a candidate exception has **zero** referencing commits in the range, it belongs to a prior PR and is **excluded** from this body — listing it would mislead the reviewer. Subagent returns a structured table `id | provenance commits | include? (Y/N)` for the main thread to review before composing.

**Structure:**
- **What changed** — the feature/module migrated, in reviewer-facing terms. Not "we ran Phase D" — "migrated funds business logic to the shared module."
- **User-visible impact** — ideally *"none — behavioral + API equivalence preserved."* Be explicit about this.
- **Files changed** — high-level summary by category. E.g., "8 files relocated to `:shared/funds/` (`androidMain`); 6 promoted to `commonMain`; 2 held in `androidMain` for a future session — see plan.md."
- **Risk areas** — from `plan.md` risk register. What should the reviewer focus on?
- **QA heatmap** — link to or embed `heatmap.md` from F.5 (with Result cells filled in by user during F.6).
- **Migration exceptions (if any, provenance-verified above)** — listed with links to `.kmm/exceptions/` files + the referencing commits in this PR's range + brief rationale. Exceptions with zero provenance are NOT listed.
- **Tests** — baseline counts per source set: how many in `<dest>/androidUnitTest` (held files), how many promoted to `<dest>/commonTest` (migrated files), all green confirmation, iOS verification status (or host-limitation note).
- **Out-of-scope follow-ups** — pre-existing broken tests quarantined via `@Ignore` (from Phase B.2 and Phase E.0); files flipped `migrate` → `hold` during Phase D (from D.3) with one-line context. Reviewer-facing list, not a backlog dump.
- **Footer (single line):** `Full migration context: .kmm/migrations/<branch>/` — single line, lets curious reviewers navigate without bloating the body.

**Two artifacts produced (G2 — pr.md vs pr-body.md split).** G.1 writes both files:

- **`pr.md`** — the phase artifact, conforming to the universal phase file format (status + tasks + decisions log + the provenance-check result table + the PR body wrapped in a code fence for visual review). NOT a `--body-file` source — the wrapper would ship as part of the PR.
- **`pr-body.md`** — the raw PR body content (no wrapper, no audit metadata). This is the `--body-file` source. Crystal-clear naming: `pr-body.md` IS the body.

G.4 invokes `gh pr create --body-file .kmm/migrations/<branch>/pr-body.md`. **Never `--body-file pr.md`** — that would ship the audit wrapper as the PR body.

**Excluded** (do not appear in PR body):
- Phase references (no "Phase 0", "Phase D", etc.).
- Mention of the skill or the migration workflow itself.
- *"I considered creating X but chose Y..."* process narrative.
- Trust scores, decisions logs, audit details.
- Bloat.

### G.2 — Self-review (Sonnet)

Re-read the draft:
- Process bleed? Trim.
- Workflow jargon? Remove.
- Verify clarity for a reviewer who knows nothing about the migration workflow — they should understand what changed and what to verify.
- Tight, scannable, professional.

### G.3 — User review

- Skill presents the draft body.
- User edits / approves / rewrites.

### G.3.5 — Branch-state pre-fetch (Haiku, parallel)

Before G.4 opens the PR, dispatch parallel fetches to deterministically choose the push invocation:

- `git status --short` — working-tree dirty? If yes, halt and surface to user (uncommitted work shouldn't ship in a PR opened from skill).
- `git ls-remote --heads origin <branch>` — does the branch exist on origin? Determines whether `-u` is needed.

Report shape:
```
working_tree: clean | dirty (file list)
branch_on_origin: yes | no
recommended_push: git push | git push -u origin <branch>
```

G.4 reads this report and chooses the right push invocation without improvising.

### G.4 — PR opening (optional)

- If user wants skill to drive:
  1. Push per G.3.5's recommended invocation.
  2. `gh pr create --title <X> --body-file .kmm/migrations/<branch>/pr-body.md` (note: **`pr-body.md`**, not `pr.md` — see G.1 for the split rationale).
- Else: skill outputs `pr-body.md` content to terminal, user opens PR manually.

### G.5 — Phase G retro

After PR is open (or body output), amend `retro.md` with `## Phase G — PR Creation (captured YYYY-MM-DD)` — five-bullet structure (recap / smooth / stuck / could-improve / user steering log). User can skip with `skip retro`.

This is the final phase retro of the session. **No session-end consolidate, no skill/drop verdicts.** The retro.md file (now containing one section per phase that ran) is the closing artifact of the session, parallel to pr.md being the closing artifact for the PR. A future planning session can read retro.md to drive skill improvements; this session does not.

---

## Outputs

- **`pr.md`** — the phase artifact (status, tasks, decisions log, provenance-check table, the PR body wrapped in a code fence). Conforms to the universal phase file format. NEVER passed to `gh pr create --body-file`.
- **`pr-body.md`** — the `--body-file` source. Pure body content; no wrapper. This is what ships to the PR.
- PR URL once opened (recorded in `pr.md` after G.4).

Both stored in session folder so the PR can be regenerated or referenced post-merge.

---

## Phase-specific gates

Beyond universals:

- Phase F complete with user "migration complete" sign-off.
- PR body has no process bleed (workflow internals invisible).
- User confirms before PR opens.
