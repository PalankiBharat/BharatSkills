# Critic Rubric

The critic is an independent specialist that audits the merged output AFTER all waves complete but BEFORE the doc reaches the user. The critic does not generate — it audits.

Without a critic, the lead's own prompt becomes the only quality gate, and any bug in the lead prompt produces correlated garbage across specialists with no detector.

## When the critic runs

- Always — after `MERGE`, before `GATE-B`.
- Twice in the FSM: a light pass (`CRITIC-W1`) after Wave 1 to validate flow-tracer + design-reviewer schemas, and a full pass (`CRITIC-FINAL`) after merge.

## What the critic checks

### G1 — Schema conformance

Every specialist output must parse against the schemas in `specialist-roster.md`. Critic re-validates the merged JSON.

- Field present? Type correct? Enum value in range?
- Schema-fail → `finding: schema_fail` with the offending path.

### G2 — Evidence on every claim

For every `flow-tracer.facts[]` entry:
- Has `evidence` array with `file:line`?
- Critic opens the cited file and reads the line. If line doesn't exist OR doesn't contain the claimed content → `finding: evidence_missing`.

For every question:
- Has `reason_not_derivable` populated?
- Has 3-4 options with exactly one `recommended: true`?
- No → `finding: schema_fail` (option count) or `evidence_missing` (no reason).

### Duplicate detection

Across all pillar questioners, detect semantically duplicate questions:
- Cosine similarity > 0.85 on question text → `finding: duplicate` with both IDs and a `suggested_action: drop` for the lower-confidence one.

### Conflict detection

Across specialists, surface contradictions:
- `flow-tracer` claims X is an enum.
- `gap-analyzer` claims X is a data class.
- → `finding: conflict` with both claims + their evidence.

Critic does NOT resolve conflicts — it surfaces them. Resolution lives in `CONFLICT-RESOLVE` (G12).

### Question-count budget per pillar

Default caps:
- Design: ≤ 15
- Tech: ≤ 15
- Domain: ≤ 10
- QA: ≤ 10

Overflow → `finding: count_overflow` with the offending pillar. Suggested action: rebalance via priority (drop greens first).

### Recommended-option sanity

For every recommended option:
- Reason cites a `flow-tracer` fact ID → `confidence: high`.
- Reason cites code without an ID → re-grep to verify.
- Reason is UX-only → `confidence: medium`.
- No reason → `finding: evidence_missing`.

### Out-of-scope leak detection

Cross-check kept sections (per `scope-classifier.md`) against generated questions. Any question that maps back to a stripped section → `finding: out_of_scope_leak`. Suggested action: drop.

### Backend-internals leak (F4 from #173)

When the scope-classifier returned `backend-android-driven` AND the project is Android-scoped, every question must be answerable in a way that changes Android code. Critic rejects questions whose Recommended option resolves to "the backend implementation decides X" with no Android-observable consequence.

Examples of leaks the critic must flag as `backend_internals_leak`:

