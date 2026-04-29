# Subagent Status Contract

> Every subagent in the kmm-pr-reviewer skill ends its final report with
> EXACTLY ONE of the four status headers below. The orchestrator branches
> on the status. YOU MUST pick the most accurate one; ambiguity is a
> violation.

## Contents

- [The four statuses](#the-four-statuses)
- [Rules](#rules)
- [Per-phase mapping](#per-phase-mapping)

## The four statuses

```
═══ STATUS: DONE ═══
All required work completed. Every checklist item ticked. Zero findings.
Safe to proceed to the next phase.

═══ STATUS: DONE_WITH_CONCERNS ═══
Work completed. Every checklist item has a verdict. Flagging N findings:
  1. F<N> — <severity> — <category> — <path:line>

═══ STATUS: BLOCKED ═══
Cannot proceed. Reason: <reason>. Need: <what would unblock>.
Checklist items unable to be evaluated:
  - <checklist item> — <why>

═══ STATUS: NEEDS_CONTEXT ═══
Specific information gap: <exact question>.
Checklist items requiring context:
  - <checklist item> — <what is missing>
Suggest orchestrator: <fetch master version | fetch researcher notes | other>.
```

## Rules

- The header is the literal string. No paraphrasing, no translation, no emoji substitutes.
- `BLOCKED` and `NEEDS_CONTEXT` NEVER result in "retry same subagent with identical prompt." Re-dispatch with a modified prompt carrying new inputs is a new dispatch by this contract.
- `DONE` requires every checklist item ticked AND zero findings. A single finding moves the status to `DONE_WITH_CONCERNS`.
- `DONE_WITH_CONCERNS` is NOT a way to smuggle "I gave up on this checklist item" past the orchestrator — every concern is a tracked finding per `finding_schema.md`. Items the reviewer could not evaluate go under `BLOCKED` or `NEEDS_CONTEXT`, never silently buried.
- The orchestrator advances to the next phase only when every dispatched subagent has emitted a status.

## Per-phase mapping

| Phase | Expected statuses | Orchestrator action |
|---|---|---|
| 0 (bootstrap) | `DONE` (state.json written) or `BLOCKED` (gh auth, network) | DONE → Phase 1; BLOCKED → present error to user, halt |
| 1 (review_guide) | `DONE` (review_guide.md written) or `NEEDS_CONTEXT` (a file's classification looks ambiguous) | DONE → Phase 2; NEEDS_CONTEXT → re-dispatch bootstrap or ask user |
| 2 (per-file × N) | `DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT` per file | All `DONE`/`DONE_WITH_CONCERNS` → Phase 3. Any `BLOCKED`/`NEEDS_CONTEXT` → REQUIRES_APPROVAL (re-dispatch with extra context, skip and proceed, or abandon) |
| 3 (triager) | `DONE` (triager_report.md written) or `NEEDS_CONTEXT` (a finding's evidence doesn't reproduce — flag for re-investigation) | DONE → Phase 4 |
| 4 (approval presenter) | `DONE` (findings_pending_approval.md written) | DONE → present to user, await `approved`/`revise`/`abandon` |
| 5 (poster) | `DONE` (posted_review.md written, GitHub URL recorded) or `BLOCKED` (gh API error) | DONE → write final summary; BLOCKED → present error, posted_review.md records the failure |
