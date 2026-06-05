# Phase G — PR Creation

**Purpose.** Produce a PR ready for review **and ready for parity QA** — the PR is what Phase H (receive & resolve code review) and Phase I (the in-skill parity loop) operate on. **PR body is about WHAT, not HOW.** Migration workflow internals stay in the session folder; the PR communicates user-visible changes only.

**The PR opens with parity QA still pending — by design.** QA is no longer a gate before the PR; it runs after, in the migration skill's Phase I loop (agent-device replay against the frozen golden), tracked against this PR's embedded heatmap. So the body carries the heatmap as an explicit **pre-merge QA checklist** (embedded, not linked — `.kmm/migrations/` is gitignored, so there's no repo path to point at). This is the supported flow, not a waiver.

**Body discipline: concise and value-driven.** The current structure is good; keep it lean. Lead with the value (what changed, user-visible impact), abstract over detail, cut anything a reviewer doesn't need to decide "is this safe to merge?". No jargon, no process narrative, no padding.

**Inputs:** all prior session files complete (especially `validation.md` and `heatmap.md`), `project.md`.

---

## Sub-phases

### G.1 — PR body composition (Sonnet subagent)

**Exception provenance check (mandatory pre-step; ideally already run at end of Phase F).** Before listing any migration exceptions in the body, the G.1 subagent runs `git log <base-branch>..HEAD --grep '<exception-id>' --oneline` for every candidate exception under `.kmm/exceptions/`. The base branch is read from `project.md.git.base_branch` if present; else detected via `git symbolic-ref refs/remotes/origin/HEAD`. If a candidate exception has **zero** referencing commits in the range, it belongs to a prior PR and is **excluded** from this body — listing it would mislead the reviewer. Subagent returns a structured table `id | provenance commits | include? (Y/N)`. (Phase F.6 also runs this check so orphan exceptions surface before composition.) **The orchestrator already knows this session's exception-ids — pass that list to the G.1 subagent in its prompt** so it provenance-checks the known set rather than re-scanning every file under `.kmm/exceptions/` (minor speedup; the subagent still confirms each via `git log`).

**Structure (concise — each section is the minimum a reviewer needs):**
- **What changed** — the feature/module migrated, in reviewer-facing terms. Not "we ran Phase D" — "migrated funds business logic to the shared module."
- **User-visible impact** — ideally *"none — behavioral + API equivalence preserved."* Be explicit about this.
- **Files changed** — high-level summary by category. E.g., "8 files relocated to `:shared/funds/` (`androidMain`); 6 promoted to `commonMain`; 2 held in `androidMain` for a future session." Cite an **exact consumer count** (e.g. "9 consumer ViewModels updated"), not "~9" — `coverage.md` should carry the precise enumeration so the body never falls back to an approximation; if it only has a category note, count from the diff before composing.
- **Risk areas** — from `plan.md` risk register. What should the reviewer focus on?
- **QA — pending (parity via the migration skill's Phase I loop)** — state plainly that behavioral parity QA runs on this PR via the migration skill's in-skill Phase I loop (agent-device A/B replay against the frozen golden, master vs PR head), and **embed `heatmap.md` directly here as a checklist** (`- [ ]` rows per surface). `.kmm/migrations/` is gitignored, so embed the table inline — do not link to a path. Result cells stay unchecked; they're a pre-merge gate the Phase I loop fills in.
- **Migration exceptions (if any, provenance-verified above)** — listed with links to `.kmm/exceptions/` files + the referencing commits in this PR's range + brief rationale. Exceptions with zero provenance are NOT listed.
- **Tests** — baseline counts per source set (held vs promoted), all-green confirmation, iOS verification status (or host-limitation note). One or two lines.
- **Out-of-scope follow-ups** — pre-existing broken tests quarantined (`@Ignore` or build-level exclude, from Phase B.2 / E.0) and files flipped `migrate` → `hold` during Phase D (D.3), one line each. Reviewer-facing list, not a backlog dump.
- **No gitignored-path footer.** Do NOT add a `Full migration context: .kmm/migrations/<branch>/ (local)` line — it points reviewers at a path they can't open and G.2's process-bleed pass only rewrites it. The migration's reviewer-facing artifacts (the tracked `.kmm/exceptions/` files) are already linked from the Migration-exceptions section; nothing else belongs in the body.

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

### G.2 — Self-review (Sonnet subagent)

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

After PR is open (or body output), amend `retro.md` with `## Phase G — PR Creation (captured YYYY-MM-DD)` — five-bullet structure (recap / smooth / stuck / could-improve / user steering log). **Blocking, non-skippable** (per SKILL.md Retro gate).

Phase G is **no longer the final phase** — Phase H (receive & resolve code review) follows, then Phase I (parity-QA + bug-fixing); the session-end consolidation runs after the Phase I retro. Proceed to Phase H with the PR URL.

---

## Outputs

- **`pr.md`** — the phase artifact (status, tasks, decisions log, provenance-check table, the PR body wrapped in a code fence). Conforms to the universal phase file format. NEVER passed to `gh pr create --body-file`.
- **`pr-body.md`** — the `--body-file` source. Pure body content; no wrapper. This is what ships to the PR.
- PR URL once opened (recorded in `pr.md` after G.4).

Both stored in session folder so the PR can be regenerated or referenced post-merge.

---

## Phase-specific gates

Beyond universals:

- Phase F complete (`validation.md` status `complete`) — automated checks + crash-free smoke. (No manual-QA sign-off gate; parity QA is Phase I.)
- PR body has no process bleed (workflow internals invisible), is concise/value-driven, and **embeds the heatmap as a pre-merge QA checklist** in the QA section.
- User confirms before PR opens.
- `pr-body.md` (never `pr.md`) is the `--body-file` source.