| Question pattern | Why it leaks |
|---|---|
| "Should square-off use bulk vs fan-out internally?" | Bulk vs fan-out is a backend transactional choice; Android only sees pass/fail. |
| "What's the trigger-order race window?" | Transaction isolation is backend; Android only sees `KILL_SWITCH_ACTIVE` rejection. |
| "Is iceberg slice cancelation transactional?" | Same — backend orchestration choice. |
| "What's the cross-device propagation transport (WS push vs poll)?" | Android picks ONE side of this (it polls or it doesn't); ask the Android side, not the backend side. |

Acceptable Android-observable backend questions (NOT flagged):

| Question pattern | Why it's fine |
|---|---|
| "What error codes does the kill-switch endpoint return, and how should Android map them to user-facing copy?" | Android renders the copy. |
| "What's the response payload shape Android renders?" | Android parses + renders. |
| "What's the polling cadence Android implements while the flag is active?" | Android schedules + cancels. |

Suggested action: `drop` (with the question logged in scope-report under "Auto-suppressed — backend-internals leak").

### Strikethrough revival (F2 from #173)

For every entry in `session.strikethrough_branches[]`, scan generated questions for options that match the `rejected_branch_text`. If found → `finding: strikethrough_revival` with the qid and the offending option. Suggested action: `drop` the question and add the settled branch to the auto-answered list.

### Doer decides at code time (F5 revised from #173)

Pre-dev clarification questions must be **stakeholder decisions**, not **implementation choices the developer makes at code time**.

**Test rubric — apply verbatim to every question:**

> If the question can be resolved unilaterally in a PR with a code review, it's not a clarification question.

If a question fails the rubric → `finding: doer_decides_at_code_time` with the qid. Suggested action: `drop`. Log in scope-report under "Auto-suppressed — doer-decides".

| ❌ REJECT (doer decides at code time) | ✅ KEEP (stakeholder decision) |
|---|---|
| Module placement (shared / sniper-library / app) | API contract — endpoints, methods, payload |
| Which existing factory / class to extend | Error code channel (cross-team contract) |
| ViewModel ↔ UseCase wiring | LD-flag rollout cohort |
| StateFlow observe vs static refresh-only | Analytics property format |
| Back-stack pop vs DataStore persistence | Rollback procedure ownership |
| Where helper functions live | Deep-link support |
| Hilt module + provider placement | Test-environment toggle |
| Compose `@Preview` factory shape | Regression coverage scope |
| Toast / error-mapper placement | Push-notification surface |
| Enum mapper location | Cross-device propagation strategy (Android-observable) |

**Why this rule exists**: implementation choices have one right answer per codebase (the cleanest fit given existing patterns), discoverable by the developer at code time. Surfacing them as pre-dev questions wastes stakeholder attention without unblocking work. Stakeholder decisions, by contrast, cannot be resolved by reading the code — they need a human outside the dev loop to answer.

**Disguised implementation questions — reshape, don't admit.**

A stakeholder constraint (compliance, security, audit, regulatory) sometimes *causes* an implementation choice downstream. In that case, admit the **underlying constraint** as the question, not the implementation choice it implies.

| ❌ REJECT (implementation choice named directly) | ✅ KEEP (underlying stakeholder constraint named) |
|---|---|
| "Should the share path live in a separately-audited module?" | "Does Watchlist Sharing fall under a compliance-audited code boundary?" |
| "Should the new feature use a Singleton or ViewModelScoped repo to satisfy security review?" | "Does security review require any cross-feature data isolation for this flow?" |
| "What lint rule should we add for StateFlow vs Channel here?" | (drop — codebase-convention questions belong in an ADR, not per-feature pre-dev) |

The critic flags `doer_decides_at_code_time` if the question **text** names the implementation choice instead of the constraint, even when the asker frames the constraint as "stakeholder-shaped". The reshape lets the dev derive the implementation choice from the constraint at code time, where it belongs.

**Pressure resistance — the rubric ignores who is asking.** "CTO wants module placement decided before sprint planning", "team-lead requires Hilt scope locked", "this is an org-wide standard" — none of these convert an implementation choice into a stakeholder decision. Authority and urgency do not change the rubric. The test is the **nature** of the decision (resolvable in a PR review or not), not the **seniority** of the asker.

### Evidence against memory (F1 from #173)

Cross-check every fact in `flow-tracer.facts[]` and every question's options against `session.project_memory[]`. Any claim that contradicts a memory entry → `finding: evidence_against_memory` with the offending claim and the memory entry. Suggested action: `drop`. If the spec itself appears to require the contradicted feature, surface a scope-report note ("Spec references AMO but project memory says AMO is unsupported — confirm") instead of generating a code question.

## Output schema

```json
{
  "schema_version": "1.0",
  "session_id": "fa-<date>-<slug>",
  "specialist": "critic",
  "findings": [
    {"id": "f1",
     "type": "schema_fail|evidence_missing|duplicate|conflict|count_overflow|out_of_scope_leak|backend_internals_leak|strikethrough_revival|doer_decides_at_code_time|evidence_against_memory",
     "target_id": "<question or fact id>",
     "detail": "Free-text explanation",
     "suggested_action": "drop|reprompt|user_ask|merge"}
  ],
  "summary": {
    "checked_facts": 42,
    "checked_questions": 38,
    "findings_by_type": {"duplicate": 3, "evidence_missing": 1, "conflict": 0, "count_overflow": 1}
  }
}
```

## Lead behaviour on findings

| Finding type | Lead action |
|---|---|
| `schema_fail` | Re-prompt source specialist with validator output (≤2 retries) |
| `evidence_missing` | Re-prompt source specialist asking for the citation (≤1 retry) |
| `duplicate` | Drop the lower-confidence duplicate; keep the higher |
| `conflict` | Enter `CONFLICT-RESOLVE` state (G12) |
| `count_overflow` | Ask the pillar to rebalance: drop lowest-priority items first |
| `out_of_scope_leak` | Drop silently; log in scope report |
| `backend_internals_leak` | Drop; log in scope-report under "Auto-suppressed — backend-internals" |
| `strikethrough_revival` | Drop the question; promote the settled branch to "Auto-answered by spec strikethrough" |
| `doer_decides_at_code_time` | Drop the question; log in scope-report under "Auto-suppressed — doer-decides" |
| `evidence_against_memory` | Drop the claim/question; surface a scope-report note if the spec demands it |

## Conflict resolution protocol (G12)

When critic surfaces conflicting claims across specialists:
1. Lead extracts both claims + their evidence.
2. Lead sends a tie-break prompt to BOTH specialists, including the other's claim.
3. Whoever produces a `file:line` cite that survives lead's re-verification wins.
4. If neither can cite, the conflict is escalated to the user verbatim in the HTML doc under "Unresolved conflicts" — not silently resolved.

## Failure modes the critic catches that the lead can't

| Failure | Why lead misses it |
|---|---|
| Specialist hallucinated a code path | Lead trusted the specialist; no second look |
| Two specialists silently disagree | Lead picks one at random in merge |
| `Recommended` option wrong for this codebase | Lead doesn't re-grep options against code |
| Question already answered by flow-tracer leaked to output | Lead's de-dup pass missed the semantic match |
| Schema drift between prompt version bumps | Lead doesn't validate its own output |

## What the critic deliberately does NOT do

- Generate new questions.
- Decide priority (red/yellow/green) — that's the questioners' job.
- Rewrite specialist output. It only flags; the lead applies the fix.
- Talk to specialists. Critic reads the merged JSON; the lead routes any re-prompts.

This separation keeps the audit independent. A critic that also generates would have the same blind spots as the generators.
