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

## Output schema

```json
{
  "schema_version": "1.0",
  "session_id": "fa-<date>-<slug>",
  "specialist": "critic",
  "findings": [
    {"id": "f1",
     "type": "schema_fail|evidence_missing|duplicate|conflict|count_overflow|out_of_scope_leak",
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
