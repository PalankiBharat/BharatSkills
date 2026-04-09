# Dependency Decision Framework

When migrating an Android SDK to KMM, every Android-only dependency needs a decision:
**Replace** (KMM-native lib), **Port** (rewrite in pure Kotlin), or **Abstract** (expect/actual interface).

## Decision tree

1. Does an official/mature KMM-compatible replacement exist?
   → YES: **Replace**. Always prefer this. Less maintenance, community support.
   → NO: Continue to 2.

2. Is the code simple enough to port to pure Kotlin (<500 LOC, no complex native interop)?
   → YES: **Port** to commonMain. Single codebase beats dual maintenance.
   → NO: Continue to 3.

3. Does the library have separate native SDKs for both platforms (Android + iOS)?
   → YES: **Abstract** with expect/actual interface. Each platform uses its native SDK.
   → NO: Abstract with expect/actual, iOS impl may need cinterop or Swift bridge.

## Common library decisions

| Android Library | Decision | KMM Replacement | Rationale |
|----------------|----------|-----------------|-----------|
| **Protobuf (protobuf-kotlin-lite)** | Replace | Wire by Square (`com.squareup.wire`) | KMM-native, generates multiplatform code from .proto files. Mechanical migration. |
| **FlatBuffers (flatbuffers-java)** | Port | Pure Kotlin in commonMain | No KMM FlatBuffers lib. Generated classes are simple byte-offset readers. Port the Table base class + generated readers. |
| **Gson** | Replace | kotlinx.serialization | Already in most KMM projects. `@SerializedName` → `@SerialName`, `Gson().fromJson()` → `Json.decodeFromString()`. |
| **joda-time** | Replace | kotlinx-datetime | Already in most KMM projects. `DateTime` → `Instant`/`LocalDateTime`, `DateTimeZone` → `TimeZone`. |
| **SharedPreferences** | Replace | multiplatform-settings (`com.russhwolf:multiplatform-settings`) | Standard KMM key-value storage. Wraps SharedPrefs (Android) and NSUserDefaults (iOS). No expect/actual needed. **Consumer note:** When the SDK uses multiplatform-settings internally and the consumer DI module creates `SharedPreferencesSettings` (Android) or `NSUserDefaultsSettings` (iOS), the consumer needs an explicit `implementation("com.russhwolf:multiplatform-settings:1.2.0")` dependency. The SDK's transitive dep exposes the `Settings` interface but not the platform-specific factory classes (`SharedPreferencesSettings`, `NSUserDefaultsSettings`). |
| **ObjectBox** | Abstract **or Replace** | DataStore KMP (simple data) or expect/actual interface + Koin injection (complex queries) | No KMM support. **For simple persistence** (single objects, small lists without queries): use DataStore KMP with `@Serializable` objects and `OkioSerializer` — runs entirely in commonMain, no per-platform implementations needed. See `references/dependency-replacements.md` Typed DataStore section. **For complex queries** (indexes, relations, large datasets): Abstract with expect/actual + Koin injection. |
| **Room** | Replace | Room KMP (2.7+) or SQLDelight | Room has official KMP support since 2.7. SQLDelight is the alternative. |
| **AndroidX ViewModel (< 2.8.0)** | Replace (upgrade) | `androidx.lifecycle:lifecycle-viewmodel` 2.8.7+ | KMP-native since 2.8.0; ViewModel + viewModelScope work directly in commonMain. No expect/actual needed. Just upgrade. **Artifact disambiguation:** Use `androidx.lifecycle:lifecycle-viewmodel`, NOT `org.jetbrains.androidx.lifecycle:lifecycle-viewmodel` (JetBrains repackaged variant with different versioning). |
| **Retrofit + OkHttp** | Replace | Ktor Client | Platform engines via expect/actual (CIO/Android for Android, Darwin for iOS). |
| **RxJava** | Replace | kotlinx-coroutines + Flow | Standard KMM reactive. |
| **Hilt/Dagger** | Replace | Koin | KMM-compatible. When migrating a library consumed by a Hilt app: keep Hilt in the app, add Koin alongside for the library's types, bridge via small module. **Kotlin/Native warning (non-blocking):** Koin 4.0 and kotlinx-serialization reference `kotlin.uuid.Uuid` internally. On Kotlin 2.0.x, iOS native compilation emits warnings like "Unresolved reference: kotlin.uuid.Uuid." Informational only — no build failures or runtime crashes. Resolves on Kotlin 2.1+. |
| **Android Log** | Replace | Custom Logger or Napier/Kermit | Use existing Logger if project has one, otherwise Napier. |
| **java.util.UUID** | Replace | `kotlin.uuid.Uuid` (Kotlin 2.0+) | Built into Kotlin stdlib. |
| **org.json.JSONObject/JSONArray** | Replace | `kotlinx.serialization.json.JsonObject/JsonArray` | Already in most KMM projects. |
| **java.util.concurrent** | Replace | kotlinx.coroutines.sync.Mutex + atomicfu | `@Synchronized` → `Mutex.withLock{}`, `ConcurrentLinkedQueue` → Mutex-guarded MutableList. |
| **Dispatchers.IO** | Keep | `Dispatchers.IO` (with `import kotlinx.coroutines.IO`) | Available on JVM + Native targets since coroutines 1.7.0. Extension property on Native — requires explicit import. NOT available on JS/Wasm. Do NOT replace with `Dispatchers.Default`. |
| **External AAR SDK (no KMM)** | Replace (if KMM exists) or Abstract | Ask user if a KMM/KMP version of the SDK exists (check for KMM branches in the SDK repo). If yes: replace with the KMM version before Phase 4 to avoid building throwaway Android bridge adapters. If no: Abstract with expect/actual interface. | Before building Android-only bridge adapters, always confirm KMM availability with the user — building adapters then discovering a KMM version exists means double work. |

