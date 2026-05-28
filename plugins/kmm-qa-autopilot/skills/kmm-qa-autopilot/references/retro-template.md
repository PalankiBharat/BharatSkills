# Session Retro — Template (Phase 8)

Write to `$RUN_DIR/retro.md` after the report. **Save only — never edit the skill during a run.**
This is how kmm-qa-autopilot improves from every real PR: capture what hurt, with evidence, so a
later session can triage it into the skill (worktree edit → version bump → PR).

Be **evidence-backed, no guesswork.** Skip any category with nothing to report — don't pad.

```markdown
# kmm-qa-autopilot — session retro: PR #<num> (<date>)

- Build variant: ProductionRelease   Baseline: <ref>   Devices: A=<serial> B=<serial>
- Market: <open|closed>   Outcome: <overall verdict>   Wall-clock: ~<Xm> (builds <Xm>, run <Xm>)

## What hurt (each: observation → evidence this run → proposed skill change → goal)

### Speed
- <e.g. cold ProductionRelease build = Xm each> → <proposed change> → speed

### Robustness
- <failures / manual re-syncs / deviations (e.g. used adb swipe for a data probe)> → <change> → robustness

### Confidence
- <false 🔴s + proven root cause; over-strict/over-masked; UI-unreachable documented changes> → <change> → confidence

### Harness
- <anything hand-driven that a script should do> → <change> → harness

## False positives caught (so the next run is cleaner)
| checkpoint | raw verdict | real cause | how confirmed |
|---|---|---|---|
| <j>/<cp> | 🔴 | scroll-offset / stateful server copy / eviction | <convergence / order-swap / re-login> |

## Named gaps (not tested / not reachable)
- <journey or documented change that couldn't be exercised, and why>

## Refuted / learned (don't re-propose)
- <hypotheses this run disproved, with the measurement>
```

Triage note: everything here is a **candidate, not a decision**. Apply in a separate session with
user review — get approval per item, then edit the skill source in a worktree and open a PR.
