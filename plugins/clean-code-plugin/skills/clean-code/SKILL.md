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
5. **Discover the domain language** — before writing a single line, name the problem's nouns and verbs. Every entity, action, and predicate in your code should come from this vocabulary, not from generic programming terms

## Rules (Non-Negotiable)

**Naming:** Intention-revealing. Classes = nouns. Functions = verbs. No abbreviations. No `data`, `info`, `a1`, `a2`. Names describe INTENT and DOMAIN concepts, not implementation mechanics (e.g., `markAsVisited` describes purpose, not `setToZero` which describes how; `isWithinOcean` speaks the domain, not `isWithinBounds` which is generic).

**Functions:** ONE thing only. 5-20 lines. 0-2 parameters. No side effects. One abstraction level per function. Apply stepdown rule — high-level entry function calls mid-level helpers which call low-level operations.

**Stepdown at file level:** The entry point function appears FIRST in the file, BEFORE any class or helper it delegates to. The reader encounters "what this does" before "how it works".

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
- [ ] Stepdown rule applied — entry point first, then class/helpers, read top-to-bottom like prose
- [ ] Domain language used throughout, not generic terms
- [ ] No null returns, no ignored exceptions
- [ ] No dead code, no commented-out code

## Pre-loaded Rules Card

The prehook injects `references/rules-card.md` — a condensed summary of ALL clean code rules (~50 lines). This is always available in your context. USE IT.

## Deep Dive References (read when you need full examples)

- `references/functions.md` — function design, stepdown rule, extraction patterns (includes Number of Islands canonical example)
- `references/naming.md` — naming conventions with domain examples
- `references/classes.md` — SOLID, cohesion, encapsulation
- `references/error-handling.md` — exception patterns, null handling
- `references/comments.md` — when to comment (almost never)
- `references/formatting.md` — vertical/horizontal layout
- `references/testing.md` — TDD, F.I.R.S.T. principles
