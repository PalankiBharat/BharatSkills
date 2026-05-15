# Cache Layer

Flow-tracer is the most expensive specialist — it walks UI → ViewModel → Repo → SDK across multiple repos. On sibling-feature analyses where the story keyword has been traced before, re-running costs ~40% of the wall-clock + tokens for no new information.

## What gets cached

Only `flow-tracer` output. Other specialists run every time because they depend on the story text, which is variable.

## Cache key

`flow-tracer-cache/<repo-sha>-<feature-keyword-slug>-<lead-prompt-version>.json`

Components:
- `repo-sha` — `git rev-parse HEAD` of the app repo at run start. SDK repos' SHAs are recorded inside the cached value, not in the key.
- `feature-keyword-slug` — the dominant noun(s) extracted from the story title. For ambiguous titles, the lead asks the user for a single keyword OR derives it deterministically (first three tokens after stopword removal).
- `lead-prompt-version` — semver of the lead prompt. Bump → cache miss.

## Storage

`.feature-analyzer/cache/<key>.json` — gitignored by default. Layout:

```json
{
  "key": "abc1234-custom-time-frame-1.2.0",
  "created_at": "2026-05-13T09:24:01Z",
  "lead_prompt_version": "1.2.0",
  "app_repo_sha": "abc1234",
  "sdk_shas": {
    "marketpulse-android-sdk": "def5678",
    "finance-android-sdk": "ghi9012",
    "sesame-android-sdk": null
  },
  "flow_tracer_output": { /* full flow-tracer envelope */ }
}
```

## Lookup flow

1. Lead computes the key after Pre-flight.
2. Reads `.feature-analyzer/cache/<key>.json`. Hit → validate (next step). Miss → spawn flow-tracer normally.
3. **Validation on hit**:
   - For each SDK in `sdk_shas`, compare against current `git rev-parse HEAD` in the SDK checkout. Any mismatch → cache **stale**, treat as miss.
   - If the app `repo-sha` differs from the current (rare — usually checked at key time), miss.
4. Hit + valid → inline `flow_tracer_output` into wave 1 as if flow-tracer just ran. Skip the spawn.

## Invalidation

Cache entry becomes invalid in any of these cases:

- Lead prompt version bumped → key mismatch.
- Any sibling SDK's `git rev-parse HEAD` no longer matches the recorded SHA.
- App repo SHA no longer matches (only on stale workspaces where someone moves HEAD between cache write and read).
- Explicit `--no-cache` flag.

Stale entries are NOT auto-deleted; they're just unused. A periodic prune (e.g. `.feature-analyzer/cache/*.json` older than 30 days) keeps the dir small.

## Why include SDK SHAs in the value, not the key

If a sibling SDK gets updated and the flow-tracer fact set should change, we want the cache to MISS — but we don't want to demand the user knows every SDK SHA upfront. By storing them in the value, the lead validates them lazily on lookup and treats any mismatch as a miss. Keeps the key short while still preventing stale reads.

## What never gets cached

- Question outputs from `*-questioner` specialists. They depend on story text + gap delta + flow-tracer (the last is already cached upstream).
- Critic findings. They're cheap relative to flow-tracer and depend on the merged output.
- Design-reviewer output. Figma can change between runs without an SDK SHA bump.

## Cache + determinism

`determinism-rules.md` R4 ties the session-id to the lead prompt version. A cache hit only proves "this exact flow-tracer output is current"; it doesn't make the run deterministic on its own — that's the rest of the determinism rules. They compose: cache for speed, determinism rules for reproducibility.

## When the cache hurts

- First-run on a repo: always miss. Adds zero overhead but no benefit. (No-op.)
- High SDK churn: SHA changes invalidate every entry. If your SDKs change daily, the cache buys ~one hit per cache write. Disable with `--no-cache` if so.

## Adding new cached specialists

If a future specialist becomes a cache candidate (e.g. design-reviewer if Figma changes are rare), follow the same key pattern: include the upstream-stability-marker (Figma file revision) inside the value, validate lazily.
