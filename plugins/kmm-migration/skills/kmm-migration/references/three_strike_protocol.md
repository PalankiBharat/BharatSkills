# Three-Strike Protocol

> When a subagent fails to resolve the same problem after three distinct
> approaches, STOP. Do not retry. Escalate per this protocol.

## Contents

- [Trigger conditions](#trigger-conditions)
- [Strike report schema](#strike-report-schema)
- [Escalation paths](#escalation-paths)

## Trigger conditions

- Same root problem attempted with three meaningfully different approaches.
- "Different approach" means substantively different tactic, not the same
  tactic with a typo fix.
- Attempt 3 failing ≠ trigger — the subagent completes the attempt 3 report
  THEN stops.

## Strike report schema

Write to `kmm_migration/reports/<feature>/strikes/<ISO-timestamp>_<subagent-name>.md`:

```markdown
# Strike Report — <subagent> — <timestamp>

## Problem
<one sentence>

## Attempt 1
- Tactic: <brief>
- Output observed: <path:line references + logs>
- Why it failed: <fact-based>

## Attempt 2
(same structure)

## Attempt 3
(same structure)

## Pattern across attempts
<what the three failures have in common — often the clue>

## Requesting
<one of: root-cause investigation | different-shape subagent | user decision>
```

## Escalation paths

After writing the strike report, emit `STATUS: BLOCKED` pointing to it.
Orchestrator chooses:

1. Dispatch `debug_investigator` (wraps `superpowers:systematic-debugging`).
2. Dispatch a different-shape subagent (e.g., research-only, no code tools).
3. Escalate to user with `REQUIRES_APPROVAL`.

Never retry the same subagent with the same prompt.
