# Superpowers Invocation Recipes

> Three `superpowers:*` skills are invoked internally. No other superpowers
> skill is invoked by this skill's dispatches. **Superpowers is a HARD
> DEPENDENCY** — the SKILL.md body runs a preflight check before Phase 0 and
> emits a `NEEDS YOUR CALL` gate if superpowers is not installed.

## Contents

- [Hard dependency](#hard-dependency)
- [using-git-worktrees](#using-git-worktrees)
- [verification-before-completion](#verification-before-completion)
- [systematic-debugging](#systematic-debugging)

## Hard dependency

All three sub-skills are REQUIRED, not optional. Graceful-degradation
fallbacks would ship untested and weaken the "battle-tested" claim.

Install via:

```
/plugin install superpowers@claude-plugins-official
```

The skill refuses to proceed past preflight if the `Skill` tool cannot
resolve `superpowers:verification-before-completion` (the canary probe).
See `SKILL.md` § Preflight.

## using-git-worktrees

**REQUIRED SUB-SKILL:** superpowers:using-git-worktrees

- Invoked ONCE per migration, at Phase 0, by `00_worktree_initializer`.
- Used to create the single migration worktree recorded in state.json.

## verification-before-completion

**REQUIRED SUB-SKILL:** superpowers:verification-before-completion

- Invoked by every reviewer (`spec_compliance_reviewer`, `code_quality_reviewer`,
  `kmm_focused_final_reviewer`) and every gate validator
  (`05_baseline_gate_validator`, `13_parity_gate_validator`,
  `15_final_baseline_reverifier`) before emitting PASS.
- Reinforces Rule 5 (evidence before claims).

## systematic-debugging

**REQUIRED SUB-SKILL:** superpowers:systematic-debugging

- Invoked by `debug_investigator` when a subagent hits three-strike.
- Root-cause investigation; directly fights the "patch-over" anti-pattern.
