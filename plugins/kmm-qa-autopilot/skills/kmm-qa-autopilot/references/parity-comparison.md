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

**On untagged value-table screens (reports/ledgers/statements), the visible-text signal IS the
primary oracle** — the on-screen amounts/dates are the migrated logic's output, so a stable text that
differs is a real value 🔴, while text-count deltas at a scroll boundary are soft hints. Don't treat a
clean text-based 🟢 as weak: with static (market-closed) data and zero live masking it's a strict,
trustworthy comparison. Tagging every cell is unnecessary — a screen-level tag only aids navigation.

## EVICTION is not a bug

Even though prod allows concurrent sessions, if one device gets bumped to login mid-run, that
device's screens stop matching for a reason that has nothing to do with the migration. The
oracle detects "auth surface on exactly one device" and returns EVICTION instead of a false 🔴.
When you see it: re-login on both devices and re-run that journey; don't report it as a finding.

## DIVERGENCE — the bug-handling protocol

A 🔴 is a strong lead, not an automatic bug. Run this protocol **in order** — it's the fix for the
PR #420 failure mode (one B failure → an account-state hypothesis → ~8 wasted tool calls before the
real cause, a missing URL slash, was read from source):

1. **Reproduce ≥2× on B** before treating the 🔴 as real (re-run the checkpoint). A one-off flake
   isn't a finding.
2. **If the divergence could be *expected behavior*** — account-state, one-device-per-account, server
   dedupe, eviction — try it **once**, then **ASK THE USER UPFRONT via the AskUserQuestion tool**
   ("B's 2nd biometric registration on the same account failed — is that expected, or should both
   succeed?"). A one-line question beats an 8-call hypothesis you then have to tear down. Do **not**
   assume and burn turns building/refuting a theory.
3. **Batch, don't tunnel.** Accumulate *all* findings across *all* journeys into one list; don't stop
   the run to chase the first 🔴.
4. **Root-cause each batched finding with a per-issue code-audit subagent** (model-tiered) — see
   [code-audit-subagents.md](code-audit-subagents.md) — before writing it up as confirmed.

Before reporting any single 🔴, also rule out the known false-positive classes:
- Open the side-by-side `a.s0.png` / `b.s0.png` for that checkpoint — does the difference show
  visually, or is it a hierarchy artifact?
- Re-check the value isn't actually live (a number that *should* have been masked but the seed
  missed and it didn't tick in 2s). If so, add it to `--seed-mask` and re-run that checkpoint.
- **Chart-axis render jitter (the "relaunch" trick):** SciChart axis ticks/series re-render at a
  sub-value offset, so a device can **diverge from ITSELF on relaunch** (e.g. A flipped `23379→23383`
  on relaunch while the real NIFTY value `23382.60` was identical on both). Confirm by relaunching the
  *same* build and re-capturing — if it differs from itself, it's render noise, not the migration.
  Mask the chart region (default seed now covers `axis*`/`renderableseries`/`annotation`) or, for an
  axis number with no stable id, `compare-parity.py --mask-text <token>` — not `--server-state-text`.
- Confirm both builds were at the same step (a flaky tap can leave one device a screen behind →
  spurious presence diffs). Re-run the checkpoint.
- **Scroll/paging offset:** a single extra row at a list boundary is almost always the two devices
  resting at slightly different scroll offsets, not a migration bug. Scroll **both to a deterministic
  anchor** (list bottom / `scrollUntilVisible`) and re-compare; if it converges (no A-only/B-only),
  it's drift → not a 🔴.
- **Stateful-action server copy:** on a shared account a submit/send/download confirmation can differ
  purely by request ORDER (the 2nd request sees mutated server state). Check the copy isn't in either
  build's source (i.e. it's server-returned); if so mask it (`--server-state-text`) and compare the
  pre-submit state instead. Treat like EVICTION, not a 🔴. (Confirm via an order-swap if unsure: run
  the action on B first, then A — if the message follows the order, not the build, it's server state.)
- **A doc doesn't excuse it:** if a `.kmm/exceptions/*.md` claims this change is intentional, that's
  context, not a verdict. Keep the 🔴 unless YOUR captured values match the documented old→new exactly.
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
