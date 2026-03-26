# Android / Kotlin Logging Reference for Root Cause Analysis

## Table of Contents
1. [Tag Convention](#tag-convention)
2. [UI / Composable Layer](#ui--composable-layer)
3. [ViewModel Layer](#viewmodel-layer)
4. [Repository Layer](#repository-layer)
5. [Remote / API Layer](#remote--api-layer)
6. [Local / Database Layer](#local--database-layer)
7. [Collecting Logs from User](#collecting-logs-from-user)
8. [Coroutine / Threading Diagnostics](#coroutine--threading-diagnostics)
9. [Lifecycle Diagnostics](#lifecycle-diagnostics)

---

## Tag Convention

Use a consistent, filterable prefix for all diagnostic logs:

```kotlin
private const val RCA_TAG = "RCA_[FeatureName]"
```

Filter with:
```bash
adb logcat -s "RCA_*"
adb logcat | grep "RCA_"
```

---

## UI / Composable Layer

```kotlin
// Log state as received from ViewModel
LaunchedEffect(state) {
    Log.d("RCA_UI", "State: items=${state.items.size}, loading=${state.isLoading}, error=${state.error}")
}

// Track recomposition
SideEffect {
    Log.d("RCA_UI", "Recomposed: [ComposableName] at ${System.currentTimeMillis()}")
}
```

What to capture: state values received, recomposition triggers, click/event emissions.

---

## ViewModel Layer

```kotlin
fun onEvent(event: ScreenEvent) {
    Log.d("RCA_VM", "Event: $event")
    Log.d("RCA_VM", "State BEFORE: ${_state.value}")
    // ... processing ...
    Log.d("RCA_VM", "State AFTER: ${_state.value}")
}

// Flow collection
viewModelScope.launch {
    repository.getData()
        .onStart { Log.d("RCA_VM", "Flow started") }
        .onEach { Log.d("RCA_VM", "Emission: $it") }
        .onCompletion { Log.d("RCA_VM", "Flow done, cause: $it") }
        .catch { Log.e("RCA_VM", "Flow error", it) }
        .collect { data ->
            Log.d("RCA_VM", "Collected: ${data.size} items")
        }
}
```

What to capture: every event received, state before/after, Flow lifecycle (start, each emission, completion, errors), coroutine dispatcher.

---

## Repository Layer

```kotlin
fun getData(): Flow<List<Item>> {
    Log.d("RCA_REPO", "getData() called")
    return flow {
        val cached = localSource.getAll()
        Log.d("RCA_REPO", "Cache: ${cached.size} items, stale=${isCacheStale()}")

        if (isCacheStale()) {
            Log.d("RCA_REPO", "Fetching remote...")
            val remote = remoteSource.fetch()
            Log.d("RCA_REPO", "Remote: ${remote.size} items")
            emit(remote.map { it.toDomain() })
        } else {
            emit(cached.map { it.toDomain() })
        }
    }
}
```

What to capture: which data source chosen and why, cache staleness, data counts before and after mapping, mapper input/output if suspect.

---

## Remote / API Layer

```kotlin
// OkHttp Interceptor (catches everything)
class RCALoggingInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        Log.d("RCA_API", "REQ: ${request.method} ${request.url}")
        val response = chain.proceed(request)
        Log.d("RCA_API", "RES: ${response.code} in ${response.receivedResponseAtMillis - response.sentRequestAtMillis}ms")
        return response
    }
}

// Ktor
install(Logging) {
    logger = object : Logger {
        override fun log(message: String) { Log.d("RCA_API", message) }
    }
    level = LogLevel.ALL
}
```

What to capture: full URL with query params, response code and body, timing, headers (auth present? content-type?).

---

## Local / Database Layer

```kotlin
suspend fun getItems(): List<ItemEntity> {
    Log.d("RCA_DB", "Querying items...")
    val result = dao.getAllItems()
    Log.d("RCA_DB", "Returned ${result.size} rows")
    if (result.isNotEmpty()) {
        Log.d("RCA_DB", "First: ${result.first()}, Last: ${result.last()}")
    }
    return result
}
```

What to capture: query being executed, row counts, sample data (first/last), write success/failure.

---

## Collecting Logs from User

Ask the user to run:

```bash
# Clear old logs
adb logcat -c

# Capture with RCA filter
adb logcat -v time | grep "RCA_" > rca_logs.txt
```

Then reproduce the bug and share `rca_logs.txt`.

---

## Coroutine / Threading Diagnostics

If you suspect a threading issue:

```kotlin
Log.d("RCA_THREAD", "Thread: ${Thread.currentThread().name}, isMain=${Looper.myLooper() == Looper.getMainLooper()}")
```

---

## Lifecycle Diagnostics

If you suspect a lifecycle issue:

```kotlin
// Activity/Fragment
override fun onResume() {
    super.onResume()
    Log.d("RCA_LIFECYCLE", "${this::class.simpleName} onResume")
}

// Compose
DisposableEffect(Unit) {
    Log.d("RCA_LIFECYCLE", "[ComposableName] entered composition")
    onDispose { Log.d("RCA_LIFECYCLE", "[ComposableName] left composition") }
}
```
