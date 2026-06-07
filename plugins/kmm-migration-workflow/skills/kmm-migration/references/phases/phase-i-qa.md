# Phase I — Parity loop (in-skill agent-device A/B)

**Purpose.** Phase I is a **closed autonomous `/loop`** that runs in-skill agent-device A/B parity QA and converges the heatmap checklist to all-green — fixing every parity-restoring bug **through the workflow** as it goes. **This is the final phase.** Phase I does **not** hand the PR to a separate QA skill; the migration skill now runs parity QA itself, deterministically, against the frozen runtime golden.

**The contract is behavioral equivalence for a trading app.** Computed financial values (P&L, totals, order values, derived prices) must match **to the digit**. That forces the verification design: **deterministic replay of the frozen golden is the primary path** — frozen wires in, exact computed-value diff out, no market-movement false positives, R8/serialization exercised on real payloads (R8 specifically at the I.2.8 Release pass). **Live A/B with narrow masking is the exception**, used only for un-recordable streaming surfaces. See `references/runtime-golden.md` (capture, PII gate, masking, replay-vs-live) and `references/agent-device.md` (command surface, `.ad` scripts, checkpoint format, subagent-mediation) — this phase cites those, it does not restate them.

**The loop reuses the migration's discipline — it does not bypass it.** Every parity-restoring fix routes through §Late-change discipline (failing-test-first → subagent edit → green → exception-if-behavior-shifts → commit → retro). The loop **schedules** that discipline per iteration; it never live-patches. A behavior-shifting fix, dependency change, plan-flip, eviction, or mutating/real-money journey **pauses** the loop at a human gate.

**Inputs:** `pr.md` (PR URL, recorded at G.4), `review.md` (Phase H), `heatmap.md`, `journeys.md`, the frozen `golden/` tree, `validation.md`, `plan.md`, `coverage.md`, `project.md`.

---

## Sub-phases

### I.1 — Loop setup (once, at loop entry — NOT per iteration)

Done once before the first iteration; nothing here repeats inside the loop body.

1. **Reuse the PR URL from `pr.md`** (recorded at G.4) directly — do **not** re-query `gh pr view --json` (a jq-quoting flake cost a needless detour in a prior session). If G.4 only emitted `pr-body.md` for a manual open, prompt the user for the PR URL once it's up.
2. **Build APKs per the two-stage flavor policy.** The iteration loop runs on **`ProductionDebug`** so logcat is available for diagnosis; the binding final-sanity pass runs on **`ProductionRelease`** (R8 — see I.2.8). Build **master ProductionDebug ONCE** and reuse it across all iterations; **only the migrated `ProductionDebug` side rebuilds after a fix**. The `ProductionRelease` pair is built later, at I.2.8, not here. Any single A/B comparison uses the **same flavor on both legs** (master-Debug vs migrated-Debug in the loop; master-Release vs migrated-Release at I.2.8) — never cross-flavor.
3. **Open agent-device session(s)** (subagent-mediated, per `references/agent-device.md` §Subagent-mediation; every command device-scoped). **For live-A/B journeys only**, perform the **single manual prod login** — the sole manual step; the session persists across iterations via **force-stop + relaunch, never `clearState`**. **Replay journeys need NO login** (frozen wires carry the authenticated responses).
4. **Seed per-journey `.ad` probes from the catalog.** Each `journeys.md` entry → an agent-device `.ad` script that drives the interaction **invoking the migrated logic** (not just opening the screen), each paired with its frozen golden under `golden/<journey>/`. Per-journey `.ad` probes are recorded via `agent-device record` (deferred replay-mechanism research); `scripts/ad-capture.sh` is used during the loop to capture each checkpoint into the normalized JSON that `compare-golden.py` consumes. The `.ad` + golden are the durable, reusable QA assets (replay subsequent iterations).

**Anti-false-exit guard (hard stop at setup).** If the baseline↔PR git diff is empty (nothing actually migrated), STOP — there is nothing to parity-check and a green checklist would be vacuous. Surface to the user; do not run the loop.

### I.2 — Loop body (one iteration)

The skill drives this as the `/loop` body (see I.3). One pass over all pending journeys:

1. **Per journey, pick the mode:**
   - **Replay (default).** Feed the frozen recorded responses to the migrated build; replay the `.ad` probe; capture via `scripts/ad-capture.sh`; **`scripts/compare-golden.py` exact-diffs the computed values against the golden** (no masking — replay freezes inputs, so there is nothing to mask). Computed financial values compare to the digit.
   - **Live A/B (exception).** Only for un-recordable streaming surfaces (e.g., a self-re-rendering chart that wire-replay cannot freeze). Run master + migrated live; diff snapshots with **narrow semantic masking** — mask only an externally-fed live feed not derived from migrated logic; **NEVER mask a computed value** (per `references/runtime-golden.md` §Masking policy). Live fallback is **flagged** in the report.
