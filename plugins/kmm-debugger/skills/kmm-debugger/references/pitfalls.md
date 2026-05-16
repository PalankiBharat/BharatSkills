# KMM migration pitfalls — symptom → root cause → right fix

When a bug doesn't have an obvious root cause, scan this list. The pitfall framing often gets to the answer faster than tracing the symptom forward through the code.

## 1. commonMain can't read AGP `BuildConfig` → BuildKonfig adopted everywhere

**Symptom**
- Production AAR contains staging URL (or vice versa)
- Users on production builds talk to staging backend; staging users talk to prod
- One Gradle `./gradlew publish` invocation silently produces wrong-flavored AARs

**Root cause**
- AGP's per-flavor `BuildConfig.java` is Android-only — commonMain can't see it
- Migration author chose BuildKonfig as a uniform replacement (it works on both Android and iOS)
- BuildKonfig 0.17.0 generates **one** `BuildKonfig.kt` per Gradle invocation, picked from the `buildkonfig.flavor` property
- The wiring from AGP's product flavor to `buildkonfig.flavor` was either (a) never committed despite being claimed in a commit message, or (b) committed but fragile (depends on `doFirst { project.extra.set("buildkonfig.flavor", ...) }` task-graph hooks)
- Multi-flavor publish requires sequential invocations, one per flavor — easy to miss

**Right fix: `expect/actual` with platform-native config**
- commonMain: `expect object SesameConfig { val baseUrl: String; ... }`
- androidMain: `actual object SesameConfig { actual val baseUrl: String get() = BuildConfig.SESAME_BASE_URL }` — restore AGP `productFlavors { buildConfigField "SESAME_BASE_URL", "..." }` for the cross-platform fields
- iosMain: `actual object SesameConfig { actual val baseUrl: String get() = BuildKonfig.SESAME_BASE_URL }` — iOS still uses BuildKonfig (no AGP available)
- Rename commonMain readers from `BuildKonfig.SESAME_BASE_URL` to `SesameConfig.baseUrl`

**Why this is structurally safer than fixing the BuildKonfig wiring**
- AGP's `productFlavors { buildConfigField }` is a 10+ year primitive — multi-flavor builds in a single invocation, deterministic, no `doFirst` hooks
- `./gradlew publish` on the SDK now produces all 3 Android AARs correctly in one invocation; AGP handles flavors natively
- iOS publish still per-flavor (already was) — unchanged
- Consumer-side experience unchanged — still pulls the single Maven coordinate, GMM variant matching picks the right per-flavor AAR

**Verification**
- `./gradlew sesame-sdk:bundleProductionReleaseAar`
- `unzip -p <aar> classes.jar > /tmp/jar.jar && unzip -p /tmp/jar.jar com/yourpkg/BuildConfig.class > /tmp/BuildConfig.class`
- `javap -c -constants /tmp/BuildConfig.class | grep SESAME_BASE_URL` → expect the prod URL
- Repeat for staging AAR → expect the staging URL

---

## 2. Room KMP suspend DAOs in commonMain → async cache machinery to bridge

**Symptom**
- `getSegmentDetails(context)` returns null briefly after `Sesame.initialize()`
- A pre-existing sync API (e.g., `Sesame.getSegmentDetails(context): SegmentDetails?`) now has a race window where it returns null even when local data exists
- New fields like `internal var segmentDetailsCache: SegmentDetails? = null` were added during the migration
- An observer-collector pattern populates the cache on every Room change

**Root cause**
- Room KMP requires DAO methods in commonMain to be `suspend` or return `Flow` for non-Android targets
- `SesameUserDao.getById(id: Long)` therefore became `suspend`
- The pre-migration API was synchronous (ObjectBox `box.get(id)` was sync)
- To preserve the sync public API, the migration introduced an in-memory cache populated by an observer
- Between `initialize()` returning and the observer's first emission, the cache is null

