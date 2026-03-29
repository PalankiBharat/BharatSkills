# KMM Migration Reference

Consolidated reference for Android-to-KMM migrations. Project-agnostic. Covers dependency replacements, architecture patterns, and production-proven gotchas.

> **Version note:** Always verify library versions via Context7, find-docs, or web search. Version numbers in this file may be outdated.

---

## Table of Contents

### 1. Dependency Replacement Map
- [Networking: Retrofit + OkHttp → Ktor Client](#networking-retrofit--okhttp--ktor-client)
- [Serialization: Gson / Moshi → kotlinx.serialization](#serialization-gson--moshi--kotlinxserialization)
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

### 2. KMM Architecture Patterns
- [Source Set Structure](#source-set-structure)
- [expect/actual Declarations](#expectactual-declarations)
- [Framework Export (iOS)](#framework-export-ios)
- [ViewModel Pattern](#viewmodel-pattern)
- [DI Pattern (Koin)](#di-pattern-koin)
- [Coroutines](#coroutines)
- [KMM Interface First](#kmm-interface-first)

### 3. Battle-Tested Gotchas
- [iOS Build Environment](#ios-build-environment)
- [SwiftUI Gotchas](#swiftui-gotchas)
- [KMM/Kotlin Gotchas](#kmmkotlin-gotchas)
- [Process Gotchas](#process-gotchas)

---

# 1. Dependency Replacement Map

A project-agnostic reference for every common Android library and its KMM replacement. Each entry includes: library, replacement, rationale, and before/after code examples.

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

# 2. KMM Architecture Patterns

Quick-reference for Kotlin Multiplatform Mobile patterns. Project-agnostic; use as a checklist and code template source.

---

## Source Set Structure

| Source Set     | Contains                                                              | Platform APIs |
|----------------|-----------------------------------------------------------------------|---------------|
| `commonMain`   | ViewModels, repositories, use cases, models, networking (Ktor), DI   | None          |
| `androidMain`  | Ktor OkHttp engine, Android-specific platform implementations         | Yes           |
| `iosMain`      | Ktor Darwin engine, iOS-specific platform implementations             | Yes           |
| `commonTest`   | Shared tests (kotlin-test + coroutines-test)                          | None          |

**Decision rule: where does this code live?**

- No platform APIs at all → `commonMain`
- Needs Android SDK or iOS framework → use `expect/actual` or inject via DI; put each side in its platform source set
- Tests with no platform I/O → `commonTest` (runs on both JVM and iOS Native)

---

## expect/actual Declarations

### Official JetBrains hierarchy of preference

1. **Dependency Injection (Koin)** — if you already have DI, use it for platform deps too; no `expect/actual` required
2. **Interface + `expect fun` factory** — define a common interface in `commonMain`, write an `expect fun` that returns the platform implementation
3. **`expect actual class`** — only justified when inheriting a platform base class or authoring a framework

> "Using classes in simple cases where interfaces would be sufficient is not recommended." — JetBrains docs

### Pattern 2: Interface + expect fun factory

```kotlin
// commonMain
interface Logger {
    fun log(message: String)
}

expect fun createLogger(): Logger
```

```kotlin
// androidMain
import android.util.Log

actual fun createLogger(): Logger = object : Logger {
    override fun log(message: String) {
        Log.d("App", message)
    }
}
```

```kotlin
// iosMain
actual fun createLogger(): Logger = object : Logger {
    override fun log(message: String) {
        println(message) // maps to NSLog on iOS
    }
}
```

### Pattern 3: expect/actual for platform values

```kotlin
// commonMain
expect val platformName: String

// androidMain
actual val platformName: String = "Android"

// iosMain
actual val platformName: String = "iOS"
```

---

## Framework Export (iOS)

```kotlin
// build.gradle.kts (shared module)
kotlin {
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    targets.withType<org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget> {
        binaries.framework {
            baseName = "Shared"
            isStatic = true
            linkerOpts("-lsqlite3")       // link native libs when needed

            // Make specific deps part of the public framework API
            export(libs.koin.core)
            export(libs.kotlinx.coroutines.core)
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(libs.ktor.client.core)
            implementation(libs.koin.core)        // internal use only
            api(libs.kotlinx.coroutines.core)     // visible to Swift consumers
        }
        androidMain.dependencies {
            implementation(libs.ktor.client.okhttp)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
    }
}
```

**api() vs implementation() rules:**

| Scenario                                             | Use         |
|------------------------------------------------------|-------------|
| Dep's types appear in your public API / Swift surface | `api()`     |
| Dep is used only inside the Kotlin module            | `implementation()` |
| Dep in `framework { export(...) }` block             | Must also be `api()` in sourceSets |

**Warning:** Exporting `kotlinx.coroutines.core` from the framework can cause duplicate symbol linker errors if another KMP module in the same app also exports it. Only export it if your framework is the sole source of coroutines in the binary.

---

## ViewModel Pattern

### BaseViewModel contract

```kotlin
// commonMain
abstract class BaseViewModel<State, Action, Effect>(
    initialState: State,
) : ViewModel() {

    private val _state = MutableStateFlow(initialState)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _effects = MutableSharedFlow<Effect>(extraBufferCapacity = 16)
    val effects: SharedFlow<Effect> = _effects.asSharedFlow()

    protected var currentState: State
        get() = _state.value
        set(value) { _state.value = value }

    abstract fun processAction(action: Action)

    protected fun emitEffect(effect: Effect) {
        viewModelScope.launch { _effects.emit(effect) }
    }
}
```

### Concrete ViewModel example

```kotlin
// commonMain
data class CounterState(val count: Int) {
    companion object {
        fun default() = CounterState(count = 0)
    }
}

sealed interface CounterAction {
    data object Increment : CounterAction
    data object Decrement : CounterAction
}

sealed interface CounterEffect {
    data class ShowToast(val message: String) : CounterEffect
}

class CounterViewModel : BaseViewModel<CounterState, CounterAction, CounterEffect>(
    initialState = CounterState.default()
) {
    override fun processAction(action: CounterAction) {
        when (action) {
            CounterAction.Increment -> currentState = currentState.copy(count = currentState.count + 1)
            CounterAction.Decrement -> {
                if (currentState.count == 0) {
                    emitEffect(CounterEffect.ShowToast("Already at zero"))
                } else {
                    currentState = currentState.copy(count = currentState.count - 1)
                }
            }
        }
    }
}
```

### Platform consumption

```kotlin
// Android (Jetpack Compose)
@Composable
fun CounterScreen(vm: CounterViewModel = koinViewModel()) {
    val state by vm.state.collectAsState()

    LaunchedEffect(Unit) {
        vm.effects.collect { effect ->
            when (effect) {
                is CounterEffect.ShowToast -> Toast.makeText(context, effect.message, Toast.LENGTH_SHORT).show()
            }
        }
    }

    Text(text = "Count: ${state.count}")
    Button(onClick = { vm.processAction(CounterAction.Increment) }) { Text("Increment") }
}
```

```swift
// iOS (SwiftUI)
struct CounterView: View {
    @StateObject private var vm = KoinHelper.shared.counterViewModel()

    var body: some View {
        VStack {
            Text("Count: \(vm.state.count)")
            Button("Increment") {
                vm.processAction(action: CounterAction.Increment())
            }
        }
        // Note: `for await` on a Kotlin Flow requires the SKIE plugin (`co.touchlab.skie`).
        // Without SKIE, Kotlin Flows are not directly consumable as Swift AsyncSequence.
        .task {
            for await effect in vm.effects {
                switch onEnum(of: effect) {
                case .showToast(let e):
                    showToast(e.message)
                case .navigateBack:
                    dismiss()
                }
            }
        }
    }
}
```

---

## DI Pattern (Koin)

### Module setup

```kotlin
// commonMain
val repositoryModule = module {
    single<UserRepository> { UserRepositoryImpl(get()) }  // singleton
    single<ApiClient> { ApiClientImpl(get()) }
}

val viewModelModule = module {
    factory { CounterViewModel() }                         // fresh per nav push
    factory { UserViewModel(get()) }
}
```

```kotlin
// androidMain
val androidModule = module {
    single<PlatformLogger> { AndroidLogger() }
}
```

```kotlin
// iosMain
val iosModule = module {
    single<PlatformLogger> { IosLogger() }
}
```

### iOS PresenterProvider (KoinComponent bridge)

```kotlin
// iosMain — single access point for Swift
class KoinHelper : KoinComponent {
    fun counterViewModel(): CounterViewModel = get()
    fun userViewModel(): UserViewModel = get()

    companion object {
        val shared = KoinHelper()
    }
}
```

```swift
// Swift
@StateObject private var vm = KoinHelper.shared.counterViewModel()
```

### Migration from Hilt

| Hilt                                      | Koin equivalent                          |
|-------------------------------------------|------------------------------------------|
| `@HiltViewModel class Foo @Inject constructor(bar: Bar)` | `factory { FooViewModel(get()) }` |
| `hiltViewModel<FooViewModel>()`           | `koinViewModel<FooViewModel>()`          |
| `@Provides @Singleton fun provideBar()`   | `single { BarImpl() }`                   |
| `@Inject lateinit var bar: Bar` (field)   | Pass through constructor; use `get()` in module |

---

## Coroutines

### Rules

- `Dispatchers.Main` — UI updates only
- `Dispatchers.Default` — CPU-bound background work
- **NEVER `runBlocking` on the main thread** — iOS watchdog kills the app after ~5 seconds
- **Never create unscoped `CoroutineScope(Dispatchers.IO).launch { }`** — these leak; always use `viewModelScope`
- Tie every scope to a lifecycle (`viewModelScope` in ViewModels, `lifecycleScope` in Android Activities/Fragments)

**`Dispatchers.IO` in commonMain:** Available with `kotlinx-coroutines-core` 1.7+. If the Android source code uses `Dispatchers.IO`, upgrade the coroutines version to 1.7+ and keep using `Dispatchers.IO` in commonMain — Android is the source of truth, don't change dispatchers unnecessarily. On iOS, `Dispatchers.IO` maps to a background thread pool appropriate for I/O-bound work (network, disk).

### Patterns

```kotlin
// Safe: scoped to ViewModel lifecycle
class MyViewModel : ViewModel() {
    fun loadData() {
        viewModelScope.launch {
            val result = withContext(Dispatchers.Default) { repository.fetch() }
            currentState = currentState.copy(data = result)
        }
    }
}
```

```kotlin
// Safe: concurrent work within a single scope
viewModelScope.launch {
    val (users, posts) = coroutineScope {
        val usersDeferred = async { repository.getUsers() }
        val postsDeferred = async { repository.getPosts() }
        usersDeferred.await() to postsDeferred.await()
    }
    currentState = currentState.copy(users = users, posts = posts)
}
```

```kotlin
// WRONG: unscoped, leaks if ViewModel is cleared
CoroutineScope(Dispatchers.IO).launch { repository.fetch() }

// WRONG: blocks main thread on iOS
runBlocking { repository.fetch() }
```

---

## KMM Interface First

Before creating a wrapper class, ask:

1. Does the KMM SDK already expose an interface with equivalent behavior?
2. Is the only difference a name or minor API surface?

If yes to both → use the KMM interface directly (swap import + rename callsites). No wrapper needed.

**Wrapper is only justified when:**
- The interfaces have genuinely different method signatures or semantics
- You need to adapt between incompatible lifecycle models
- The third-party type cannot be used directly in `commonMain` (e.g., it's platform-specific)

```kotlin
// PREFER: use KMM interface directly
import com.example.sdk.DataRepository  // KMM interface already exists

class MyViewModel(private val repo: DataRepository) : BaseViewModel<...>() { ... }
```

```kotlin
// AVOID unless genuinely necessary: wrapper just for name mapping
class MyDataRepository(private val sdkRepo: SdkDataRepository) : DataRepository {
    override fun getData() = sdkRepo.fetchData()  // only difference was the name
}
```

---

# 3. Battle-Tested Gotchas

Hard-won learnings from real production KMM migrations. Every item here burned time on a real project. Project-agnostic.

---

## iOS Build Environment

### New Swift Files Need pbxproj Registration
- Every new `.swift` file must be manually registered in the Xcode project file (`project.pbxproj`)
- Required entries: `PBXBuildFile`, `PBXFileReference`, and `PBXGroup`
- Without this: file exists on disk but is NOT compiled. No clear error message — the types just don't exist
- This is the #1 most common iOS build failure for KMM migrations

### pod install After Worktree Setup
- Running `pod install` in the `iosApp/` directory is REQUIRED after:
  - Creating a new git worktree
  - Adding new CocoaPods dependencies
  - Switching branches that modify the Podfile
- `Podfile.lock` is tracked but `Pods/` directory is not
- Missing this causes immediate xcodebuild failure: "framework not found"

### local.properties Must Be Copied to Worktrees
- Each git worktree needs its own `local.properties` file (Android SDK path)
- Not automatically propagated — must be copied manually
- Missing this causes Gradle to fail with "SDK location not found"

### SourceKit False Positives — Trust xcodebuild
- Xcode/SourceKit frequently shows "No such module 'shared'" or similar errors
- These are IDE indexing false positives — NOT real errors
- `xcodebuild` succeeds regardless
- Rule: NEVER spend time debugging SourceKit errors. Run `xcodebuild` — if it passes, ignore IDE errors

### :shared:build vs :shared:assemble
- `:shared:build` runs tests. If pre-existing tests are failing, it will fail even if your code is fine
- `:shared:assemble` compiles without running tests
- `:shared:linkDebugFrameworkIosSimulatorArm64` compiles iOS framework only
- Use `assemble` or `linkDebugFramework` when pre-existing test failures block build verification

---

## SwiftUI Gotchas

### Sheet Must Be Dismissed Before Navigation
- If you navigate away while a `.sheet` is presented, the sheet persists to the next screen
- Root cause: SwiftUI does not automatically dismiss sheets when the presenting view navigates
- Fix: Use a `pendingAction` flag + `onDismiss` callback to sequence: dismiss sheet first, THEN navigate

```swift
@State private var pendingNavigation: Destination? = nil
.sheet(isPresented: $showSheet, onDismiss: {
    if let destination = pendingNavigation {
        pendingNavigation = nil
        router.navigate(to: destination)
    }
}) { ... }
```

### UIKit Touch Callbacks Need Main Queue Dispatch
- When using `UIViewRepresentable` with touch delegates (e.g., signature drawing)
- `touchesEnded` callback fires but does not trigger SwiftUI re-render
- Fix: Wrap state update in `DispatchQueue.main.async { }`
- Why: UIKit touch callbacks are on main thread but SwiftUI binding update needs explicit dispatch

```swift
// In UIViewRepresentable Coordinator:
func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    DispatchQueue.main.async {
        self.parent.didFinishDrawing = true  // triggers SwiftUI re-render
    }
}
```

### WKWebView Needs WKUIDelegate for JavaScript window.open()
- Some web pages (e.g., e-sign flows) use `window.open()` for popups
- Without `WKUIDelegate`, WKWebView SILENTLY discards these requests — button appears to do nothing
- Fix: Add `WKUIDelegate` conformance, implement `webView(_:createWebViewWith:)`, set `javaScriptCanOpenWindowsAutomatically = true`

### UIApplication.shared.open() Async Context
- In iOS 16+, `open()` is async
- Inside `.task {}` blocks: needs `await` — `await UIApplication.shared.open(url)`
- Inside sync closures (button actions, sheet callbacks): does NOT need `await`
- Getting this wrong: compile error in one direction, missing await warning in the other

### Keyboard Handling Pattern
- Standard pattern for screens where CTA button should float above keyboard:

```swift
@State private var keyboardHeight: CGFloat = 0
// In body:
.onReceive(Publishers.keyboardHeight) { height in
    keyboardHeight = height
}
.offset(y: -keyboardHeight)
```

- When fixing keyboard issues, audit ALL screens of the same type, not just the one reported

### Racy Fallback Routing
- Never use `asyncAfter`/`DispatchQueue.main.asyncAfter` as a fallback for "if VM doesn't respond in time"
- Race condition: both the VM callback and the timer fallback can fire, causing double navigation
- Fix: Use a proper state machine. If concerned about VM responsiveness, add a timeout to the VM itself

---

## KMM/Kotlin Gotchas

### Enum Case Sensitivity
- "CONTROL" vs "control" breaks feature flags silently
- Kotlin is case-sensitive. If Android sends "control" and KMM expects "CONTROL", the enum won't match
- `@SerialName` annotations and case-insensitive comparison can help
- Always verify enum string values match between Android and KMM

### Lost Concurrency During Migration
- Android code using async/await for parallel uploads can silently become sequential in KMM
- If you see multiple API calls that were concurrent, ensure they remain concurrent:

```kotlin
// WRONG — sequential:
val result1 = api.upload(file1)
val result2 = api.upload(file2)

// RIGHT — concurrent:
coroutineScope {
    val deferred1 = async { api.upload(file1) }
    val deferred2 = async { api.upload(file2) }
    awaitAll(deferred1, deferred2)
}
```

### Data Class Field Additions Break iOS
- Adding fields to a Kotlin data class used in the shared framework (e.g., `UserCredentials`) requires updating Swift call sites
- Swift uses positional constructors for Kotlin data classes — adding a field shifts all positions
- Always check Swift callers after modifying shared data classes

### Multiple Flows on a Single ViewModel
- Some VMs expose both `effect: SharedFlow<Effect>` AND a separate `navigationEvents: SharedFlow<Route?>`
- You MUST subscribe to BOTH separately from Swift
- If you only subscribe to `effect`, you miss ALL navigation events from `navigationEvents`
- Always check the VM for ALL public Flow properties, not just `state` and `effect`

### SKIE Nested Dot Notation
- SKIE generates nested dot notation for sealed class subtypes
- Swift: `PinVerificationEvent.OTPEnter`, NOT flat `OTPEnter`
- This affects action dispatch and effect handling from Swift
- Sealed subtypes from Swift: `Effect.NavigateToNext`, not `NavigateToNext`

### Backtick Test Names Crash Kotlin/Native
- `` fun `test my behavior`() `` compiles on JVM but CRASHES on Kotlin/Native
- Always use camelCase: `fun testMyBehavior()`
- This is a `commonTest` rule — tests must work on BOTH JVM and Native

### Standalone Enum Serialization Crashes on Native
- Encoding a non-`@Serializable` enum standalone crashes on Kotlin/Native
- Fix: test serialization within the context of a parent `@Serializable` class, not standalone

### expect/actual VMs Can't Be Instantiated in commonTest
- If your ViewModel uses `expect/actual` (e.g., `expect abstract class KMMViewModel`), it can't be directly created in `commonTest`
- Fix: create a test wrapper class in the test directory that extends the VM

---

## Process Gotchas

### Always Audit Routing After Building Screens
- A screen can be fully implemented — correct layout, correct state handling — but not wired in navigation
- After building any screen, always check: is it reachable? Is the `Destination` case in `Router`? Is it in `RootView`'s `navigationDestination`?
- The most common "it doesn't work" bug is a missing navigation wire, not a code bug

### iOS VMs May Be Simpler Than Android VMs
- Don't assume iOS and Android VMs are identical
- iOS often has: fewer routes, different edge cases, simpler error handling
- Always parity-check the VM before building the screen — read the actual implementation

### Reference Legacy Code Without Checkout
- Use `git show <base-branch>:<path>` to read legacy code without checking out the branch
- Substitute the actual branch name (e.g., `master`, `main`, or your project's default branch)
- Keeps the worktree clean while still having access to the original implementation

### Field Additions Require Cross-Platform Check
- Any field added to a shared data class or interface must be checked on BOTH platforms
- Android: do existing callers pass the new field?
- iOS: Swift positional constructors — does the new field break existing call sites?

### Pre-Existing Test Failures Are Not Your Problem
- If tests were failing BEFORE your changes, they are not your responsibility
- Use `:shared:assemble` instead of `:shared:build` to bypass pre-existing test failures
- Document pre-existing failures so they are not confused with regressions
