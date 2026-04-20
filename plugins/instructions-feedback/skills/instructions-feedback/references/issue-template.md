# Issue Template

Use this template to render title and body for each approved candidate.

## Title format

Short, imperative, <70 chars. Prefix with the target so triage is easy.

| Classification | Title prefix | Example |
|---|---|---|
| `claude-md` | `[CLAUDE.md]` | `[CLAUDE.md] Require gradle output on "done" claims` |
| `constitution` | `[Constitution]` or `[Principle <N>]` | `[Principle V] Tighten "fast and solid" with timing budgets` |
| `path-rule` | `[rules/<file>]` | `[rules/concurrency] Flag missing Mutex on shared in-memory cache` |
| `memory-only` | `[Memory]` | `[Memory] Capture Punch's Mixpanel project key location` |

Avoid vague titles like "improve docs", "better rule". Name the change.

## Body template

```markdown
## Context

**Session date**: <YYYY-MM-DD>
**Source quote** (user said):
> <verbatim user text, trimmed>

**Claude's interpretation**:
<one or two sentences paraphrasing what the rule or preference is>

## Proposed change

**Target**: `<file path>` — `<section>` (if applicable)
**Classification**: <claude-md | constitution | path-rule | memory-only>
**Priority**: <P0 | P1 | P2>

### Current state

<quote or describe what's currently in the target — or "N/A (new addition)">

### Proposed amendment

<concrete suggested wording, diff-style if small, or bullet points if a new section>

## Why this matters

<1-2 sentences tying this to a principle or an incident class; if the user
gave a reason, quote it>

## Acceptance criteria

- [ ] <file> updated with the wording above (or a refinement agreed in discussion)
- [ ] <if constitution>: `/speckit.constitution` rerun with version bump (PATCH for wording, MINOR for new principle, MAJOR for removals)
- [ ] <if constitution or claude-md>: dependent `.specify/templates/plan-template.md` Constitution Check updated if a new gate is needed
- [ ] Change linked back to this issue in the commit message

## Session link

<Claude Code session identifier or a short description that lets a reader find the source conversation; omit if not available>

---

*Raised by the `instructions-feedback` skill. Do not implement without reviewing
the quote and interpretation above — the detection pass can misread
intent, and the review-gate approval is not a substitute for judgment
by the principle owner.*
```

## Labels

Always apply:
- `instructions-feedback`
- One of: `claude-md` / `constitution` / `path-rule` / `memory-only`
- One of: `priority:P0` / `priority:P1` / `priority:P2`

Do not invent new labels on the fly. If none of the four classifications
fit, drop the candidate during the review gate.

## Assignees

Do not auto-assign. The triager will decide owners. Leave blank unless
the user explicitly specifies an assignee during review.
