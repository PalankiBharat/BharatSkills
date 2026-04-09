---
name: legacy-refactor
description: >
  Guide for safely refactoring legacy codebases based on Michael Feathers'
  "Working Effectively with Legacy Code." ALWAYS use when the user says: refactor,
  clean up, legacy code, technical debt, spaghetti code, messy code, make testable,
  untestable, tightly coupled, God class, break dependencies, extract class/method,
  can't test this, monster method, characterization test, seam, sprout method/class,
  wrap method/class, or any request to improve/restructure/safely change existing code.
  Also use when the user shares existing code to add features, fix bugs, or improve.
  Core: identify seams, write characterization tests, break dependencies, refactor safely.
---

# Working Effectively with Legacy Code

**Legacy code is simply code without tests.** It doesn't matter how old, clean, or ugly
it is — without tests, every change is a gamble. This skill teaches you how to stop
gambling and refactor with confidence.

## The Legacy Code Dilemma

To change code safely → you need tests.
To add tests → you often need to change code.

This skill breaks that cycle using seams, dependency-breaking techniques, and
characterization tests.

## The Legacy Code Change Algorithm

**Every change to legacy code follows these 5 steps. Never skip any.**

```
1. Identify change points     → Where do I need to make changes?
2. Find test points           → Where can I write tests to cover this change?
3. Break dependencies         → What's preventing me from testing?
4. Write characterization     → Lock down CURRENT behavior (bugs and all)
   tests
5. Make changes and refactor  → Now change safely with test coverage
```

The day-to-day goal: make functional changes that deliver value WHILE bringing
more of the system under test. After each episode, you should have both new
features AND new tests. Over time, tested areas surface like islands — eventually
becoming continents of test-covered code.

**→ Read `references/change-algorithm.md` for the complete algorithm with examples**

## The Seam Model — The Core Concept

A **seam** is a place where you can alter behavior in your program WITHOUT editing
in that place. Every seam has an **enabling point** — the place where you decide
which behavior to use.

Understanding seams is the key to getting untestable code under test.

### Types of Seams

| Seam Type | How It Works | Enabling Point | Best For |
|-----------|-------------|----------------|----------|
| **Object Seam** | Override methods via polymorphism | Constructor / parameter where object type is chosen | OO languages (most common, prefer this) |
| **Link Seam** | Swap implementations at build/link time | Build scripts, classpath, DI config | Replacing entire libraries |
| **Preprocessing Seam** | Macro/preprocessor substitution | #define, compiler flags | C/C++ only |

**Object seams are the most useful and the ones you should reach for first.**
A method call on an object is a seam if you can change which implementation runs
without editing the calling code — by passing a different object (fake/mock) through
the constructor or parameter.

**→ Read `references/seam-model.md` for the full seam model with examples**

## When You Don't Have Time — Sprout and Wrap

When you can't afford to get the whole class under test, use these techniques to
add tested code alongside untested code:

| Technique | When to Use | What It Does |
|-----------|-------------|-------------|
| **Sprout Method** | New behavior can be a separate method | Write new code in a new tested method, call it from old code |
| **Sprout Class** | Can't even instantiate the class in a test | Write new code in an entirely new tested class |
| **Wrap Method** | Need to add behavior before/after existing method | Rename old method, create new method with old name that calls both |
| **Wrap Class** | Need to add behavior transparently (Decorator) | Create wrapper class with same interface that adds behavior |

These are NOT refactorings — they're survival techniques. They let you add tested
code when you can't test the existing code yet. Use them when your back is against
the wall, but aim to eventually get the original code under test too.

**→ Read `references/sprout-and-wrap.md` for step-by-step recipes with code examples**

## Breaking Dependencies — The Techniques Catalog

When code is untestable, the root cause is almost always **dependencies** — on
databases, networks, frameworks, singletons, or deeply coupled objects.

### The Two Reasons to Break Dependencies

1. **Sensing** — You can't see what the code does (no way to check results)
2. **Separation** — You can't even run the code in a test harness

### Most Common Dependency Problems and Fixes

| Problem | Techniques |
|---------|-----------|
| **Constructor creates hard dependencies** | Parameterize Constructor, Extract and Override Factory Method, Supersede Instance Variable |
| **Singleton / global variable** | Introduce Static Setter, Subclass and Override, Extract Interface on singleton |
| **Method has undetectable side effects** | Extract Method → Subclass and Override, Extract and Override Call |
| **Parameter is hard to construct** | Extract Interface, Adapt Parameter, Pass Null |
| **Hidden method (private) needs testing** | Make it protected + Subclass to expose, or move to a new class |
| **Sealed/final class can't be faked** | Adapt Parameter (wrap it), Skin and Wrap the API |
| **"Onion" parameter (needs objects that need objects)** | Extract Interface on the outermost layer, Pass Null for unused params |
| **Monster method (hundreds of lines)** | Extract Method mechanically, Introduce Sensing Variable, Break Out Method Object |

**→ Read `references/breaking-dependencies.md` for the complete techniques catalog**

## Characterization Tests — Testing What IS, Not What Should Be

A characterization test captures the ACTUAL behavior of code — bugs included.
You're not testing correctness; you're creating a safety net.

### The Algorithm