2. **Classify each heatmap row:** 🟢 / 🔴 / ⚪-indeterminate (**anchor absent on both = NOT green** — guards the vacuous-pass trap; `compare-golden.py` exit 3) / ⚠️-eviction (live A/B only). `compare-golden.py` exit 0 = PARITY (🟢), exit 1 = DIVERGENCE (🔴), exit 3 = INDETERMINATE (⚪).
3. **For each 🔴:** reproduce **≥2×** (a one-shot divergence may be transient); then a **per-issue root-cause subagent** (Sonnet for small, Opus for complex — per SKILL.md §Smart subagent routing) with full context (symptom + both values + `git diff` + relevant `.kmm/exceptions/*` claims + captured evidence). Classify as **parity-restoring bug** (common) / **intentional change** (exception path) / **known false-positive class** (eviction, scroll-offset, chart-jitter, stateful server copy). QA forms its own evidence-backed verdict — exception docs and author claims are context, not proof.
4. **Fix parity-restoring bugs AUTONOMOUSLY through the workflow** (per SKILL.md §Late-change discipline — the loop schedules this discipline, never a live patch):
   1. **Failing-test-first** — the divergence becomes a red, KMM-portable baseline-style test proving the bug. No fix before the red test.
   2. **Surgical subagent edit** — every edit via a dispatched subagent (never the orchestrator, per SKILL.md §Subagent-mediated execution). Make the red test green.
   3. **Migration-exception BEFORE the edit if it touches a frozen / `migrated` / `promoted` baseline or the frozen golden** — the orchestrator creates/confirms the `.kmm/exceptions/*.md` entry (under `Authorizes.baseline-edit`) **before dispatching**, because the `frozen_baseline_guard` hook does not fire on subagent calls (per SKILL.md §Migration-exception process and `references/runtime-golden.md` §Freeze protection). Commit carries `[migration-exception <id>]`.
   4. **Commit** (two-commit cadence), then **re-validate at the Phase F.6 mechanical scope** — surgical (≤5 LOC, single file, no new types/signatures) → F.3 (build + tests) only; non-surgical → full F.1. Announce the scope + one-line justification.
   5. **Rebuild only the migrated `ProductionDebug` APK** (master Debug is untouched, never rebuilt) and **re-run only the affected probe** — not the whole catalog. (Exception: when the bug was surfaced by the I.2.8 Release pass, rebuild the migrated `ProductionRelease` APK instead — see I.2.8.)
   6. **Retro entry** for the fix (the loop keeps learning per iteration).
5. **PAUSE at a gate** (do not fix autonomously; surface and wait) when the fix:
   - **shifts observable behavior** → migration-exception **+ explicit user sign-off** before proceeding;
   - needs a **dependency change**;
   - implies a **`migrate→hold` plan-flip** (Phase D.3 path, user approval);
   - hits **eviction** on a live journey (re-login required);
   - touches a **mutating / real-money journey** (confirmation before any live action).
   When the right process isn't obvious, surface to the user — never improvise around a gate (per SKILL.md §When in doubt).
6. **Update outputs:** the heatmap Result cells + the `qa.md` bug-fixing log (repro, failing test, fix, exception ref, re-validation scope, commit SHA).
7. **(Conditional) iOS forward-check.** If an iOS UI path **consumes the migrated commonMain code this session**, drive the same journey on the iOS simulator via agent-device and assert **crash-free + the computed output matches the frozen golden** (the same commonMain logic, consumed from iOS, must produce the same numbers). This is a *forward* check only — there is no pre-migration iOS behavior to A/B against. **No consuming iOS path → a named gap** recorded in `qa.md`. (The deterministic test for "an iOS UI path consumes the migrated code this session," and iOS replay-vs-forward, are defined by research spike **R4** — forward-reference it; do not invent the detector here.)
8. **(Loop-exit gate) ProductionRelease final-sanity A/B.** **Run once, after the Debug iteration loop (steps 1–7) has converged to all-🟢 across every journey — not per iteration.** A green ProductionDebug loop is **necessary but not sufficient** — Debug skips R8, which can strip `@Serializable` keep rules that only fail under Release, producing serialization false-greens (per `references/runtime-golden.md`). So before the completion promise can be emitted: build the **master + migrated `ProductionRelease`** pair (R8-minified shipped artifact), and re-run **every catalog journey's replay probe** master-Release vs migrated-Release with `compare-golden.py` exact-diff. **Parity is NOT declared green until this Release pass is all-🟢.** A Release-only divergence (green in Debug, red in Release) is a real parity bug — diagnose and fix it through the same I.2.4 workflow (its failing-test-first proof runs against the Release artifact), then rebuild the migrated Release side and re-run the affected Release probe. The master Release APK is built once and reused like the Debug master.

### I.3 — Convergence: the `/loop` completion promise

