# Monster Methods

From Chapter 22 of "Working Effectively with Legacy Code."

## Varieties of Monsters

### Bulleted Methods
Nearly flat — a sequence of code chunks, minimal nesting. Looks like a bullet list.
Easier to decompose because you can see the sections.

### Snarled Methods  
Deep nesting, complex conditionals, intertwined logic. Much harder.
Local variables declared in one section and used in distant sections.

## Strategy: Mechanical Extraction

### With an Automated Refactoring Tool (IDE)
1. Find a chunk of code that does something identifiable
2. Use IDE's Extract Method refactoring (it checks for safety)
3. Name the extracted method descriptively
4. Run characterization tests after each extraction
5. Repeat from the edges inward

### Without an Automated Tool
1. **Preserve Signatures** — copy-paste exact parameter types and names
2. Introduce a sensing variable if you need to verify behavior
3. Extract from the outside in — start with obvious, self-contained chunks
4. Run tests (or at least compile) after every single extraction
5. If anything breaks, revert immediately

## Tackling Steps

### 1. Find Coupling Points
Look for local variables that are used across multiple sections.
These create "tangling" that prevents clean extraction.

### 2. Extract from the Edges
Start with code at the beginning or end of the method that's relatively
independent. These extractions are lowest risk.

### 3. Handle the Tangled Middle
For intertwined sections:
- **Introduce Sensing Variable** — add a variable to capture intermediate state
- **Break Out Method Object** — when there are too many locals to pass as params

## Break Out Method Object

When a method has so many local variables that extraction is impractical,
move the entire method to its own class:

```kotlin
// BEFORE: Monster method with 15 local variables
class OrderProcessor {
    fun processOrder(order: Order) {
        var subtotal = 0.0
        var taxRate = 0.0
        var discount = 0.0
        var shippingCost = 0.0
        // ... 12 more locals ...
        // ... 500 lines using all these locals ...
    }
}

// AFTER: Method becomes a class — locals become fields
class OrderProcessingCommand(
    private val processor: OrderProcessor,
    private val order: Order
) {
    private var subtotal = 0.0
    private var taxRate = 0.0
    private var discount = 0.0
    private var shippingCost = 0.0
    // All former locals are now fields
    
    fun run() {
        // Same logic, but now Extract Method works freely
        // because fields are accessible from any extracted method
        calculateSubtotal()
        applyDiscounts()
        calculateTax()
        calculateShipping()
        finalizeOrder()
    }
    
    private fun calculateSubtotal() { /* extracted chunk */ }
    private fun applyDiscounts() { /* extracted chunk */ }
    // ...
}

// In original class:
fun processOrder(order: Order) {
    OrderProcessingCommand(this, order).run()
}
```

## The Introduce Sensing Variable Technique

When you can't sense what a chunk of code does:

```kotlin
// Add a variable to capture state for testing
var lastCalculatedTax = 0.0  // sensing variable

fun calculateTotal(items: List<Item>): Double {
    // ... complex logic ...
    val tax = computeTax(subtotal)
    lastCalculatedTax = tax  // capture for testing
    // ...
}
```

Use sensing variables temporarily during refactoring. Remove them once you have
proper tests with proper seams.

## Safety Practices for Monster Methods

1. **Single-Goal Editing** — only extract, or only add, never both at once
2. **Compile after every change** — catch typos immediately
3. **Run tests after every extraction** — catch behavior changes immediately
4. **Use version control** — commit after each successful extraction
5. **Work in pairs** — four eyes catch what two miss
6. **Don't rename during extraction** — preserve names exactly, rename later
7. **Mark progress** — annotate with comments or TODO markers as you go

## When the Method Can't Be Extracted Easily

Sometimes monster methods are so tangled that mechanical extraction fails.
In these cases:
1. Write characterization tests for the overall method behavior
2. Use Sprout Method — add new behavior in new tested methods
3. Over time, the old logic shrinks as new code grows around it
4. Eventually enough is tested to start extracting from the original
