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

## Rules — Action Directives

**Naming — for every name, ask these questions:**
1. "Does this name describe WHY or HOW?" If HOW (mechanism), rename to WHY (intent).
2. "Is this word from the domain or from generic programming?" If generic, replace with domain.
3. "Can a reader understand this without reading the implementation?" If no, rename.

**Functions — for every function, check:**
1. "Does this do more than one thing?" Extract a non-restating helper if yes.
2. "Are all lines at the same abstraction level?" If high mixed with low, extract.
3. "Can I name each branch/direction?" If raw `row-1`, `col+1` appear inline, extract `exploreNorth()`, `exploreSouth()`, etc.
4. 5-20 lines, 0-2 params, no side effects, no boolean flags.

**File-level stepdown:** Entry point function FIRST → class definition → helpers → primitives. Reader hits "what" before "how".

**Code speaks:** No comments explaining WHAT. If you need a comment, rename or extract instead. Only comment WHY when non-obvious. **No section-header comments** (`// --- Section ---`, `// ===== Setup =====`) — use blank lines between concept groups. If headers are needed, the class has too many responsibilities.

**Errors:** Exceptions, not error codes. Never return null. Never pass null. Fail fast.

**Classes:** One reason to change. High cohesion. Law of Demeter — never chain `a.getB().getC()`.

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
- [ ] No section-header comments — blank lines separate concept groups

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