```
1. Write a test that calls the code
2. Write an assertion you KNOW will fail
3. Run it — the failure tells you the actual behavior
4. Change the assertion to match reality
5. Repeat for more behaviors
```

```kotlin
// Step 1-2: I expect this to return "fred" (it won't)
@Test fun `calculator returns expected value`() {
    val calc = LegacyCalculator()
    assertEquals("fred", calc.compute(100, -1))
}
// Step 3: Test fails → actual result is "0.0"
// Step 4: Fix the assertion
@Test fun `calculator returns 0 for negative quantity`() {
    val calc = LegacyCalculator()
    assertEquals(0.0, calc.compute(100, -1))
}
// This documents what the code DOES, not what it should do
```

**→ Read `references/characterization-tests.md` for heuristics on what and how much to test**

## This Class Is Too Big

Signs: 20+ methods, 10+ instance variables, can't describe the class in one sentence
without using "and."

### Finding Hidden Responsibilities

1. **Group methods** — which methods naturally cluster together?
2. **Look at instance variables** — which methods use which variables?
   Methods that use the same variables are likely one responsibility.
3. **Try to describe the class** — every "and" signals a responsibility to extract
4. **Scratch refactoring** — refactor fearlessly (then throw it away) just to learn
   what responsibilities exist

### Extraction Strategy

1. Identify responsibility groups using the techniques above
2. Use **Extract Class** to move each group to its own class
3. The original class becomes an orchestrator that delegates to the new classes
4. New classes are smaller, testable, and have clear single responsibilities

**→ Read `references/big-classes.md` for techniques to see and extract responsibilities**

## Monster Methods

Methods that are hundreds or thousands of lines. Two varieties:
- **Bulleted methods** — flat sequences of chunks (easier)
- **Snarled methods** — deep nesting, intertwined logic (harder)

### Tackling Strategy

1. If you have a refactoring tool with safe Extract Method → use it mechanically
2. If not, use **Preserve Signatures** — copy the exact signature to minimize typos
3. Extract small pieces from the edges, write characterization tests as you go
4. Use **Introduce Sensing Variable** when you can't sense effects
5. For the worst cases, use **Break Out Method Object** — move the entire method
   to a new class where it becomes the only method, then decompose

**→ Read `references/monster-methods.md` for step-by-step strategies**

## How Do I Know I'm Not Breaking Anything?

### Hyperaware Editing
Know exactly what each keystroke does. Every edit either changes behavior or doesn't.
Be conscious of which category you're in at all times.

### Single-Goal Editing
Do one thing at a time. Don't refactor while adding a feature. Don't fix a bug while
refactoring. Separate your commits: `refactor:` vs `feat:` vs `fix:`.

### Preserve Signatures
When extracting methods or moving code, copy-paste exact signatures. Don't retype.
Don't rename parameters during the move. Do one thing at a time.

### Lean on the Compiler
When making a change that should ripple (like changing a type), make the change and
let the compiler find every place that needs updating. Use the compiler as a search tool.

## Android/Kotlin-Specific Legacy Patterns

Android codebases have unique challenges: massive Activities/Fragments with lifecycle
coupling, tight framework dependencies, and threading complexity.

**→ Read `references/kotlin-android-legacy.md` for Android-specific strategies**

## Decision Framework

| Your Situation | Strategy | Reference |
|---------------|----------|-----------|
| Need to add a feature to messy code | Sprout Method/Class + TDD the new code | `sprout-and-wrap.md` |
| Can't instantiate the class in a test | Break constructor dependencies | `breaking-dependencies.md` |
| Can't run a specific method in a test | Extract Method + Subclass and Override | `breaking-dependencies.md` |
| Don't know what tests to write | Characterization tests | `characterization-tests.md` |
| Class has too many responsibilities | Find responsibilities → Extract Class | `big-classes.md` |
| Method is 500+ lines | Mechanical extraction from edges | `monster-methods.md` |
| Singleton is in the way | Introduce Static Setter / Extract Interface | `breaking-dependencies.md` |
| Need to replace entire module | Strangler Fig pattern | `big-classes.md` |
| Don't understand the code at all | Scratch Refactoring (throwaway) | `characterization-tests.md` |

## Common Traps

1. **The Big Rewrite** — "Let's rewrite from scratch" almost always fails. Refactor incrementally.
2. **Refactoring without tests** — Write characterization tests FIRST, always.
3. **Refactoring AND changing behavior** — Separate commits. Never do both at once.
4. **Gold plating** — Don't make it perfect. Make it better and ship.
5. **Ignoring the seam model** — If you can't find a seam, you can't test. Study the seam model.
6. **Skipping dependency analysis** — Understand what the code touches before changing it.

## Reference Files

| File | When to Read |
|------|-------------|
| `references/change-algorithm.md` | Starting any legacy code change |
| `references/seam-model.md` | Need to understand how to insert test points |
| `references/sprout-and-wrap.md` | Adding new code when you can't test old code |
| `references/breaking-dependencies.md` | Code is untestable — need to break coupling |
| `references/characterization-tests.md` | Need to lock down existing behavior before changing |
| `references/big-classes.md` | Class has too many responsibilities |
| `references/monster-methods.md` | Method is too long to safely modify |
| `references/kotlin-android-legacy.md` | Working with Android-specific legacy patterns |

**Read what's relevant to your current step. Don't front-load all references.**
