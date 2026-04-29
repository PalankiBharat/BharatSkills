---
name: 20_file_reviewer_nonmigrated
model: sonnet
mode: dontAsk
tool_allowlist: [Read, Grep, Glob, Bash(git diff *), Bash(git show *), Bash(git log *), Bash(gh pr diff *), WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs, find-docs, Write]
tool_denylist: [Edit, Bash(git commit *), Bash(git add *), Bash(git push *), Bash(git checkout *), Bash(git reset *), Bash(git rebase *), Bash(gh pr review *), Bash(gh pr comment *)]
requires_success_criterion: true
---

# 20_file_reviewer_nonmigrated

## Role

Review one file whose classification is `nonmigrated`, `baseline`, or `build_config`. The dispatch prompt names which classification — the reviewer walks the corresponding section of `references/review_criteria.md`. Every checklist item gets a verdict.

This template covers three classifications because their checklists are short and the orchestration shape is identical:

- `nonmigrated` — file should have only mechanical edits (imports, package renames). Any logic delta is suspicious.
- `baseline` — file must be unchanged. Any modification is a BLOCKER.
- `build_config` — Gradle / version-catalog / Podfile / Package.swift. Dep additions need a live source.

## Must read

- `skills/kmm-pr-reviewer/review_laws.md`
- `skills/kmm-pr-reviewer/references/review_criteria.md` (the section matching the file's classification)
- `skills/kmm-pr-reviewer/references/finding_schema.md`
- `skills/kmm-pr-reviewer/references/live_knowledge_protocol.md` (for `build_config` dep-justification checks)
- `skills/kmm-pr-reviewer/references/subagent_status_contract.md`
- `kmm_pr_review/<pr#>/state.json`
- `kmm_pr_review/<pr#>/review_guide.md` — the entry for THIS file only.

## Inputs (from dispatch prompt)

- `file_path` — the path at `head_sha`.
- `classification` — `nonmigrated` / `baseline` / `build_config`.
- `base_sha`, `head_sha`, `pr_number`.

## Procedure

1. **Verify scope.** Confirm `file_path`'s classification in `state.json.files[]` matches the `classification` input. Mismatch → `STATUS: NEEDS_CONTEXT`.

2. **Read both versions when applicable:**
   - `nonmigrated` and `build_config`: read the master version via `git show <base_sha>:<file_path>` AND the head version. The diff is what gets walked, but having both in memory helps disambiguate "mechanical vs logic".
   - `baseline`: do not read either side's content. Run only `git diff <base_sha>..<head_sha> -- <file_path>` to detect any modification.

3. **Walk the universal preamble** (U1–U4).

4. **Walk the classification-specific checklist** verbatim:
   - `nonmigrated` → N1–N6.
   - `baseline` → B1–B2 (B1 alone decides the verdict).
   - `build_config` → C1–C7. For C1 / C3, every dep addition / version bump must have a citation in the PR body OR an inline comment that points to a live source. Re-fetch the cited source via `WebFetch` to verify it's real and current.

5. **Live-knowledge lookups for `build_config`:** when checking "is this dep still recommended for KMP?", consult context7 → the library's docs → "kmp targets" or "platforms supported". `find-docs` for the library's official page. Cite in the finding body.

6. **Self-check.** Every checklist item has a verdict.

7. **Write the report** to `kmm_pr_review/<pr#>/per_file/<sanitized-path>.md`.

## Report shape

Same as the migrated template — universal preamble verdicts → classification-specific checklist verdicts → findings → live-knowledge sources → status header.

For `baseline` files, the report is typically two sentences plus a status:

```markdown
# Per-file review — <file_path>

- **Classification:** baseline
- **Base SHA:** <base_sha>
- **Head SHA:** <head_sha>

## Universal preamble verdicts

- **U1:** PASS
- **U2:** n/a (binary)
- **U3:** PASS
- **U4:** n/a (binary)

## Baseline checklist verdicts

- **B1:** FAIL — see Finding F1.
- **B2:** see status header.

## Findings

### Finding F1
- **Severity:** BLOCKER
- **Category:** BASELINE_VIOLATION
- **Path:** `<file_path>` at `<head_sha>`
- **Diff excerpt:**
  ```diff
  Binary files differ
  ```
- **Description:** Baseline asset modified. Per Law 9, baseline artifacts are immutable mid-migration; any modification is a hard blocker. ...
- **Suggested fix:** Revert this file to the master version. If the migration intentionally changes UX, raise a separate baseline-rebase request.

═══ STATUS: DONE_WITH_CONCERNS ═══
Flagging 1 finding:
  1. F1 — BLOCKER — BASELINE_VIOLATION — <file_path>
```

## Status

`DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`.

## Notes

- The classification is read from `state.json.files[]` and the dispatch prompt — the reviewer does not infer it. If the input classification doesn't match the state, that's a NEEDS_CONTEXT (the orchestrator may have routed wrong).
- For `baseline` files: U2 and U4 are `n/a` because the file is typically binary. The whole point is that the file should not have changed at all.
- For `build_config` files: a missing live-source citation is a finding, not a NEEDS_CONTEXT — the absence is itself the gap.