The skill drives I.2 via the harness **`/loop` mechanism**, with the completion promise below as the **exit condition**. Each iteration re-enters the loop body (I.2) — re-running only the still-pending/affected probes — until the promise is **genuinely** true, or a gate (I.2.5) / the max-iterations cap pauses it.

**Completion promise (emitted ONLY when genuinely true; verbatim):**

> Every catalog journey is 🟢 with a real anchor reached **on the ProductionRelease A/B pass (I.2.8)**, zero open 🔴, zero ⚪-indeterminate, the iOS forward-check passed-or-is-a-named-gap, and any remaining finding is an explicitly user-deferred recorded follow-up.

**Convergence guards (non-negotiable):**
- **Max-iterations safety cap.** If the loop cannot converge within the cap, it **PAUSES and surfaces** the open rows — it **never false-passes** to escape. A stuck loop ends in a human gate, not a green wall.
- **Anti-false-exit guards.** Empty baseline↔PR diff = **hard stop** (I.1). Anchor-absent-on-both = **⚪, not 🟢** (I.2.2). A ⚪ row is never counted toward green.
- **Emitting the completion promise while it is not genuinely true is prohibited.** A false promise to escape the loop is the single worst failure mode this phase guards against — the promise is a factual claim about the heatmap, not a loop-exit convenience.
- **Release-sanity is binding.** The completion promise may not be emitted on Debug-loop greenness alone — the ProductionRelease A/B pass (I.2.8) must be all-🟢 first. A Debug-green / Release-red state is an open 🔴.

Only when the promise is genuinely true (or every remaining row is an explicit, recorded user-deferral) does the loop exit to I.4.

### I.4 — Write `qa.md` (parity record + bug-fixing log)

Living document, finalized here with status `complete`. Contains:
- PR URL + base branch.
- **Per-journey verdict table** — one row per catalog journey: mode (replay / live), verdict (🟢 / 🔴 / ⚪), the computed values compared, and the masked-field count (0 for replay; the narrow set for live).
- **Bug-fixing log** — per parity-restoring bug: repro, failing-test-first evidence, fix, migration-exception ref (if any), re-validation scope, commit SHA. (Empty if the loop found nothing.)
- iOS forward-check result (passed / named-gap).
- Any explicitly **user-deferred** finding, as a recorded follow-up.

`.kmm/migrations/` is gitignored, so `qa.md` is **working-tree-only** — no audit commit (per SKILL.md gitignore-collapse). Bug-fix **code** commits normally.

### I.5 — Phase I retro

Amend `retro.md` with `## Phase I — Parity loop (captured YYYY-MM-DD)` — five-bullet structure. **Blocking, non-skippable** (per SKILL.md Retro gate). This is the final phase retro. Per-iteration fix friction (I.2.4) feeds it — the loop keeps learning from what parity QA caught.

### I.6 — Session close-out

Run the session-end consolidation step (SKILL.md → Special actions → Session close-out). This is a **safety-net sweep** — pure per-repo facts were written to `project.md` **inline at discovery** throughout the session, so most `[project.md]` values are already in place. The sweep diffs `retro.md`'s `[project.md]`/`[both]` bullets against current `project.md` and diff-confirms only what wasn't already captured (usually nothing). Not skippable; writes remain diff-confirmed. After consolidation, the session is complete — offer worktree cleanup per Phase E post-session notes once the PR merges.

---

## Output: `qa.md`

- Header (status, tasks)
- PR URL + base branch
- Per-journey verdict table (mode, verdict, computed values compared, masked count)
- Bug-fixing log (per bug: repro, failing test, fix, exception ref, re-validation scope, commit SHA)
- iOS forward-check result (passed / named-gap)
- User-deferred follow-ups (if any)
- Decisions log

---

## Phase-specific gates

Beyond universals:

- Phase H complete (code review received + blockers resolved through the workflow; user approved).
- PR open with URL recorded; working tree clean at loop entry.
- **Every fix routes through the workflow** — failing-test-first, exception-if-behavior-shifts, all edits via subagents, committed and re-validated at F.6 scope. **No live patches.**
- **The loop pauses at every human-gated class** (I.2.5): behavior-shifting fix (+ user sign-off), dependency change, `migrate→hold` plan-flip, eviction, mutating/real-money journey.
- **Replay is the default; live A/B is the exception** — and the **PII gate is honored** before any golden is touched (per `references/runtime-golden.md`).
- **Convergence** is on the verbatim completion promise, or the loop **pauses at the max-iterations cap** — it never false-passes. Anti-false-exit guards (empty-diff hard stop; anchor-absent-on-both = ⚪) hold.
- **iOS forward-check passed-or-named-gap.**
- Phase I retro captured (blocking) and session-end consolidation run before the session is declared complete.
- **ProductionDebug for the loop, ProductionRelease for the binding final-sanity** — parity is not green until the I.2.8 Release A/B pass is all-🟢 (Debug skips R8 → serialization false-greens).
