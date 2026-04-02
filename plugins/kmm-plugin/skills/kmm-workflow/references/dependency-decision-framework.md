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
| **ObjectBox** | Abstract | expect/actual interface + Koin injection | No KMM support. Separate SDKs exist for Android (Kotlin) and iOS (Swift). Bridge pattern: Kotlin interface in commonMain, Android impl wraps ObjectBox-Android, iOS impl delegates to Swift ObjectBox via Koin-injected bridge. |
| **Room** | Replace | Room KMP (2.7+) or SQLDelight | Room has official KMP support since 2.7. SQLDelight is the alternative. |
| **Retrofit + OkHttp** | Replace | Ktor Client | Platform engines via expect/actual (CIO/Android for Android, Darwin for iOS). |
| **RxJava** | Replace | kotlinx-coroutines + Flow | Standard KMM reactive. |
| **Hilt/Dagger** | Replace | Koin | KMM-compatible. When migrating a library consumed by a Hilt app: keep Hilt in the app, add Koin alongside for the library's types, bridge via small module. |
| **Android Log** | Replace | Custom Logger or Napier/Kermit | Use existing Logger if project has one, otherwise Napier. |
| **java.util.UUID** | Replace | `kotlin.uuid.Uuid` (Kotlin 2.0+) | Built into Kotlin stdlib. |
| **org.json.JSONObject/JSONArray** | Replace | `kotlinx.serialization.json.JsonObject/JsonArray` | Already in most KMM projects. |
| **java.util.concurrent** | Replace | kotlinx.coroutines.sync.Mutex + atomicfu | `@Synchronized` → `Mutex.withLock{}`, `ConcurrentLinkedQueue` → Mutex-guarded MutableList. |
| **Dispatchers.IO** | Keep | `Dispatchers.IO` (with `import kotlinx.coroutines.IO`) | Available on JVM + Native targets since coroutines 1.7.0. Extension property on Native — requires explicit import. NOT available on JS/Wasm. Do NOT replace with `Dispatchers.Default`. |

## Coroutines version guidance

Always check if upgrading kotlinx-coroutines unlocks APIs needed in commonMain:
- **1.9.0+**: Latest stable with full Native support
- **1.8.0+**: Improved Native coroutine support
- **1.7.0+**: New Kotlin/Native memory model (fixes threading issues)

**`Dispatchers.IO` on Native:** Available since 1.7.0 as an **extension property** — requires `import kotlinx.coroutines.IO` (IDE may not auto-suggest it). Works on JVM + Native targets. NOT available on JS/Wasm — use `expect`/`actual` if targeting those. On Native, the IO pool has up to 64 threads (lazily allocated, no elasticity). See `references/platform-api-gotchas.md` for the full platform API reference.

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
