# KMM Dependency Replacement Map

Project-agnostic reference for every common Android library and its KMM replacement. Each entry includes: library, replacement, rationale, and before/after code examples.

> **Version note:** Always verify library versions via Context7, find-docs, or web search. Version numbers in this file may be outdated.

---

## Table of Contents

- [Networking: Retrofit + OkHttp → Ktor Client](#networking-retrofit--okhttp--ktor-client)
- [Serialization: Gson / Moshi → kotlinx.serialization](#serialization-gson--moshi--kotlinxserialization)
  - [Consumer Impact: ApiClient Generic Type Changes](#consumer-impact-apiclient-generic-type-changes)
- [Dependency Injection: Hilt / Dagger → Koin 4](#dependency-injection-hilt--dagger--koin-4)
- [Preferences: SharedPreferences → Multiplatform-Settings](#preferences-sharedpreferences--multiplatform-settings-russhwolf)
- [Database: Room → Room 2.7+ KMP or SQLDelight](#database-room--room-27-kmp-or-sqldelight)
- [Storage: DataStore → DataStore KMP](#storage-datastore--datastore-kmp)
- [Reactive: RxJava → kotlinx-coroutines + Flow](#reactive-rxjava--kotlinx-coroutines--flow)
- [Date/Time: java.time → kotlinx-datetime](#datetime-javatime--kotlinx-datetime)
- [Testing: JUnit → kotlin-test](#testing-junit--kotlin-test)
- [Mocking: MockK / Mockito → Hand-written Fakes](#mocking-mockk--mockito--hand-written-fakes)
- [Image Loading: Coil 2 → Coil 3](#image-loading-coil-2--coil-3)
- [LiveData → StateFlow](#livedata--stateflow)
- [Logging: Android Log → Napier](#logging-android-log--napier)
- [Library Discovery](#library-discovery)
- [Platform API Gotchas (commonMain)](#platform-api-gotchas-commonmain)

---

## Networking: Retrofit + OkHttp → Ktor Client

**Replacement:** `io.ktor:ktor-client-core`, `io.ktor:ktor-client-okhttp` (Android), `io.ktor:ktor-client-darwin` (iOS)

**Why:** Retrofit is JVM-only and relies on Java reflection. Ktor is Kotlin-native, coroutine-first, and supports all KMP targets via swappable engines.

**Platform engines via expect/actual:**

```kotlin
// commonMain
expect fun httpClient(): HttpClient

// androidMain
actual fun httpClient(): HttpClient = HttpClient(OkHttp) {
    install(ContentNegotiation) { json() }
}

// iosMain
actual fun httpClient(): HttpClient = HttpClient(Darwin) {
    install(ContentNegotiation) { json() }
}
```

**Before (Retrofit + OkHttp):**

```kotlin
interface ApiService {
    @GET("users/{id}")
    suspend fun getUser(@Path("id") id: String): User

    @POST("users")
    suspend fun createUser(@Body user: CreateUserRequest): User
}

val okHttpClient = OkHttpClient.Builder()
    .addInterceptor(AuthInterceptor())
    .build()

val retrofit = Retrofit.Builder()
    .baseUrl("https://api.example.com/")
    .client(okHttpClient)
    .addConverterFactory(GsonConverterFactory.create())
    .build()

val api = retrofit.create(ApiService::class.java)
```

**After (Ktor):**

```kotlin
// commonMain
class ApiService(private val client: HttpClient) {
    suspend fun getUser(id: String): User =
        client.get("https://api.example.com/users/$id").body()

    suspend fun createUser(user: CreateUserRequest): User =
        client.post("https://api.example.com/users") {
            contentType(ContentType.Application.Json)
            setBody(user)
        }.body()
}

// HTTP client with auth header
val client = HttpClient(engine) {
    install(ContentNegotiation) {
        json(Json { ignoreUnknownKeys = true })
    }
    install(DefaultRequest) {
        header("Authorization", "Bearer $token")
    }
}
```

**Alternative:** [Ktorfit](https://foso.github.io/Ktorfit/) wraps Ktor with Retrofit-style annotations if you prefer that interface pattern.

---

## Serialization: Gson / Moshi → kotlinx.serialization

**Replacement:** `org.jetbrains.kotlinx:kotlinx-serialization-json`

**Why:** Gson and Moshi use Java reflection, which is unavailable on Kotlin/Native. kotlinx.serialization uses compile-time code generation and works across all KMP targets.

**Before (Gson):**

```kotlin
data class User(
    @SerializedName("user_id") val id: String,
    @SerializedName("full_name") val name: String,
    val email: String
)

val gson = Gson()
val user = gson.fromJson(jsonString, User::class.java)
val json = gson.toJson(user)
```

**Before (Moshi):**

```kotlin
@JsonClass(generateAdapter = true)
data class User(
    @Json(name = "user_id") val id: String,
    val name: String
)

val moshi = Moshi.Builder().build()
val adapter = moshi.adapter(User::class.java)
val user = adapter.fromJson(jsonString)
```

**After (kotlinx.serialization):**

```kotlin
@Serializable
data class User(
    @SerialName("user_id") val id: String,
    @SerialName("full_name") val name: String,
    val email: String
)

val json = Json { ignoreUnknownKeys = true }
val user = json.decodeFromString<User>(jsonString)
val encoded = json.encodeToString(user)
```

### Consumer Impact: ApiClient Generic Type Changes

When SDK remote stores migrate from Gson (`JSONObject`) to kotlinx-serialization (`JsonObject`), the `ApiClient<Request, Response>` generic parameter types change:

**Before (consumer DI):**
```kotlin
@Provides fun provideApiClient(httpClient: HttpClient): ApiClient<Map<String, String>, JSONObject> =
    KtorApiClientImpl(httpClient, StringToJSONMapper())
```

**After (consumer DI):**
```kotlin
@Provides fun provideApiClient(httpClient: HttpClient): ApiClient<Map<String, String>, JsonObject> =
    KtorApiClientImpl(httpClient, StringToJsonObjectMapper())
```

Changes:
- `org.json.JSONObject` → `kotlinx.serialization.json.JsonObject` in generic params
- Inner mapper classes may be renamed (e.g., `StringToJSONMapper` → `StringToJsonObjectMapper`)
- Consumer DI modules that construct these ApiClient instances need updating

**Phase 6 action:** Grep consumer DI for `ApiClient<.*JSONObject>` and update to `JsonObject`.

---

## Dependency Injection: Hilt / Dagger → Koin 4

**Replacement:** `io.insert-koin:koin-core`, `io.insert-koin:koin-android`, `io.insert-koin:koin-compose`

**Why:** Hilt and Dagger rely on annotation processing (kapt/ksp) with Android-specific generated code. Koin 4 is fully KMP-aware with a runtime DSL that works in commonMain.

**Before (Hilt):**

```kotlin
@HiltViewModel
class UserViewModel @Inject constructor(
    private val repository: UserRepository,
    private val analytics: Analytics
) : ViewModel()

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides @Singleton
    fun provideUserRepository(api: ApiService): UserRepository =
        UserRepositoryImpl(api)
}
```

**After (Koin 4):**

```kotlin
// commonMain — shared module
val commonModule = module {
    single<UserRepository> { UserRepositoryImpl(get()) }
    factory { UserViewModel(get(), get()) }
}

// androidMain — platform module
val androidModule = module {
    single<Analytics> { FirebaseAnalytics(androidContext()) }
}

// Android Application
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidContext(this@App)
            modules(commonModule, androidModule)
        }
    }
}

// Composable
@Composable
fun UserScreen(viewModel: UserViewModel = koinViewModel()) { ... }
```

---

## Preferences: SharedPreferences → Multiplatform-Settings (russhwolf)

**Replacement:** `com.russhwolf:multiplatform-settings`

**Why:** SharedPreferences is Android-only. Multiplatform-Settings wraps NSUserDefaults (iOS) and SharedPreferences (Android) behind a common `Settings` interface in commonMain.

**Decision matrix — which persistence library to use:**

| Data shape | Recommended library | Rationale |
|---|---|---|
| Simple key-value prefs (booleans, strings, ints) | **Multiplatform-Settings** | Lightweight, zero setup, direct API. No serialization overhead. |
| Typed/structured data, proto-based schemas | **DataStore KMP** | Type safety via proto or preferences DSL. Better for complex config objects. |
| Already using DataStore in the Android source | **DataStore KMP** | Lowest friction — same API surface, only construction changes. |
| Relational data, complex queries | **Room 2.7+ KMP** or **SQLDelight** | Full database, not a preference store. |

When migrating `SharedPreferences` with only simple key-value pairs (e.g., boolean toggles, theme settings, feature flags), default to **Multiplatform-Settings** — not DataStore — even if DataStore is already in the project for other purposes. Use the simplest tool that fits the data shape.

**Before (SharedPreferences):**

```kotlin
val prefs = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
val username = prefs.getString("username", "")
prefs.edit { putString("username", "alice") }
prefs.edit { remove("username") }
```

**After (Multiplatform-Settings):**

```kotlin
// commonMain
// Note: Settings() no-arg constructor is only available in platform source sets.
// In commonMain, use an expect/actual factory or inject via DI.
val settings: Settings = Settings()

val username = settings.getString("username", defaultValue = "")
settings.putString("username", "alice")
settings.remove("username")

// Flow-based observation (multiplatform-settings-coroutines)
settings.getStringFlow("username", defaultValue = "")
    .collect { value -> /* react to changes */ }
```

**Platform wiring:**

```kotlin
// androidMain
actual fun createSettings(): Settings =
    SharedPreferencesSettings(context.getSharedPreferences("app_prefs", MODE_PRIVATE))

// iosMain
actual fun createSettings(): Settings =
    NSUserDefaultsSettings(NSUserDefaults.standardUserDefaults)
```

---

## Database: Room → Room 2.7+ KMP or SQLDelight

### Option A: Room 2.7+ KMP (easiest migration from existing Room)

**Replacement:** `androidx.room:room-runtime:2.7+` with KMP support enabled

**Why:** Room 2.7+ added native KMP support. If already on Room, this is the lowest-friction path — same DAOs, same entities, same annotations.

**Before (Room Android-only):**

```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    val name: String
)

@Dao
interface UserDao {
    @Query("SELECT * FROM users") suspend fun getAll(): List<UserEntity>
    @Insert suspend fun insert(user: UserEntity)
}

@Database(entities = [UserEntity::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao
}
```

**After (Room KMP):**

```kotlin
// commonMain — same DAO and Entity definitions (mostly unchanged)
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    val name: String
)

@Dao
interface UserDao {
    @Query("SELECT * FROM users") suspend fun getAll(): List<UserEntity>
    @Insert suspend fun insert(user: UserEntity)
}

// Platform-specific database construction
// androidMain
actual fun createDatabase(ctx: Context): AppDatabase =
    Room.databaseBuilder(ctx, AppDatabase::class.java, "app.db").build()

// iosMain
actual fun createDatabase(): AppDatabase =
    Room.databaseBuilder(name = "app.db").build()
```

### Option B: SQLDelight (KMP-first, mature tooling)

**Replacement:** `app.cash.sqldelight:android-driver`, `app.cash.sqldelight:native-driver`

**Why:** SQLDelight generates type-safe Kotlin from `.sq` SQL files, works on all KMP targets, and has excellent IDE support. Preferred for greenfield KMP databases.

**Before (Room):**

```kotlin
@Entity data class User(@PrimaryKey val id: String, val name: String)
@Dao interface UserDao { @Query("SELECT * FROM User") fun getAll(): List<User> }
```

**After (SQLDelight):**

```sql
-- commonMain/sqldelight/com/example/User.sq
CREATE TABLE User (
  id   TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL
);

selectAll:
SELECT * FROM User;

insert:
INSERT INTO User(id, name) VALUES (?, ?);
```

```kotlin
// commonMain — generated queries used directly
val driver: SqlDriver = createDriver()
val db = AppDatabase(driver)

val users: List<User> = db.userQueries.selectAll().executeAsList()
db.userQueries.insert(id = "1", name = "Alice")
```

---

## Storage: DataStore → DataStore KMP

**Replacement:** `androidx.datastore:datastore-preferences-core` (KMP experimental)

**Why:** JetBrains and Google added experimental KMP support to DataStore. The common API surface is unchanged; only construction is platform-specific via expect/actual.

**Before (Android DataStore):**

```kotlin
val Context.dataStore by preferencesDataStore(name = "settings")

val DARK_MODE = booleanPreferencesKey("dark_mode")
val isDark: Flow<Boolean> = context.dataStore.data.map { it[DARK_MODE] ?: false }

suspend fun setDarkMode(enabled: Boolean) {
    context.dataStore.edit { it[DARK_MODE] = enabled }
}
```

**After (DataStore KMP):**

```kotlin
// commonMain
expect fun createDataStore(): DataStore<Preferences>

val DARK_MODE = booleanPreferencesKey("dark_mode")

class SettingsRepository(private val dataStore: DataStore<Preferences>) {
    val isDark: Flow<Boolean> = dataStore.data.map { it[DARK_MODE] ?: false }

    suspend fun setDarkMode(enabled: Boolean) {
        dataStore.edit { it[DARK_MODE] = enabled }
    }
}

// androidMain
actual fun createDataStore(): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath { appContext.filesDir.resolve("settings.preferences_pb").toOkioPath() }

// iosMain
actual fun createDataStore(): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath {
        val dir = NSFileManager.defaultManager.URLForDirectory(
            NSDocumentDirectory, NSUserDomainMask, null, true, null
        )!!.path!! // Production code should use safe unwrapping — this is simplified for illustration
        "$dir/settings.preferences_pb".toPath()
    }
```

---

## Reactive: RxJava → kotlinx-coroutines + Flow

**Replacement:** `org.jetbrains.kotlinx:kotlinx-coroutines-core`

**Why:** RxJava is JVM-only. Kotlin coroutines and Flow are built into the Kotlin standard library and work across all KMP targets.

**Mapping:**

| RxJava | KMP equivalent |
|--------|---------------|
| `Observable<T>` | `Flow<T>` |
| `Single<T>` | `suspend fun(): T` |
| `Completable` | `suspend fun(): Unit` |
| `Maybe<T>` | `suspend fun(): T?` |
| `Subject<T>` | `MutableSharedFlow<T>` |
| `BehaviorSubject<T>` | `MutableStateFlow<T>` |
| `.subscribeOn(io())` | `withContext(Dispatchers.IO)` |
| `.observeOn(mainThread())` | `flowOn(Dispatchers.Main)` |

**Before (RxJava):**

```kotlin
fun getUsers(): Observable<List<User>> =
    Observable.fromCallable { api.fetchUsers() }
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())

// Usage
disposable = getUsers()
    .map { users -> users.filter { it.active } }
    .subscribe(
        { users -> showUsers(users) },
        { error -> showError(error) }
    )
```

**After (Flow):**

```kotlin
fun getUsers(): Flow<List<User>> = flow {
    emit(api.fetchUsers())
}.flowOn(Dispatchers.IO)

// Usage
viewModelScope.launch {
    getUsers()
        .map { users -> users.filter { it.active } }
        .collect { users -> _uiState.value = users }
}
```

---

## Date/Time: java.time → kotlinx-datetime

**Replacement:** `org.jetbrains.kotlinx:kotlinx-datetime`

**Why:** `java.time` (and `java.util.Date`) are JVM-only. kotlinx-datetime is a multiplatform drop-in replacement with an API mirroring java.time.

**Mapping:**

| java.time | kotlinx-datetime |
|-----------|-----------------|
| `LocalDateTime.now()` | `Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())` |
| `Instant.now()` | `Clock.System.now()` |
| `Duration.ofSeconds(n)` | `n.seconds` (kotlin.time) |
| `ZoneId.systemDefault()` | `TimeZone.currentSystemDefault()` |
| `LocalDate.parse("2024-01-01")` | `LocalDate.parse("2024-01-01")` |

**Before (java.time):**

```kotlin
val now: LocalDateTime = LocalDateTime.now()
val today: LocalDate = LocalDate.now()
val instant: Instant = Instant.now()
val delay: Duration = Duration.ofSeconds(30)
val formatted = now.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
```

**After (kotlinx-datetime):**

```kotlin
import kotlinx.datetime.*
import kotlin.time.Duration.Companion.seconds

val instant: Instant = Clock.System.now()
val tz = TimeZone.currentSystemDefault()
val now: LocalDateTime = instant.toLocalDateTime(tz)
val today: LocalDate = now.date
val delay = 30.seconds
val formatted = instant.toString() // ISO-8601 by default
```

---

## Testing: JUnit → kotlin-test

**Replacement:** `org.jetbrains.kotlin:kotlin-test`

**Why:** JUnit is JVM-only. kotlin-test is the official KMP test framework and maps to the platform-native runner (JUnit on JVM, XCTest on iOS, etc.) automatically.

**Mapping:**

| JUnit | kotlin-test |
|-------|------------|
| `import org.junit.Test` | `import kotlin.test.Test` |
| `Assert.assertEquals(a, b)` | `assertEquals(a, b)` |
| `Assert.assertTrue(x)` | `assertTrue(x)` |
| `Assert.assertNull(x)` | `assertNull(x)` |
| `Assert.assertNotNull(x)` | `assertNotNull(x)` |
| `@Before` | `@BeforeTest` |
| `@After` | `@AfterTest` |

**Before (JUnit):**

```kotlin
import org.junit.Test
import org.junit.Assert.*
import org.junit.Before

class UserRepositoryTest {
    private lateinit var repo: UserRepository

    @Before
    fun setUp() { repo = UserRepositoryImpl(FakeApi()) }

    @Test
    fun `returns users from api`() {
        val users = repo.getUsers()
        assertEquals(2, users.size)
        assertTrue(users.first().active)
    }
}
```

**After (kotlin-test):**

```kotlin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.BeforeTest

class UserRepositoryTest {
    private lateinit var repo: UserRepository

    @BeforeTest
    fun setUp() { repo = UserRepositoryImpl(FakeApi()) }

    @Test
    fun returnsUsersFromApi() {
        // Note: backtick test names crash Kotlin/Native — use camelCase
        val users = repo.getUsers()
        assertEquals(2, users.size)
        assertTrue(users.first().active)
    }
}
```

---

## Mocking: MockK / Mockito → Hand-written Fakes

**Replacement:** No library — hand-write focused fake implementations.

**Why:** MockK and Mockito both rely on JVM bytecode manipulation or reflection, neither of which is available on Kotlin/Native. There is no viable mocking library for commonTest. Fakes are the correct KMP pattern.

**Before (MockK):**

```kotlin
val mockRepo = mockk<UserRepository>()
every { mockRepo.getUsers() } returns listOf(User("1", "Alice"))
every { mockRepo.saveUser(any()) } just Runs

val viewModel = UserViewModel(mockRepo)
viewModel.load()

verify { mockRepo.getUsers() }
```

**Before (Mockito):**

```kotlin
val mockRepo = mock(UserRepository::class.java)
`when`(mockRepo.getUsers()).thenReturn(listOf(User("1", "Alice")))

val viewModel = UserViewModel(mockRepo)
viewModel.load()

verify(mockRepo).getUsers()
```

**After (hand-written fake):**

```kotlin
// commonTest — a focused fake; unused methods throw to catch accidental calls
class FakeUserRepository : UserRepository {
    val savedUsers = mutableListOf<User>()
    var usersToReturn: List<User> = emptyList()

    override fun getUsers(): List<User> = usersToReturn

    override fun saveUser(user: User) {
        savedUsers += user
    }

    override fun deleteUser(id: String): Unit =
        error("FakeUserRepository.deleteUser not implemented")
}

// Usage in test
class UserViewModelTest {
    @Test
    fun loadsUsersOnInit() {
        val fake = FakeUserRepository().apply {
            usersToReturn = listOf(User("1", "Alice"))
        }
        val viewModel = UserViewModel(fake)
        viewModel.load()
        assertEquals(1, viewModel.users.value.size)
    }
}
```

---

## Image Loading: Coil 2 → Coil 3

**Replacement:** `io.coil-kt.coil3:coil-compose`, `io.coil-kt.coil3:coil-network-ktor`

**Why:** Coil 2 is Android-only. Coil 3 added full KMP support with an identical public API — it's a dependency version bump with minor import changes.

**Before (Coil 2):**

```kotlin
// build.gradle.kts
implementation("io.coil-kt:coil-compose:2.7.0")

// Composable
AsyncImage(
    model = "https://example.com/image.jpg",
    contentDescription = "Profile photo",
    modifier = Modifier.size(48.dp)
)
```

**After (Coil 3):**

```kotlin
// build.gradle.kts
implementation("io.coil-kt.coil3:coil-compose:3.x.x")
implementation("io.coil-kt.coil3:coil-network-ktor:3.x.x")

// Composable — identical call site
AsyncImage(
    model = "https://example.com/image.jpg",
    contentDescription = "Profile photo",
    modifier = Modifier.size(48.dp)
)

// Singleton setup (commonMain)
val imageLoader = ImageLoader.Builder(platformContext)
    .components { add(KtorNetworkFetcherFactory()) }
    .build()
```

---

## LiveData → StateFlow

**Replacement:** `kotlinx.coroutines.flow.StateFlow` (part of `kotlinx-coroutines-core`)

**Why:** LiveData is Android lifecycle-aware and lives in `androidx.lifecycle` — it has no KMP equivalent. StateFlow is the direct coroutine-based replacement and is fully multiplatform. SKIE automatically bridges StateFlow to Swift as `AsyncSequence`.

**Mapping:**

| LiveData | StateFlow |
|----------|-----------|
| `MutableLiveData<T>()` | `MutableStateFlow<T>(initialValue)` |
| `LiveData<T>` | `StateFlow<T>` |
| `liveData.observe(owner) { }` | `lifecycleScope.launch { stateFlow.collect { } }` |
| `liveData.value = x` | `stateFlow.value = x` |
| `liveData.postValue(x)` | Use `update { }` for atomic modifications when multiple coroutines may write concurrently. Direct `.value =` is safe for single-writer scenarios. |
| `MediatorLiveData` | `combine(flow1, flow2) { ... }` |

**Before (LiveData):**

```kotlin
class UserViewModel : ViewModel() {
    private val _user = MutableLiveData<User>()
    val user: LiveData<User> = _user

    fun load(id: String) {
        viewModelScope.launch {
            _user.value = repository.getUser(id)
        }
    }
}

// Android observer
viewModel.user.observe(viewLifecycleOwner) { user ->
    nameTextView.text = user.name
}
```

**After (StateFlow):**

```kotlin
// commonMain ViewModel (shared)
class UserViewModel(private val repository: UserRepository) : ViewModel() {
    private val _user = MutableStateFlow<User?>(null)
    val user: StateFlow<User?> = _user.asStateFlow()

    fun load(id: String) {
        viewModelScope.launch {
            _user.value = repository.getUser(id)
        }
    }
}

// Android collector
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.user.collect { user ->
            nameTextView.text = user?.name
        }
    }
}

// Swift (via SKIE — automatic AsyncSequence bridging)
// for await let user in viewModel.user {
//     nameLabel.text = user?.name
// }
```

---

## Logging: Android Log → Napier

**Replacement:** `io.github.aakira:napier`

**Why:** `android.util.Log` is Android-only. Napier is a lightweight KMP logging library that delegates to `android.util.Log` on Android and `NSLog`/`os_log` on iOS.

**Before (Android Log):**

```kotlin
Log.v("UserRepo", "Fetching user $id")
Log.d("UserRepo", "User loaded: $user")
Log.i("UserRepo", "Cache hit for $id")
Log.w("UserRepo", "User not found, returning null")
Log.e("UserRepo", "Failed to fetch user", exception)
```

**After (Napier):**

```kotlin
// Initialization (once, in platform entry point)
// Android Application or iOS AppDelegate:
Napier.base(DebugAntilog())

// commonMain usage — identical API everywhere
Napier.v("Fetching user $id", tag = "UserRepo")
Napier.d("User loaded: $user", tag = "UserRepo")
Napier.i("Cache hit for $id", tag = "UserRepo")
Napier.w("User not found, returning null", tag = "UserRepo")
Napier.e("Failed to fetch user", throwable = exception, tag = "UserRepo")
```

---

## Library Discovery

When encountering an Android-only library not listed here:

**[klibs.io](https://klibs.io)** — the official KMP library discovery site. Search by library name or category to find KMP-compatible alternatives. Always check here before attempting to wrap or port a library manually.

**Quick checklist for any unknown library:**
1. Check if the library itself has added KMP support in a recent release (many have).
2. Search klibs.io for alternatives.
3. Check the library's GitHub issues/releases for KMP tracking issues.
4. If none found, evaluate: can the functionality be replaced with a KMP-native API (e.g., `kotlinx-datetime` instead of Joda-Time)?

---

## Platform API Gotchas (commonMain)

> **See also:** `references/platform-api-gotchas.md` for the full table with all APIs not available on Native.

The following JVM/Android APIs are frequently used by migration agents but are NOT available in `commonMain`. Always use the replacement.

### @Volatile

```kotlin
// BAD — JVM-only
@Volatile
var cached: String? = null

// GOOD — available since Kotlin 1.8.20
@kotlin.concurrent.Volatile
var cached: String? = null
```

### @Synchronized → atomicfu

```kotlin
// BAD — JVM-only
@Synchronized
fun getOrCreate(): T { ... }

// GOOD — requires kotlinx-atomicfu dependency
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

class Cache : SynchronizedObject() {
    fun getOrCreate(): T = synchronized(this) { ... }
}
```

Add to `build.gradle.kts`:
```kotlin
commonMain.dependencies {
    implementation("org.jetbrains.kotlinx:atomicfu:0.23.2")
}
```

### Dispatchers.IO

Available in commonMain for JVM + Native targets since kotlinx-coroutines 1.7.0 (Kotlin 1.8.20+).

```kotlin
// IMPORTANT: On Native, Dispatchers.IO is an extension property, not a member.
// The IDE may not auto-import it. Always add this import explicitly:
import kotlinx.coroutines.IO

// GOOD — works in commonMain (JVM + Native)
withContext(Dispatchers.IO) { networkCall() }

// ONLY needed if targeting JS/Wasm (where Dispatchers.IO doesn't exist):
// commonMain
expect val ioDispatcher: CoroutineDispatcher
// androidMain / nativeMain
actual val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
// jsMain
actual val ioDispatcher: CoroutineDispatcher = Dispatchers.Default
```

**Native caveats:** IO pool uses up to 64 threads, lazily allocated. No elasticity — threads are never released once created.

### String.format()

```kotlin
// BAD — Java stdlib, not on Native
String.format("%.2f", value)

// GOOD — pure Kotlin
fun Double.formatDecimal(precision: Int): String {
    val factor = 10.0.pow(precision)
    val rounded = kotlin.math.round(this * factor) / factor
    val parts = rounded.toString().split(".")
    val intPart = parts[0]
    val decPart = (parts.getOrElse(1) { "0" }).padEnd(precision, '0').take(precision)
    return "$intPart.$decPart"
}
```

### Collection methods (Java 21+)

```kotlin
// BAD — Java 21 SequencedCollection, crashes on JVM 8 and absent on Native
list.removeFirst()
list.removeLast()

// GOOD
list.removeAt(0)
list.removeAt(list.lastIndex)
```