**Right fix: `runBlocking` from androidMain on a local DAO read**
```kotlin
// androidMain
fun getSegmentDetails(context: Context): SegmentDetails? {
    val id = sesamePreferences.sesameUserId ?: return null
    if (id <= 0) return null
    return runBlocking {
        val entity = sesameUserDao.getById(id) ?: return@runBlocking null
        entity.segment?.let { json ->
            runCatching { SegmentDetails.getSegmentDetailsFromJson(json) }.getOrNull()
        }
    }
}
```

**Why `runBlocking` is fine here (despite migration commits often explicitly rejecting it)**
- The commit that rejected `runBlocking` was almost certainly rejecting it for **network calls** (which can take seconds and block UI)
- A local primary-key Room read is microseconds — sub-millisecond on modern devices
- The cost of `runBlocking` is dispatching to the calling thread; on a fast local read, this is negligible
- The async cache + observer pattern is solving a problem that doesn't exist (it's protecting against a non-existent blocking concern)

**What to delete after the fix**
- The cache field (`segmentDetailsCache`, `journeyCompletionCache`, etc.)
- The observer `scope.launch { dao.observeById(id).collect { ... } }` in `initialize()`
- Any "snapshot-on-init cache" reinvented semantics master had for free

---

## 3. ObjectBox/Realm → Room with no in-place data migration

**Symptom**
- Existing users (mid-journey on old build) get stuck after app upgrade — see "Open Account" CTA again, have to re-OTP
- Init-time refetch was added to compensate, but the network call sometimes fails silently and leaves the user wedged
- `Event.SessionStateRefreshFailed` was added — host code has a `-> Unit` (no-op) branch for it

**Root cause**
- ObjectBox / Realm aren't Kotlin-Multiplatform — they're Android-only
- KMM forces a switch to Room KMP (or SQLDelight)
- The migration shipped without an ObjectBox→Room data migrator
- Existing installs upgrade to an empty Room DB; the `sesameUserId` survives in `SharedPreferences` (multiplatform-settings backing) but Room has no row
- Migration added init-time refetch as a compensation mechanism; the refetch was over-engineered (sealed-result type + failure-event emission + host handler) and the host typically swallows the event with `-> Unit`

**Right fix: investigate whether a real migrator is needed**

First, decide what gets stored: classify each pre-migration entity's fields as **server-recoverable** vs **client-only**:
- Server-recoverable (e.g., `SesameUser` fields hydrated from `GET /user/{id}`): worst case, user does one extra action that triggers a server fetch (re-OTP, open a journey screen) and the new DB hydrates automatically via existing `saveInDb` paths
- Client-only (e.g., `IncomeProofToUploadDetails` with file paths for pending-upload files): genuinely lost without a migrator — user must redo whatever workflow created that state

If everything is server-recoverable (common), **no real migrator is needed**. Apply the hybrid pattern instead:

```kotlin
// commonMain — slim opportunistic one-shot
internal suspend fun rehydrateRoomFromServerIfNeeded(
    sesameUserId: Long,
    dao: SesameUserDao,
    userRemoteStore: UserRemoteStore,
) {
    if (sesameUserId <= 0) return
    if (dao.getById(sesameUserId) != null) return  // already hydrated — no-op
    var fetched: SesameUser? = null
    userRemoteStore.getUser(
        sesameUserId = sesameUserId,
        onSuccess = { user -> fetched = user },
        onFailure = { },  // silent — journey screens recover on next interaction
    )
    fetched?.saveInDb(dao)
}
```

```kotlin
// Sesame.android.kt initialize()
sesamePreferences.sesameUserId?.takeIf { it > 0 }?.let { id ->
    scope.launch {
        rehydrateRoomFromServerIfNeeded(
            sesameUserId = id,
            dao = sesameUserDao,
            userRemoteStore = UserRemoteStore(this@Sesame.httpClient!!),
        )
    }
}
```

