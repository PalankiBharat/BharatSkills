---
name: clean-code
description: Comprehensive guide for writing clean, maintainable code following Robert C. Martin's Clean Code principles. Use when writing any code, refactoring existing code, reviewing code, or when the user asks for clean code practices, code quality improvements, or software craftsmanship guidance. Covers naming, functions, comments, formatting, error handling, and general code organization principles.
---

# Clean Code — Mandatory Rules

These rules apply to ALL code you produce. No exceptions.

## Step 0: Before Writing ANY Code

1. Read `references/naming.md` — ALWAYS
2. Read `references/functions.md` — if writing functions
3. Read `references/classes.md` — if writing classes
4. Read `references/error-handling.md` — if code has error paths
5. Identify the problem's **domain language** — use domain nouns/verbs, not generic ones

**If reference files contain examples for the exact problem being solved, you MUST follow them over your own generic knowledge.**

## Rules (Non-Negotiable)

**Naming:** Intention-revealing. Classes = nouns. Functions = verbs. No abbreviations. No `data`, `info`, `a1`, `a2`. Use domain vocabulary.

**Functions:** ONE thing only. 5-20 lines. 0-2 parameters. No side effects. One abstraction level per function. Apply stepdown rule — high-level entry function calls mid-level helpers which call low-level operations.

**Code speaks:** No comments explaining WHAT. If you need a comment, rename or extract instead. Only comment WHY when non-obvious.

**Errors:** Exceptions, not error codes. Never return null. Never pass null. Fail fast.

**Classes:** Single responsibility. High cohesion. Law of Demeter — don't chain method calls on objects you got from other objects.

**Organization:** Stepdown rule for function ordering. Group related concepts. Blank lines between concepts. 80-120 char lines.

**DRY:** No duplication. But no premature abstraction for single use.

## Workflow

0. **Read references** (mandatory — not optional)
1. **Domain language** — name the vocabulary before coding
2. **Write** — functional first, using domain language
3. **Refactor** — apply rules above ruthlessly
4. **Verify** — every function does ONE thing, names reveal intent, no comments needed

## Post-flight Check

- [ ] Every name reveals intent without needing a comment
- [ ] Every function does one thing, 5-20 lines, 0-2 params
- [ ] Stepdown rule applied — read top-to-bottom like prose
- [ ] Domain language used throughout, not generic terms
- [ ] No null returns, no ignored exceptions
- [ ] No dead code, no commented-out code

## Deep Dive References

- `references/naming.md` — naming conventions with domain examples
- `references/functions.md` — function design, stepdown rule, extraction patterns
- `references/classes.md` — SOLID, cohesion, encapsulation
- `references/comments.md` — when to comment (almost never)
- `references/formatting.md` — vertical/horizontal layout
- `references/error-handling.md` — exception patterns, null handling
- `references/testing.md` — TDD, F.I.R.S.T. principles
