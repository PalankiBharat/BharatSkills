# Existing Flow Trace (Phase 0.5)

Before generating ANY question, walk the existing code end-to-end if the story extends a feature that already ships. The single biggest cause of wasted stakeholder time is asking questions the code already answers.

## When to trigger

Trigger if the story matches **any** extension-pattern signal (see `story-clarifier.md` extension detector):

- Keywords: *add, allow, let users, custom, advanced, configurable, extend, more <noun>*
- Story mentions an existing screen, sheet, model, enum, or repo by name
- Story says "similar to <feature>" / "like the existing <X>"
- Developer flags it manually (`extension: true` or instruction "this extends X")

If none match, skip Phase 0.5 entirely.

## Walk order (UI → SDK)

For each extension story, traverse this chain and cite `file:line` for every fact:

1. **UI entry point** — grep story keywords against composables / fragments / activities.
2. **ViewModel** — what state holders own the screen; what events flow in/out.
3. **UseCase / Interactor** (if present) — domain logic boundary.
4. **Repository** — local persistence + remote dispatch.
5. **SDK boundary** — which SDK call(s) leave the app. Identify wire format (REST / gRPC / WS / IPC).
6. **Sibling SDK source** — locate the actual source repo, not the JAR / decompiled / example. See "Sibling SDK locator".

## Sibling SDK locator

Known sibling SDKs (trading/fintech default):

| SDK | Typical checkout | Source-of-truth files |
|---|---|---|
| `marketpulse-android-sdk` | `~/AndroidStudioProjects/marketpulse-android-sdk` | `ChartDurationModel.kt`, `HistoryRemoteStore.kt`, `IHistoryRepository.kt` |
| `finance-android-sdk` | `~/AndroidStudioProjects/finance-android-sdk` | chart engine, indicator-period mapping |
| `sesame-android-sdk` | `~/AndroidStudioProjects/sesame-android-sdk` | auth, session, entitlements |

Locator order:
1. Sibling worktree adjacent to the app under `~/AndroidStudioProjects/<sdk-name>` or `~/workspace/<sdk-name>`.
2. Gradle dependency declaration — read `implementation` lines in app's `build.gradle.kts` to confirm the version, then resolve the checkout.
3. If neither found, **stop** and surface a Pre-flight failure: "SDK `<name>` source not found. Either checkout the repo at `<path>` or pass `--sdk-skip <name>`." Do NOT read JARs or decompiled bytecode — they hallucinate types.
4. Forbidden paths: any file under `examples/`, `demo/`, `sample/`, `test-fixtures/`, or `*-decoded/*`. Reading these is a P0 bug.

## Output schema

The trace emits a `flow_doc` block consumed by the HTML doc (renders under "Existing flow audit") AND by `gap-analyzer` (computes delta against the story).

```json
{
  "schema_version": "1.0",
  "session_id": "fa-<date>-<slug>",
  "extension_signals": ["keyword:custom", "mentions:DurationSelectionBottomSheet"],
  "sdks_probed": [
    {"name": "marketpulse-android-sdk", "path": "...", "status": "found"},
    {"name": "finance-android-sdk", "path": "...", "status": "found"},
    {"name": "sesame-android-sdk", "path": null, "status": "not_applicable",
     "reason": "auth not in scope"}
  ],
  "chain": [
    {"layer": "ui", "name": "DurationSelectionBottomSheet",
     "file": "app/.../DurationSelectionBottomSheet.kt", "line": 24, "confidence": "high"},
    {"layer": "viewmodel", "name": "ChartViewModel",
     "file": "app/.../ChartViewModel.kt", "line": 88, "confidence": "high"},
    {"layer": "repo", "name": "PlottedFXRemoteService",
     "file": "app/.../PlottedFXRemoteService.kt", "line": 42, "confidence": "high"},
    {"layer": "sdk", "name": "HistoryRemoteStore",
     "file": "marketpulse-android-sdk/.../HistoryRemoteStore.kt", "line": 45,
     "confidence": "high"}
  ],
  "facts": [
    {"id": "flow-duration-wire-format",
     "claim": "Duration is sent as query param `duration=<type>` (string)",
     "evidence": [{"file": "marketpulse-android-sdk/.../HistoryRemoteStore.kt", "line": 45}],
     "confidence": "high"},
    {"id": "flow-existing-duration-set",
     "claim": "20 production durations live in ChartDurationModel.kt (not the 14-entry demo enum)",
     "evidence": [{"file": "marketpulse-android-sdk/.../ChartDurationModel.kt", "line": 12}],
     "confidence": "high"}
  ],
  "needs_from": [],
  "partial": false
}
```

## Hard rules

- **Every claim has a `file:line` cite**. No cite → critic discards the claim.
- **Confidence stamp** on every fact (`high` = cited; `medium` = inferred; `low` = speculation).
- **`low` facts never auto-answer questions** — they go into the "Unsure" bucket so the developer can confirm.
- **Source files only** — never read JARs, decompiled output, examples, or demos. If the sibling SDK source isn't checked out, fail Pre-flight rather than guess.

## Auto-answer rule

After the trace completes, the team lead diffs the trace against the question candidates produced by the questioner specialists. Any question whose answer is in `facts[]` with `confidence: high` is **dropped from the output** and logged in the scope report as "auto-answered by flow-tracer".

Example dropped questions (Custom Time Frame):
- "What duration values currently exist?" → answered by `flow-existing-duration-set`
- "How is duration passed to the network?" → answered by `flow-duration-wire-format`
- "Does WebSocket re-subscribe on duration change?" → answered by a WS subscription cite

## What to do when the trace is incomplete

Set `partial: true`. Surface the missing layer in the HTML scope report so the developer knows which questions were generated against incomplete information. Do NOT silently fall back to question-only output.
