---
description: Read-only audit of any KMM migration PR — whether it was made with this skill or not. Reviews every changed line against the constitution, clean-code reference, and KMM-specific principles. Returns a table of issues. On user approval, posts selected issues as inline GitHub comments. Distinct from /kmm-verify (which is a completeness check on migrations done with this skill).
argument-hint: "<pr-number-or-url> | <branch-name>"
---

# /kmm-audit

You are running this command as the orchestrator. Read `skills/kmm-migration-workflow/constitution.md`, `skills/kmm-migration-workflow/references/clean-code.md`, and `skills/kmm-migration-workflow/references/orchestration-protocol.md` first.

Audit mode is **read-only by default**. The skill's principles are encoded once — they apply equally to migrations done with this skill and migrations done by hand. Audit lets the user benefit from the principle library on **any** PR, even legacy ones.

This is **not** the verify phase. Verify checks completeness of a migration done with the skill (plan-vs-reality across architecture/plan/migration-guide/tasks). Audit checks principle adherence of a migration done by anyone, with no skill artifacts to cross-reference.

## When to invoke

The user runs `/kmm-audit <pr>` when they want a principles-driven review of a KMM migration PR. Examples:
- A teammate's PR that migrates files into commonMain.
- A PR opened months ago that the user wants a second-look on.
- A PR opened **with** this skill that the user wants a fresh principle-pass on (audit and verify are not redundant — they look at different things).

## Inputs

- `<pr>` — a GitHub PR number, URL, or local branch name. Resolve in this order:
  1. If it parses as a number → `gh pr view <number>`.
  2. If it parses as a URL → `gh pr view <url>`.
  3. Otherwise treat as a local branch → `git diff <base>...<branch>`.
- The constitution (always loaded).
- `references/clean-code.md` (loaded by the auditor).

## What you do

### 1. Resolve the PR and gather context.

For a GitHub PR:
- `gh pr view <pr> --json number,title,body,baseRefName,headRefName,files,headRepository`
- `gh pr diff <pr>` — the unified diff.
- `gh pr view <pr> --json commits` — commit list (for retrospective context).

For a local branch:
- `git diff <base>...<branch>` — the unified diff (where `<base>` is the merge-base; ask once if unclear).
- `git log <base>..<branch>` — commits.

Write the diff to `<repo>/.kmm-audit/<pr-or-branch>/diff.patch` so the auditor can read it without re-fetching. Create the directory if it doesn't exist.

### 2. Check whether the PR was made with this skill.

If `<pr>`'s repo contains a `kmm/<scope>/` directory whose `spec.md` references the same baseline SHA the PR diff is built on, this is a skill-made migration. In that case, tell the user:

> This PR was made with `kmm-migration-workflow`. Audit will still run (different lens than verify), but you may want `/kmm-verify` for completeness. Continue with audit? [y / cancel]

The user picks. Default is to continue — audit and verify look at different things, and running both is fine.

If no skill artifacts are present, this is an external migration and audit is the only relevant lens.

### 3. Dispatch `pr-auditor`.

```
Dispatch: agents/pr-auditor.md
Task: Audit the KMM migration PR for principle violations.
      Diff: <repo>/.kmm-audit/<pr-or-branch>/diff.patch
      PR metadata: <repo>/.kmm-audit/<pr-or-branch>/metadata.json
Model: sonnet
Mode: read-only (no Write/Edit; gh read-only fine)
```

The auditor walks the diff line by line, applies every applicable principle from the constitution + `clean-code.md`, and returns a structured `AUDIT_REPORT` with one row per finding.

Audit categories the auditor walks:

- **Constitution violations**: anything explicitly forbidden by the constitution shows up here. Examples: TODO/FIXME/XXX/HACK in migrated code (§9); type casts (§9); platform-bound imports in commonMain (§11); legacy threading-model adapters in commonMain (§11); migration-tracking comments (§9); scaffolding-pattern holders/wrappers without behaviour (§10); refactor that expanded scope (§6).
- **Clean-code violations**: every section of `references/clean-code.md` produces a category (mechanism-led names, generic-name parameters, multi-purpose functions, dead code, redundant comments, scaffolding without behaviour, etc.). Each finding cites the section.
- **KMM-specific issues**: missing `expect/actual` for a clearly-platform-bound API; `androidx.*` imports in commonMain; `LiveData`/`RxJava` references in commonMain; `as Type` unsafe casts; `@Suppress` added in migrated code; concurrency primitives other than `kotlinx.coroutines` crossing the shared boundary.
- **Public API drift**: the diff changes a public method's name, parameter names, parameter order, or return type — this is a backward-incompatible change unless explicitly authorised. Flag every instance.
- **Behaviour drift**: a code change that looks like it might alter behaviour (a removed null check, a changed default, a swapped operator, an inverted branch). The auditor cannot prove behaviour drift without running tests; it flags suspicions for human review.
- **Test coverage gaps**: files newly in commonMain without a corresponding `*Test.kt` in commonTest — flag as `NO_BASELINE_TESTS`.

Each finding carries: file, line range (in the migrated form), severity (`HIGH` / `MEDIUM` / `LOW` / `NIT`), the principle reference, what the auditor observed, and what the auditor would have done instead (the "if I (the skill) did this, I would have done it like this" framing — concrete enough that the user could turn it into an inline comment verbatim).

