> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both.

# 11. Workers / Receivers / Services

> Paths: `app/src/main/java/.../**/*Worker.kt`, `*Receiver.kt`, `*Service.kt`.
> Stack: **JVM-only.** WorkManager, `BroadcastReceiver`, and
> `Service` are Android-framework primitives. They stay in `app/`
> and **do not need baseline tests** for the KMM migration.

### Responsibility

WorkManager workers: background jobs (sync, retry queues, polling
fallbacks). BroadcastReceivers: respond to system events. Services:
long-running foreground work (rare in this codebase).

### What to mock

- ✅ Use cases / repositories the worker invokes — fakes preferred for consistency, but MockK / Mockito are allowed here since Workers / Receivers / Services live permanently in `:app/src/test/` (JVM-only). They never promote to `commonTest`, so the freeze-contract / KMM-portability constraints that ban MockK in baseline source sets don't apply.
- ✅ Logger and analytics.
- ❌ Don't mock `WorkerParameters` — pass a real one via `TestListenableWorkerBuilder` (transitive of WorkManager).

### Coverage checklist

**Outcome**
- [ ] Happy path returns `Result.success()` and persists output Data (if any).
- [ ] Transient failure returns `Result.retry()`.
- [ ] Permanent failure returns `Result.failure()` with a typed reason.
- [ ] Cooperative cancellation: stopped mid-run, returns promptly, no partial-write.

**Backoff**
- [ ] After N consecutive failures, the worker stops scheduling itself / surfaces an error.

**Receivers**
- [ ] `onReceive` with the expected `Intent` action triggers the handler.
- [ ] `onReceive` with an unrelated action is a no-op.
- [ ] `onReceive` with a malformed extras bundle does not crash.

### Template (Worker — JVM-only)

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class WatchlistSyncWorkerTest {

    private lateinit var context: Context
    @Mock private lateinit var syncUseCase: ISyncWatchlistUseCase

    @Before fun setUp() {
        MockitoAnnotations.openMocks(this)
        context = ApplicationProvider.getApplicationContext()
    }

    @Test fun `success on remote sync returns success`() = runTest {
        whenever(syncUseCase.perform()).thenReturn(Result.success(Unit))
        val worker = TestListenableWorkerBuilder<WatchlistSyncWorker>(context)
            .setWorkerFactory(workerFactoryWith(syncUseCase))
            .build()

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())
    }

    @Test fun `IOException returns retry`() = runTest {
        whenever(syncUseCase.perform()).thenThrow(IOException())
        val worker = TestListenableWorkerBuilder<WatchlistSyncWorker>(context)
            .setWorkerFactory(workerFactoryWith(syncUseCase))
            .build()

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
    }
}
```

### Anti-patterns

- Calling `worker.doWork()` without injecting test doubles — defaults to real network/DB.
- Assuming WorkManager will retry. Test the worker, not WorkManager.
- Adding workers to the migration baseline source set. They aren't migration-bound.

---

