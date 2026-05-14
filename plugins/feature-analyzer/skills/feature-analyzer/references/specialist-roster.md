# Specialist Roster

Each specialist is a single-responsibility agent. The team lead spawns them, feeds them inputs from earlier waves, and merges their outputs. Specialists never call each other — see `cross-agent-broker.md`.

## Roster

| Specialist | Required | Trigger | Wave |
|---|---|---|---|
| `flow-tracer` | Conditional | Extension story OR any code-touching feature | 1 |
| `design-reviewer` | Conditional | Figma URLs present in story | 1 |
| `gap-analyzer` | Always | After flow-tracer | 2 |
| `domain-questioner` | Always | Pillar fixed | 3 |
| `tech-questioner` | Always | Pillar fixed | 3 |
| `qa-questioner` | Always | Pillar fixed | 3 |
| `critic` | Always | After merge | post-merge |
| `red-team` | Opt-in | `--adversarial` for high-stakes (trading, payments, compliance) | post-critic |

## Common output envelope

Every specialist returns a JSON object with at minimum:

```json
{
  "schema_version": "1.0",
  "session_id": "fa-<date>-<slug>",
  "lead_prompt_version": "1.2.0",
  "specialist": "<name>",
  "partial": false,
  "needs_from": [],
  ...specialist-specific fields...
}
```

Schema-fail → lead retries with the validation error appended (≤2 retries per G11). Persistent fail → that specialist returns `partial: true` and the pillar is flagged.

## Specialist contracts

### `flow-tracer`

**Owns**: A-to-Z codebase + sibling-SDK walk.
**Inputs**: filtered story sections + repo paths.
**Output**: see `existing-flow-trace.md`. Key fields: `sdks_probed`, `chain`, `facts[]`, each with `file:line` + `confidence`.
**Self-check (G8)** before return:
- [ ] All 3 sibling SDKs probed or marked `not_applicable`.
- [ ] Every fact has a `file:line` cite.
- [ ] Wire format identified (REST / WS / IPC) if SDK boundary crossed.
- [ ] Persistence layer identified if data round-trip exists.
- [ ] Confidence stamped on every fact.

### `design-reviewer`

**Owns**: Figma fetch, screen catalog, design questions.
**Inputs**: Figma URLs + gap delta (from gap-analyzer in wave 2, if running iteratively).
**Output**:
```json
{
  "screens": [{"node_id": "...", "name": "...", "fileKey": "..."}],
  "questions": [<Question>...]
}
```
**Self-check**:
- [ ] Every screen has a Figma `node_id` that resolves.
- [ ] Every design question has 3-4 options + 1 Recommended.

### `gap-analyzer`

**Owns**: Diff story vs. current code; identify the true delta.
**Inputs**: story + flow-tracer output.
**Output**:
```json
{
  "delta": [
    {"id": "delta-1", "what_changes": "...", "current_state": "...", "target_state": "...", "evidence": [...]}
  ],
  "open_assumptions": [...]
}
```

### `domain-questioner` / `tech-questioner` / `qa-questioner`

**Owns**: questions in their pillar.
**Inputs**: story + gap delta + flow-tracer facts.
**Output**: `{"questions": [<Question>...]}`.
**Hard rule**: every question MUST include `reason_not_derivable` — the explicit reason this can't be answered from code or Figma. No reason → critic rejects.

### `critic`

**Owns**: independent audit.
**Inputs**: merged output (everything from waves 1-3).
**Output**:
```json
{
  "findings": [
    {"type": "schema_fail|evidence_missing|duplicate|conflict|count_overflow",
     "target_id": "...", "detail": "...", "suggested_action": "drop|reprompt|user_ask"}
  ]
}
```
See `critic-rubric.md` for the full check list.

### `red-team` (opt-in)

**Owns**: try to break the output.
**Inputs**: final merged output.
**Output**: `findings[]` same shape as critic but with `category: "adversarial"`.
Targets: questions that pretend to be answered but aren't; flow-tracer cites that mislead about behaviour; option pills where "Recommended" is wrong for this codebase.

## Question schema (shared across all questioners)

```json
{
  "id": "design-d4-chip-order-7a3f",
  "pillar": "design|tech|qa|domain",
  "priority": "red|yellow|green",
  "role": "PM|Backend|Design|Compliance|QA|DevOps",
  "question": "How should custom-duration chips be ordered?",
  "options": [
    {"label": "Ascending by seconds",
     "tradeoff": "Predictable for power users; new entries appear deep in the list.",
     "recommended": true,
     "reason": "Matches existing chip clubbing in DurationSelectionBottomSheet."},
    {"label": "Newest first",
     "tradeoff": "Surfaces recent edits; chips reshuffle every save.",
     "recommended": false},
    {"label": "Manual drag",
     "tradeoff": "Most flexible; needs new drag handle UI.",
     "recommended": false}
  ],
  "reason_not_derivable": "Ordering is a UX decision; no precedent in code.",
  "impact": "Affects chip render order and any saved-order persistence.",
  "confidence": "high|medium|low"
}
```

### Stable question ID

`<pillar>-<topic-slug>-<8-char-hash-of-question-text>`
- `pillar` MUST be one of: `design | tech | qa | domain`. No other values are accepted.
- `topic-slug`: kebab-case from the question's main noun
- hash: first 8 chars of SHA-1 of the question text

Same story + same code state → same ID. Enables determinism (G7) and regression-testing across runs.

### Role → pillar map (mandatory)

The **role tag** on the question card is what stakeholders see (PM, Backend, Design, Compliance, QA, DevOps). The **pillar slug** in the qid is what the critic counts. These are distinct namespaces and the mapping is fixed:

| Role tag (visible) | Pillar slug (in qid) |
|---|---|
| PM / Product Owner | `domain` |
| Backend / API | `tech` |
| Design | `design` |
| QA | `qa` |
| Compliance / Legal | `domain` |
| DevOps / Infra | `tech` |

A question whose role tag is "Backend" still has a qid starting with `tech-`. A question for Compliance maps to `domain-`. This keeps the pillar count budget meaningful (`tech ≤ 15`, `domain ≤ 10`, etc.) while letting the visible role tag stay human-friendly. Critic rejects any qid whose prefix is outside the 4-pillar set.

### Option count rule

- Min 3 options, max 4. Outside that range → critic flags `count_overflow` and asks the questioner to rebalance.
- Exactly 1 option marked `recommended: true`. Zero or multiple → reject.
- `recommended: true` MUST cite a reason. Reasons grounded in `flow-tracer` facts get `confidence: high`; UX-only reasons get `medium`; speculation gets `low`.

### Forbidden — open-text-only questions

Open-ended text fields without options are forbidden in Mode 1. The only allowed exception is the per-question "Other / override" text input that supplements the radio options. A questioner returning a question without an options array → critic rejects.

## Confidence scoring (G6)

Every claim / question carries `confidence`:

- `high` — cited `file:line` OR explicit Figma node OR direct quote from story.
- `medium` — inferred from related code with stated reasoning.
- `low` — speculation.

Lead behaviour:
- `low` claims do NOT auto-answer questions.
- `low` questions are batched into a separate "Unsure — please confirm" section so the developer can drop them rapidly.

## Determinism

See `determinism-rules.md`. Specialists must select from templated question slots rather than freestyle generation. Each output is seeded with the session-id so traceable across runs.
