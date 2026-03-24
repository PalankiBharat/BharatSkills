# Test Prompt Generation Framework

## How to generate test prompts for a skill

### Analyze the skill's purpose

Read the skill's `description` field and SKILL.md to understand:
1. What domain does the skill operate in? (code quality, testing, design, etc.)
2. What triggers the skill? (prehook, manual invocation, both?)
3. What output does the skill produce? (code, review, report, etc.)

### Prompt categories

Generate at least one prompt per category:

**1. Happy Path**
A straightforward request in the skill's domain.
- If the skill is about code quality → "Write a function to solve X"
- If the skill is about testing → "Write tests for this module"
- If the skill is about design → "Design a component for X"

**2. Production Scenario**
A real-world, multi-file or complex request.
- ViewModel, Repository, API handler, full feature
- Tests the skill under realistic complexity

**3. Edge Case**
Tests boundary conditions:
- Very simple problem (does the skill over-engineer?)
- Problem with error handling (does the skill enforce error patterns?)
- Problem in a different language than the reference examples

**4. Multi-Concern**
Exercises multiple rules simultaneously:
- A class with functions, error handling, and naming all at once
- Forces the skill to apply ALL its rules, not just the obvious ones

### Prompt design rules

- Keep prompts SIMPLE enough that the output is easy to validate
- Specify the output file name (so you can read it directly)
- Specify the language (to test language-specific conventions)
- Do NOT mention the skill or its rules — the whole point is that the
  skill works transparently without the developer knowing

### Example prompts for a code quality skill

```
1. "Solve the word search problem in Kotlin. Write to WordSearch.kt"
2. "Write a Kotlin ViewModel for an ATM machine with PIN validation,
    balance inquiry, cash withdrawal, and mini statement. Write to AtmViewModel.kt"
3. "Write a function to check if a string has balanced parentheses in Python.
    Write to balanced.py"
4. "Implement an LRU cache in Kotlin with get, put, remove, and evict.
    Write to LruCache.kt"
```
