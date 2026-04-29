---
name: kmm-pr-reviewer
description: >-
  Use when the user is reviewing a PR that migrates Android code to Kotlin
  Multiplatform — verifying the port is 1:1, no UI/UX drift, no behavioural
  drift, no missed logic, no scope creep, no platform leaks, and no silent
  baseline modifications. Enforces a per-file checklist via dedicated
  subagents (a file is not complete until every box ticks). Read-only
  orchestrator — never edits, never commits; only the final
  comment-posting subagent talks to GitHub via gh CLI, and only after the
  user approves the findings list. Triggers: "review KMM PR", "review this
  KMM migration PR", "kmm pr review", "kmp pr review", "check KMM
  regression PR", "verify KMM port", "review kmm-migration PR".
when_to_use: >-
  Active review of a KMM-migration PR before merge — to catch parity drift,
  missed logic, scope creep, dep additions, platform leaks, baseline
  modifications, and stub leftovers introduced by the migration. Not for
  greenfield code review. Not for non-KMM PRs.
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Bash(git *)
  - Bash(gh *)
  - Bash(jq *)
  - WebSearch
  - WebFetch
  - mcp__context7__*
  - find-docs
paths:
  - "**/*.kt"
  - "**/*.kts"
  - "**/build.gradle.kts"
  - "**/settings.gradle.kts"
argument-hint: "<PR# | PR-URL>"
---

# kmm-pr-reviewer Skill

> Read-only orchestrator for KMM-migration PR review.
> Per-file Sonnet reviewer enforces a classification-specific checklist;
> triager Sonnet re-verifies findings against the actual diff; user
> cherry-picks; Haiku posts a single GitHub review on approval.
> See `skills/kmm-pr-reviewer/review_laws.md` for the 10 review laws YOU
> MUST follow.

## Contents

