# Phase G — PR Creation

**Purpose.** Produce a PR ready for review. **PR body is about WHAT, not HOW.** Migration workflow internals stay in the session folder; PR communicates user-visible changes only.

**Inputs:** all prior session files complete (especially `validation.md` and `heatmap.md`), `project.md`.

---

## Sub-phases

### G.1 — PR body composition (Sonnet)

**Structure:**
- **What changed** — the feature/module migrated, in reviewer-facing terms. Not "we ran Phase D" — "migrated funds business logic to the shared module."
- **User-visible impact** — ideally *"none — behavioral + API equivalence preserved."* Be explicit about this.
- **Files changed** — high-level summary by category. E.g., "8 files relocated to `:shared/funds/` (`androidMain`); 6 promoted to `commonMain`; 2 held in `androidMain` for a future session — see plan.md."
- **Risk areas** — from `plan.md` risk register. What should the reviewer focus on?
- **QA heatmap** — link to or embed `heatmap.md` from F.5 (with Result cells filled in by user during F.6).
- **Migration exceptions (if any)** — listed with links to `.kmm/exceptions/` files + brief rationale.
- **Tests** — baseline counts per source set: how many in `<dest>/androidUnitTest` (held files), how many promoted to `<dest>/commonTest` (migrated files), all green confirmation, iOS verification status (or host-limitation note).
- **Out-of-scope follow-ups** — pre-existing broken tests quarantined via `@Ignore` (from Phase B.2 and Phase E.0); files flipped `migrate` → `hold` during Phase D (from D.3) with one-line context. Reviewer-facing list, not a backlog dump.
- **Footer (single line):** `Full migration context: .kmm/migrations/<branch>/` — single line, lets curious reviewers navigate without bloating the body.

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

### G.4 — PR opening (optional)

- If user wants skill to drive: `gh pr create --title <X> --body-file .kmm/migrations/<branch>/pr.md`.
- Else: skill outputs the body to terminal, user opens PR manually.

### G.5 — Phase G retro

After PR is open (or body output), amend `retro.md` with `## Phase G — PR Creation (captured YYYY-MM-DD)` — five-bullet structure (recap / smooth / stuck / could-improve / user steering log). User can skip with `skip retro`.

This is the final phase retro of the session. **No session-end consolidate, no skill/drop verdicts.** The retro.md file (now containing one section per phase that ran) is the closing artifact of the session, parallel to pr.md being the closing artifact for the PR. A future planning session can read retro.md to drive skill improvements; this session does not.

---

## Output: `pr.md`

The saved PR body for record. Plus the PR URL once opened (if applicable).

Stored in session folder so PR can be regenerated or referenced post-merge.

---

## Phase-specific gates

Beyond universals:

- Phase F complete with user "migration complete" sign-off.
- PR body has no process bleed (workflow internals invisible).
- User confirms before PR opens.