**Properties of the hybrid pattern**
- Gated on `dao.getById(id) == null` — runs at most once per upgrade, no-op on subsequent `initialize()` calls
- One-shot self-completing — the `scope.launch` body returns after the single network call resolves; no leak
- Silent on failure — the user's journey screens have their own server fetches that will hydrate Room on next interaction. No event needed.
- No sealed result type, no event class, no host handler — delete those if they were added

**If client-only data exists**, write a real migrator: re-add the old storage as a one-time-use dep (e.g. `compileOnly("io.objectbox:objectbox-kotlin:3.4.0")` in androidMain only), restore the old entity classes for reading, copy rows to Room on first launch post-upgrade, delete the old files, set an idempotency flag in prefs. Plan on ~100-300 LOC.

---

## 4. Init-time coroutine machinery (singleton scopes, observer leaks)

**Symptom**
- App lag develops after 5+ minutes of use
- Heap profile shows growing number of observer references on a Room entity
- "Memory leak detected" warnings in Logcat
- `Sesame.initialize()` is called multiple times per session (re-init on session expiry, on certain screen flows) and each re-init adds collectors

**Root cause**
- Migration introduced `internal val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)` as a singleton — never cancelled
- `initialize()` calls `scope.launch { ... }` for various init-time work — refetch, observer collectors, cache population
- Subsequent `initialize()` calls don't cancel the prior launches
- Long-running collectors (`Flow.collect { }`) accumulate indefinitely

**The constraint**
- The singleton scope often has legitimate use elsewhere — e.g., 24+ fire-and-forget `Sesame.instance!!.scope.launch { sesameUser.saveInDb(...) }` calls for durability across ViewModel teardown
- These are short-lived launches that self-complete after the DB write
- **The scope field stays alive** — only the init-time launches on it need to go

**Right fix: delete init-time launches, prefer self-completing one-shots**

