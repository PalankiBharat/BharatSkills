# Parity Comparison — the hybrid oracle

`scripts/compare-parity.py` is the verdict engine. This explains how it thinks so you can read
its output, tune the mask, and aggregate checkpoints into a journey verdict.

## Why hybrid, and why not pixels

This is a live prod trading app. Prices, charts, clocks, and P&L change every tick and will
never be byte-identical on two devices at the same instant — so a pixel/ΔE diff would scream
"divergence" on every frame. But the migration moves *business logic* (ViewModels, UseCases,
Repositories, mappers) and leaves the UI untouched. So the right question isn't "do the pixels
match" — it's **"does the same structure and the same computed values come out the other side."**

The oracle answers that with the **view hierarchy** (resource-id = Compose testTag → text),
masking anything that proves itself volatile.

## Live-field masking by double-sampling

Each device is captured twice ~2s apart. A `resource-id` whose text (or presence) changes
between a device's *own* two samples is volatile — it's moving on its own, not because of the
build. Those ids are masked before A is compared to B. A small seed list
(`price`, `ltp`, `pnl`, `chart`, `canvas`, `clock`, `time`, …) covers fields that happen not to
tick during the capture window (e.g. market closed). Tune via `--seed-mask`.

This is self-calibrating: market open → lots masked; market closed → almost nothing masked and
the comparison gets stricter (which is fine — static values *should* match exactly).

## What counts as what

| Signal | Source | Verdict weight |
|---|---|---|
| Tagged element present on one build only (non-volatile) | `resource-id` set diff | 🔴 DIVERGENCE (presence) |
| Shared tagged element, stable text differs | `resource-id` → text | 🔴 DIVERGENCE (value) — *the wrong-number case* |
| Tagged diff but the id is volatile | masked | reported under `masked`, not a verdict |
| Untagged class-count differs | class multiset | 🟡 DRIFT hint only |
| One device on an auth surface, other not | auth markers | ⚠️ EVICTION (precedence) |

Per-checkpoint verdict: **EVICTION** > **DIVERGENCE** (any hard signal) > **DRIFT** (only soft
hints) > **PARITY**. Exit codes: PARITY/DRIFT=0, DIVERGENCE=1, EVICTION=2.

## EVICTION is not a bug

Even though prod allows concurrent sessions, if one device gets bumped to login mid-run, that
device's screens stop matching for a reason that has nothing to do with the migration. The
oracle detects "auth surface on exactly one device" and returns EVICTION instead of a false 🔴.
When you see it: re-login on both devices and re-run that journey; don't report it as a finding.

## DIVERGENCE — confirm before you call it

A 🔴 is a strong lead, not an automatic bug. Before reporting:
- Open the side-by-side `a.s0.png` / `b.s0.png` for that checkpoint — does the difference show
  visually, or is it a hierarchy artifact?
- Re-check the value isn't actually live (a number that *should* have been masked but the seed
  missed and it didn't tick in 2s). If so, add it to `--seed-mask` and re-run that checkpoint.
- Confirm both builds were at the same step (a flaky tap can leave one device a screen behind →
  spurious presence diffs). Re-run the checkpoint.
- A genuine 🔴 on a *value* (`order_count`, a P&L total, a formatted price that's stable) is the
  headline finding — that's a migration that changed behavior. Quote both values.

## Aggregating to a journey verdict

A journey = its ordered checkpoints. Roll up:
- Any **EVICTION** → journey is **inconclusive** until re-run.
- Any confirmed **DIVERGENCE** → journey **🔴 DIVERGENCE**.
- Only **DRIFT** hints → **🟡 DRIFT** (note them; usually live/timing).
- All **PARITY** → **🟢 PARITY HOLDS**.

## Overall run verdict

- 🟢 **PARITY HOLDS** — every affected journey is 🟢 (mutating journeys the user declined are listed as untested, not green).
- 🟡 **REVIEW DRIFT** — no hard divergences, but drift hints worth a glance.
- 🔴 **DIVERGENCE FOUND** — at least one confirmed structural/value divergence. The migration changed observable behavior; do not treat it as a no-op.
