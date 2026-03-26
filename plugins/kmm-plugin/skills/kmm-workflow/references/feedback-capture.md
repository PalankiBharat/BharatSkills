# Feedback Capture

Three feedback files are created in Phase 0 alongside PLAN.md and PROGRESS.md:
- `KMM_FEEDBACK.md` — KMM skill gaps: missing patterns, dep map holes, test gotchas
- `KMM_WORKFLOW_FEEDBACK.md` — Assessment accuracy: misclassifications, missed files, parallelism issues
- `GAMEPLAN_FEEDBACK.md` — Planning/execution: build issues, checkpoint problems, escalations

## When Agents Write

| Trigger | File | What to capture |
|---------|------|----------------|
| Classification wrong | KMM_WORKFLOW_FEEDBACK | What was X, actually Y, why |
| Unmapped file found | KMM_WORKFLOW_FEEDBACK | What file, why missed, resolution |
| Library not in dep map | KMM_FEEDBACK | Library, replacement found, add to map |
| Pattern not in references | KMM_FEEDBACK | Pattern needed, solution, add to which file |
| Test hard to write | KMM_FEEDBACK | What made it hard, workaround |
| Batch parallelism failed | KMM_WORKFLOW_FEEDBACK | Why, how restructured |
| Checkpoint build failed | GAMEPLAN_FEEDBACK | What failed, was template wrong |
| Escalation happened | GAMEPLAN_FEEDBACK | What, decision, automate next time? |
| New gotcha discovered | KMM_FEEDBACK | Gotcha, add to battle-tested-gotchas.md |

## Entry Format

```
### [Phase N, Task/Batch] — YYYY-MM-DD
**Category:** classification-miss | missing-pattern | dep-map-gap | test-gotcha |
  parallelism-issue | build-issue | escalation | assessment-gap | consumer-miss | new-gotcha
**What happened:** [concrete description]
**How it was resolved:** [what agent did]
**Suggestion for skill:** [specific improvement — what to add/change in which reference file]
```

## Rules

- Write IMMEDIATELY when trigger happens — don't batch
- Be specific: file names, error messages, exact patterns
- Always include "Suggestion for skill" — actionable, not just observation
- Append-only — never delete entries
- Orchestrator reviews at each checkpoint
