# Determinism Rules

Same story + same repo state must produce the same question set. Without determinism, we can't regression-test the skill or compare runs across iterations.

## Why determinism matters

- **Regression testing** — assert that a known-good question set still appears after a skill edit.
- **Diff-based debugging** — diff two runs to find where drift was introduced.
- **Trust** — stakeholders see the same questions when they re-run the analysis, not a reshuffled set.

## Rules

### R1 — Stable question IDs

Every question has an ID of the form `<pillar>-<topic-slug>-<hash>`:

- `pillar` ∈ `design | tech | qa | domain`
- `topic-slug` — kebab-case from the question's central noun (e.g. `chip-order`, `wire-format`, `empty-state`)
- `hash` — first 8 hex chars of `sha1(question_text)`

Examples:
- `design-chip-order-7a3f9c12`
- `tech-wire-format-bd442101`
- `qa-empty-state-9911eede`

The hash means rewording a question creates a new ID — so renames are visible in diffs. Topic-slug means similar questions across pillars are distinguishable at a glance.

### R2 — Deterministic ordering

Output ordering is fixed:

1. Priority bucket: `red → yellow → green`
2. Pillar within bucket: `domain → tech → qa → design`
3. ID within pillar: alphabetic

Specialists must NOT impose their own order — the lead reorders before emitting the HTML doc.

### R3 — Templated, not freestyle

Specialists select from / fill templated question slots rather than freestyle generation. Each pillar has a question template catalog (lives in the questioner specialist prompt). The catalog covers:

- Pillar's standard concerns (e.g. tech: wire format, persistence, retries, concurrency, performance).
- Story-conditional slots that activate when story keywords match.

Freestyle questions outside the catalog → require a `freestyle: true` flag + an `evidence` array showing why the catalog didn't cover it. Critic audits these more strictly.

### R4 — Session-id seeding

Every output carries:

```
session_id: "fa-<YYYY-MM-DD>-<feature-slug>"
lead_prompt_version: "<semver>"
```

Both fields embedded in every specialist output and the final HTML. Enables:

- Cross-run diffing with the same seed.
- Cache key for the flow-tracer (see `cache-layer.md`).
- Replay log alignment (see `replay-log-format.md`).

### R5 — No clock / random reads

Specialists must NOT read `Date.now()`, `Math.random()`, or the system clock for any data that ends up in the output. The date in the session-id is the only allowed clock read, and it's a single point fixed at the start of the run.

Forbidden in output: timestamps on individual facts, random sample IDs, "generated at HH:MM:SS". The lead is the sole source of any timestamp metadata.

### R6 — Stable-key serialization

When emitting JSON in the replay log, keys are sorted alphabetically. When emitting the HTML doc, repeat sections are ordered by the rule above. Stable ordering means diff tools highlight real changes instead of key-order noise.

## What this buys us

- A regression test can pin a question ID and assert "this question still appears" across runs.
- An iteration-2 vs iteration-1 diff shows only the IDs that actually changed.
- A bug report can quote a question ID and the maintainer can reproduce the exact prompt that produced it.

## What this costs

- Some loss of phrasing variety — but variety in pre-dev questions is not a feature; clarity is.
- Templating restricts edge-case questions — `freestyle: true` is the escape hatch when the template catalog genuinely doesn't cover a case.

## When determinism breaks (expected)

- Lead prompt version bumps invalidate the cache and may reshuffle the catalog.
- Repo state changes (new code on the SDK boundary) → flow-tracer facts change → some questions get auto-answered → ID set shrinks. This is the desired behaviour; the developer sees the diff in the scope report.
- Story changes → new question set. That's the user editing input; nothing skill-side breaks.