### 4. Receive the report.

The auditor returns a markdown table the user can read in chat:

```
| # | File | Line | Severity | Principle | Observed | Should be |
|---|---|---|---|---|---|---|
| 1 | shared/src/commonMain/.../AuthSession.kt | 12 | HIGH | Constitution §11 | `import androidx.lifecycle.LiveData` | Drop the import; use `Flow<AuthState>` instead. LiveData is platform-bound and cannot live in commonMain. |
| 2 | shared/src/commonMain/.../AuthSdkHolder.kt | 1–18 | HIGH | clean-code §structure.no-scaffolding-without-behaviour | `class AuthSdkHolder(val sdk: AuthSdk) { fun get() = sdk }` adds no behaviour | Remove the holder; reference `AuthSdk` directly. The wrapper is short-term scaffolding (the failure mode this skill exists to prevent — see Constitution §10). |
| 3 | shared/src/commonMain/.../UserManagerImpl.kt | 1 | MEDIUM | clean-code §naming.intent-over-mechanism | `class UserManagerImpl` — `*Manager*Impl` is mechanism-named | Rename to a domain term, e.g., `UserDirectory` (records and looks up users). |
| ... | ... | ... | ... | ... | ... | ... |
```

Severity rubric:
- **HIGH** — constitution violation OR public API drift OR behaviour drift. Blocks merge in the auditor's view; the user has the final call.
- **MEDIUM** — clean-code violation that creates lasting tech debt (mechanism-led name, holder without behaviour, function does two things, dead code, etc.).
- **LOW** — minor clean-code observation, easy to fix.
- **NIT** — nitpick (style, blank-line placement); the user usually ignores these.

### 5. Present the report and ask the user what to do.

Print the table. Then ask:

> Audit found `<N>` issues: HIGH=`<H>` MEDIUM=`<M>` LOW=`<L>` NIT=`<I>`.
>
> Options:
>   A) Post all HIGH issues as inline comments on the PR (recommended for HIGH issues — they affect mergeability)
>   B) Post selected issues — give me a comma-separated list of issue numbers from the table
>   C) Just print the report — don't post anything (default for read-only audit; user reviews and acts manually)
>   D) Discuss — drill into a specific finding
>
> Reply: A / B / C / D

Default is C — pure audit mode. The user explicitly opts into A or B if they want comments posted. Posting is a public action; never default it.

### 6. On A or B — post inline comments.

For each issue the user selected:

- Compose the comment body: a concise statement of the finding ("`<observed>`") + the principle citation + the "should be" recommendation. Format:

  ```
  **[`<principle>`]** <observed>

  <should-be recommendation>

  _— audited via /kmm-audit (kmm-migration-workflow)_
  ```

- Post the comment on the PR using `gh pr review <pr> --comment ...` for general comments OR `gh api repos/<owner>/<repo>/pulls/<pr>/comments -F path=<file> -F line=<line> -F body=<body>` for inline comments. Inline comments are preferred when the finding is at a specific line; general comments for cross-cutting findings (e.g., "no commonTest files added").

- Use `gh api` rather than the higher-level `gh pr review` for inline-line targeting; the API supports `path` and `line` directly.

- Throttle: post one comment, capture the response, post the next. Don't batch via shell loop because gh rate-limits.

After all comments are posted, print a summary:
```
Posted <N> comments on PR <url>:
  - <file>:<line> — <one-line>
  - ...
```

### 7. On C — print and exit.

The audit report is preserved at `<repo>/.kmm-audit/<pr-or-branch>/audit-report.md` for the user to revisit. Print the path and exit.

### 8. Constitution check (audit-mode appropriate).

- Touched: §3 (no silent decisions — user opts into posting comments), §4 (live-sourced reasoning — every finding cites a constitution principle or a clean-code section, never recall), §12 (everything outside spec gets logged — the audit report is the audit's documentation).
- Pass/fail:
  - `[ ]` Diff was fully read by the auditor (line count matches `wc -l`)
  - `[ ]` Every finding cites a principle or section reference
  - `[ ]` No comments posted without user approval
- On fail: STOP. Report which checks failed.

## What you do NOT do

- Do not modify the audited PR's code. Audit is read-only.
- Do not post comments without explicit user opt-in (option A or B). Default is print-only.
- Do not invent findings. Every finding must trace to a constitution principle or a clean-code section.
- Do not run `/kmm-verify` — verify is for skill-made migrations and requires the skill's artifacts. Audit is the lens for everything else.
- Do not push branches or create PRs of your own. The audit is observation; remediation is the PR author's job.

## Failure modes

- **`gh` is not authenticated** — surface the error, tell the user to run `gh auth login`. Do not retry.
- **PR not found** — surface the error; offer to retry with a different identifier.
- **Auditor returns malformed `AUDIT_REPORT`** — refire once with explicit instruction to emit the structured table format. If second attempt fails, escalate.
- **The PR diff is enormous (>5000 lines)** — print a warning, ask the user whether to proceed or to scope the audit to a subset of files (option presented).
- **The PR has merge conflicts with base** — the diff may be ambiguous. Surface the warning; the user picks whether to audit the head-only diff or the rebased state.
