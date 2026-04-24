# Verification Protocol

> The iron-law framing for evidence-based completion. Invoked by every reviewer and every gate validator (replaces the external `superpowers:verification-before-completion`).

## Contents

- [The iron law](#the-iron-law)
- [Rationalization table](#rationalization-table)
- [Procedure](#procedure)

## The iron law

**NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.**

If you have not run the verification command *in this message*, you cannot claim it passes. This is Rule 5 (Evidence Before Claims) of `migration_laws.md`, restated for reviewers and gate validators.

## Rationalization table

| Thought | Reality |
|---|---|
| "Previous run passed, so it still passes" | Stale evidence. Run the command NOW. Attach the output. |
| "It compiled, so the tests must pass" | Compilation ≠ tests. Run the tests. |
| "Obviously this matches the baseline" | Obvious isn't evidence. Run the baseline suite. Attach the diff. |
| "The linter is green, so the build is green" | Linter ≠ build. Run the build. |
| "Just a tiny change, won't break anything" | Tiny changes break things all the time. Run the verification. |
| "I'll verify later if needed" | Now or never — claim = verified NOW, or no claim. |

## Procedure

1. IDENTIFY the exact command that proves the claim (test runner, build, diff, gate-validator script).
2. RUN the command fresh in this message. No short-circuits. No partial runs.
3. READ the output + exit code. Attach both to the report.
4. VERIFY the output actually confirms the claim (output might say PASS while exit code is 1, etc.).
5. ONLY THEN emit the claim (`STATUS: DONE`, `PASS`, etc.).

Do not use phrases like "should work", "probably passes", "seems to", "appears to" in any report — these are rule violations.
