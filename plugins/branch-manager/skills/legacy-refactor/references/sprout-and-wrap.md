# Sprout and Wrap Techniques

From Chapter 6 of "Working Effectively with Legacy Code."

When you can't get existing code under test but need to add functionality, use
these techniques to add TESTED code alongside untested code.

## Sprout Method

Write new functionality in a new, tested method. Call it from the old code.

### Steps
1. Identify where the new code needs to go
2. Write a call to a new method (comment it out)
3. Identify what local variables the new method needs → make them parameters
4. Determine if it needs to return values → assign return value
5. Develop the new method using TDD
6. Uncomment the call

### Example

```kotlin
// BEFORE: Need to add duplicate filtering to this untested method
fun postEntries(entries: List<Entry>) {
    for (entry in entries) {
        entry.postDate()
    }
    transactionBundle.listManager.add(entries)
}

// AFTER: Sprout a tested method
fun postEntries(entries: List<Entry>) {
    val uniqueEntries = uniqueEntries(entries) // ← sprouted call
    for (entry in uniqueEntries) {
        entry.postDate()
    }
    transactionBundle.listManager.add(uniqueEntries)
}

// New method — developed with TDD, fully tested
fun uniqueEntries(entries: List<Entry>): List<Entry> {
    return entries.filter { entry ->
        !transactionBundle.listManager.hasEntry(entry)
    }
}
```

### When dependencies are too bad to instantiate
If the class can't be instantiated in a test, make the sprout a **companion object
function (static method)**. Pass instance variables as arguments. It's ugly but it's
tested. Later, move it back to an instance method when you get the class under test.

## Sprout Class

When you can't even create the class in a test harness, write new code in an
entirely new class and use it from the old code.

### Steps
1. Identify the new behavior
2. Create a new class with a descriptive name
3. Write the class using TDD
4. Instantiate the new class in the old code and call it

### Example

```kotlin
// Can't test QuarterlyReportGenerator (massive dependencies)
// Need to add a table header — sprout a new class

class QuarterlyReportTableHeaderGenerator {
    fun generate(): String {
        return "<tr><td>Department</td><td>Manager</td><td>Profit</td></tr>"
    }
}

// In the old untestable method, just add:
val headerGenerator = QuarterlyReportTableHeaderGenerator()
pageText += headerGenerator.generate()
```

The sprouted class may look trivial, but it's a stake in the ground for future
refactoring. Over time, more responsibilities can move from the old class to new ones.

## Wrap Method

Add behavior before/after an existing method without modifying the method body.

### Form 1: Rename and replace

```kotlin
// BEFORE
fun pay() {
    // complex payment logic
}

// AFTER
private fun dispatchPayment() {
    // exact same complex payment logic (just renamed)
}

fun pay() {
    logPayment()          // new behavior (tested)
    dispatchPayment()     // original behavior (unchanged)
}
```

Callers of `pay()` don't know anything changed. The original logic is untouched.

### Form 2: New entry point

```kotlin
fun makeLoggedPayment() {
    logPayment()  // new, tested
    pay()         // existing, untouched
}
```

Callers choose which behavior they want.

## Wrap Class (Decorator Pattern)

Create a wrapper class with the same interface that adds behavior.

```kotlin
class LoggingEmployee(private val employee: Employee) : Employee by employee {
    override fun pay() {
        logPayment()
        employee.pay()
    }
    
    private fun logPayment() { /* new tested logic */ }
}

// Usage: replace Employee with LoggingEmployee transparently
val employee: Employee = LoggingEmployee(realEmployee)
```

### When to Use Wrap Class vs Wrap Method
- **Wrap Class** when new behavior is independent and shouldn't pollute the existing class
- **Wrap Class** when the class is already too big and you want to stop the bleeding
- **Wrap Method** when the behavior naturally belongs in the same class

## Key Principles

- These techniques add tested code WITHOUT testing the old code
- They're survival techniques, not ideal design
- Use them when time pressure prevents full dependency breaking
- Over time, familiarity with the old code grows and you'll start getting it under test
- The sprouted/wrapped code becomes a roadmap for future refactoring
