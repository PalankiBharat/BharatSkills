# Phase G — PR Creation

**Purpose.** Produce a PR ready for review. **PR body is about WHAT, not HOW.** Migration workflow internals stay in the session folder; PR communicates user-visible changes only.

**Inputs:** all prior session files complete (especially `validation.md` and `heatmap.md`), `project.md`.

---

## Sub-phases

### G.1 — PR body composition (Sonnet)

**Structure:**
- **What changed** — the feature/module migrated, in reviewer-facing terms. Not "we ran Phase D" — "migrated funds business logic to the shared module."
- **User-visible impact** — ideally *"none — behavioral + API equivalence preserved."* Be explicit about this.
- **Files changed** — high-level summary by category (e.g., "6 files moved to `:shared/funds/`, 12 consumer imports updated in `app/`").
- **Risk areas** — from `plan.md` risk register. What should the reviewer focus on?
- **QA heatmap** — link to or embed `heatmap.md` from F.5.
- **Migration exceptions (if any)** — listed with links to `.kmm/exceptions/` files + brief rationale.
- **Tests** — baseline count moved to commonTest, all green confirmation, iOS verification status (or host-limitation note).
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

### G.5 — Session retro

After PR is open (or body output), the skill runs the **Session retro** action (see `SKILL.md` → Special actions). Three short questions, written to `.kmm/migrations/<branch>/retro.md`. Diff-confirmed before write. User can `skip retro` to bypass.

This is the final step of the workflow. The retro.md file is the closing artifact of the session, parallel to pr.md being the closing artifact for the PR.

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
