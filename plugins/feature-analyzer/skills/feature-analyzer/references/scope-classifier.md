# Platform Scope Classifier

Stories arrive as cross-platform specs (web + desktop + iOS + backend + Android in one doc). The skill targets Android. Without filtering, ~30% of the original story is non-Android noise that gets surfaced to Android-targeted teams as questions.

## Classifier output

For each section in the story (split by heading / bullet group / AC group), assign exactly one label:

| Label | Meaning | Default action |
|---|---|---|
| `android` | Android-specific behavior | **Include** |
| `shared` | Cross-platform business rules / data model / regulatory | **Include** |
| `ios` | iOS-only | Strip |
| `web` | Browser-only | Strip |
| `desktop` | Desktop client (multi-monitor, hotkeys, sync groups) | Strip |
| `backend` | Server-side only | **Conditional** — see below |

## Keyword rubric

Use the strongest signal in the section. Ambiguous → `shared`.

- `android` — *Compose, Activity, Fragment, ViewModel, ANR, Play Store, APK, AAB, Material 3, Jetpack*
- `ios` — *SwiftUI, UIKit, App Store, TestFlight, ViewController, .swift, .xcodeproj*
- `web` — *DOM, browser, Chrome, Firefox, JavaScript, CSS, React (web context), Vite, Webpack*
- `desktop` — *Electron, multi-monitor, multi-window, hotkey, system tray, sync group, snap-to-grid, second screen*
- `backend` — *endpoint, query param, response payload, DB column, microservice, Kafka, Redis, Lambda*
- `shared` — *business rule, regulatory, market hours, KYC, pricing, segment (equity/F&O/commodity), feature flag*

When the section mentions multiple platforms, pick the one with the most concrete artifact mentioned. If still ambiguous, label `shared` and let the rest of the pipeline decide.

## Backend-conditional rule

Backend sections are dropped UNLESS the kept (Android + shared) sections imply a new server-side ask. Trigger keywords inside Android/shared sections:

- "new endpoint" / "new API" / "new route"
- "new field" / "new column"
- "new param" / "new query string"
- "new event" / "new webhook" / "new topic"
- "backend must" / "server needs to"

Found → keep backend in scope, but tag it as `backend-android-driven`. Not found → strip backend; log in scope report.

## Override

Callers can force-include other platforms via `--include-platform desktop,ios`. Useful for cross-platform feature kickoffs. Default is android-only.

## Scope-report block

After classification, emit this block (rendered at top of the HTML doc and prepended to the answer copy-all):

```
Scope filter applied
────────────────────
  ✓ Included sections:
      • Android (12 ACs)
      • Shared business rules (4 ACs)
  ✗ Stripped sections (out of platform):
      • Desktop multi-monitor sync (8 ACs) — label: desktop
      • iOS share sheet wording (3 ACs) — label: ios
  ⚠ Conditional sections:
      • Backend (INCLUDED — Android section references new query param `custom=true`)
```

Developer reading this block sees exactly what the skill filtered. If they disagree, they re-run with `--include-platform` or edit the section labels.

## FSM placement

`SCOPE-FILTER` state runs between `PREFLIGHT` and `WAVE1`:

```
PREFLIGHT → SCOPE-FILTER → ABORT (no android/shared sections found)
                         → WAVE1 (proceed with filtered story)
```

The filtered story (Android + shared + optional backend) is the only input the questioner specialists see. They cannot reach the stripped sections — guarantees no off-platform questions leak.

## Failure modes

| Mode | Detection | Action |
|---|---|---|
| All sections classified non-Android | After classifier | Abort with "Story has no Android scope. Pass `--include-platform <X>` to override." |
| Section spans multiple platforms in one sentence | Detected by keyword cluster | Re-split section by sentence; reclassify per sentence |
| Backend trigger keyword in a stripped section | Keyword check on every section | Promote backend to included; log promotion reason |

## Backend-internals filter (F4 from #173)

When a story is Android-scoped and the scope-classifier promotes a backend section to `backend-android-driven`, that label means "Android needs new server-side support" — NOT "ask any backend question you can think of". The filter passes only Android-observable backend concerns to the questioner. Everything else stays out.

Allowed backend slots (Android-observable):

- **Error code mapping** — what codes does the server return and how does Android render each?
- **Response payload shape** — what fields does Android parse + display?
- **Polling cadence** — what interval does Android poll on (if polling is the chosen transport)?
- **WebSocket event schema** — what events does Android subscribe to + how does it react?
- **Idempotency / retry rules** — what Android-side guard does the contract require?
- **Auth + session shape** — what header / token does Android send?

Suppressed backend slots (backend-internals only):

- Transactional choice (bulk vs fan-out, single transaction vs saga).
- Storage layer (Postgres vs Redis flag).
- Internal queue / broker choice.
- Race-window / isolation-level questions.
- Cron job scheduling internals.
- Microservice boundary choices.

The classifier emits `session.scope_report.backend_internals_filter: "android"` so the questioner knows which slot list to use. The critic enforces the filter at audit time (`backend_internals_leak` finding — see `critic-rubric.md`).

If the project is Backend-scoped (not Android), the filter is OFF and the questioner generates full backend-internals questions.

## Why this matters

- Cuts question count by ~30% on multi-platform stories.
- Prevents wasted stakeholder time on questions outside their platform.
- Catches backend dependencies without dragging in unrelated backend scope.
- Removes the recurring developer interrupt of "ignore desktop / ignore iOS".
