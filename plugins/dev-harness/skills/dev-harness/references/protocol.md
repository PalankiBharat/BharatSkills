# Protocol — mailboxes, statuses, sentinels

Every run owns a `.harness/` directory at the repo root (gitignored). The Orchestrator and the four panes communicate ONLY through files in it. **Only the Orchestrator writes a role's inbox**; a pane only ever reads its own inbox. That makes pane isolation structural.

## Layout
```
.harness/
  story.md · log.md · state.json
  tech-lead/ dev/ qa/ architect/   each: inbox.md outbox.md status feedback.md worklog.md
  qa/emulator.lock
  artifacts/  spec.md findings.md open-questions.md plan.md dev-handoff.md
              qa-scenarios.md qa-flows/ qa-report.md architect-review.md
              architect-replan.md testtag-requests.md
  review/     themed HTML review pages
```

## Status sentinel (`<role>/status`)
| status | meaning |
|---|---|
| `idle` | waiting |
| `working` | Orchestrator wrote a new inbox; pane is processing (only the Orchestrator sets this) |
| `done` | finished; outbox + artifacts written (supervisor sets it from the worker's exit) |
| `blocked` | cannot proceed (emulator died, missing input) |
| `needs-user` | Tech Lead surfaced open questions |

## Artifact paths (canonical)
**All scratch artifacts live under `.harness/artifacts/`** (gitignored): spec, findings, open-questions, plan, dev-handoff, qa-scenarios, qa-flows/, qa-report, architect-review, architect-replan, testtag-requests. A worker's cwd is the **repo root**, so always use the full `.harness/artifacts/<file>` path — never bare `artifacts/<file>` (that would write to the committed repo root). Code goes to `app/src/**`. `EXPECT:` accepts either `.harness/artifacts/X` or bare `artifacts/X` (the supervisor normalizes both to the run's `.harness/`).

## Dispatch contract
An inbox message is `<INSTRUCTION>` plus optional `EXPECT: <artifact path>`. The supervisor marks `done` only if the worker exits 0 AND the EXPECTed artifact is present — else `blocked`. The Orchestrator also re-checks artifacts on disk (never trusts a flag alone).

## Helper scripts
`lib.sh` (notepad + pick_serial + redact) · `harness-init.sh` · `send.sh` · `poll.sh` · `role-runner.sh` (supervisor) · `feedback.sh` · `render-review.sh`.
