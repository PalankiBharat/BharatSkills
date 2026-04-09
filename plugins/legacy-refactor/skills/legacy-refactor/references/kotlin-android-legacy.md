# Kotlin/Android Legacy Code Patterns

Applying "Working Effectively with Legacy Code" to Android-specific challenges.

## The Android Legacy Problem

Android legacy code has unique challenges:
- Activities/Fragments are framework classes with lifecycle coupling
- Can't easily construct Activities in a test harness
- UI logic, business logic, and data access are often tangled together
- Tight coupling to Android Context, Intents, Bundles, SharedPreferences
- Threading complexity (main thread, background threads, coroutines)

## Common Legacy Patterns and How to Break Them

### 1. The 2000-Line Activity/Fragment

**Problem:** All logic lives in the Activity — UI, business logic, data access.

**Strategy: Progressive Extraction**

```
Step 1: Extract business logic → ViewModel (testable without Android)
Step 2: Extract data access → Repository (testable with fakes)
Step 3: Extract UI logic → UI State mapping (testable pure functions)
Step 4: Activity becomes thin — just observes and delegates
```

Use **Sprout Class** for each extraction. The Activity delegates to new tested classes.

### 2. Direct Android Framework Dependencies

| Framework Dependency | Seam Technique |
|---------------------|---------------|
| `Context.getSharedPreferences()` | Extract interface `PreferenceStore`, inject |
| `System.currentTimeMillis()` | Extract interface `Clock`, inject `FakeClock` |
| `Log.d()` | Extract interface `Logger`, inject |
| `Toast.makeText()` | Extract to UI state that the Activity observes |
| `Intent` construction | Extract to `Navigator`/`Router` interface |
| `Bundle` reading | Extract to typed data class with factory |
| `Resources.getString()` | Pass strings as parameters, or use `StringProvider` interface |

### 3. Singletons and Static Access

```kotlin
// BEFORE: Untestable singleton
class OrderManager {
    fun process() {
        val user = UserSession.getInstance().currentUser  // Global!
        val db = DatabaseHelper.getInstance()              // Global!
        // ...
    }
}

// AFTER: Dependencies injected (Hilt or manual)
class OrderManager(
    private val userSession: UserSession,
    private val db: DatabaseHelper
) {
    fun process() {
        val user = userSession.currentUser
        // ...
    }
}
```

For singletons you can't change yet: use **Introduce Static Setter** for testing.

### 4. Callbacks / Listeners Everywhere

```kotlin
// BEFORE: Callback hell in legacy code
api.fetchUser(userId, object : Callback<User> {
    override fun onSuccess(user: User) {
        db.saveUser(user, object : Callback<Unit> {
            override fun onSuccess(unit: Unit) {
                view.showUser(user) // Untestable — deep nesting
            }
        })
    }
})

// AFTER: Wrap in suspend functions, test with coroutines
suspend fun loadAndSaveUser(userId: String): User {
    val user = api.fetchUser(userId)  // suspend
    db.saveUser(user)                 // suspend
    return user                       // testable return value
}
```

### 5. AsyncTask / Thread / Handler Legacy

Replace with structured coroutines:
```kotlin
// Extract the business logic out of the threading mechanism
// The logic should be a pure suspend function
// The threading (Dispatchers) should be injected

class DataProcessor(
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    suspend fun process(data: RawData): ProcessedData = withContext(dispatcher) {
        // Pure business logic — testable
        transformData(data)
    }
}

// In tests: use TestDispatcher
```

## Practical Refactoring Workflow for Android

### Phase 1: Stop the Bleeding
- Use **Sprout Class** for all new features (new ViewModel, UseCase, Repository)
- Don't add more code to the God Activity/Fragment
- Each sprint, write characterization tests for code you're about to change

### Phase 2: Extract ViewModel
1. Identify what state the UI needs (create a `UiState` data class)
2. Move logic from Activity to ViewModel, one method at a time
3. Use `Subclass and Override` to break Android dependencies
4. Write tests for each moved method before and after the move
5. Activity observes ViewModel state via StateFlow/LiveData

### Phase 3: Extract Repository
1. Identify all data access (network, DB, preferences)
2. Create Repository interfaces
3. Move data access behind Repository, inject with Hilt/manual DI
4. Use fake repositories in ViewModel tests

### Phase 4: Extract UseCases (if needed)
1. If ViewModel is getting big, extract domain logic to UseCases
2. Each UseCase does one thing, takes Repository as dependency
3. Fully testable with fake repositories

## Key Android Seams

```kotlin
// Constructor injection seam (Hilt)
@HiltViewModel
class OrderViewModel @Inject constructor(
    private val repository: OrderRepository,  // ← seam
    private val validator: OrderValidator      // ← seam
) : ViewModel()

// Factory seam (manual DI)
class OrderViewModel(
    private val repository: OrderRepository
) : ViewModel() {
    class Factory(private val repo: OrderRepository) : ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            return OrderViewModel(repo) as T
        }
    }
}
```

## Testing Strategy

| Layer | Test Type | Fakes Needed |
|-------|-----------|-------------|
| ViewModel | Unit test | Fake Repository, TestDispatcher |
| UseCase | Unit test | Fake Repository |
| Repository | Unit test | Mock API, In-memory Room DB |
| Activity/Fragment | UI test (Espresso) | Fake ViewModel (if possible) |

## The Boy Scout Rule for Android

Every time you touch legacy code:
- Extract one method from the Activity to the ViewModel
- Replace one direct dependency with an injected interface
- Write one characterization test for the code you're changing
- Delete one block of dead/commented-out code

Small moves compound. Within months, the codebase transforms.
