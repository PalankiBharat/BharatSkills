# Completion Promises

Every subagent emits exactly one completion-promise token on its **final line**, with no trailing text. The orchestrator extracts the promise by reading only the last line.

## Tokens

| Token | Emitted by | Meaning | Orchestrator action |
|---|---|---|---|
| `RESEARCH_COMPLETE: <topic> \| answer: ... \| source: ... \| verified: <ISO date>` | researcher | Live-source lookup succeeded. | Record in `findings.md`. |
| `RESEARCH_BLOCKED: <topic> \| reason: no live source ... \| suggest: ...` | researcher | No live source found. | Escalate to user; never fall back to training data. |
| `ARCHITECTURE_ANALYSIS: blockers: N \| high: N \| medium: N \| verified: X/Y checks` | architecture-reviewer | Architecture reviewed. | If `blockers > 0` or `high > 0`, fix and re-dispatch. |
| `CAPTURE_COMPLETE: <source> \| staged: <target> \| tests: N \| consumers-updated: N \| verify-red: N proven` | test-capturer | File staged, tests written + green, verify-red performed. | Mark task `[x]`. Reject if `verify-red:` is missing/`0`. |
| `CAPTURE_BLOCKED: <source> \| reason: ...` | test-capturer | Mechanical block. | Escalate to user with diagnostic. |
| `MIGRATE_COMPLETE: <target> \| swaps: [...] \| expect-actual: [...] \| tests: <N green>` | migrator | File migrated; spec applied verbatim; baseline tests still green. | Mark task `[x]`. |
| `MIGRATE_BLOCKED: <file> \| reason: ...` | migrator | Mechanical block. | Escalate to user with diagnostic. |
| `VERIFY_COMPLETE_PASS: scope=<scope> \| files=N \| tests=count \| targets=...` | completeness-verifier | Plan reflects reality. | Print summary; advance to pr-phase. |
| `VERIFY_COMPLETE_FAIL: scope=<scope> ... gaps: ...` | completeness-verifier | Plan-vs-reality gaps detected. | Escalate to user with gap list. Do not auto-replan. |
| `AUDIT_REPORT: pr=<n> \| blockers: N \| high: N \| medium: N` | pr-auditor | PR audited. | Print findings; offer to post inline comments. |
| `RETRO_COMPLETE: scope=<scope> \| recommendations=N` | skill-retrospector | Retrospective ready. | Print to chat; user copies into skill repo. |
| `QA_DIAGNOSE_COMPLETE: bug-id=<id> \| file=<path> \| line=<n> \| path=<surgical\|refactor> \| test-to-write=<test-name>` | qa-debugger | Bug diagnosed; proposed entry written to `bugs.md` as `PROPOSED`. | Surface to user with `[y / discuss / decline]`; on `y`, promote `PROPOSED` → `OPEN` and dispatch apply-fix. |
| `QA_DIAGNOSE_BLOCKED: bug-id=<id> \| reason: <one-line>` | qa-debugger | Root cause not isolable. | Escalate to user; they collect more signal and re-pinpoint. No retry with same inputs. |
| `QA_FIX_COMPLETE: bug-id=<id> \| file=<path> \| new-test=<test-name> green \| verify-red=proven \| regressions=0 \| targets-compile-clean=<list>` | qa-debugger | Failing test wrote red, fix applied per spec, test green, baselines green, targets compile. | Mark `bugs.md` entry `OPEN` → `FIXED` with `Fixed-at:` and `Fixed-by-test:`. Resume QA loop (rebuild). |
| `QA_FIX_BLOCKED: bug-id=<id> \| reason: <one-line>` | qa-debugger | Mechanical block during fix application (verify-red didn't red, fix didn't green, regression, compile fail). | Escalate to user. Append `Block-reason` to entry. Do not silently retry. |
| `REQUIRES_APPROVAL: <description> ... Recommended: <option> Why: ...` | any subagent | Interpretive failure; user decision needed. | Escalate immediately. No retry. |

## Token grammar

Single line. Kind (left of first colon), followed by zero or more `key: value` segments separated by ` | `. No embedded newlines.

Orchestrator regex:
```
^(RESEARCH_COMPLETE|RESEARCH_BLOCKED|ARCHITECTURE_ANALYSIS|CAPTURE_COMPLETE|CAPTURE_BLOCKED|MIGRATE_COMPLETE|MIGRATE_BLOCKED|VERIFY_COMPLETE_PASS|VERIFY_COMPLETE_FAIL|AUDIT_REPORT|RETRO_COMPLETE|QA_DIAGNOSE_COMPLETE|QA_DIAGNOSE_BLOCKED|QA_FIX_COMPLETE|QA_FIX_BLOCKED|REQUIRES_APPROVAL):\s*(.*)$
```

A malformed last line is treated as `*_BLOCKED` with reason `malformed-completion-promise` and escalated to the user.

## Multi-finding subagents

Subagents that produce structured reports (researcher with multiple lookups, architecture-reviewer, completeness-verifier) place the structured content **before** the completion line. The completion line is always last and always single-line.

```
## Findings
| Question | Answer | Source | Verified |
|---|---|---|---|
| <q1> | <a> | <URL> | <date> |

RESEARCH_COMPLETE: <topic> | answer: see findings table | source: see findings table | verified: <ISO date>
```
