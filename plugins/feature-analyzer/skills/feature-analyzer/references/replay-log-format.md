# Replay Log Format

Every specialist invocation — prompt, output, retries, `needs_from` exchanges — is persisted so a session can be replayed deterministically for post-mortems and skill regression tests.

## Why

- **Diff drift** — compare two runs of the same story to find what changed.
- **Reproduce bad output** — a developer files an issue with a session-id; maintainer replays the exact prompt that produced the bad output.
- **Skill regression tests** — pin a session's prompts as fixtures; assert the skill still produces the same output after edits.

## Layout

`.feature-analyzer/<feature-slug>/<session-id>/`

```
.feature-analyzer/
  custom-time-frame/
    fa-2026-05-13-custom-time-frame/
      00-preflight.json
      01-scope-filter.json
      02-flow-tracer-0.json           # first invocation
      02-flow-tracer-1.json           # retry after schema-fail (if any)
      03-design-reviewer-0.json
      04-gap-analyzer-0.json
      05-domain-questioner-0.json
      05-tech-questioner-0.json
      05-qa-questioner-0.json
      06-merge.json
      07-critic-0.json
      08-conflict-resolve.json        # only if conflicts found
      09-final.html
      manifest.json
```

The numeric prefix encodes wave / FSM-state order so a directory listing reads as a timeline.

## Per-step JSON

```json
{
  "step": "02-flow-tracer-0",
  "fsm_state_before": "WAVE1",
  "fsm_state_after": "WAVE1",
  "specialist": "flow-tracer",
  "attempt": 0,
  "started_at": "2026-05-13T09:24:11Z",
  "completed_at": "2026-05-13T09:24:43Z",
  "duration_ms": 32118,
  "tokens": {"input": 8420, "output": 3211},
  "prompt": "...",
  "output": { /* specialist envelope, full */ },
  "needs_from_resolved": [
    {"target": "...", "question": "...", "answer_source": "cache|spawn|fallback"}
  ]
}
```

## manifest.json

Top-level summary written by the lead on `DONE`:

```json
{
  "session_id": "fa-2026-05-13-custom-time-frame",
  "feature_slug": "custom-time-frame",
  "lead_prompt_version": "1.2.0",
  "started_at": "2026-05-13T09:24:00Z",
  "completed_at": "2026-05-13T09:31:42Z",
  "fsm_transitions": [
    {"from": "INIT", "to": "PREFLIGHT", "at": "..."},
    {"from": "PREFLIGHT", "to": "SCOPE-FILTER", "at": "..."},
    "..."
  ],
  "totals": {
    "wall_clock_ms": 462000,
    "tokens_in": 84210,
    "tokens_out": 21882,
    "specialists_spawned": 7,
    "retries": 1,
    "needs_from_resolved": 3,
    "needs_from_rejected": 0
  },
  "partial_pillars": [],
  "final_output_path": "docs/feature-analysis/custom-time-frame-analysis.html"
}
```

## Retention

- Default: keep last 30 days, then prune.
- Sessions referenced in an open GitHub issue (filed via `skill-feedback`) are kept indefinitely — pruner respects an `issue: <number>` marker file inside the session dir.
- `--no-log` flag disables persistence entirely (for ephemeral / sensitive runs).

## Privacy

The story text itself may contain sensitive product info. Replay logs are gitignored by default. The skill includes a `.gitignore` entry covering `.feature-analyzer/` so no log is committed accidentally.

## Replay protocol

To replay a session (e.g. for a regression test):

1. Read `manifest.json` to learn the FSM trajectory.
2. For each numbered step, read its JSON and re-issue the `prompt` to the same specialist.
3. Compare new output against the recorded `output`. Differences highlight where the skill's behaviour drifted.

A helper script (`scripts/replay.py`, not bundled in this version but described here for completeness) automates this. For now, replays are manual.

## Skill regression test workflow

1. Pick a "golden" session that produced a known-good output.
2. After a skill edit, replay the session.
3. Assert the new HTML doc matches the recorded one on stable IDs and option sets. Phrasing drift is allowed; ID drift is a regression.

## What never goes in the log

- API keys / credentials extracted from env or memory.
- Raw user PII from the story (if any) — the lead is expected to redact email addresses, phone numbers, and account IDs before persisting. Redaction is a pre-write step, not a post-hoc audit.
- The user's Figma access token (when reading via Figma MCP).

## Per-session size budget

If the cumulative size of a session exceeds 10 MB, the lead emits a warning and stores prompts as references (hashes) instead of inlined text. This handles pathological runs where a story is enormous; prevents disk bloat without losing the prompt → output mapping.
