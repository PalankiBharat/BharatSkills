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
| **SharedPreferences** | Replace | multiplatform-settings (`com.russhwolf:multiplatform-settings`) | Standard KMM key-value storage. Wraps SharedPrefs (Android) and NSUserDefaults (iOS). No expect/actual needed. |
| **ObjectBox** | Abstract | expect/actual interface + Koin injection | No KMM support. Separate SDKs exist for Android (Kotlin) and iOS (Swift). Bridge pattern: Kotlin interface in commonMain, Android impl wraps ObjectBox-Android, iOS impl delegates to Swift ObjectBox via Koin-injected bridge. |
| **Room** | Replace | Room KMP (2.7+) or SQLDelight | Room has official KMP support since 2.7. SQLDelight is the alternative. |
| **Retrofit + OkHttp** | Replace | Ktor Client | Platform engines via expect/actual (CIO/Android for Android, Darwin for iOS). |
| **RxJava** | Replace | kotlinx-coroutines + Flow | Standard KMM reactive. |
| **Hilt/Dagger** | Replace | Koin | KMM-compatible. When migrating a library consumed by a Hilt app: keep Hilt in the app, add Koin alongside for the library's types, bridge via small module. |
| **Android Log** | Replace | Custom Logger or Napier/Kermit | Use existing Logger if project has one, otherwise Napier. |
| **java.util.UUID** | Replace | `kotlin.uuid.Uuid` (Kotlin 2.0+) | Built into Kotlin stdlib. |
| **org.json.JSONObject/JSONArray** | Replace | `kotlinx.serialization.json.JsonObject/JsonArray` | Already in most KMM projects. |
| **java.util.concurrent** | Replace | kotlinx.coroutines.sync.Mutex + atomicfu | `@Synchronized` → `Mutex.withLock{}`, `ConcurrentLinkedQueue` → Mutex-guarded MutableList. |

## Coroutines version guidance

Always check if upgrading kotlinx-coroutines unlocks APIs needed in commonMain:
- **1.8.0+**: `Dispatchers.IO` available in commonMain (previously JVM-only)
- **1.7.0+**: New Kotlin/Native memory model (fixes threading issues)

If the project uses coroutines <1.8.0 and needs `Dispatchers.IO` in commonMain, upgrade as part of the migration.

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