If a launch was only there to support a cache that no longer exists (Pitfall #2 fix) or a refetch that's been reshaped (Pitfall #3 fix), just delete it. The remaining init-time launch, if any, should be:
- Self-completing (e.g., a single network call, gated on a condition that becomes false after the first successful run)
- Not a perpetual observer / collector

```kotlin
// AVOID — never-completing collector in initialize()
scope.launch {
    sesameUserDao.observeById(id).collect { entity -> ... }
}

// PREFER — self-completing one-shot
scope.launch {
    rehydrateRoomFromServerIfNeeded(sesameUserId, sesameUserDao, userRemoteStore)
}
```

**Verification: integration test for re-init**
```kotlin
@Test
fun init_then_init_again_has_no_lingering_children() = runTest {
    Sesame.initialize(...)
    awaitOpportunisticRefetchCompletion()  // or mock the network so it completes immediately
    Sesame.initialize(...)
    awaitOpportunisticRefetchCompletion()
    assertEquals(0, Sesame.instance!!.scope.coroutineContext.job.children.count())
}
```

---

## 5. Transitive dep version drift at consumer (Ktor, Kotlin, etc.)

**Symptom**
- After consuming a KMM SDK alpha, the consumer app's WebSocket / Ktor / serialization behavior changes subtly
- Specific symptom: index-options tick decode fails, causing blank LTP cells (kotlinx.serialization 1.8.0 is stricter than 1.4.x)
- Chart streaming has latency spikes after the SDK bump

**Root cause**
- The SDK's POM declares Ktor / Kotlin / kotlinx-coroutines versions higher than the consumer's declared pins
- Gradle resolves to the **highest** version across the dependency graph
- Consumer's resolved Ktor is now (say) 2.3.11, even though `app/dependencies.gradle` says `implementation "io.ktor:ktor-client-core:2.2.2"`
- The 2.3.x serialization defaults are stricter; payloads that decoded fine on 2.2.x now throw `MissingFieldException`
- The OkHttp engine internals in Ktor 2.3.x have different connection-pool retention characteristics

**Diagnosis**
- `./gradlew dependencies` on the consumer to see resolved versions, not declared ones
- Look at the SDK's published POM (`<sdk-coordinate>/<version>/<artifact>.pom`) — what does the SDK declare for transitives?
- Check if other transitives in the consumer's graph (like an analytics SDK, a charting SDK) are also pulling higher Ktor / Kotlin versions

**Right fix: align the SDK's pins to the consumer's declared intent**

The SDK is downstream of the consumer in terms of "who's the source of truth for pins" — the SDK should conform to the consumer's pins, not the other way around. Catalog edits in the SDK's `gradle/libs.versions.toml`:
```toml
kotlin = "<consumer-declared-version>"
ktor = "<consumer-declared-version>"
```

Verify feasibility before downgrading: check klib manifests in `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/<hash>/default/manifest` for the `compiler_version` field — that's the floor the consumer compiler must meet.

**Caveat: another transitive may still raise the floor**
- If a sibling SDK (e.g., mystique_kmm_sdk-android) pulls Ktor 2.3.5 too, sesame downgrading to 2.2.2 reduces sesame's contribution but the consumer still resolves to 2.3.5
- In that case, the consumer needs `configurations.all { resolutionStrategy.force('io.ktor:*:2.2.2') }` or the sibling SDK also needs to downgrade
- Diagnose with Logcat decode failures first — don't force-pin blind

---

## 6. Multi-flavor publishing limitations (BuildKonfig 0.17.0 specifically)

**Symptom**
- Sesame publish fires off — produces 3 Android AARs + 3 iOS klibs in one Gradle invocation — but all 3 Android AARs contain the same BuildKonfig values (the last flavor's, or the default's)
- No build error; the wrong-flavored AARs are silently published

**Root cause**
- BuildKonfig 0.17.0 generates one `BuildKonfig.kt` per Gradle invocation, based on the `buildkonfig.flavor` Gradle property
- When `./gradlew publish` runs, AGP correctly produces 3 distinct AARs (one per `productFlavor`), but all 3 contain the same `BuildKonfig.kt` from commonMain
- BuildKonfig 0.18+ might fix this but introduces other constraints (e.g., 0.18 leaks kotlin-stdlib 2.3.x onto AARs, breaking consumer compatibility)

**Right fix: use AGP's native variant model instead of BuildKonfig everywhere (see Pitfall #1)**

If `expect/actual` + AGP per-flavor `buildConfigField` is the chosen path:
- BuildKonfig is consumed only by iosMain
- iOS publish is per-invocation anyway (one flavor at a time, with `-Pbuildkonfig.flavor=production` etc.)
- Android publish works in one Gradle invocation because AGP generates per-flavor `BuildConfig.java` natively

If keeping BuildKonfig as the source for both platforms is non-negotiable, the per-flavor publish workflow requires multiple Gradle invocations:
```bash
./gradlew publishProductionFlavor       # internally: ./gradlew publish -Pbuildkonfig.flavor=production
./gradlew publishStagingFlavor
./gradlew publishProdlikestagingFlavor
```
…with wrapper tasks that set the `-P` flag in a `doFirst { project.extra.set("buildkonfig.flavor", "production") }` block. This works but is fragile (task-graph order matters; easy to get wrong).

**The AGP-native variant approach (Pitfall #1) is strongly preferred.**

---

## Cross-cutting principle

When you see multiple pitfalls in a single migration (very common — the same author often makes the same class of mistake in multiple places), the right fix usually involves **deletion** rather than addition. The migration's machinery to bridge the new platform's constraints often does more harm than good. Subtract back to a simpler shape that respects each platform's native mechanisms.

The most common deletion sequence from a real migration:
1. Delete the async cache field + observer collector (Pitfall #2 fix)
2. Delete the singleton-scope perpetual launches in `initialize()` (Pitfall #4 fix)
3. Delete the speculative event class + the host's no-op handler (Pitfall #3 fix's downstream)
4. Reshape one remaining init-time launch as a slim self-completing opportunistic one-shot (Pitfall #3 fix)

Net delta: ~150 lines deleted, ~30 lines added (an `expect/actual` Config trio + a slim refetch function).
