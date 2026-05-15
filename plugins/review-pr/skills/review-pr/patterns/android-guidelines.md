# Android Framework Guidelines

Apply patterns for the detected tech stack. The TechStackProfile is injected into your agent prompt by the coordinator (see SKILL.md Step 0 and Step 3). Check the "Tech Stack" section at the top of your prompt for values like `networking: ktor`, `di: hilt`, etc. If a category shows `unknown`, flag "unknown stack — review manually" and do not apply stack-specific rules for that category.

## Resources
Hardcoded strings in code → `strings.xml`. Hardcoded colors/hex → `colors.xml`. Hardcoded dp/sp literals → `dimens.xml`. Drawable paths hardcoded → resource reference. Flag any user-facing string not using `R.string.*`.

## Background Work
Data sync triggered from Activity/Fragment → `WorkManager`. Recurring `Handler.postDelayed` for background tasks → `WorkManager`. `GlobalScope.launch` for background work → `viewModelScope` or `WorkManager`. Minimum WorkManager interval is 15 minutes.

## Data Persistence
Sensitive data (tokens, passwords) in plain `SharedPreferences` → encrypted `DataStore` — flag as blocker. `SharedPreferences.Editor.commit()` (blocks main thread) → `apply()`. Room `@Query` functions not returning `Flow<>` — flag if the data is observed reactively.

## Networking (Ktor for this project)
New `HttpClient` instance created per request → singleton. Network call in Fragment/Activity → move to ViewModel. No timeout configured on `HttpClient` → flag. Auth headers not injected via a Ktor plugin/interceptor → flag. No retry strategy on transient network failures → flag.

## DI Scoping (detect from TechStackProfile.di)
`@Provides` function without a scope annotation → flag (defaults to unscoped — new instance every injection). Expensive objects (database, HTTP client) without `@Singleton` → flag. `@Singleton` applied to a ViewModel-lifetime dependency → flag (wrong scope, will outlive ViewModel).

## UI State
Mutable state (`MutableStateFlow`, `MutableLiveData`) exposed as public property from ViewModel → flag. Multiple separate state flows where a single sealed state class would suffice → flag. `StateFlow` collected in Compose without `collectAsStateWithLifecycle()` → flag.

## Permissions
Permission requested at app startup without contextual trigger → flag. `requestPermissions()` without checking `shouldShowRequestPermissionRationale()` first → flag. Old `onRequestPermissionsResult()` → migrate to `ActivityResultContracts.RequestPermission()`.

## Notifications
`NotificationCompat.Builder` without channel ID → flag (crashes on Android 8+). `IMPORTANCE_HIGH` for promotional/non-urgent notifications → flag (should be `IMPORTANCE_LOW`). No notification ID → flag (can't update or cancel). No `PendingIntent` → flag (notification taps do nothing).

## App Startup
Heavy initialisation in `Application.onCreate()` → `Initializer` (App Startup library). Optional library initialised eagerly → mark `tools:node="remove"` and initialise lazily. Single-use lazy values not using `by lazy {}` → flag.

## Memory
`BitmapFactory.decodeResource()` without `inSampleSize` → flag (OOM risk on large images). Broadcast receiver registered without matching `unregisterReceiver` in lifecycle cleanup → flag.

## Kotlin Idioms
`class` used for state that is copied/compared → `data class`. Mutable collection returned from public API → immutable collection. State without sealed class hierarchy → flag when multiple distinct states exist. Non-exhaustive `when` on sealed class (with `else`) → flag.
