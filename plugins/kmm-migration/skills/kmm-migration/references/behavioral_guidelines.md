# Behavioral Guidelines

> Load-bearing behavioural rules for every subagent. Complements
> `migration_laws.md` with the CLAUDE.md-style practical directives.

## Contents

- [Think before coding](#think-before-coding)
- [Simplicity first](#simplicity-first)
- [Surgical changes](#surgical-changes)
- [Goal-driven execution](#goal-driven-execution)

## Think before coding

Before any edit:

- State your assumptions explicitly. If uncertain, ask (emit
  `STATUS: NEEDS_CONTEXT`).
- If multiple interpretations exist, list them. Never pick silently.
- If a simpler approach exists, say so.
- If anything is unclear, STOP. Name what's confusing. Ask.

Hiding confusion behind plausible prose is a Law 12 violation.

## Simplicity first

- Minimum code that satisfies the migration_guide entry.
- No abstractions for single-use code.
- No flexibility / configurability the spec did not request.
- No defensive error handling for impossible scenarios.
- Ask: "Would a senior engineer say this is overcomplicated?" If yes,
  simplify. If the spec entry itself looks overcomplicated, emit
  `STATUS: DONE_WITH_CONCERNS` with a simpler-alternative note.

## Surgical changes

- Touch only what the migration_guide entry authorizes.
- Every changed line traces to a spec entry.
- Match existing style even if you'd write it differently.
- Don't "improve" adjacent code, comments, formatting, or imports.
- Remove imports/symbols YOUR changes orphaned. Do not remove pre-existing
  dead code.
- If you notice unrelated dead code, mention it in your report; do NOT
  delete it.

## Goal-driven execution

- Every dispatch carries a success criterion (the specific spec entry).
- Loop: write → verify against criterion → adjust. Until criterion met.
- "Make it work" is NEVER a success criterion. Demand a verifiable one
  via `STATUS: NEEDS_CONTEXT` if missing.
