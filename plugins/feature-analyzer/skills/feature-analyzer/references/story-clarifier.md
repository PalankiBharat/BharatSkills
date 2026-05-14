# Story Clarifier

Parse the user story / feature spec and surface everything that's unclear, assumed, or missing BEFORE the team lead spawns the questioner specialists.

This file is consumed by the team lead (Mode 1) for input prep and by `gap-analyzer` (Wave 2) for delta computation. It is also read directly in Mode 2 Phase 1.

## Detect Figma URLs (mandatory)

Before parsing for clarification, scan the raw story text for Figma URLs. Every match is queued for `design-reviewer` (Wave 1) which will fetch the node, walk the linked frames, capture screenshots, and produce a screen catalog. See `figma-walk.md` for URL patterns, walk protocol, and output schema.

Captured into `session.figma_targets[]`:

```json
{
  "figma_targets": [
    {"raw_url": "...", "kind": "design|proto|file|board|make|slides",
     "file_key": "...", "node_id": "...", "section_in_story": "..."}
  ]
}
```

If no Figma URLs are present, leave the array empty — `design-reviewer` runs in `figma_unavailable: true` mode and skips the walk, but still emits design questions from text alone.

## Capture the source story first (mandatory)

Before any parsing, the team lead captures the raw story text exactly as the reviewer submitted it (whitespace, line breaks, markdown, formatting — all preserved). The captured text becomes `session.source_story` and is threaded through to:

- The HTML doc's Original Story tab (renders verbatim — see `html-output.md` § "Tab strip + Original Story panel").
- The replay log at `00-source-story.md`.
- The `--format md` fallback (prepended under a `## Original story` heading).

The lead is forbidden from rewriting, summarising, or truncating the source story. The clarifier output below extracts structured fields, but those fields ADD to the source — they NEVER REPLACE it. If the source story is enormous (>20k chars), the lead truncates only the tail with an explicit `[…story truncated by lead at N chars; full text in replay log]` marker; the prefix is always preserved unmodified.

## What to extract from the input

Regardless of input format (free text, ticket, structured AC), extract:

1. **Core intent** — what the user is trying to achieve (one sentence).
2. **Actors** — who interacts (end user, system, admin, external API).
3. **Trigger** — what initiates (user action, system event, time-based, external).
4. **Input data** — what data the feature needs.
5. **Output / result** — expected outcome.
6. **Scope boundary** — what's explicitly IN scope vs assumed-but-not-stated.

## Extension-story detector

Before generating any questions, decide whether this story EXTENDS a feature that already ships. If yes, Phase 0.5 (flow-tracer) is mandatory — see `existing-flow-trace.md`.

### Extension signals

Match any of:

- **Keywords**: *add, allow, let users, custom, advanced, configurable, extend, extra, more <noun>, additional*.
- **References to existing artefacts**: screen names, sheet names, model/enum names, or repo names mentioned in the story.
- **Comparative phrasing**: "similar to <feature>", "like the existing <X>", "just like <Y> but with <Z>".
- **Manual flag**: developer says "this extends X" or sets `extension: true`.

Match at least one → set `extension_story: true`. Match none → set `extension_story: false`. Skip Phase 0.5 only when explicitly false.

### Output of the detector

```json
{
  "extension_story": true,
  "extension_signals": [
    "keyword:custom",
    "keyword:add",
    "mentions:DurationSelectionBottomSheet"
  ],
  "candidate_existing_features": [
    {"name": "duration selection", "evidence_in_story": "let users define custom durations"}
  ]
}
```

The team lead feeds this into `flow-tracer` as the starting set of greps.

## Ambiguity detection

Flag these common patterns:

### Vague language
- "should handle errors" → which errors? how? what does the user see?
- "real-time" → WebSocket? Polling? acceptable latency?
- "similar to [existing feature]" → which parts are similar? what differs?
- "fast" / "performant" → define the threshold.

### Missing states
- First use (empty state)
- Failure
- Loading
- Partial success
- Timeout
- No permission

### Unstated business rules (trading/fintech defaults)
- Market hours only or 24/7?
- All segments (equity, F&O, commodity, currency)?
- Pre-market / market / post-market / all?
- Circuit breaker / trading halt handling?
- All exchanges (NSE, BSE, MCX) or specific?
- KYC-verified required?
- SEBI / exchange-specific regulations?

### For non-trading apps
- Multi-user implications (shared state, permissions)
- Offline behavior
- Data persistence
- Feature flag / rollout strategy

## Option-pill format for clarifying questions

When the clarifier itself emits questions (rather than feeding the questioner specialists), follow the same schema as the rest of Mode 1. No open-text questions.

```
**Q**: How should custom-duration chips be ordered?
- ★ **Recommended — Ascending by seconds** — Matches existing chip clubbing in `DurationSelectionBottomSheet.kt:24`.
- Newest first — Surfaces recent edits; chips reshuffle every save.
- Manual drag — Most flexible; needs new drag handle UI.
- Override: [free-text input]
```

If rendering to the HTML doc, use the question-card template in `html-output.md`. If the caller asked for `--format md`, render this as the literal markdown above.

## Output schema (consumed by team lead)

```json
{
  "core_intent": "Allow users to add custom durations to the chart timeframe picker.",
  "actors": ["app user", "chart engine"],
  "trigger": "User taps 'Add custom' in the duration sheet.",
  "scope_in": [...],
  "scope_ambiguous": [...],
  "extension_story": true,
  "extension_signals": ["keyword:custom", "mentions:DurationSelectionBottomSheet"],
  "candidate_existing_features": [...],
  "missing_acs": [...],
  "assumptions": [
    {"text": "Custom durations are per-user (not shared)", "if_wrong": "Need sync logic + conflict resolution"}
  ],
  "clarifying_questions": [<Question with options>]
}
```

## What the clarifier deliberately does NOT do

- Generate domain / tech / QA questions. Those are the questioner specialists' job.
- Trace the codebase. That's flow-tracer's job.
- Decide priority. That's set by the questioner that generates the question.
- Strip out-of-platform sections. That's `scope-classifier.md`'s job.

Keeping these concerns separate prevents the clarifier from drifting into a god-step that owns everything.
