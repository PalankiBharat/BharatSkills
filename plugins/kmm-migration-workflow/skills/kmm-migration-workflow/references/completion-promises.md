# Completion Promises

Every subagent emits exactly one completion-promise token on its **final line**, with no trailing text. The orchestrator extracts the promise by reading only the last line.

## Tokens

| Token | Emitted by | Meaning | Orchestrator action |
|---|---|---|---|
| `RESEARCH_COMPLETE: <topic> \| answer: ... \| source: ... \| verified: ...` | researcher | Live-source lookup succeeded with a verifiable citation. | Record finding in `findings.md`. |
| `RESEARCH_BLOCKED: <topic> \| reason: no live source ... \| suggest: ...` | researcher | No live source found. | Escalate to user; do not fall back to training data. |
| `PLAN_ANALYSIS: blockers: N \| high: N \| medium: N \| verified: X/Y checks` | plan-analyzer | Plan reviewed. | If `blockers > 0` or `high > 0`, fix the plan and re-dispatch. Else proceed. |
| `CAPTURE_COMPLETE: <source> \| staged: <target-staging> \| tests: N \| consumers-updated: N \| verify-red: N proven \| self-check: <report>` | test-capturer | File staged, tests written + green, verify-red performed, self-check passed. | Mark task `[x]`. Reject if `verify-red:` is missing/`0` or `self-check:` is missing/not-passed. |
| `CAPTURE_BLOCKED: <source> \| reason: ... \| strike: N of 3` | test-capturer | Mechanical block; refire after diagnostic. | Refire same agent with diagnostic; max 3 strikes. |
| `MIGRATE_COMPLETE: <target> \| swaps: [...] \| expect-actual: [...] \| tests: <N green> \| self-check: <report>` | migrator | File migrated; spec applied verbatim; self-check passed. | Dispatch `structural-verifier`. Reject if `self-check:` is missing/not-passed. |
| `MIGRATE_BLOCKED: <file> \| reason: ... \| strike: N of 3` | migrator | Mechanical block. | Refire same agent with diagnostic; max 3 strikes. |
| `VERIFY_PASS: <file> \| methods: N/N match \| strings: identical \| defaults: identical` | structural-verifier | Migration is structurally 1:1. | Mark migrate task `[x]`. |
| `VERIFY_FAIL: <file> ... violations: ...` | structural-verifier | Structural divergence. | Refire `migrator` with the violation list; strike applies. |
| `VERIFY_COMPLETE_PASS: scope=<scope> \| files=N \| tests=count \| targets=...` | completeness-verifier | Plan reflects reality; migration ready for `/kmm-pr`. | Print summary; tell user to run `/kmm-pr`. |
| `VERIFY_COMPLETE_FAIL: scope=<scope> ... remediation: R-1, R-2, ...` | completeness-verifier | Plan-vs-reality gaps detected. | Append remediation tasks to `tasks.md`; tell user to re-run `/kmm-implement`, then `/kmm-verify`. |
| `REQUIRES_APPROVAL: <description> ... Recommended: <option> Why: ...` | any subagent | Interpretive failure; user decision needed. | Escalate to user immediately. No retry. |

## Token grammar

The first token (left of the first colon) is the kind. It is followed by zero or more `key: value` segments, separated by ` | `. The final line must be a single line (no embedded newlines).

The orchestrator parses tokens with a simple regex:
```
^(RESEARCH_COMPLETE|RESEARCH_BLOCKED|PLAN_ANALYSIS|CAPTURE_COMPLETE|CAPTURE_BLOCKED|MIGRATE_COMPLETE|MIGRATE_BLOCKED|VERIFY_PASS|VERIFY_FAIL|VERIFY_COMPLETE_PASS|VERIFY_COMPLETE_FAIL|REQUIRES_APPROVAL):\s*(.*)$
```

Anything else in the last line → invalid token → refire once with explicit instruction; second failure → mechanical-blocked.

## Multi-finding subagents

Subagents that produce multi-row data (researcher returning multiple library lookups; plan-analyzer returning a structured report) place the structured content **before** the completion line. The completion line is always last and always single-line.

Example for researcher:

```
## Findings

| Question | Answer | Source | Verified |
|---|---|---|---|
| <sub-question 1> | <answer> | <URL> | <date> |
| <sub-question 2> | <answer> | <URL> | <date> |

RESEARCH_COMPLETE: <topic> | answer: see findings table | source: see findings table | verified: <ISO date>
```

Example for plan-analyzer: see `agents/plan-analyzer.md` — the structured report sits above the single `PLAN_ANALYSIS:` line.

## Why this matters

The orchestrator runs in a tight dispatch loop. Reading subagent prose to interpret status would be slow and error-prone. The completion-promise contract turns each subagent into a state-machine transition: dispatch → run → emit token → orchestrator transitions on the token.

Subagents that bury status in the middle of their output, or that emit multiple tokens, break this loop and force the orchestrator to fall back to interpretation — which is precisely the failure mode the protocol exists to prevent.

If you are an agent reading this: emit exactly one valid token, on the final line, no trailing text, no leading whitespace. That is the contract.