- [Orchestration flow](#orchestration-flow)
- [Required reading](#required-reading-for-the-orchestrator-on-invocation)
- [Phase 0 — Bootstrap](#phase-0--bootstrap)
- [Phase 1 — Review-guide build](#phase-1--review-guide-build)
- [Phase 2 — Per-file review](#phase-2--per-file-review)
- [Phase 3 — Triager](#phase-3--triager)
- [Phase 4 — Approval gate](#phase-4--approval-gate)
- [Phase 5 — Comment posting](#phase-5--comment-posting)
- [User gates](#user-gates)
- [Dispatch bundles](#dispatch-bundles)
- [Resume flow](#resume-flow)
- [Self-contained](#self-contained--no-external-skill-dependencies)

## Orchestration flow

kmm-pr-reviewer is an orchestrator skill. The main Claude context (Opus)
never reads source files, never inspects diffs, and never posts comments.
All labour flows through subagents — Sonnet for the per-file reviewers and
the triager, Haiku for the bootstrap classifier and the comment poster.
**Five phases, one user gate (approval), no worktree** — the reviewer
operates read-only on whatever the current checkout is. Every per-file
report ends with one of the four status headers from the subagent status
contract, and the orchestrator never advances without all expected reports
present. The 10 review laws in `skills/kmm-pr-reviewer/review_laws.md` are
the absolute authority.

## Required reading for the orchestrator on invocation

YOU MUST read these files BEFORE taking any action on an invocation:

- `skills/kmm-pr-reviewer/review_laws.md`
- `skills/kmm-pr-reviewer/references/classification_protocol.md`
- `skills/kmm-pr-reviewer/references/subagent_status_contract.md`
- `skills/kmm-pr-reviewer/references/finding_schema.md`
- `skills/kmm-pr-reviewer/schemas/state_schema.md`
- `kmm_pr_review/<pr#>/state.json` (at the target repo root — if exists)

## Phase 0 — Bootstrap

Read `kmm_pr_review/<pr#>/state.json` (where `<pr#>` is parsed from the
invocation argument):

- **No state** — dispatch `00_bootstrap` (Haiku). It runs `gh pr view <pr#>
  --json baseRefName,headRefName,baseRefOid,headRefOid,files,headRepository,baseRepository,url,number`
  and `gh pr diff <pr#> --name-only`, classifies every changed path per
  `references/classification_protocol.md` into one of `migrated` /
  `nonmigrated` / `ios_port` / `baseline` / `build_config`, writes
  `pr_metadata.md` and `state.json`.

- **Existing state with `status != complete`** — present `REQUIRES_APPROVAL`
  with options: resume from current phase, restart bootstrap, or abandon.
  Resume re-reads `state.json` and continues from `phase`.

The bootstrap subagent fails loudly if `gh` auth is missing — the
orchestrator never falls back to `git diff` against `origin/master`,
because (a) the local checkout may not have the PR fetched and (b)
posting comments later requires `gh` auth anyway, so failing fast is
correct.

## Phase 1 — Review-guide build

`10_review_guide_author` (Sonnet, read-only) reads `state.json` and the full
`gh pr diff <pr#>` output, then writes
`kmm_pr_review/<pr#>/review_guide.md` per
`schemas/review_guide_schema.md`. One entry per changed file containing:

- File path and classification (verbatim from `state.json`).
- The classification-specific checklist (copied from
  `references/review_criteria.md` for that classification).
- For `migrated` files: the master path (usually identical) and the
  `base_sha` to read against.
- For `ios_port` files: the corresponding commonMain `expect` declarations
  this file's `actual`s must satisfy (located by Grep on the new diff).

The review guide is the artifact the per-file reviewers read in Phase 2.

## Phase 2 — Per-file review

The orchestrator dispatches one per-file reviewer per changed file,
parallel up to a cap (default 8 concurrent). The dispatch template is
selected by classification:

- `migrated` → `20_file_reviewer_migrated`
- `ios_port` → `20_file_reviewer_ios`
- `nonmigrated` → `20_file_reviewer_nonmigrated`
- `baseline` → `20_file_reviewer_nonmigrated` with the `BASELINE_VIOLATION`
  rule pre-applied (any modification = automatic blocker; the reviewer
  never has to think about this — `00_bootstrap` already wrote the entry)
- `build_config` → `20_file_reviewer_nonmigrated` with the dep-addition
  scan additionally enforced.

Each reviewer:

1. Reads its required-reading list (review_laws + review_criteria for its
   classification + parity_verification_protocol if `migrated` or
   `ios_port` + finding_schema + status contract + state.json + the
   review_guide entry for this file).
2. Reads the file at `head_sha` and (for `migrated`) at `base_sha` —
   uses `git show <sha>:<path>` for the master version.
3. Walks the classification-specific checklist top to bottom. For every
   item: PASS (with a one-line evidence cite using `path:line`) or FAIL
   (finding emitted per `finding_schema.md`).
4. Writes `kmm_pr_review/<pr#>/per_file/<sanitized-path>.md` ending with
   one of: `STATUS: DONE` (every box ticked, zero findings),
   `STATUS: DONE_WITH_CONCERNS` (boxes ticked but findings emitted),
   `STATUS: BLOCKED` (could not complete the checklist for a stated
   reason — usually missing context), or `STATUS: NEEDS_CONTEXT`.

A per-file reviewer NEVER returns silent — every checklist item has an
explicit verdict. This is the gate the user asked for: "unless all
ticked it does not [get] marked complete."

The orchestrator does not advance to Phase 3 until every file in the
diff has a corresponding `per_file/*.md` with a status. `BLOCKED` /
`NEEDS_CONTEXT` files are listed in `state.json.unresolved` and a
`REQUIRES_APPROVAL` is raised: re-dispatch with extra context, skip and
proceed (acknowledged risk), or abandon.

## Phase 3 — Triager

`30_triager` (Sonnet) reads:

- Every `per_file/*.md`.
- The full `gh pr diff <pr#>`.
- `state.json` for classifications and shas.
- For each finding that cites a master location — the master version of
  that file via `git show <base_sha>:<path>`.

For each finding, the triager applies the procedure in
`dispatch_templates/30_triager.md`:

1. Re-read the cited `path:line` at `head_sha`. Does the symptom exist?
   If no, drop with reason `NOT_REPRODUCIBLE`.
2. Is this finding a duplicate of another (same root cause, different
   symptom or different file)? If yes, merge into the canonical entry.
3. Re-classify severity per `finding_schema.md` (BLOCKER / MAJOR / MINOR
   / NIT).
4. Verify the suggested fix is accurate. If wrong, rewrite or strip.

Output: `triager_report.md` listing the surviving, deduped, re-classified
findings, plus a summary of how many were dropped and why.

The triager is forbidden from inventing new findings. Its job is to
filter, merge, and re-rank — never to extend.

## Phase 4 — Approval gate

`40_approval_presenter` (Sonnet, read-only) writes
`findings_pending_approval.md` per the format in
`dispatch_templates/40_approval_presenter.md`. Each finding becomes a
markdown checkbox entry with:

- `[x]` (default ticked — user unticks to drop)
- Severity tag (`BLOCKER` / `MAJOR` / `MINOR` / `NIT`)
- Category tag (from `finding_schema.md`)
- `path:line` anchor
- Body in blockquote (the proposed comment text — user may edit in place)
- Optional `**Suggested fix:**` line

The orchestrator then presents the file path to the user with the
`NEEDS YOUR CALL` message: edit the file in place (untick / refine /
delete), then reply `approved` to post, `revise` to send back to triager
with feedback, or `abandon` to exit.

If the user types `approved`:

1. Orchestrator re-reads `findings_pending_approval.md`.
2. Parses ticked items only.
3. If zero ticked items remain — graceful exit, nothing posted, write
   `posted_review.md` with a `NO_FINDINGS_POSTED` record.
4. Otherwise advances to Phase 5.

This is the only user gate in the skill. The skill never posts without
explicit approval (Law 8).

## Phase 5 — Comment posting

`50_comment_poster` (Haiku) reads the parsed approved findings list and
batches them into a single GitHub review per
`references/gh_comment_protocol.md`:

- One `POST /repos/{owner}/{repo}/pulls/{pr#}/reviews` call.
- `comments[]` contains one entry per approved finding that has a
  `path:line` anchor — `{path, line, side: "RIGHT", body}`.
- Findings without a stable line anchor (or with severity NIT and no
  inline target) become bullets in the top-level review `body`.
- `event` is `REQUEST_CHANGES` if any approved finding is severity
  `BLOCKER`, otherwise `COMMENT`.

After the review is created, the poster records the GitHub review URL
and the exact payload sent in `kmm_pr_review/<pr#>/posted_review.md`.

The poster is the ONLY subagent in the entire skill with `Bash(gh
api *)` and `Bash(gh pr review *)` on its allowlist. No other subagent
can post anywhere.

## User gates

One user gate, mid-Phase-4. All gates use the `NEEDS YOUR CALL` format.

| Gate | When | Blocks until |
|---|---|---|
| 1 | Mid-Phase-4 | User edits `findings_pending_approval.md`, replies `approved` / `revise` / `abandon` |

If `state.json.unresolved` is non-empty after Phase 2, an additional
mid-Phase-2 `REQUIRES_APPROVAL` may surface to handle BLOCKED files
before Phase 3 begins. That is a control-flow gate, not a user-decision
gate — once unresolved files are addressed (or accepted), the skill
returns to the main flow.

## Dispatch bundles

Authoritative table. Orchestrator reads this before every dispatch and
constructs the prompt with must-read and forbidden-to-read lists
explicitly.

### 00_bootstrap (Phase 0)

```yaml
phase: 0_bootstrap
model: haiku
mode: dontAsk
tool_allowlist:
  - Read
  - Grep
  - Glob
  - Bash(gh pr view *)
  - Bash(gh pr diff *)
  - Bash(gh api *)
  - Bash(git rev-parse *)
  - Bash(git fetch *)
  - Bash(jq *)
  - Write
tool_denylist:
  - Edit
  - Bash(git commit *)
  - Bash(git add *)
  - Bash(git push *)
  - Bash(gh pr review *)
  - Bash(gh pr comment *)
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/classification_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - skills/kmm-pr-reviewer/schemas/state_schema.md
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/pr_metadata.md
```

### 10_review_guide_author (Phase 1)

```yaml
phase: 1_review_guide
model: sonnet
mode: dontAsk
tool_allowlist:
  - Read
  - Grep
  - Glob
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(git log *)
  - Bash(gh pr diff *)
  - Write
tool_denylist:
  - Edit
  - Bash(git commit *)
  - Bash(git add *)
  - Bash(git push *)
  - Bash(gh pr review *)
  - Bash(gh pr comment *)
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/review_criteria.md
  - skills/kmm-pr-reviewer/references/classification_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - skills/kmm-pr-reviewer/schemas/review_guide_schema.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/pr_metadata.md
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/review_guide.md
```

### 20_file_reviewer_migrated (Phase 2 — highest-risk; full bundle)

```yaml
phase: 2_per_file_review
model: sonnet
mode: dontAsk
tool_allowlist:
  - Read
  - Grep
  - Glob
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(git log *)
  - Bash(gh pr diff *)
  - WebSearch
  - WebFetch
  - mcp__context7__*
  - find-docs
  - Write
tool_denylist:
  - Edit
  - Bash(git commit *)
  - Bash(git add *)
  - Bash(git push *)
  - Bash(git checkout *)
  - Bash(git reset *)
  - Bash(git rebase *)
  - Bash(gh pr review *)
  - Bash(gh pr comment *)
requires_success_criterion: true
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/review_criteria.md
  - skills/kmm-pr-reviewer/references/parity_verification_protocol.md
  - skills/kmm-pr-reviewer/references/finding_schema.md
  - skills/kmm-pr-reviewer/references/live_knowledge_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/review_guide.md (the entry for this file only)
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/per_file/<sanitized-path>.md
knowledge_lookup: |
  Whenever the reviewer needs a fact about KMP, a library, an interop
  pattern, or platform behaviour, it MUST consult live sources per
  references/live_knowledge_protocol.md — context7 first, then WebSearch
  / WebFetch / find-docs. Training data is forbidden as a source. Cite
  the source in the finding body with the fetch date.
inputs:
  - file_path: <new path at head_sha>
  - master_path: <path on master at base_sha; usually equals file_path or
                 the originating Android source the port replaces>
  - base_sha: <from state.json>
  - head_sha: <from state.json>
success_criterion: |
  Every checklist item in references/review_criteria.md → "migrated"
  section has a verdict (PASS with path:line evidence, OR a finding per
  finding_schema.md). Final report ends with one of STATUS: DONE |
  DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT — no silent skips.
```

### 20_file_reviewer_ios (Phase 2 — iOS port)

```yaml
phase: 2_per_file_review
model: sonnet
mode: dontAsk
tool_allowlist: <same as 20_file_reviewer_migrated>
tool_denylist: <same as 20_file_reviewer_migrated>
requires_success_criterion: true
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/review_criteria.md (ios_port section)
  - skills/kmm-pr-reviewer/references/parity_verification_protocol.md
  - skills/kmm-pr-reviewer/references/finding_schema.md
  - skills/kmm-pr-reviewer/references/live_knowledge_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/review_guide.md (the entry for this file)
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/per_file/<sanitized-path>.md
```

### 20_file_reviewer_nonmigrated (Phase 2 — strict 1:1 mechanical)

```yaml
phase: 2_per_file_review
model: sonnet
mode: dontAsk
tool_allowlist: <same as 20_file_reviewer_migrated>
tool_denylist: <same as 20_file_reviewer_migrated>
requires_success_criterion: true
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/review_criteria.md
    (nonmigrated, baseline, or build_config section per state.json
    classification)
  - skills/kmm-pr-reviewer/references/finding_schema.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/review_guide.md (the entry for this file)
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/per_file/<sanitized-path>.md
```

### 30_triager (Phase 3)

```yaml
phase: 3_triage
model: sonnet
mode: dontAsk
tool_allowlist:
  - Read
  - Grep
  - Glob
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(gh pr diff *)
  - WebSearch
  - WebFetch
  - mcp__context7__*
  - find-docs
  - Write
tool_denylist:
  - Edit
  - Bash(git commit *)
  - Bash(git add *)
  - Bash(git push *)
  - Bash(gh pr review *)
  - Bash(gh pr comment *)
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/finding_schema.md
  - skills/kmm-pr-reviewer/references/live_knowledge_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/per_file/ (every file)
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/triager_report.md
knowledge_lookup: |
  When verifying a finding that rests on a KMP / library claim, the
  triager re-fetches the source per live_knowledge_protocol.md —
  context7 first, WebSearch / find-docs as fallbacks. A finding whose
  citation cannot be re-verified is dropped as NOT_REPRODUCIBLE.
```

### 40_approval_presenter (Phase 4)

```yaml
phase: 4_approval
model: sonnet
mode: dontAsk
tool_allowlist:
  - Read
  - Write
tool_denylist:
  - Edit
  - Bash(*)
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/finding_schema.md
  - kmm_pr_review/<pr#>/triager_report.md
must_write:
  - kmm_pr_review/<pr#>/findings_pending_approval.md
```

### 50_comment_poster (Phase 5 — the only subagent that touches GitHub)

```yaml
phase: 5_post
model: haiku
mode: dontAsk
tool_allowlist:
  - Read
  - Bash(gh api *)
  - Bash(jq *)
  - Write
tool_denylist:
  - Edit
  - Bash(git commit *)
  - Bash(git push *)
must_read_before_start:
  - skills/kmm-pr-reviewer/review_laws.md
  - skills/kmm-pr-reviewer/references/gh_comment_protocol.md
  - skills/kmm-pr-reviewer/references/subagent_status_contract.md
  - kmm_pr_review/<pr#>/state.json
  - kmm_pr_review/<pr#>/findings_pending_approval.md (parsed for ticked items)
forbidden_to_read:
  - skills/kmm-pr-reviewer/dispatch_templates/*
must_write:
  - kmm_pr_review/<pr#>/posted_review.md
```

## Resume flow

Resume is user-triggered — re-invoke with the same PR number. The
orchestrator reads `kmm_pr_review/<pr#>/state.json`:

1. `phase = 0` and incomplete → re-dispatch `00_bootstrap`.
2. `phase = 1` and `review_guide.md` missing → re-dispatch
   `10_review_guide_author`.
3. `phase = 2` and `per_file/` incomplete → list missing files, dispatch
   per-file reviewers ONLY for those files.
4. `phase = 3` and `triager_report.md` missing → re-dispatch `30_triager`.
5. `phase = 4` and `findings_pending_approval.md` missing → re-dispatch
   `40_approval_presenter`.
6. `phase = 4` with `findings_pending_approval.md` present → re-prompt
   the user for `approved` / `revise` / `abandon`.
7. `phase = 5` → never auto-resumes; the user must explicitly say "post"
   to avoid double-posting on resume.
8. `status = complete` → present `posted_review.md` summary; offer to
   abandon (clears state) or no-op.

Everything in `kmm_pr_review/<pr#>/` persists across session exit,
`/clear`, context compaction, and machine reboot.

## Self-contained — no external skill dependencies

kmm-pr-reviewer has NO external skill dependencies. All protocols are
inlined under `references/` — `subagent_status_contract.md`,
`live_knowledge_protocol.md`, and `parity_verification_protocol.md`
are this skill's own copies. They are not back-references to
kmm-migration's references; the patterns are identical but the files
live in this plugin so the skill can be installed standalone.
