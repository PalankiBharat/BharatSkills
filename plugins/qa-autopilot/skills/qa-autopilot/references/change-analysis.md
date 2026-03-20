# Change Analysis Framework

## Step-by-Step Analysis Process

### 1. Categorize Every Changed File

For each file in the diff, categorize it:

```
| File | Layer | Feature | Change Type | Blast Radius |
|------|-------|---------|-------------|--------------|
| OrderRepository.kt | Data | Order Entry | Modified | High — 3 ViewModels depend on it |
| Theme.kt | UI/Theme | Global | Modified | Medium — all screens use theme |
| LoginScreen.kt | UI | Auth | New | Low — isolated feature |
```

**Layer classification guide:**

| Path pattern | Layer |
|-------------|-------|
| `*/ui/*`, `*/screen/*`, `*/compose/*`, `*Screen.kt`, `*Fragment.kt`, `*Activity.kt` | UI/Presentation |
| `*/viewmodel/*`, `*ViewModel.kt` | ViewModel |
| `*/usecase/*`, `*/domain/*`, `*UseCase.kt` | Domain/UseCase |
| `*/repository/*`, `*Repository.kt`, `*RepositoryImpl.kt` | Repository |
| `*/model/*`, `*/entity/*`, `*/dto/*`, `*Model.kt`, `*Entity.kt` | Data Model |
| `*/di/*`, `*Module.kt`, `*Component.kt` | Dependency Injection |
| `*/navigation/*`, `*NavGraph.kt`, `*Route.kt` | Navigation |
| `*/network/*`, `*/api/*`, `*Api.kt`, `*Service.kt` | Network |
| `*/db/*`, `*/dao/*`, `*Dao.kt`, `*Database.kt` | Local Storage |
| `build.gradle*`, `*.toml`, `*.properties` | Build/Config |
| `*/util/*`, `*/ext/*`, `*/helper/*` | Utility |
| `*Test.kt`, `*Spec.kt` | Test |
| `*.xml`, `*.json` (in res/) | Resources |

### 2. Understand Change Intent

For each file, read the actual diff and classify:

- **New feature**: New files, new classes, new screens
- **Bug fix**: Small targeted changes, null checks added, condition fixes
- **Refactor**: Renamed classes, extracted methods, moved code, no behavior change
- **Enhancement**: Added parameters, new fields, extended functionality
- **UI change**: Layout modifications, styling, Compose recomposition changes
- **Data model change**: New/removed fields, migration, serialization changes
- **Config change**: Build config, feature flags, environment variables

### 3. Build the Impact Graph

Start from changed files and trace UPWARD through the dependency chain:

```
Changed File (Layer N)
  └─ Consumed by (Layer N+1)
       └─ Consumed by (Layer N+2)
            └─ ... until you reach UI layer
```

**Commands to trace dependencies:**

```bash
# Find all direct usages of a changed class
CLASS_NAME="OrderRepository"
grep -rn "$CLASS_NAME" --include="*.kt" app/src/ | grep -v "build/" | grep -v "$CLASS_NAME.kt"

# Find all files that import from the changed package
PACKAGE="com.app.data.repository"
grep -rn "import $PACKAGE" --include="*.kt" app/src/

# For Hilt/DI changes, find who injects the changed dependency
grep -rn "@Inject.*$CLASS_NAME\|$CLASS_NAME.*@Inject" --include="*.kt" app/src/

# For data model changes, find all serialization/deserialization points
MODEL_NAME="OrderModel"
grep -rn "$MODEL_NAME" --include="*.kt" app/src/ | grep -v "build/"
```

### 4. Identify UI Touchpoints

Every chain must end at a UI touchpoint (screen the user can see and interact with). List every screen that is directly or transitively affected:

```
Affected Screens:
1. OrderEntryScreen — Direct: ViewModel changed
2. OrderHistoryScreen — Indirect: Repository method signature changed
3. DashboardScreen — Indirect: Uses same data model
```

### 5. Classify Risk Level

| Risk | Criteria |
|------|----------|
| 🔴 Critical | Core business logic, data persistence, payment, auth, data model changes with migrations |
| 🟠 High | Primary user flows, ViewModel logic, navigation changes, API contract changes |
| 🟡 Medium | Secondary flows, UI layout changes, error handling improvements |
| 🟢 Low | Cosmetic, text changes, test-only changes, build config |

### 6. Check for Hidden Risks

These are easy to miss:

- **Compose recomposition**: Did a `remember` or `key` change? Could cause unexpected recompositions
- **Flow/StateFlow changes**: New emissions could trigger UI updates in unexpected places
- **Hilt scope changes**: Changing `@Singleton` to `@ViewModelScoped` changes lifecycle
- **Serialization changes**: Adding/removing `@SerialName`, changing field names breaks API/DB
- **Migration missing**: Data model changed but no Room migration added
- **ProGuard/R8**: New reflection or serialization that needs keep rules
- **Thread safety**: Changed shared mutable state without synchronization

### 7. Check for Performance Risks

Performance regressions are invisible in code review but painfully visible to users:

- **Missing `key` in LazyColumn/LazyRow**: Causes full list recomposition on any data change. Diff shows `LazyColumn { items(list)` without `key = { it.id }` — this is a P0 performance issue for lists > 20 items
- **Heavy computation in @Composable**: `filter`, `sort`, `map` on large collections inside a Composable body (not wrapped in `remember`) re-executes on every recomposition
- **N+1 query patterns**: Loop calling a Room DAO instead of a single query with IN clause or JOIN. Scan for `forEach { dao.getById(it) }` patterns
- **Unbounded Flow collection**: `StateFlow` with `collectAsState()` on a flow that emits every tick (e.g., real-time price updates at 100ms) without `conflate()` or `sample()` causes 10+ recompositions/second
- **Main thread blocking**: Network/DB calls without `withContext(Dispatchers.IO)` or `suspend` — look for bare `dao.query()` or `retrofitService.call()` not in a coroutine
- **Image loading without size constraints**: `AsyncImage(url)` or `Coil.load()` without `size()` modifier loads full-resolution images into memory
- **Missing pagination**: New list screen fetching ALL items from API/DB instead of paginated chunks. Any `getAll()` or `SELECT *` without `LIMIT` on user-facing data
- **Animation on every frame**: Custom `Canvas` drawing or `drawBehind` modifier doing expensive operations (bitmap decode, path computation) inside the draw call
- **Object allocation in tight loops**: Creating new objects inside `LazyColumn.items {}` block (new formatters, new date parsers) instead of hoisting them out

**Commands to detect performance risks:**

```bash
# Find LazyColumn/LazyRow without key parameter
grep -n "LazyColumn\|LazyRow" --include="*.kt" -A5 app/src/ | grep -B5 "items(" | grep -v "key ="

# Find collectAsState without conflate/sample
grep -n "collectAsState\|collectAsStateWithLifecycle" --include="*.kt" app/src/

# Find potential main thread DB/network calls
grep -rn "\.execute()\|\.getAll()\|\.query(" --include="*.kt" app/src/ | grep -v "withContext\|Dispatchers\|suspend"

# Find missing Dispatchers.IO
grep -n "GlobalScope\|runBlocking" --include="*.kt" app/src/
```
