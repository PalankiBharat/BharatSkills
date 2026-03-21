# Clean Code Rules Card (Condensed)

## Naming
- Names MUST reveal intent — no `d`, `data`, `info`, `a1`, `a2`, `temp`
- Classes = nouns (`Customer`, `OrderValidator`). Avoid `Manager`, `Processor`
- Functions = verbs (`deletePage`, `saveUser`, `isValid`)
- Booleans = predicates (`isValid`, `hasPermission`, `canEdit`)
- One word per concept — don't mix `fetch/retrieve/get`
- Use DOMAIN vocabulary, not generic terms (e.g., `ocean` not `grid`, `submerge` not `sink`)
- Searchable names — no magic numbers, no single-letter vars outside tiny loops
- Language conventions: Python=snake_case, JS/TS/Java/Kotlin=camelCase, Classes=PascalCase

## Functions
- ONE thing only. If you can extract a non-restating function, it does too much
- 5-20 lines. Max indent level 2. 0-2 parameters (use objects for more)
- Stepdown rule: high-level calls mid-level calls low-level. Reads like prose top-to-bottom
- No side effects — function does what name promises, nothing more
- No flag args — split `render(true)` into `renderForSuite()` / `renderForSingleTest()`
- Command-query separation: either DO something or ANSWER something, not both
- Use class encapsulation to eliminate repeated parameters (shared context in instance vars)

## Classes
- Single Responsibility — one reason to change
- High cohesion — methods use most instance variables
- Law of Demeter — don't chain: `ctx.getOptions().getScratchDir().getAbsolutePath()`
- Open/Closed — extend via polymorphism, not if/else chains
- Depend on abstractions, not concretions

## Error Handling
- Exceptions, not error codes
- Never return null — use exceptions or Optional/special-case objects
- Never pass null — validate inputs at boundaries
- Extract try/catch into separate functions — error handling IS the one thing
- Fail fast — detect problems early

## Code Organization
- Blank lines between concepts
- Group related functions together
- 80-120 char lines
- No dead code, no commented-out code

## The Test: Read It Aloud
```
if (isLand(row, col)) {       // "if is land" — reads like English
    submergeIsland(row, col)   // "submerge island" — clear domain action
}
```
If it doesn't read like prose, rename until it does.
