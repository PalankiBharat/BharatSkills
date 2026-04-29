# kmm-pr-reviewer plugin

Regression-detection counterpart to `kmm-migration`. Reviews a KMM-migration PR against the prod Android app, file by file, with the same paranoia level the migration itself enforces. Posts inline review comments on user approval.

## Self-contained

No external skill dependencies. Mirrors the orchestration model of `kmm-migration` (Opus orchestrates, Sonnet reviews, Haiku posts). Install and use standalone.

## Invoke

```
/kmm-pr-reviewer <PR# | PR-URL>
```

Examples:

```
/kmm-pr-reviewer 154
/kmm-pr-reviewer https://github.com/PunchHQ/punch-android/pull/154
```

## What the skill does

- **Phase 0 — Bootstrap**: `00_bootstrap` (Haiku) fetches PR metadata via `gh pr view` / `gh pr diff`, computes `base_sha`/`head_sha`, classifies every changed path into one of `migrated` / `nonmigrated` / `ios_port` / `baseline` / `build_config`, writes `kmm_pr_review/<pr#>/state.json`.
- **Phase 1 — Review-guide build**: `10_review_guide_author` (Sonnet) reads the diff and writes `review_guide.md` — one entry per file with the classification-specific checklist already populated.
- **Phase 2 — Per-file review**: parallel dispatch of `20_file_reviewer_*` (Sonnet, one per file) by classification. Migrated files get a deep cross-check (read master version + port version, verify every public API, branch, and side-effect is preserved). iOS files get an interop-contract check. Non-migrated files get a strict 1:1 mechanical check. Baseline files must be unchanged. Each subagent ticks every checklist box or emits `STATUS: BLOCKED`.
- **Phase 3 — Triager**: `30_triager` (Sonnet) reads every per-file report plus the full diff, re-verifies each finding against the actual file/line, drops anything it cannot reproduce, dedupes, and re-classifies severity per `finding_schema.md`.
- **Phase 4 — Approval gate**: `40_approval_presenter` writes `findings_pending_approval.md` — a markdown checklist where every finding has a checkbox and editable comment body. The user unticks/edits/refines, then types `approved`. Untick-all is a graceful exit.
- **Phase 5 — Comment posting**: `50_comment_poster` (Haiku) parses the user-edited file, batches the ticked findings into a single GitHub review via `gh api`, posting line-anchored inline comments where `path:line` is set and a summary body for the rest. `event: REQUEST_CHANGES` if any ticked finding is severity `BLOCKER`, else `COMMENT`.

## Design highlights

- **10 review laws** with rationalization tables — the anti-patterns each law catches, stated verbatim so subagents self-check.
- **Read-only operation** — every subagent except `50_comment_poster` has `Edit`, `Write`, `git commit/push`, and `gh pr review/comment` on its tool denylist at the harness level.
- **No trust in producer reports** — the triager re-verifies findings against the actual diff, never against another subagent's prose.
- **Classification is destiny** — a file's bucket dictates its checklist; no ad-hoc mixing.
- **Hard checklist gate** — a per-file reviewer never silently skips a box. Either every item is ticked (PASS) or the verdict is `DONE_WITH_CONCERNS` listing the unmet items.
- **User edits the approval file in place** — no terminal-prompt limit on per-finding approval.
- **iOS reviewer fires only when iOS files exist** — the bootstrap classifier decides; no wasted dispatches.

## Files produced at the target repo root

```
kmm_pr_review/<pr#>/
├── state.json                  # single source of truth, orchestrator-only writes
├── pr_metadata.md              # gh pr view output, base/head shas, file count
├── review_guide.md             # per-file checklists (Phase 1 output)
├── per_file/<sanitized-path>.md # one review report per file (Phase 2 output)
├── triager_report.md           # final filtered list (Phase 3 output)
├── findings_pending_approval.md # cherry-pick checklist for the user (Phase 4)
└── posted_review.md            # record of what was actually posted (Phase 5)
```

The directory is `.gitignore`d. State persists across `/clear`, context compaction, and machine reboot — the user can re-invoke the skill on the same PR# to resume.

## Patterns reused from kmm-migration

- Subagent status contract (`DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`) — verbatim.
- Two-pass-style review (per-file reviewer + triager) — mirrors `spec_compliance_reviewer` + `code_quality_reviewer` fail-fast ordering.
- Live-knowledge discipline (context7 → WebSearch → training-data) — `live_knowledge_protocol.md`.
- Evidence-before-claims (every finding cites `path:line` + verbatim diff excerpt).
