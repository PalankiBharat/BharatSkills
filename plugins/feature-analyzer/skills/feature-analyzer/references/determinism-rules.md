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

Specialists select from / fill templated question slots rather than freestyle generation. The `questioner` specialist owns one consolidated catalog organised by pillar + role.

Freestyle questions outside the catalog → require a `freestyle: true` flag + an `evidence` array showing why the catalog didn't cover it. Critic audits these more strictly.

#### Template catalog (v2.1)

**Domain (PM / Compliance / business rules):**
- `regulatory-applicability` — which regulators / exchange rules apply
- `market-hours-rule` — pre-market / market / post-market behaviour
- `segment-applicability` — equity / F&O / commodity / currency
- `entitlement-gate` — KYC / margin / segment activation needed
- `rollout-strategy` — feature flag / cohort / percentage
- `business-rule-edge` — story-conditional, e.g. "what happens if X but not Y"
- `analytics-events` — which events fire, what properties

**Tech / Backend (when Android is consumer, not backend itself):**
- `api-contract` — **composite slot** (F3 from #173): endpoints + HTTP methods + request payload + response payload + error code map. ONE question, not three.
- `error-code-mapping` — Android-observable codes → user copy
- `polling-cadence` — Android-side polling interval + cancellation
- `ws-event-schema` — Android-observable event types + payloads
- `idempotency-rule` — Android-side retry guard
- `auth-shape` — header / token format

**Android-shaped stakeholder slots (F5 revised from #173):**

There is **no Android-implementation catalog**. Implementation choices (module placement, Hilt scoping, Compose state hoisting, ViewModel↔UseCase wiring, `@Preview` shape, mapper location, factory selection, navigation route mechanics) are decided by the developer at code time and rejected by the critic — see `critic-rubric.md` → "Doer decides at code time".

Android-tagged questions may only come from genuinely stakeholder-shaped slots, drawn from existing pillars:

- `rollout-strategy` (Domain) — LD-flag scope, cohort, percentage
- `analytics-events` (Domain) — properties the Android client must emit
- `api-contract` / `error-code-mapping` / `polling-cadence` (Tech-Backend) — when Android owns the negotiation
- `deep-link-support` — whether the feature is reachable via a deep link, and the URI shape (cross-team contract)
- `push-notification-surface` — whether a push channel exists and what payload Android consumes
- `test-environment-toggle` — whether a test/staging environment switch needs to ship in the build
- `rollback-procedure` — kill-switch / remote-config rollback ownership

Tag the question `role: Android` when the Android team is the answer-owner. The questioner does NOT have a mandatory Android-coverage count — Android questions appear only when the slot above genuinely applies to the story.

**QA:**
- `user-test-cases` — happy path + permission denied + empty state + timeout
- `automation-feasibility` — Espresso / Compose-test reachable
- `accessibility-audit` — TalkBack labels, focus order, dynamic font
- `regression-target` — what existing flows might break

**Design (handled by design-reviewer, listed here for completeness):**
- `screen-state-matrix` — every state per screen (default / loading / empty / error / partial)
- `interaction-pattern` — bottom-sheet vs modal vs full-screen
- `chip-ordering` / `list-ordering`
- `empty-state-copy`
- `dynamic-font-handling`

#### Composite slot guidance — `api-contract`

When the spec defines API-shaped fields (request body, response fields, error codes) but no URLs or HTTP methods, the questioner emits ONE composite question:

> "What is the [feature] backend API contract — endpoints, HTTP methods, request/response payloads, and error-code map?"

Options must cover realistic backend shapes:
- REST (separate endpoints per action)
- Single endpoint + action verb in payload
- WebSocket-only (push-driven)
- GraphQL mutation + subscription

Letting the backend team answer this once cuts 3-4 split questions down to 1 and prevents them from being asked in inconsistent forms across the doc.

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