## Coroutines and KMM library version guidance

These libraries version-lock with kotlin-stdlib — mixing causes KLIB ABI errors at iOS link time. Before choosing versions in Phase 2 SCAFFOLD, confirm the project's Kotlin version:

| Kotlin version | Ktor | kotlinx-coroutines | kotlinx-serialization | kotlinx-datetime |
|---|---|---|---|---|
| 2.1+ | 3.x | 1.9.x | 1.8.x | 0.6.x |
| 2.0.x | 2.3.x | 1.8.x | 1.7.x | 0.6.x |

**`Dispatchers.IO` on Native:** Available since coroutines 1.7.0 as an **extension property** — requires `import kotlinx.coroutines.IO` (IDE may not auto-suggest it). Works on JVM + Native targets. NOT available on JS/Wasm — use `expect`/`actual` if targeting those. See `references/platform-api-gotchas.md` for the full platform API reference.

## Wire protobuf specifics

- If proto messages share names with existing classes (e.g., proto `Scrip` vs ObjectBox `Scrip`), add `package` declaration to .proto files so Wire generates into a sub-namespace (e.g., `com.example.proto.Scrip`)
- Wire handles `google.protobuf.Timestamp` automatically
- Migration is mechanical: `Message.parseFrom(bytes)` → `Message.ADAPTER.decode(bytes)`

## iOS database bridge pattern (for ObjectBox, Realm, or any native-only DB)

When a database has no KMM support but has separate iOS/Android SDKs:

1. Define interface in `commonMain` (e.g., `ScripStore`)
2. `androidMain`: implement using the Android SDK directly
3. `iosMain`: define a `Bridge` interface, implement `actual` class that delegates to it
4. Swift: implement the Bridge wrapping the iOS SDK
5. App startup (Swift): create bridge instance → pass to `initKoin()` → Koin resolves

This avoids cinterop entirely — Swift objects enter Kotlin via function parameters.

## DI Binding Patterns

### WebSocket Client Bindings

| Type | Binding | Rationale |
|------|---------|-----------|
| `IWebSocketClient` | `factory` | Each WebSocket service (feed, trading) needs its own connection lifecycle. A `single` binding shares one client instance → message cross-contamination between channels. |
| `HttpClient` | `single` | HTTP clients are stateless request factories — safe to share. |

**Rule:** Any dependency that maintains connection state (WebSocket clients, database connections with session affinity) should be `factory` in Koin, not `single`, when multiple consumers need independent instances. The original code pattern is the indicator: if the original created `N` separate instances (e.g., `val feedClient = KtorWebSocketClientImpl()` + `val tradingClient = KtorWebSocketClientImpl()`), the Koin binding must be `factory`.
