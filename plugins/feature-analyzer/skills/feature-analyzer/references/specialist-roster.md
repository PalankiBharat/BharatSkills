# Specialist Roster

Each specialist is a single-responsibility agent. The team lead spawns them, feeds them inputs from earlier waves, and merges their outputs. Specialists never call each other — see `cross-agent-broker.md`.

## Roster (consolidated — v2.1)

Earlier versions of this skill ran 8 specialists across 3 waves. Feedback (#173) was that the extra subagents added cost without adding signal: `gap-analyzer` only rephrased what `flow-tracer` already had, and three pillar-specific questioners produced overlapping prompts with no real coherence win.

This version has 5 specialists.

| Specialist | Required | Trigger | Wave |
|---|---|---|---|
| `flow-tracer` | Always (degraded if no repo) | Always — walks code + emits the story-vs-code delta | 1 |
| `design-reviewer` | Conditional | Figma URLs present in story (otherwise degraded mode) | 1 |
| `questioner` | Always | After Wave 1; emits questions across ALL pillars in one pass | 2 |
| `critic` | Always | After merge | post-merge |
| `red-team` | Opt-in | `--adversarial` for high-stakes (trading, payments, compliance) | post-critic |

What changed from 8 → 5:

- `gap-analyzer` is **folded into `flow-tracer`** — flow-tracer now emits a `delta[]` array alongside `facts[]`. The lead reads both from one envelope.
- `domain-questioner` + `tech-questioner` + `qa-questioner` → **single `questioner`** with pillar-keyed sub-buckets. The questioner owns the full template catalog and emits one consolidated `questions[]` array. Critic still counts per-pillar caps.

This also fixes a real coherence problem: when three questioners ran in parallel they sometimes generated semantically duplicate questions that critic had to merge after the fact. One specialist with a unified template catalog avoids the dup-and-merge round-trip.

## Common output envelope

Every specialist returns a JSON object with at minimum:

```json
{
  "schema_version": "2.1",
  "session_id": "fa-<date>-<slug>",
  "lead_prompt_version": "2.1.0",
  "specialist": "<name>",
  "partial": false,
  "needs_from": [],
  ...specialist-specific fields...
}
```

Schema-fail → lead retries with the validation error appended (≤2 retries per G11). Persistent fail → that specialist returns `partial: true` and the pillar is flagged.

## Specialist contracts

### `flow-tracer`

**Owns**: A-to-Z codebase + sibling-SDK walk **AND** story-vs-code delta (absorbed from old `gap-analyzer`).
**Inputs**: filtered story sections + repo paths + `project_memory` (from PREFLIGHT — see `team-lead-protocol.md`).
**Output**: see `existing-flow-trace.md`. Key fields: `sdks_probed`, `chain`, `facts[]`, **`delta[]`**, each with `file:line` + `confidence`.
**Self-check (G8)** before return:
- [ ] All 3 sibling SDKs probed or marked `not_applicable`.
- [ ] Every fact has a `file:line` cite.
- [ ] Wire format identified (REST / WS / IPC) if SDK boundary crossed.
- [ ] Persistence layer identified if data round-trip exists.
- [ ] Confidence stamped on every fact.
- [ ] `delta[]` covers every story AC not already shipped (each entry: `what_changes`, `current_state`, `target_state`, `evidence`).
- [ ] `project_memory` constraints respected (e.g. if memory says "Punch does not support AMO", flow-tracer must NOT emit a fact assuming AMO exists; the delta MUST NOT propose adding it unless the story explicitly does).

### `design-reviewer`

**Owns**: Figma fetch + walk, screen catalog, flow graph, design tokens, design-pillar questions.
**Inputs**: `session.figma_targets[]` (from story-clarifier), flow-tracer `delta[]` (iterative).
**Protocol**: full walk rules in `figma-walk.md` — URL pattern detection, prototype/section traversal (depth ≤8), screenshot capture at `scale: 2`, design-token extraction, Code Connect cross-reference, sensitive-content stripping.
**Output**: extends the common envelope with:
```json
{
  "figma_unavailable": false,
  "screens": [
    {"node_id": "...", "file_key": "...", "name": "...",
     "screenshot_path": "...", "annotations": [...],
     "linked_components": [...], "confidence": "high"}
  ],
  "flow_graphs": [
    {"start_node": "...", "edges": [{"from": "...", "to": "...", "trigger": "ON_TAP", "label": "..."}],
     "node_index": {"...": {"name": "...", "screenshot": "..."}}}
  ],
  "design_tokens_referenced": [
    {"figma_token": "...", "value": "...", "suggested_app_token": "..."}
  ],
  "questions": [<Question>...]
}
```
**Self-check**:
- [ ] Every screen has a Figma `node_id` that resolves via `mcp__figma__get_design_context`.
- [ ] Every visited frame has a screenshot path on disk (or `downscaled: true`).
- [ ] Every design question has 3-4 options + 1 Recommended.
- [ ] Auto-answer candidates are flagged for the lead's merge step.
- [ ] No sensitive frames embedded inline.

### `questioner` (replaces domain/tech/qa questioners)

**Owns**: every non-design pillar question. One specialist produces them all so duplicates are caught before merge, and so cross-pillar concerns (e.g. an Android-implementation question that also has a backend touch-point) stay coherent.
**Inputs**: filtered story, flow-tracer output (facts + delta), `project_memory`, scope-report (incl. `backend-android-driven` flag).
**Output**:
```json
{
  "specialist": "questioner",
  "questions_by_pillar": {
    "domain": [<Question>...],
    "tech": [<Question>...],
    "qa": [<Question>...]
  }
}
```

Questions still carry stable qid + role tag per the schema below. The split into `questions_by_pillar` is for the critic's count budget; the lead flattens before rendering.

**Hard rules**:
- Every question MUST include `reason_not_derivable`. No reason → critic rejects.
- Every question MUST cite a template slot from `determinism-rules.md` (the template catalog). Freestyle → `freestyle: true` + extra critic scrutiny.
- For Android-scoped projects, the questioner MUST emit at least one Android-role question per touch-point in the delta. Empty Android coverage when delta has UI changes → critic flags `missing_android_coverage`.
- The questioner respects `project_memory` constraints — questions whose subject appears in a memory marked "not supported / not applicable" are auto-suppressed.
- Strikethrough-revival: if `story-clarifier.strikethrough_branches[]` carries a settled-decision marker for a topic, the questioner MUST NOT generate a question that surfaces the rejected branch as an option. (See `critic-rubric.md` for the matching critic check.)

### `critic`

**Owns**: independent audit.
**Inputs**: merged output (everything from waves 1-2).
**Output**:
```json
{
  "findings": [
    {"type": "schema_fail|evidence_missing|duplicate|conflict|count_overflow|backend_internals_leak|strikethrough_revival|missing_android_coverage",
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

## Question schema

```json
{
  "id": "tech-api-contract-7a3f0b2c",
  "pillar": "design|tech|qa|domain",
  "priority": "red|yellow|green",
  "role": "PM|Backend|Design|Compliance|QA|DevOps|Android",
  "question": "What is the Kill Switch backend API contract — endpoints, HTTP methods, request/response payloads?",
  "template_slot": "api-contract",
  "options": [
    {"label": "POST /kill-switch + GET /kill-switch/status",
     "tradeoff": "REST-shaped; matches existing /orders pattern.",
     "recommended": true,
     "reason": "Matches the existing /orders endpoint convention."},
    {"label": "WebSocket only (push update on every flag flip)",
     "tradeoff": "Real-time; one channel handles activate + reset + cross-device sync.",
     "recommended": false},
    {"label": "GraphQL mutation + subscription",
     "tradeoff": "Single endpoint; need GQL schema + resolvers.",
     "recommended": false}
  ],
  "reason_not_derivable": "Spec defines flag fields but no URLs or methods.",
  "impact": "Drives Retrofit interface shape + error-code mapping in the SDK.",
  "confidence": "medium"
}
```

### Stable question ID

`<pillar>-<topic-slug>-<8-char-hash-of-question-text>`
- `pillar` MUST be one of: `design | tech | qa | domain`.
- `topic-slug`: kebab-case from the question's main noun.
- hash: first 8 chars of SHA-1 of the question text.

### Role → pillar map (mandatory)

Visible **role tag** ≠ internal **pillar slug**. The map is fixed:

| Role tag (visible) | Pillar slug (in qid) |
|---|---|
| PM / Product Owner | `domain` |
| Backend / API | `tech` |
| **Android** | `tech` |
| Design | `design` |
| QA | `qa` |
| Compliance / Legal | `domain` |
| DevOps / Infra | `tech` |

`Android` is a first-class role tag, mapping to the `tech` pillar. When the scope filter retains any Android section, the questioner MUST produce Android-tagged questions across the Android-implementation slots in `determinism-rules.md` (compose state hoisting, module placement, Hilt providers, navigation, toast/error mapper, preview plan, ViewModel ↔ UseCase wiring).

### Option count rule

- Min 3 options, max 4. Outside → critic flags `count_overflow`.
- Exactly 1 option marked `recommended: true`. Zero or multiple → reject.
- `recommended: true` MUST cite a reason. Reasons grounded in flow-tracer facts → `confidence: high`; UX-only → `medium`; speculation → `low`.

### Composite slot — `api-contract`

When the story defines API-shaped fields but no URLs / methods / payload schemas, the questioner emits **one** composite "api-contract" question instead of splitting into separate read-shape / activate-shape / error-channel questions. Catalog details in `determinism-rules.md`. The composite question's options cover the realistic endpoint shapes (REST / WS / GraphQL) and let the backend team answer once.

### Forbidden — open-text-only questions

Open-ended text fields without options are forbidden in Mode 1. The only allowed exception is the per-question "Other / override" text input that supplements the radio options. Questioner returning options-less questions → critic rejects.

## Confidence scoring (G6)

- `high` — cited `file:line` OR explicit Figma node OR direct quote from story.
- `medium` — inferred from related code with stated reasoning.
- `low` — speculation.

Lead behaviour:
- `low` claims do NOT auto-answer questions.
- `low` questions are batched into a separate "Unsure — please confirm" section.

## Determinism

See `determinism-rules.md`. Specialists select from templated question slots; freestyle generation requires `freestyle: true` and the critic audits those more strictly.
