# Kotlin Multiplatform: expect/actual boundaries

Design-vocabulary reference for choosing the right seam between common and platform code. Consulted primarily by Phase A (per-file seam strategy decisions) and Phase D (foundation `expect`/`actual` setup).

## Core principle

Keep common APIs semantic and stable. Put platform mechanics behind small `expect`/`actual` declarations or interfaces, and keep Android/iOS/Desktop details out of `commonMain`.

## When to use this reference

Consult when common code needs:

- Permissions, settings, intents, share sheets, deep links, haptics, biometrics, or clipboard.
- Files, paths, clocks, locale, network reachability, sensors, crypto, media, maps, camera, native SDKs, or platform services.
- Native platform views, controllers, or Compose Multiplatform interop.
- Different implementation details on Android, iOS, Desktop, or Wasm while preserving one shared call site.
- A decision between `expect/actual`, dependency injection, interfaces, or separate platform code.

## Choose the boundary

| Situation | Prefer |
|---|---|
| Simple compile-time platform specialization | `expect`/`actual` function, value, typealias, or leaf composable |
| Implementation needs injected dependencies, lifecycle ownership, runtime choice, or test fakes | Common interface plus platform binding |
| UI is mostly shared, one leaf differs | Common composable calling an `expect` leaf |
| Entire screen differs by platform | Separate platform screens behind a common navigation contract |
| Only constants/resources differ | Common API exposing semantic values, actual values per platform |

## Keep common APIs semantic

Common code should describe what the product needs, not how the platform does it:

```kotlin
// GOOD: common API is semantic
expect fun currentRegion(): Region
```

```kotlin
// BAD: common API leaks Android implementation
expect fun currentRegionFromAndroidLocale(context: Context): Region
```

The Android actual can use `Locale` APIs. The iOS actual can use Foundation APIs. Callers should not know.

## Keep actuals thin

Actual implementations should translate the semantic API into platform calls. If the operation needs an Activity, view controller, lifecycle owner, DI, or fakes, prefer an interface supplied by platform code instead of an `expect class`:

```kotlin
// commonMain
interface ShareSheet {
    suspend fun shareText(text: String)
}
```

```kotlin
// androidMain
class AndroidShareSheet(
    private val activity: Activity,
) : ShareSheet {
    override suspend fun shareText(text: String) {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        activity.startActivity(Intent.createChooser(intent, null))
    }
}
```

The Android implementation is explicitly Activity-owned. A generic `Context` may need `FLAG_ACTIVITY_NEW_TASK` and usually hides the UI lifecycle requirement. Define what `suspend` means: for many platform UI actions it means "the sheet was launched", not "the user completed sharing."

If the actual starts accumulating business rules, move those rules back to common code and leave only platform translation in the actual.

## Prefer interfaces when tests or DI matter

Use `expect/actual` for simple compile-time platform APIs. Use interfaces when common code needs fakes, multiple implementations, runtime selection, or lifecycle ownership:

```kotlin
interface Clipboard {
    suspend fun setText(text: String)
}
```

Platform modules bind `Clipboard` to Android/iOS implementations. Common tests use a fake.

## Inject-the-collaborator seam (static-accessor / companion-facade domain models)

A recurring KMM blocker: a domain model whose `companion object` exposes `get()` / `create()` / `sync()` that **self-instantiate a service-located store** (`BankRepository()`, a static singleton). The model can't move to `commonMain` — the static accessor reaches Android/service-locator code — and it can't be baselined, because the collaborator isn't injectable.

**Standard seam: constructor-inject the collaborator; demote the companion accessor to a thin delegator (or a repository method).** The store becomes an interface supplied to the model/use-case, not something the model reaches for itself.

```kotlin
// BEFORE — companion self-instantiates a service-located store (blocks commonMain + baselining)
data class BankDetailsModel(/* … */) {
    companion object {
        fun get(id: String) = BankRepository().findBank(id)   // static reach-out
    }
}

// AFTER — collaborator injected; model is a plain commonMain data class
interface BankRepository { fun findBank(id: String): BankDetailsModel? }   // commonMain
class GetBankDetails(private val repo: BankRepository) {                    // injected, fakeable
    operator fun invoke(id: String) = repo.findBank(id)
}
```

The model is now commonMain-clean and the use-case is baselineable with a hand-rolled fake. **Migrate the model and its facade→repository conversion together** — they're one unit (see phase-d D.1 dependency-coupled chains). Note: a companion accessor that *looks* dead under a single-line grep may be live via builder-style newline call sites — verify with a multiline search before treating it as removable (phase-0 §6.5).

## Compose-specific guidance

- Keep platform-specific Composables at leaf nodes.
- Pass `Modifier` through every expected Composable that emits UI.
- Avoid platform types in `commonMain` signatures (`Context`, `Activity`, Android resource IDs, `Uri`, `Bundle`, `UIViewController`, `NSBundle`, platform permission enums, etc.).
- If native view lifecycle matters, hide it inside the platform actual and use the right interop container (`AndroidView`, `UIKitView`, etc.).
- Do not launch platform work directly from a Composable body. Use `remember`, `LaunchedEffect`, `DisposableEffect`, and stable keys inside actual Composables just as you would in common Compose code.
- Make previews/tests use common plain UI composables with fake platform services where possible.

## Common mistakes

| Mistake | Fix |
|---|---|
| `commonMain` API exposes Android/iOS types | Replace with semantic common types |
| `expect` function has parameters for one platform only | Move those details into the actual |
| Business branching duplicated in each actual | Move business rules to common code |
| One huge `Platform` expect object | Split by capability: `Clipboard`, `ShareSheet`, `Haptics` |
| Platform UI leaks high in the tree | Push platform-specific Composable to a leaf |
| No fakeable boundary for common tests | Use an interface instead of direct `expect` call |

## Red flags during review

- Common code imports platform packages.
- An actual implementation knows product state, navigation decisions, or domain rules.
- A platform API name appears in a common function name.
- Adding a third platform would require changing common callers.
- Tests need Android/iOS runtime just to verify common business behavior.
