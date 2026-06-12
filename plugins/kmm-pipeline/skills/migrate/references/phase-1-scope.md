# Phase 1 — Scope & Parity Contract

Goal: an approved `contract.md` — the single definition of "the feature" and of "behavior preserved". Everything downstream (plan, QA, review) verifies against it.

1. **Dispatch kmm-scout** with the feature name and any user-given anchors. Required inventory:
   - Entry points (screens, deep links, notifications) and the file set by layer (view / viewmodel-presenter / usecase / repository / stores / models).
   - Dependency edges in/out: what the feature calls, who calls into it (callers list per CLAUDE.md regression rule).
   - **Androidism inventory** — each item blocks a naive move and needs a seam decision: `android.*`/`androidx.*` imports in logic, `Context`/resources/`R.string`, ObjectBox usage, Retrofit usage, companion objects that self-instantiate collaborators, platform types in public signatures, Gson/serializer usage, time/locale APIs, threading assumptions.
   - Existing tests covering the feature, and which are portable vs JVM-bound.
   - **Stateful endpoints** (submit/email/order/mutation calls) — QA must treat these specially.
   - **Dead-vs-live**: require the scout's ground-truthing evidence on every "unused/dead" claim (its hard rule) — a false dead-code call here forces a mid-flight re-scope.
   - **Storage strategy question**, if the feature persists data: platform-owned stores vs shared — an architecture decision that belongs at G1/plan, never a mid-execute pivot.
   - Whether the feature touches charts/indicators or scalper presets → the matching `AI_GUIDES/*.md` becomes mandatory worker reading.
2. **Draft contract.md** from the scout report:
   - *Feature boundary*: in-scope files (the move list candidate), explicitly out-of-scope neighbors.
   - *Observable behaviors*: numbered, testable statements a user or test can check (rendered values, navigation, error copy keys, persistence effects, network calls made). These become baselines (phase 3 S0) and the QA walkthrough.
   - *iOS deliverable*: which screens/interactions Punch gains, and the parity definition for each (same data, same states, same error handling; visual idiom may be platform-native).
   - *Stateful-action appendix*: per mutating endpoint — how QA compares without double-firing real effects.
   - *Risks*: the androidism risk surface for G1 — seam directions are researched and decided in phases 2-3, never guessed here.
3. **G1 — contract approval.** Present boundary + behaviors + iOS deliverable + stateful-action surface + risks. AskUserQuestion: approve / trim scope / expand. This is the gate that defines what "Android unaffected" and "iOS parity" MEAN — get it explicit.

Journal `phase-done`, set phase 2.

Exit: approved contract.md with numbered observable behaviors.
