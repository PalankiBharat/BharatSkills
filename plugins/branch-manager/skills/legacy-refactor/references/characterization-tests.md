# Characterization Tests

From Chapter 13 of "Working Effectively with Legacy Code."

## What Are Characterization Tests?

Tests that document what code ACTUALLY does — not what it should do.
They capture current behavior, bugs included.

Their purpose: create a safety net so you know immediately if a refactoring changes behavior.

## The Algorithm

```
1. Use the code in a test harness
2. Write an assertion you KNOW will fail
3. Run it — the failure message tells you actual behavior
4. Change the assertion to match reality
5. Repeat for more inputs/paths
```

### Example

```kotlin
@Test fun `generator output for base row`() {
    val generator = PageGenerator()
    generator.assoc(RowMappings.getRow(Page.BASE_ROW))
    // Step 2: Assert something wrong
    assertEquals("fred", generator.generate())
}
// Step 3: Failure says actual output is "<node><carry>1.1 vectrai</carry></node>"
// Step 4: Fix the assertion:
@Test fun `generator output for base row`() {
    val generator = PageGenerator()
    generator.assoc(RowMappings.getRow(Page.BASE_ROW))
    assertEquals("<node><carry>1.1 vectrai</carry></node>", generator.generate())
}
```

## Heuristic: What to Test

You can't test everything. Focus on:

1. **The code you're about to change** — this is the area at risk
2. **The main path** — what happens under normal conditions
3. **Boundary conditions** — null inputs, empty collections, zero values, negatives
4. **Error paths** — what happens when things go wrong

### How much is enough?

Write characterization tests until you feel confident that you understand the
behavior of the code you're changing. You don't need 100% coverage of the
entire class — just enough around the change point.

## Characterizing Classes

To characterize a class:
1. Look at the class under test
2. Find the most central/important methods
3. Write tests for them using the assertion-failure technique
4. When you find confusing behavior, write more tests to understand it
5. Stop when you have enough understanding to make your change safely

## Targeted Testing

When the change you need to make is small, write targeted tests:
1. Write tests for the specific method you're changing
2. Write tests for methods that USE the method you're changing (callers)
3. Cover the specific conditions that your change will affect

## Scratch Refactoring

When you can't understand the code:
1. Check out a fresh branch
2. Start refactoring — extract methods, rename variables, reorganize
3. As you refactor, you'll understand the code deeply
4. **THROW AWAY all changes** (do NOT commit)
5. Now you understand the code well enough to write real characterization tests

Scratch refactoring is purely for learning. It's like taking notes while reading.

## Testing Patterns

### Testing methods that return values
```kotlin
@Test fun `compute returns expected value`() {
    val result = calculator.compute(input)
    assertEquals(actualResult, result) // discovered via failure
}
```

### Testing methods with side effects
```kotlin
@Test fun `process updates the internal state`() {
    processor.process(input)
    assertEquals(expectedState, processor.state) // check observable state
}
```

### Testing methods that call other objects (need fakes)
```kotlin
@Test fun `service forwards to repository`() {
    val fakeRepo = FakeRepository()
    val service = MyService(fakeRepo)
    service.save(item)
    assertEquals(item, fakeRepo.lastSaved) // sense through the fake
}
```

## Key Principles

- Characterization tests are NOT about finding bugs
- They document what the code DOES, not what it SHOULD do
- If you find a bug while characterizing, note it but assert the current (buggy) behavior
- Fix bugs in a separate step with separate tests
- These tests become your refactoring safety net
- Delete them only when you've replaced them with proper unit tests
