# Dependency-Breaking Techniques Catalog

From Chapters 9, 10, and 25 of "Working Effectively with Legacy Code."

These techniques are refactorings designed to be done WITHOUT tests, to GET tests
in place. They preserve behavior but may produce ugly code. The cleanup comes later.

## Parameterize Constructor

**Problem:** Constructor creates dependencies internally (hidden dependencies).

**Fix:** Pass the dependency in through the constructor instead.

```kotlin
// BEFORE: Hidden dependency
class MailingListDispatcher {
    private val service = MailService() // Can't fake this!
    init {
        service.connect()
        service.register(this, CLIENT_TYPE)
    }
}

// AFTER: Dependency is explicit and replaceable
class MailingListDispatcher(private val service: MailService) {
    constructor() : this(MailService()) // Preserve old behavior for callers
    init {
        service.connect()
        service.register(this, CLIENT_TYPE)
    }
}
// Now in tests: MailingListDispatcher(FakeMailService())
```

Key: Add a default constructor that delegates to the new one. Existing callers don't change.

## Extract Interface

**Problem:** Code depends on a concrete class that's hard to construct or has side effects.

**Fix:** Create an interface with the methods you need, have the class implement it,
inject fakes via the interface.

```kotlin
// BEFORE
class CreditValidator(private val connection: RGHConnection, ...)

// AFTER
interface IRGHConnection {
    fun rfdiReportFor(id: Int): RFDIReport
    fun actioReportFor(customerId: Int): ACTIOReport
}

class RGHConnection(...) : IRGHConnection { ... }
class FakeConnection : IRGHConnection {
    var report: RFDIReport? = null
    override fun rfdiReportFor(id: Int) = report!!
    override fun actioReportFor(customerId: Int) = error("unused")
}
// CreditValidator now accepts IRGHConnection
```

## Extract Implementer

Like Extract Interface, but you keep the original class name for the interface and
rename the concrete class. Useful in C++ or when you have many existing references.

## Subclass and Override Method

**Problem:** A method does something you can't tolerate in tests (DB calls, network, UI).

**Fix:** Make the method protected/open, create a test subclass that overrides it.

```kotlin
// BEFORE: Can't test because validate() hits the database
open class OriginationPermit : FacilityPermit() {
    open fun validate() {
        // connects to database, queries, sets validation flag
    }
}

// IN TESTS: Override the problematic method
class FakeOriginationPermit : OriginationPermit() {
    override fun validate() {
        becomeValid() // Just set the flag directly
    }
}
```

This is one of the most versatile techniques. Use it when you need to neutralize
one specific behavior within a class.

## Extract and Override Call

**Problem:** A single problematic call is buried inside a method you want to test.

**Fix:** Extract that call into its own method, then override it in tests.

```kotlin
// BEFORE
fun processTransaction(txn: Transaction) {
    // ... logic ...
    val result = creditService.validate(txn) // ← problematic call
    // ... more logic ...
}

// STEP 1: Extract the call
open fun processTransaction(txn: Transaction) {
    // ... logic ...
    val result = validateCredit(txn)
    // ... more logic ...
}
protected open fun validateCredit(txn: Transaction): Result {
    return creditService.validate(txn)
}

// STEP 2: Override in test subclass
class TestableProcessor : TransactionProcessor() {
    var fakeResult: Result = Result.APPROVED
    override fun validateCredit(txn: Transaction) = fakeResult
}
```

## Introduce Static Setter (for Singletons)

**Problem:** Singleton prevents testing — you can't replace the instance.

**Fix:** Add a static setter that allows replacing the singleton in tests.

```kotlin
class PermitRepository private constructor() {
    companion object {
        private var instance: PermitRepository? = null
        
        fun getInstance(): PermitRepository {
            if (instance == null) instance = PermitRepository()
            return instance!!
        }
        
        // NEW: Allow tests to replace the singleton
        @VisibleForTesting
        fun setTestingInstance(newInstance: PermitRepository) {
            instance = newInstance
        }
        
        @VisibleForTesting
        fun resetForTesting() { instance = null }
    }
}

// In tests:
val fakeRepo = TestingPermitRepository()
PermitRepository.setTestingInstance(fakeRepo)
```

Also make the constructor protected (not private) so test subclasses can be created.

## Adapt Parameter

**Problem:** Method parameter is a framework/library type that's hard to construct
(HttpServletRequest, Bundle, Intent, etc.)

**Fix:** Create a thin wrapper interface, wrap the real parameter in production,
use a fake in tests.

```kotlin
// BEFORE: Can't create HttpServletRequest in tests
fun populate(request: HttpServletRequest) {
    val values = request.getParameterValues(pageStateName)
    // ...
}

// AFTER: Wrap behind your own interface
interface ParameterSource {
    fun getParameterForName(name: String): String?
}

class HttpParameterSource(private val request: HttpServletRequest) : ParameterSource {
    override fun getParameterForName(name: String) = request.getParameterValues(name)?.firstOrNull()
}

class FakeParameterSource(var value: String? = null) : ParameterSource {
    override fun getParameterForName(name: String) = value
}
```

## Pass Null

**Problem:** Constructor requires parameters you don't need for the test.

**Fix:** Pass null for parameters you don't use. If the test crashes, you'll find out
which parameters actually matter.

```kotlin
// In tests — only need to test getValidationPercent, doesn't use CreditMaster
val validator = CreditValidator(fakeConnection, null, "a")
```

Don't use this in production code. Only in tests. Java/Kotlin will throw NPE if
the null parameter is actually used, which tells you exactly what you need to provide.

## Break Out Method Object

**Problem:** Monster method with too many local variables to extract methods from.

**Fix:** Move the entire method to a new class. Local variables become fields.
The method becomes the class's main (and only) method. Then decompose.

```kotlin
// BEFORE: 500-line method with 20 local variables
class OrderProcessor {
    fun processOrder(order: Order) {
        // 500 lines of intertwined logic...
    }
}

// AFTER: Method becomes a class
class OrderProcessingCommand(
    private val processor: OrderProcessor,
    private val order: Order
) {
    // Former local variables become fields
    private var subtotal = 0.0
    private var taxRate = 0.0
    // ...
    
    fun execute() {
        // Same 500 lines, but now you can extract methods freely
        // because local variables are fields accessible everywhere
    }
}
```

## Preserve Signatures

When doing ANY of these transformations, copy-paste method signatures exactly.
Don't retype. Don't rename parameters. Don't change types. Make the absolute
minimum mechanical change. Every manual keystroke is a chance for a typo-induced bug.

## Lean on the Compiler

When you change a type or remove a method, let the compiler find every place
that needs updating. Use the compiler as a search tool, not just a build tool.

## Summary of Technique Selection

| You Can't... | Try These (in order) |
|-------------|---------------------|
| Create the object | Parameterize Constructor → Extract Interface → Pass Null |
| Call a method | Subclass and Override → Extract and Override Call → Expose Static Method |
| Sense effects | Extract Interface (for fakes) → Introduce Sensing Variable |
| Break a singleton | Introduce Static Setter → Extract Interface on singleton |
| Fake a library type | Adapt Parameter → Skin and Wrap the API |
| Decompose a monster | Break Out Method Object → mechanical Extract Method |
