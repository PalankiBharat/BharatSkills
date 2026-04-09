# This Class Is Too Big

From Chapter 20 of "Working Effectively with Legacy Code."

## Signs of a Too-Big Class

- 20+ methods, 10+ instance variables
- You can't describe it without "and" ("it manages orders AND sends emails AND...")
- Multiple developers need to change it in the same sprint
- It takes a long time just to understand what the class does
- Variables are used by only some methods (low cohesion)

## Seeing Responsibilities

### Method Grouping
List all methods. Group them by what they conceptually do. Each group is a responsibility.

```
evaluate          → Evaluation
branchingExpr     → Evaluation
causalExpr        → Evaluation

addVariable       → Variable Management

nextTerm          → Parsing/Tokenizing
hasMoreTerms      → Parsing/Tokenizing
```

### Instance Variable Clustering
Draw a matrix: methods on one axis, instance variables on the other.
Mark which methods use which variables. Clusters = responsibilities.

Methods that share the same variables belong to the same responsibility.
Methods that DON'T share variables with other methods → separate responsibility.

### The "Describe It" Technique
Try to describe the class in one sentence. Every time you say "and", that's
likely a separate responsibility that could be its own class.

"This class manages user authentication AND sends notification emails AND
logs activity AND validates input."
→ UserAuthenticator, EmailNotifier, ActivityLogger, InputValidator

### Feature Sketches
Draw the internal dependencies: which methods call which other methods,
which methods use which variables. Look for clusters that are relatively
independent of each other.

### Scratch Refactoring
When you can't see the responsibilities, do a throwaway refactoring:
1. Branch from main
2. Aggressively extract classes and methods
3. See what groupings emerge
4. Throw away ALL changes
5. Now do it for real, with tests

## Extraction Strategy

### 1. Interface Segregation First
Before moving code, create interfaces for the different groups of methods.
This helps callers depend on only the methods they need.

### 2. Extract Class
Move a responsibility group to a new class:

```kotlin
// BEFORE: God class
class OrderProcessor {
    // Order validation methods
    fun validateOrder(order: Order): Boolean { ... }
    fun checkInventory(items: List<Item>): Boolean { ... }
    
    // Payment methods
    fun chargeCard(card: CreditCard, amount: Double): Boolean { ... }
    fun processRefund(orderId: String): Boolean { ... }
    
    // Notification methods
    fun sendConfirmationEmail(order: Order) { ... }
    fun sendShippingNotification(order: Order) { ... }
}

// AFTER: Extracted classes
class OrderValidator {
    fun validateOrder(order: Order): Boolean { ... }
    fun checkInventory(items: List<Item>): Boolean { ... }
}

class PaymentProcessor {
    fun chargeCard(card: CreditCard, amount: Double): Boolean { ... }
    fun processRefund(orderId: String): Boolean { ... }
}

class OrderNotifier {
    fun sendConfirmationEmail(order: Order) { ... }
    fun sendShippingNotification(order: Order) { ... }
}

// OrderProcessor becomes an orchestrator
class OrderProcessor(
    private val validator: OrderValidator,
    private val payment: PaymentProcessor,
    private val notifier: OrderNotifier
) {
    fun process(order: Order) {
        validator.validateOrder(order)
        payment.chargeCard(order.card, order.total)
        notifier.sendConfirmationEmail(order)
    }
}
```

### 3. After Extract Class
The original class delegates to smaller classes. Over time, callers can depend
on the smaller classes directly, and the original class may shrink to nothing.

## The Strangler Fig Pattern (for modules/systems)

When an entire module needs replacement:
1. Build new functionality alongside the old
2. Route calls from old → new, one feature at a time
3. Eventually old code has no callers → delete it

Never rewrite from scratch. Always strangle incrementally.

## Prevention: Sprout Class

When adding new behavior to an already-large class, use **Sprout Class** instead
of adding more methods. This stops the bleeding and creates a roadmap for
future extraction.

## Key Principles

- The biggest obstacle to improving large code is believing it will always be ugly
- Small improvements compound — extract one class today, another next week
- Use Sprout Class for new code to stop making things worse
- When you've refactored a few classes out, the remaining class becomes manageable
- Name the new classes well — good names reveal design opportunities
