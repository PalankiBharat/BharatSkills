# Self-Contained Design

> kmm-migration has NO external skill dependencies. Three patterns
> (worktree setup, verification-before-completion, root-cause investigation)
> are inlined as native reference files.

## Contents

- [Why self-contained](#why-self-contained)
- [The 3 inlined patterns](#the-3-inlined-patterns)

## Why self-contained

Earlier drafts of this skill invoked three `superpowers:*` skills internally. That added an install-step dependency and coupled us to a third-party plugin's versioning. The 3 patterns are compact enough to own natively; inlining them keeps the skill self-contained and easier to adopt.

## The 3 inlined patterns

| Pattern | Our reference | Used by |
|---|---|---|
| Worktree setup | `references/worktree_setup_protocol.md` | `00_worktree_initializer` (once, Phase 0) |
| Evidence-based completion | `references/verification_protocol.md` | every reviewer + every gate validator |
| Root-cause investigation | `references/root_cause_protocol.md` | `debug_investigator` (three-strike only) |
