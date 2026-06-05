# KMM Migration — Runtime-Golden Parity Loop (agent-device + `/loop`)

**Date:** 2026-06-05
**Status:** Design approved — ready for implementation planning
**Scope:** `plugins/kmm-migration-workflow/skills/kmm-migration/` only (the migration skill). No other skill is modified.
**Affected phases:** Phase 0/A (journey catalog), Phase B (runtime golden), Phase F (heatmap reframe + smoke/capture upgrades), Phase I (autonomous parity-fix loop).

---

## 1. Problem

The migration skill's final phase (Phase I — Parity-QA + Bug-fixing) currently **does not run QA itself**. It hands off to the separate, heavy, user-triggered `kmm-qa-autopilot` skill (two ProductionRelease APKs, two visible emulators, a manual prod login on each, Maestro flows, live-field masking, A/B diff → per-journey verdict) and then stays open to fix any bug *through the workflow*. Three structural weaknesses follow from this:

1. **QA is out-of-skill and non-autonomous.** The "fix until the checklist passes" cycle is manual: a human triggers autopilot, reads verdicts, fixes, re-triggers. There is no closed loop.
2. **The QA checklist (heatmap) is too technical.** It is derived from the git diff ("this symbol changed → watch this surface"). It reads like a code map, not a test plan a QA or a real user would recognize.
3. **The equivalence contract is verified late and noisily.** Behavioral parity is a *post-hoc live A/B* on a real prod account. For a **trading app** this is structurally weak: master and migrated hit the server milliseconds apart, the market moves, and computed values (P&L, totals, order values) differ **because the market moved, not because the migration broke**. Live A/B literally cannot prove a migrated financial calculation is correct. Separately, R8/ProductionRelease **serialization parity is explicitly deferred** to Phase I today because nothing earlier exercises real payloads under R8.

This redesign closes all three by turning the equivalence contract into a **recorded runtime golden** — captured from real user journeys early (Phase B), and **verified deterministically** in an autonomous `/loop` (Phase I) driven by **agent-device**.

## 2. Goals / Non-goals

**Goals**
- Phase I becomes a closed, autonomous `/loop`: run A/B parity QA → fix parity-restoring bugs through the workflow → re-run → converge on an all-green checklist.
- The QA checklist is authored from a **user/QA lens** (a journey catalog), not the diff.
- The equivalence contract is a **runtime behavioral golden** (real network wires + computed UI outputs), captured on master in Phase B, frozen, and replayed against the migrated build.
- **Deterministic replay is the primary verification path** (correct for a trading app); live A/B with narrow masking is the explicit exception for un-recordable streaming surfaces.
- agent-device replaces fragile/vague UI-driving across the skill (Phase F smoke, the QA probes) and unlocks an **iOS runtime forward-check**.

**Non-goals**
- Modifying `kmm-qa-autopilot` or any other skill. (It may remain installed and separately invocable; the migration skill no longer depends on it.)
- Replacing the unit-level baseline discipline (Phase B test-discipline). The runtime golden is **additive** to unit baselines, not a replacement.
- Shipping the iOS app feature itself. The iOS forward-check is conditional on an iOS UI path that already consumes the migrated code this session; otherwise it is a named gap.

## 3. Design decisions (resolved with the user)

