# The Legacy Code Change Algorithm

From Chapter 2 of "Working Effectively with Legacy Code."

## The Two Ways to Change Software

**Edit and Pray** — Plan carefully, make changes, then poke around hoping nothing broke.
This is the industry standard. It's gambling.

**Cover and Modify** — Put a safety net of tests around the code BEFORE changing it.
Then make changes with rapid feedback. This is working with a safety net.

## The Algorithm

### 1. Identify Change Points

Where exactly do you need to make changes? This depends on your architecture.
If you don't understand the code well enough, use these techniques:
- **Notes/Sketching** — Draw diagrams of class relationships
- **Listing Markup** — Print code, annotate with markers and notes
- **Scratch Refactoring** — Refactor the code just to understand it, then throw away ALL changes

### 2. Find Test Points

Where can you write tests to cover your changes?
- Look for **interception points** — places where you can detect effects of the change
- Find **pinch points** — narrow places where tests cover many changes at once
- Prefer testing closest to the change, but sometimes a higher-level test is easier

### 3. Break Dependencies

Dependencies are the #1 impediment to testing. Two reasons to break them:
- **Sensing** — You need to see what the code does but can't
- **Separation** — You can't even run the code in isolation

Use the dependency-breaking techniques catalog. Key principle: these initial
refactorings should be **very conservative** — minimal edits, preserve signatures,
lean on the compiler. They may leave scars, but you can heal them once tests are in place.

### 4. Write Tests

Write **characterization tests** that document CURRENT behavior:
1. Call the code in a test
2. Assert something you know is wrong
3. Run it → the failure shows actual behavior
4. Fix the assertion to match reality
5. Repeat

These are NOT correctness tests. They're behavior-preservation tests.

### 5. Make Changes and Refactor

NOW you can safely change code:
- Use **TDD** for new behavior (write failing test → make it pass → refactor)
- Use **Programming by Difference** (subclass, override, test, then fold back)
- Apply the **Boy Scout Rule** — leave code cleaner than you found it

The extended TDD cycle for legacy code:
```
0. Get the class under test (this is the hard part)
1. Write a failing test case
2. Get it to compile
3. Make it pass (try not to change existing code)
4. Remove duplication
5. Repeat
```

## The Virtuous Cycle

Each change episode should produce:
- New/modified functionality
- New tests covering the changed area

Over time, tested areas grow from islands into continents. Work in tested areas
is dramatically faster, safer, and more enjoyable.

## When Dependency Breaking Looks Ugly

Breaking dependencies sometimes produces ugly code — extra parameters,
weird interfaces, non-ideal naming. That's okay.

> "When you break dependencies in legacy code, you often have to suspend your
> sense of aesthetics a bit. They are like incision points in surgery: there might
> be a scar left in your code after your work, but everything beneath it can get
> better. If later you can cover code around the point where you broke the
> dependencies, you can heal that scar, too."

The goal is to create seams — the cleanup comes after you have tests.
