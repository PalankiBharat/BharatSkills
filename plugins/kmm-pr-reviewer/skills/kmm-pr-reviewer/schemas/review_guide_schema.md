# review_guide.md schema

> The per-file review guide written by `10_review_guide_author` in
> Phase 1. Each entry is the input the corresponding per-file reviewer
> reads before walking its checklist.

## Location

`kmm_pr_review/<pr#>/review_guide.md`

## Top-level structure

```markdown
# Review guide for PR #<pr#>

- **PR URL:** <pr_url>
- **Base branch:** <base_branch>
- **Base SHA:** <base_sha>
- **Head SHA:** <head_sha>
- **Files in scope:** <count> (migrated: <n>, ios_port: <n>, nonmigrated: <n>, baseline: <n>, build_config: <n>)
- **iOS reviewer dispatch:** <yes|no>

---

## File: <path>

(One section per file in `state.json.files[]`. The path is repo-relative
and at `head_sha`. Format below.)
```

## Per-file entry shape

```markdown
## File: <path>

- **Classification:** <migrated | ios_port | nonmigrated | baseline | build_config>
- **Change type:** <ADDED | MODIFIED | REMOVED | RENAMED>
- **Paired master path:** <path on master at base_sha, OR `null`>
- **Lines added / removed:** +<int> / -<int> (from `gh pr diff --stat`)
- **Module:** <gradle module root, e.g. `shared/` or `app/`>
- **Source set:** <commonMain | androidMain | iosMain | androidTest | commonTest | n/a>

### Checklist (from references/review_criteria.md → <classification> section)

- [ ] U1 — Diff is in scope.
- [ ] U2 — No `TODO` / `FIXME` / `XXX` introduced.
- [ ] U3 — No build output paths leaked.
- [ ] U4 — No live-knowledge violations in code or comments.
<followed by the classification-specific items, copied verbatim from review_criteria.md>

### Cross-reference — corresponding `expect`s (ios_port only)

(Only present when classification is `ios_port`. Lists the commonMain
expect declarations the actual implementations in this file must
satisfy. Located via Grep against the diff at head_sha.)

- `expect class FooStore` declared at `shared/src/commonMain/kotlin/com/app/foo/FooStore.kt:14`
- `expect fun bar(): Int` declared at `shared/src/commonMain/kotlin/com/app/util/Util.kt:7`

### Reviewer dispatch hint

- **Template:** `20_file_reviewer_<migrated|ios|nonmigrated>` (per classification)
- **Inputs to pass in dispatch prompt:**
  - `file_path: <path>`
  - `master_path: <paired_master_path or null>`
  - `base_sha: <base_sha>`
  - `head_sha: <head_sha>`
- **Expected report path:** `kmm_pr_review/<pr#>/per_file/<sanitized-path>.md`
```

## Sanitization rule for report paths

A file at `<path>` produces a per-file report at `kmm_pr_review/<pr#>/per_file/<sanitized>.md` where `<sanitized>` is the path with `/` and `.` replaced by `_`. Example:

- `shared/src/commonMain/kotlin/com/app/login/LoginViewModel.kt`
- → `shared_src_commonMain_kotlin_com_app_login_LoginViewModel_kt`
- → `kmm_pr_review/154/per_file/shared_src_commonMain_kotlin_com_app_login_LoginViewModel_kt.md`

The sanitized name is also recorded in `state.json.last_dispatch.expected_report_path` so the orchestrator can poll for completion.

## Section ordering

Files are listed in the same order as `state.json.files[]` — which mirrors `gh pr view --json files` ordering, generally alphabetical by path. The reviewer doesn't depend on order; the order is for human-readability of the guide.

## Update discipline

`review_guide.md` is written ONCE in Phase 1. It is not modified later. If a file's classification changes (e.g., a per-file reviewer emits `STATUS: NEEDS_CONTEXT` flagging a misclassification and the user agrees), the orchestrator may re-dispatch `10_review_guide_author` to regenerate the guide. The previous version is preserved in `kmm_pr_review/<pr#>/.archive/review_guide_<iso>.md`.