| # | Decision | Chosen | Rationale |
|---|---|---|---|
| D1 | QA engine inside the loop | **agent-device, in-skill** | Self-contained in the migration skill; token-efficient snapshots + `assert` + `.ad` replay are ideal for an autonomous loop; unlocks iOS. Phase I stops delegating to autopilot. |
| D2 | What QA compares against | **A/B parity (master vs migrated)** | Behavioral equivalence is the contract; A/B catches silent value-drift without a pre-known "right" answer. Masking is done **semantically by the agent** on token-efficient snapshots, not a ported python comparator. |
| D3 | iOS scope | **Android A/B core + conditional iOS forward-check** | Uses agent-device's cross-platform strength without over-scoping sessions where iOS can't consume the migrated code yet. iOS A/B-against-master is impossible (no pre-migration iOS behavior), so iOS is a *forward* check only. |
| D4 | Fix autonomy | **Autonomous within the existing gates** | The loop reuses the migration skill's existing human gates (behavior-shift exception + sign-off, dependency change, `migrate→hold` plan-flip, eviction re-login, mutating/real-money journey) and is autonomous everywhere else. It invents no new autonomy. |
| D5 | Network-wire golden mechanism | **Hybrid: replay where we can, live where we must** | Record real wires on master; replay frozen responses to the migrated build for deterministic journeys (exact diff, no masking, serialization-under-R8 verified, no login/real-money risk); fall back to live A/B + masking only for genuinely-live surfaces. |
| D6 | Trading-app emphasis | **Replay is the *primary* path; never mask a computed value** | Live values are the point of a trading app and cannot be trusted in a live A/B. Replay freezes market data so computed financial outputs compare to the digit. Masking is reserved for externally-fed streaming feeds not derived from migrated logic. |

## 4. Architecture — the spine

> **Capture real user-journey behavior as a runtime golden early; verify the migrated build reproduces it in an autonomous loop.**

```
Phase 0/A ──► user-journey catalog (user/QA lens; diff demoted to coverage cross-check)
                   │  (one catalog, reused downstream)
                   ▼
Phase B ──► drive MASTER with agent-device across every journey
            record: real network wires + computed UI outputs  ──► FROZEN runtime golden
                   │  (+ existing unit baselines, unchanged)
                   ▼
Phase F ──► heatmap = the journey catalog, each row carrying its golden reference (Result = TBD)
            smoke test upgraded to agent-device; network/crash capture wired in
                   │
                   ▼
Phase I ──► /loop:  replay golden → migrated build  (deterministic, exact diff)
                    live A/B + narrow masking  (only un-recordable streaming surfaces)
                    diverge → root-cause → fix parity-restoring bug → rebuild → re-run
                    converge → all-green checklist → retro → close
```

## 5. Per-phase design

### 5.1 Phase 0/A — User-journey catalog (the new spine)

A new artifact, `journeys.md`, authored from the **user/QA lens**, not the diff:

- **User journeys**: what real users actually do with the feature (e.g., "open holdings → change date range → expand a position → view P&L").
- **Expectations**: what the user expects to see at each step (the observable outcome), in plain language.
- **Negative / edge paths a QA would try**: empty states, invalid input, offline/airplane mode, back-navigation, re-entry, mid-flow interruption. These are **first-class journeys**, not skips (OTP-lockout-style account-damaging paths excepted — declined gap unless a test account is confirmed).
- **Read-only vs state-mutating** classification per journey (carried forward to the safety gate).

