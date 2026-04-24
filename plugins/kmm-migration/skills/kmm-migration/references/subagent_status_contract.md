# Subagent Status Contract

> Every subagent in the kmm-migration skill ends its final report with
> EXACTLY ONE of the four status headers below. The orchestrator branches
> on the status. YOU MUST pick the most accurate one; ambiguity is a
> violation.

## Contents

- [The four statuses](#the-four-statuses)
- [Rules](#rules)

## The four statuses

```
═══ STATUS: DONE ═══
All required work completed. All internal checks pass. Safe to proceed.

═══ STATUS: DONE_WITH_CONCERNS ═══
Work completed. Flagging N concerns for orchestrator attention:
  1. <concern> at <path:line> — <why it matters>

═══ STATUS: BLOCKED ═══
Cannot proceed. Reason: <reason>. Need: <what would unblock>.
See strikes/<ts>_<me>.md for failed attempts.

═══ STATUS: NEEDS_CONTEXT ═══
Specific information gap: <exact question>.
Suggest orchestrator dispatches <researcher | fresh inventory | …>.
```

## Rules

- `BLOCKED` and `NEEDS_CONTEXT` NEVER result in "retry same subagent with
  identical prompt." Re-dispatch with a modified prompt carrying new inputs
  is a new dispatch by this contract.
- `DONE_WITH_CONCERNS` is NOT a way to smuggle scope creep past review —
  concerns describe work the orchestrator should route elsewhere, not work
  the subagent silently did.
- The header is the literal string. No paraphrasing, no translation, no
  emoji substitutes.
