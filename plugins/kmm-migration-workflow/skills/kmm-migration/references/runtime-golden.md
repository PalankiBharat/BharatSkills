# Runtime golden reference

Reference for capturing, storing, protecting, and consuming the runtime golden. Loaded by Phase B (golden capture), Phase C (freeze), Phase I (parity QA loop), and the `kmm-qa-autopilot` skill.

---

## What the golden is

A **frozen runtime behavioral contract**: real network wires + computed UI outputs per journey checkpoint, captured on `master` before any migration touches the feature.

The golden is **additive** to the unit baselines — it does not replace them. Unit baselines (Phase B/C) prove logic in isolation; the runtime golden proves the full installed build (serialization, R8, network parsing, rendering pipeline) produces the same user-visible outputs.

---

## Storage layout

```
.kmm/migrations/kmm/<feature>-<depth>/golden/
  <journey>/
    <checkpoint>/
      checkpoint.json      # normalized checkpoint (see agent-device.md)
      wires/
        *.json             # raw network wire captures
      screenshot.png       # screen at checkpoint anchor
      logcat.txt           # scoped logcat from app PID
  <journey>.ad             # replayable .ad journey script
```

The entire `migrations/` tree is gitignored. The golden is **never committed** and **never appears in the PR**.

---

## PII gate (BLOCKING, trading data)

Before any golden is written, run `scripts/scrub-pii.py --gate <golden-dir>` (must be gitignored) and `--scan` each wire (report PII classes to the user). The golden is never committed and never embedded in the PR. Only shareable artifacts (report/PR text) are passed through `--scrub`; golden wires are left intact (replay needs them).

---

## Masking policy

Never mask a value the migrated code computes (P&L, totals, derived prices, order values) — that is the headline signal. Mask only an externally-fed live feed not derived from migrated logic (raw streaming tick, self-re-rendering chart axis). Replay freezes inputs, so for replayed journeys there is nothing to mask; masking applies only to the live-A/B exception path.

---

## Replay vs live decision rule

**Replay is the default.** Replay is deterministic, produces an exact computed-value diff, carries no login or real-money risk, and exercises serialization under R8. Use replay for every journey that can be recorded.

**Live A/B + narrow masking is the exception** — for surfaces where replay is infeasible (e.g., a streaming chart that cannot be frozen by wire replay). A journey where replay is infeasible falls back to live and is **flagged** in the session report so the deviation is visible.

The per-repo mechanism for replay (HTTP interception layer, mock-server wiring, etc.) is recorded in the repo's research doc / `project.md`. Do not invent the replay mechanism here; consult those sources.

---

## Freeze protection

The runtime golden freezes in lockstep with the unit baselines at the end of Phase C.

- Editing a frozen golden requires the **same migration-exception gate** as editing a frozen baseline (see `test-discipline/migration-baselines.md` §Freeze and exception provenance).
- The orchestrator **confirms the exception BEFORE any subagent edits a frozen golden**. This is a hard gate: hooks do not fire on subagent tool calls, so the orchestrator must enforce the gate in the subagent prompt itself — it cannot be delegated to a hook.
- Exception entries are written to `.kmm/exceptions/` with the same provenance fields used for baseline exceptions.
