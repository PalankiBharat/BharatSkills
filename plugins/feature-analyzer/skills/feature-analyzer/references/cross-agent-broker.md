# Cross-Agent Broker

Specialists cannot call each other. Every cross-specialist need routes through the team lead via a `needs_from` field on the specialist's output.

## Why

Direct specialist-to-specialist calls create:
- Cycles (A→B→A) that deadlock or burn tokens.
- Non-deterministic ordering — merge results depend on which message arrived first.
- A graph instead of a tree, which breaks deterministic replay (G7, G10).

Routing through the lead makes the dependency graph a tree, the merge deterministic, and every cross-specialist exchange visible in the replay log.

## `needs_from` schema

Per specialist output:

```json
{
  ...
  "needs_from": [
    {"target": "flow-tracer",
     "question": "What is the wire format for the duration request?",
     "fallback": "Assume REST query param if unanswered"}
  ]
}
```

Fields:
- `target` — exact specialist name (`flow-tracer | design-reviewer | gap-analyzer | …`). Lead rejects unknown names.
- `question` — concrete, single-sentence question.
- `fallback` — what the specialist will assume if the lead returns no answer (one sentence).

## Budget (G4)

- Max **2** `needs_from` requests per specialist invocation.
- 3rd request → lead refuses; specialist must use its `fallback` for the unanswered need.

## Cycle detection

Lead maintains a request graph keyed by specialist name. Reject any request whose resolution would require re-invoking a specialist that has already produced its output for this wave AND the new question depends on the prior output of the requester.

Detection:
1. Lead pre-builds an allowed-edges set: e.g. `gap-analyzer ← flow-tracer`, `*-questioner ← gap-analyzer`, `*-questioner ← flow-tracer`. These are the allowed flows.
2. Any `needs_from` outside the allowed set → reject with `cycle_reject` and the specialist falls back.
3. The allowed set is static per FSM wave plan; if you add a specialist, update both the wave plan and the allowed set.

## TTL

Every `needs_from` has TTL = 1 hop. The lead resolves the request once and inlines the answer into the requester's next pass — the answer is NOT re-broadcast to the rest of the team. This bounds the work per request and prevents fan-out.

## Resolution flow

When the lead sees `needs_from` on a specialist output:

1. **Cache lookup** — is the answer already in another specialist's output for this session? If yes, inline and skip re-invocation.
2. **Allowed-edge check** — see above. Cycle or unknown → reject, log, fallback applies.
3. **Spawn or re-prompt** — if the target specialist has already returned, send a fresh focused prompt to the target with just the new question. If the target hasn't run yet, queue the answer for inlining when it runs.
4. **Inline into requester** — restart the requester with `inlined_answers[]` appended to its prompt, ID-tagged so the requester can see which `needs_from` was resolved.
5. **Log** — record the request, the resolution path (cache vs spawn), and the answer in the replay log.

## Failure modes and handling

| Mode | Detection | Handling |
|---|---|---|
| Target specialist name unknown | Schema check on `target` | Reject; specialist falls back |
| Question not answerable from target's domain | Target returns `cannot_answer: true` | Lead inlines the `cannot_answer` flag; requester falls back |
| Budget exceeded (3rd request) | Counter per specialist | Reject 3rd request silently to specialist (logged) |
| Cycle | Allowed-edge check | Reject; specialist falls back |
| Resolution timeout (>30s wall) | Lead timer | Mark `needs_from` as `unresolved`; requester falls back; partial flag stays on requester only |

## Example flow

```
tech-questioner returns:
  questions: [...],
  needs_from: [
    {"target": "flow-tracer",
     "question": "Is duration sent in body or query string?",
     "fallback": "Assume query string"}
  ]

Lead:
  - Edge check: tech-questioner ← flow-tracer  ✓ allowed
  - Cache lookup in flow-tracer.facts → finds fact `flow-duration-wire-format` (high confidence)
  - Inlines answer into tech-questioner's prompt as `inlined_answers: [{q: "...", a: "Query string, key=duration, value=type"}]`
  - Re-runs tech-questioner; new output has refined questions, no needs_from
  - Logs the exchange to replay log
```

## What never goes through the broker

- Lead → specialist communication (that's just spawning).
- Specialist → user (specialists never talk to user; only lead does, via gates).
- Specialist → critic (critic reads merged output, not individual specialist channels).

## Why the budget is 2

Empirically, 3+ `needs_from` per specialist signals the specialist's prompt is under-specified (it should have got the info upfront). Forcing fallback at 3 surfaces the prompt bug instead of papering over it with extra hops.