The existing **diff-derived technical surfaces** (today's heatmap source: changed symbols → screens) **demote to a coverage cross-check**: after the catalog is authored, a subagent verifies every changed symbol from the Phase A plan is exercised by at least one journey. A changed symbol with no covering journey is a **catalog gap to fill**, surfaced to the user — this keeps "no exclusions" honest while letting the *primary* framing be user-centric.

Authoring placement: Phase 0 discovers scope via the user's described navigation flow already; the catalog extends that. Phase A enriches each journey with the per-file risk surfaces it touches. The catalog is **frozen reference** for B/F/I — one catalog, authored once.

Subagent-mediated per the skill's rules: a Sonnet subagent drafts the catalog from the Phase 0 flow + Phase A plan; the orchestrator synthesizes. Because the catalog **defines the entire downstream test surface**, the user confirms it before it freezes — a new **coverage-approval gate** (distinct from the `project.md` diff-confirm protocol, which stays scoped to `project.md`; `journeys.md` itself is a session-local, gitignored working file). The gate is approval of *what gets tested*, not a file-write ceremony.

### 5.2 Phase B — Runtime golden capture

**Additive to the existing unit baselines.** After the unit baselines are written and before freeze, Phase B drives the **master/current** build through every journey in the catalog with agent-device and records a **runtime behavioral golden**:

- **Network wires**: real request/response payloads per journey checkpoint (`agent-device network` capture, paired with the app's HTTP layer — see §6 replay harness).
- **Computed UI outputs**: token-efficient accessibility snapshots at each checkpoint (the on-screen computed values — P&L, totals, derived prices, list contents — that the migrated logic must reproduce).
- **Crash/log evidence**: per-journey logs for context.

Stored under the session's local working state (`.kmm/migrations/.../golden/<journey>/<checkpoint>/`), **gitignored** like the rest of `migrations/`.

**Freeze discipline.** The golden is **frozen alongside the unit baselines** (Phase C). It is part of the equivalence contract: editing a frozen golden requires the same migration-exception gate as editing a frozen unit baseline. (Mechanism: the freeze covers the golden directory; the orchestrator confirms an exception file before any subagent edits a frozen golden — symmetric to the frozen-baseline rule, since hooks don't fire on subagent calls.)

**PII is a hard gate (trading app).** Recorded wires contain account balances, holdings, order data, and possibly PII (phone, IDs). Before the golden is written to disk: a **no-PII / secret scan** runs (phone/PIN/OTP/auth-token/account-number patterns); on any hit the capture is scrubbed or the journey is flagged. The golden is **never committed** (gitignored) and never embedded in the PR body. This mirrors autopilot's `.kmm-qa` no-PII scan, hardened for financial data.

**Determinism capture.** For replay to reproduce computed values to the digit, the recording must capture the **exact** payloads (including any server timestamps/sequence the computed output depends on). Time-derived or session-derived inputs that the migrated code consumes are captured as part of the frozen input set.

### 5.3 Phase F — Heatmap reframe + capture upgrades

- **Heatmap = the journey catalog.** F.5 no longer drafts a diff-derived heatmap from scratch; it **renders the journey catalog** as the tickable QA checklist, each row carrying a pointer to its frozen golden reference. Result column starts `TBD` and is filled in Phase I. The PR body (Phase G) embeds this user-readable checklist.
- **Smoke test upgraded to agent-device** (F.5). The current "structured-tap CLI / screenshot-and-report" smoke is replaced by agent-device: `open` → `snapshot` → `assert` app reached a known state, crash-free, via `agent-device logs`/crash capture as the gate evidence. Removes the fragile/ambiguous device-driving the skill warns about.
- **Network-capture wired into the existing HTTP parity checks** (F.3). The skill already has HTTP-client timeout-parity and server-registration-parity checks "via project's HTTP-inspection capability." That capability becomes **`agent-device network`** — a concrete, uniform mechanism for observing real `tookMs`, timeout behavior, and host registration per service.
- **Crash-capture as the smoke gate** (F.5). `agent-device` crash/log capture is the crash-free-launch evidence.

### 5.4 Phase I — The autonomous parity-fix loop

**Setup (once, at loop entry — not per iteration):**
1. Reuse the PR URL from `pr.md`.
2. Build **master baseline** + **migrated head** as ProductionRelease (R8) APKs. **Master is built once and reused**; only the migrated side rebuilds after a fix.
3. Open agent-device session(s); for live-A/B journeys only, perform the **one manual prod login** (the sole manual step; session persists across iterations via force-stop + relaunch, never `clearState`). **Replay journeys need no login** (frozen wires).
4. Seed probes: each catalog journey → an agent-device `.ad` replay script that drives the interaction invoking the migrated logic (not just opening the screen). `.ad` scripts + the frozen golden are the durable, reusable QA artifacts.

**Loop body (one iteration):**
1. For each pending journey, pick the verification mode:
   - **Replay (default)**: feed the frozen recorded responses to the migrated build; replay the `.ad` probe; capture the migrated computed outputs; **diff exactly against the golden's computed outputs** (no masking).
   - **Live A/B (exception)**: only for un-recordable streaming surfaces — run master + migrated live, diff snapshots with **narrow semantic masking** (mask only externally-fed live feeds, **never** a computed value).
2. Classify each row → 🟢 / 🔴 / ⚪-indeterminate (anchor absent on both = **not green**; guards the vacuous-pass trap) / ⚠️-eviction (live A/B only).
3. For each 🔴: reproduce ≥2×; root-cause via a per-issue subagent (Sonnet small / Opus complex), given full context (symptom + both values + `git diff` + relevant `.kmm/exceptions/*` claims + captured evidence); classify as **parity-restoring bug** (common) / **intentional change** (exception path) / **known false-positive class** (eviction, scroll-offset, chart-jitter, stateful server copy).
4. **Fix parity-restoring bugs autonomously through the workflow**: failing-test-first (the divergence becomes a red test) → surgical subagent edit → green → commit → retro entry. Re-validate at Phase F.6 mechanical scope (surgical → F.3 + F.5 smoke; non-surgical → full F.1). Rebuild the migrated APK; re-run only the affected probe.
5. **Pause at a gate** when a fix shifts observable behavior (migration-exception + **user sign-off**), needs a dependency change, implies a `migrate→hold` plan-flip, hits eviction (re-login), or touches a mutating/real-money journey (confirmation).
6. Update the heatmap Result cells + the `qa.md` bug-fixing log (repro, failing test, fix, exception ref, re-validation scope, commit SHA).
7. *(Conditional iOS)* If an iOS UI path consumes the migrated code this session, run the **iOS forward-check** via agent-device on the simulator: drive the same journey, assert crash-free + that the computed output matches the frozen golden (the same commonMain logic, consumed from iOS, must produce the same numbers). No iOS path → named gap.

**Convergence / exit — the `/loop` completion promise** (only emitted when genuinely true; false promises to escape the loop are prohibited):
> Every catalog journey is 🟢 with a real anchor reached, **zero** open 🔴, **zero** ⚪-indeterminate, the iOS forward-check passed-or-is-a-named-gap, and any remaining finding is an explicitly **user-deferred** recorded follow-up.

Plus a **max-iterations safety cap** that **pauses and surfaces** (never false-passes) if it cannot converge. Anti-false-exit guards carried from autopilot: empty baseline↔PR diff = hard stop; anchor-absent-on-both = ⚪, not 🟢.

**Then:** Phase I retro (blocking) + session close-out, exactly as today.

## 6. The replay harness (research-gated)

**Honesty flag:** agent-device *captures* network traffic (documented). It is **not verified** to *serve/replay* recorded responses as a mock. The deterministic-replay path therefore pairs agent-device's capture with a **replay mechanism at the app's HTTP layer**, whose feasibility for this app is a **planning-stage research item**, not an assumption.

Candidate mechanisms (to be evaluated in writing-plans / a research subagent):
- A local **record/replay proxy** seeded from the captured wires; the app is pointed at it via the existing host config (`project.md` → `networking.shared_client_config` host constants). Cleanest if the app honors a configurable base URL per the BuildKonfig flavor fields the skill already tracks.
- An **OkHttp/Ktor interceptor** or test-double in a dedicated build variant that serves cassettes.
- Reuse of any existing app-side mocking hook (discovered via codebase scan).

**Fallback if replay proves infeasible for a journey:** that journey falls back to live A/B with narrow masking (the hybrid's exception path) and is flagged in the report — the design degrades gracefully, it does not block.

Research items to resolve in planning:
- R1: Can agent-device serve recorded responses, or do we need a separate proxy? (Read `agent-device help workflow` + network docs; spike.)
- R2: Does the app support a configurable base URL / mock endpoint cleanly (BuildKonfig host fields)? Which variant?
- R3: How are time/session-derived inputs that affect computed outputs frozen for replay?
- R4: iOS forward-check — how to detect "an iOS UI path consumes the migrated code this session" deterministically; iOS replay vs forward-only.

## 7. agent-device integration surface

Commands the design relies on (verified from the README): `apps`, `open`, `snapshot -i`, `tap`/`fill`/`scroll`, `assert`, `wait`, `screenshot`, `logs`, `network`, crash capture, `record`/`replay` (`.ad` scripts), `close`. Platforms: Android emulator/device + iOS simulator (the cross-platform axis). Node 22+, Xcode (iOS), Android SDK/ADB.

Per the skill's rules, all agent-device runs are **subagent-mediated** (device-driving is a multi-step exploration/execution, not orchestrator work), and main context stays a terse dashboard — verbose snapshots/logs live in subagents and files.

## 8. Broader upgrades (all included)

| Upgrade | Where | Effect |
|---|---|---|
| agent-device replaces the smoke driver | Phase F.5 | Concrete, reliable launch/crash smoke via `snapshot`+`assert`; ends fragile structured-tap/coordinate driving. |
| `agent-device network` as the HTTP-inspection capability | Phase F.3 | Uniform mechanism for the existing timeout-parity + server-registration-parity checks (real `tookMs`, host reachability). |
| crash/log capture as the smoke gate | Phase F.5 | Crash-free-launch evidence is `agent-device` crash/log output. |
| iOS runtime forward-check | Phase I.7 | First time the migrated commonMain is *behavior*-checked on iOS (today: build-only). Conditional on a consuming iOS UI path. |
| `.ad` scripts + frozen golden as reusable assets | Phase B/I | Record-once, replay-many across iterations and future sessions (UI rarely changes in a migration). |

## 9. Impact on skill files

New/changed (final list confirmed in writing-plans):
- `SKILL.md` — directory layout (add `golden/`, `journeys.md`, `journeys`/golden freeze + PII gate, agent-device tooling-discipline note); phase overview table (Phase 0/A catalog, Phase I loop); Realistic-expectations paragraph (Phase I is now an in-skill loop, not a hand-off).
- `references/phases/phase-0-discovery.md` + `phase-a-diagnostic.md` — author `journeys.md` (user/QA lens) + diff coverage cross-check.
- `references/phases/phase-b-baseline.md` — runtime golden capture (agent-device on master), PII gate, golden freeze.
- `references/phases/phase-c-freeze.md` — extend freeze to the golden.
- `references/phases/phase-f-validation.md` — heatmap = catalog; agent-device smoke; `network`-capture HTTP checks; crash gate.
- `references/phases/phase-i-qa.md` — **rewritten** as the autonomous `/loop` (setup, loop body, replay vs live, autonomy gates, convergence/completion-promise, iOS forward-check, retro/close).
- New: `references/agent-device.md` (command surface, subagent-mediation, `.ad` conventions) and `references/runtime-golden.md` (capture format, replay mechanism, masking policy, PII gate).
- **Version bump in all four places** (plugin.json, marketplace.json entry + top-level metadata.version, README row) per the repo's load-bearing rule — done at implementation, not now.

## 10. Risks & mitigations

- **Replay harness infeasible** → graceful fallback to live A/B per journey (hybrid exception path); flagged, never blocks. (R1–R3.)
- **Over-masking hides a real trading bug** → hard rule: never mask a computed value; replay removes most masking entirely; masking reserved for externally-fed streaming surfaces and always reported.
- **Autonomous loop spins / false-converges** → strict completion promise, max-iter pause-not-pass, anchor/empty-diff anti-vacuous guards, all the existing human gates.
- **Recorded PII in a trading app** → blocking no-PII/secret scan before any golden write; golden gitignored, never in the PR.
- **Loop autonomy bypasses the skill's discipline** → it does not: every fix still runs failing-test-first → subagent edit → exception-if-behavior-shifts → commit → retro; the loop only schedules and gates that existing discipline.
- **Two QA implementations drift** (skill vs autopilot) → the migration skill no longer depends on autopilot; autopilot is unaffected and remains separately usable.

## 11. Success criteria

- Phase I runs as a closed `/loop` that converges an all-green user-readable checklist with no manual fix-trigger cycle, pausing only at the defined gates.
- A migrated computed financial value that diverges from the frozen golden is caught **deterministically** (replay), to the digit, with no market-movement false positive.
- R8 serialization parity is verified on **real payloads** inside the running app (gap closed, no longer deferred).
- The QA checklist in the PR body reads as user journeys + expectations, not a symbol map.
- iOS migrated behavior is runtime-checked when a consuming UI path exists; a named gap otherwise.
- No PII ever leaves the local working tree.

## 12. Out of scope

- Changes to `kmm-qa-autopilot` or any other skill/plugin.
- Replacing unit-level baseline discipline.
- Shipping the iOS app feature.
- Building the replay proxy itself in this design doc (its mechanism is selected in writing-plans after R1–R3).
