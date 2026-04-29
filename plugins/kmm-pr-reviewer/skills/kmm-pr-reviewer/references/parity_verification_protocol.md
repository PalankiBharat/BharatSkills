# Parity Verification Protocol

> How a `migrated` or `ios_port` reviewer cross-checks the master version
> against the port. The procedure is mechanical — the reviewer follows it
> step by step, never skipping. "Probably the same" is not parity (Law 5).

## Contents

- [Inputs](#inputs)
- [Step 1 — Read both versions](#step-1--read-both-versions)
- [Step 2 — Enumerate the master surface](#step-2--enumerate-the-master-surface)
- [Step 3 — Verify each surface element in the port](#step-3--verify-each-surface-element-in-the-port)
- [Step 4 — Enumerate side-effects](#step-4--enumerate-side-effects)
- [Step 5 — Cross-check defaults and null handling](#step-5--cross-check-defaults-and-null-handling)
- [Step 6 — Concurrency contract](#step-6--concurrency-contract)
- [Step 7 — Resource references](#step-7--resource-references)
- [Step 8 — Interop pattern](#step-8--interop-pattern)
- [Swift interop](#swift-interop)

## Inputs

From the dispatch prompt:

- `file_path` — the new path at `head_sha`.
- `master_path` — the path on master at `base_sha` (the OG Android source the port replaces). May be `null` if this is a brand-new commonMain file.
- `base_sha`, `head_sha` — from `state.json`.

## Step 1 — Read both versions

```bash
# Master version — full file, not a slice
git show <base_sha>:<master_path>

# Head version — full file
git show <head_sha>:<file_path>
```

Hold both in working memory before walking the checklist. Do not interleave reading and walking — read first, then walk. Reading first prevents the reviewer from anchoring on the port and missing things that exist only on master.

If the master version is empty (paired master file did not exist), skip steps 2–4 and walk only the standalone-checks (steps 7–8 plus universal U1–U4 from review_criteria.md).

## Step 2 — Enumerate the master surface

Build a list of every publicly-visible symbol in the master file:

- Top-level functions: `^(public |internal )?(suspend )?fun .*(`.
- Top-level properties: `^(public |internal )?(val|var) .*`.
- Classes / interfaces / objects / sealed classes: `^(public |internal |open |abstract |sealed )?(class|interface|object) .*`.
- Companion-object members.
- Public members of public classes.

For each symbol, capture the full signature line verbatim. Use Grep with patterns above against the master version. Visibility-private and `internal` symbols that are not used outside the file are out of scope for API parity (they are still in scope for behavioural parity at their call sites — see step 4).

Number the list `S1`, `S2`, … `Sn`. This is the parity ledger.

## Step 3 — Verify each surface element in the port

For each `S<i>` in the parity ledger, locate the corresponding declaration in the port. Acceptable locations:

- Same file at the new path.
- A different file in the same module if the port split one file into several (allowed if the migration intent documents it).
- A different source set if the migration intentionally moved the symbol — allowed only if the migration intent documents it.

For each found declaration, compare verbatim:

- Symbol name.
- Parameter list (types, order, names, default values, nullability, varargs).
- Return type and nullability.
- Generic type parameters and constraints.
- Modifiers: `public` / `internal` / `open` / `final` / `abstract` / `suspend` / `inline` / `infix` / `operator` / `tailrec` / `external`.
- Annotations that are part of the contract: `@JvmStatic`, `@JvmOverloads`, `@JvmName`, `@Throws`, KMP-target-specific annotations.

Differences → `API_DRIFT` (BLOCKER) finding citing both `master_path:line` and `file_path:line`.

If `S<i>` is missing from the port, it is `MISSING_LOGIC` (BLOCKER) unless the migration intent explicitly documents the removal.

## Step 4 — Enumerate side-effects

Side-effects are the regression hot-zone. For each public function (and any private function that one of them transitively calls — limit to two levels of depth on the master side), enumerate the observable side-effects in execution order:

- **Logging**: `Log.d`, `Log.v`, `Log.i`, `Log.w`, `Log.e`, `Timber.d` etc. — capture the level, tag, and message template (or the lambda body for lazy variants).
- **Analytics**: any `analytics.track(...)`, `firebaseAnalytics.logEvent(...)`, `mixpanel.track(...)`, repository-specific tracking calls — capture the event name and the property keys.
- **Network**: every HTTP call. Capture: method (GET/POST/etc.), URL (template), headers explicitly set, request-body type, expected response type. If the file uses Retrofit, the calls are interface methods — track the interface and the actual method called.
- **Database**: every Room / SQLDelight / SQLite call. Capture: DAO/method name, the arguments shape.
- **Filesystem**: every read / write / delete with the path expression.
- **Shared preferences / DataStore**: every `getString` / `putString` / `edit` block — capture the key.
- **Navigation**: `findNavController().navigate(...)`, `nav.popBackStack()`, deep-link emissions, etc.
- **Broadcasts / intents**: every `sendBroadcast`, `startActivity`, `startService`.
- **Side-effect callbacks**: anything that publishes to a `MutableStateFlow`, `MutableSharedFlow`, `LiveData`, `BehaviorSubject` — capture the published value shape and the order.

Number the list `E1`, `E2`, … `Em`. This is the side-effect ledger.

For each `E<j>`, locate the equivalent in the port. Verify:

- The side-effect occurs (existence).
- It occurs in the same execution order relative to other side-effects in the same function.
- The arguments are equivalent (same event name, same log message template, same URL, same DB query shape).

Missing → `MISSING_LOGIC` (BLOCKER). Reordered → `PARITY_DRIFT` (BLOCKER) unless the reorder is provably observationally equivalent (e.g., commutative `setOf` operations on different keys). Argument drift (different event name, different log level) → `PARITY_DRIFT` (BLOCKER).

## Step 5 — Cross-check defaults and null handling

For every parameter with a default value, every property with an initializer, every `?:` Elvis fallback, every `!!` non-null assertion, and every `requireNotNull` / `checkNotNull` / `check` / `require` call — verify the same construct exists in the port with the same value.

Pay particular attention to:

- Default-value drift: `port has retries = 3` vs `master has retries = 5`.
- Sentinel-return drift: master returns `Result.failure(NetworkError("offline"))` and port returns `Result.failure(NetworkError())` — the message changed.
- Eager vs lazy initialization: master uses `by lazy { ... }` and port uses immediate `=` — semantics differ.

Differences → `PARITY_DRIFT` (BLOCKER).

## Step 6 — Concurrency contract

Walk every `launch` / `async` / `withContext` / `flowOn` / `coroutineScope` / `supervisorScope` / `runBlocking` / `runCatching`-with-suspend on master. For each, verify the port has the same construct with the same dispatcher and the same scope.

Specifically:

- `Dispatchers.Main` ↔ `Dispatchers.Main`. Cannot be silently widened to `Dispatchers.Default`.
- `viewModelScope` on master should map to the equivalent KMP-friendly scope on the port (the migration researcher's notes typically document this; in absence, expect `viewModelScope` preserved or a one-to-one wrapper).
- `withContext(Dispatchers.IO)` blocks must remain `withContext(Dispatchers.IO)` — KMP exposes `Dispatchers.IO` via expect/actual, so the call is portable.
- Custom dispatchers wired via DI should be preserved with the same DI shape.

Unsourced changes → `PARITY_DRIFT` (MAJOR). Sourced changes (KMP-compat: e.g., `viewModelScope` not available in `commonMain` so the migration uses `MoleculeViewModel` per researcher's notes) → PASS with the citation in the verdict.

## Step 7 — Resource references

For every `R.string.*`, `R.drawable.*`, `R.dimen.*`, `R.color.*`, `R.layout.*` reference in the master version, locate the corresponding access in the port (which may now go through a `expect`-declared accessor or a string-resource lookup wrapper). Verify the resource ID is unchanged.

If the resource file itself is in the diff (modified `strings.xml`, modified `dimens.xml`), cross-check the value at the referenced key. Value drift → `UI_DRIFT` (MAJOR). Key rename → `SILENT_RENAME` (MAJOR) AND `UI_DRIFT` (MAJOR) — emit both.

## Step 8 — Interop pattern

If the file declares `expect` or `actual` keywords:

- `expect` lives in `commonMain`. The corresponding `actual` lives in `androidMain` (and `iosMain` for entities with iOS targets).
- Verify both sides exist in the diff or were already present on master and remain unchanged.
- If `actual` exists without an `expect`, or vice versa, → `INTEROP_PATTERN_VIOLATION` (MAJOR).

If the file uses dependency injection for platform-specific behaviour (an interface in `commonMain`, implementations registered in `androidMain` / `iosMain` modules):

- The interface lives in `commonMain`.
- Implementations in `androidMain` / `iosMain` are wired via the DI framework the repo already uses (Koin / Hilt / kotlin-inject / Metro / etc. — the migration researcher determined this; do not assume).
- Implementation classes implement every interface member, with matching signatures.
- The DI registration is present and correct in both platforms.

Mixing the two patterns for the same entity (e.g., `expect class FooStore` AND a `FooStore` interface for the same conceptual entity) → `INTEROP_PATTERN_VIOLATION` (MAJOR).

Improvising a pattern (e.g., a `companion object` that branches on `Platform.current`) → `INTEROP_PATTERN_VIOLATION` (MAJOR) AND a recommendation to use the documented pattern.

## Swift interop

For `ios_port` files exposed to Swift consumers, the boundary needs special care:

- **`sealed class` / `sealed interface`** exposed to Swift becomes a base class with disjoint subclasses; Swift cannot exhaustively switch on it without a wrapper. If the migration documents an enum-based wrapper pattern, verify the wrapper exists.
- **`suspend fun`** exposed to Swift becomes an `(arg, completion: (R, Error?) -> Void) -> Void` callback in Objective-C interop. The migration researcher's notes typically prescribe an explicit async-bridge wrapper (e.g., `kotlinx-coroutines-swift` or a hand-rolled `NSObject` wrapper). Verify the wrapper exists if exposed.
- **`inline class` / value classes** are not interop-friendly; verify the file does not expose them across the boundary.
- **Generic types with reified parameters** are not interop-friendly; verify they are not exposed.
- **Companion object** members are accessed via `<Class>.companion.member` from Swift. Verify the JS/Swift interop annotations (`@ObjCName`, `@HiddenFromObjC`, etc.) match the migration researcher's conventions.

Violations → `IOS_TYPE_LEAK` (MAJOR), citing both the offending declaration and the prescribed wrapper from the migration researcher's notes.
