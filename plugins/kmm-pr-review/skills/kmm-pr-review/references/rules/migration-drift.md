# Migration drift

Loaded only when migration is detected. Runs as the master-grounded specialist's lens in **drift mode**.

The migration drift specialist has three responsibilities:

1. **Drift checks** — old code paths left behind, broken consumer wiring, baseline drift (M-* rules below).
2. **iOS-readiness enforcement with elevation** — every `ios-readiness.md` finding with `iOS_blocking: true` is **auto-promoted to P0** for migration PRs. Migration's purpose is iOS consumption; iOS-blocking issues cannot be deferred.
3. **Attribution** — for migrated files, compare master's old-path version against the new commonMain version to attribute each finding as PR-induced vs pre-existing.

Cite as `references/rules/migration-drift.md#<rule-id>`.

---

## Attribution gate (applied to every finding before priority assignment)

For each candidate finding on migrated code:

1. **Locate the master's pre-migration version** at the old path (from `master-baselines/`).
2. **Apply the same rule to that master version.**
3. Classify:
   - Master triggers same rule with same applicability → **Pre-existing** → P3, surfaced under "P3 — Pre-existing (suggested follow-ups)".
   - Master doesn't trigger because the rule didn't apply at the old path (e.g., S-TYPE-01 applies in commonMain but not in androidMain) → **PR-induced (migration caused the violation by changing location)** → full severity, iOS-blocking ones auto-promoted to P0.
   - Master doesn't trigger because the new file changed the code → **PR-induced (migration modified the code)** → full severity.

Default when unclear: PR-induced. If the specialist can't confidently locate a master analog, treat as PR-induced and let the user decide.

---

## M-CLEANUP — old code paths left behind

### M-CLEANUP-01 — Old Android-only file not deleted post-migration
**Severity:** P0 (build break or two sources of truth) | P1 (rename detection missed)
**Pattern:** an addition under `:shared/src/commonMain/.../<X>.kt` without a corresponding deletion of the old Android-only file. Verify by searching the diff for the class/function name in `app/src/main/**`.
**Why:** Two implementations diverge silently. Android consumers may still resolve the old class. Compile may succeed with both present in different packages.
**Suggestion:** Delete the old file. If callers must keep importing the old package temporarily, use a `typealias` in the old location pointing to the new class, with `@Deprecated("Use <new path>", ReplaceWith(...))` and a removal target version.
**Source:** https://kotlinlang.org/api/latest/jvm/stdlib/kotlin/-deprecated/

### M-CLEANUP-02 — Stale Hilt module / `@Inject` annotations
**Severity:** P1
**Pattern:** moved class still carries `@Inject constructor`, `@Module`, `@Provides`, `@Singleton`, `@Binds`; OR a leftover Hilt `@Provides` in `androidApp` references the deleted Android-only class.
**Why:** Hilt is JVM/Android-only. `@Inject` in commonMain doesn't resolve. Orphan Hilt modules point at deleted locations and break the DI graph.
**Suggestion:** Remove Hilt annotations from the moved class. Re-wire via Koin (team convention). Remove orphan `@Provides` blocks.
**Source:** https://dagger.dev/hilt/ + https://insert-koin.io/docs/reference/koin-mp/kmp/

### M-CLEANUP-03 — Orphan Android-only test left behind
**Severity:** P1
**Pattern:** moved class has a test under `androidTest/` or `app/src/test/` that wasn't moved to `commonTest`.
**Why:** Shared logic deserves shared tests. Leaving the test on Android means iOS path is uncovered.
**Suggestion:** Move to `commonTest` if expressible with `kotlin.test`. If JVM-only dependencies, keep in `androidUnitTest` but add commonTest covering the same behavior.
**Source:** https://kotlinlang.org/api/core/kotlin-test/

---

## M-PARITY — iOS consumer wiring

### M-PARITY-01 — Migrated class has no iOS consumer call site
**Severity:** P0 (migration incomplete by definition)
**Pattern:** a feature moved to commonMain whose only consumer change in the diff is Android-side; no SwiftUI view, no iOS ViewModel, no `iosApp/**` change references the migrated symbol.
**Why:** A migration whose purpose is to share code but whose only consumer is still Android hasn't delivered the migration's value. Almost always: iOS is using a parallel implementation (drift) or the iOS update is missing. Either way, the migration is half-done at merge time.
**Suggestion:** Add the iOS consumer change in this PR. If genuinely a follow-up, the PR description must link the tracking issue and the project lead must explicitly sign off.
**Source:** Migration intent.

### M-PARITY-02 — iOS wiring binds concrete class instead of interface
**Severity:** P1
**Pattern:** migration introduces an interface in commonMain but the iOS Koin module (or manual wiring) binds the concrete class instead of the interface.
**Why:** iOS getting the concrete class defeats the abstraction and ties iOS to Android-side behavior. Common when devs move code mechanically without updating iOS DI.
**Suggestion:** Bind the iOS Koin module to the interface; let DI provide the iOS-specific implementation.
**Source:** https://insert-koin.io/docs/reference/koin-mp/kmp/

### M-PARITY-03 — Public API of moved class changed without explicit intent
**Severity:** P0 (if iOS consumer breaks) | P1
**Pattern:** signature differences between master's version of the moved file and the new commonMain version: parameters added/removed/reordered, return type changed, `suspend` modifier added, generic type parameters added/removed, nullability flipped, default argument changes.
**Why:** Migrations should preserve public API unless the PR explicitly says otherwise. Silent API changes invalidate consumer expectations and create bridge-time errors hard to debug.
**Suggestion:** Revert the signature to match, or call out the deliberate change in the PR description and confirm both consumers are updated.
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Library API recommendations)

### M-PARITY-04 — Visibility tightened during migration
**Severity:** P1
**Pattern:** the move added an `internal` modifier (or removed `public` default) where the old code was effectively public.
**Why:** `internal` in a multiplatform module scopes to the module, not the file/package. iOS-side consumers (different binary) still see internal symbols, but Android consumers in different Gradle modules don't. Asymmetric break: Android fails, iOS keeps working.
**Suggestion:** Default `public` for migrated symbols. Tighten to `internal` only after the migration stabilizes and you've confirmed all consumers.
**Source:** https://kotlinlang.org/docs/visibility-modifiers.html

---

## M-VISUAL — Paparazzi / Roborazzi baseline drift (team convention)

### M-VISUAL-01 — Migrated screen has no baseline carryover
**Severity:** P1
**Pattern:** a Compose screen migrated from `app/` to `:shared` (or its Android consumer rewritten to use a migrated VM) without a corresponding Paparazzi/Roborazzi baseline update.
**Why:** Team convention: capture pre-migration baselines, validate migrated screens against them. Skipping = visual regressions slip.
**Suggestion:** Either: (a) add the screen to the Paparazzi/Roborazzi test set if absent; (b) regenerate the baseline if the migration changed structure intentionally (PR description must call this out); (c) attach baseline diff PNGs to the PR.
**Source:** Team convention + https://github.com/cashapp/paparazzi + https://github.com/takahirom/roborazzi

### M-VISUAL-02 — Baseline regenerated without PR-description explanation
**Severity:** P1
**Pattern:** regenerated `.png` baselines in `src/test/snapshots/` or `roborazzi/` with no PR description explaining the visual change.
**Why:** A silently regenerated baseline is the visual equivalent of `--no-edit` on logic — the safety net is gone and no one reviewed the change.
**Suggestion:** PR description must call out which screens changed visually and why.
**Source:** Team convention.

---

## M-BUILD — Gradle / dependency drift

### M-BUILD-01 — Android-only dependency added to commonMain
**Severity:** P0
**Pattern:** the migration PR adds a dependency to `commonMain` in `:shared/build.gradle.kts` that is JVM/Android-only — non-KMP `androidx.*`, AndroidX Test, Robolectric, Mockito, Hilt, anything pulling `android.os.*`.
**Why:** Same as `_base.md#s-type-01` — commonMain compiles for iOS.
**Suggestion:** Move to `androidMain.dependencies { ... }` or replace with a KMP equivalent.
**Source:** https://kotlinlang.org/docs/multiplatform/multiplatform-add-dependencies.html

### M-BUILD-02 — Inconsistent dependency versions across source sets
**Severity:** P1
**Pattern:** same dependency in commonMain/androidMain/iosMain with different versions or different artifact coordinates resolving to the same library.
**Why:** Version skew between source sets is hard-to-debug; manifests as `NoSuchMethodError` only on one platform.
**Suggestion:** Define version once in `gradle/libs.versions.toml`, reference from all source sets.
**Source:** https://docs.gradle.org/current/userguide/platforms.html

---

## M-DOC — migration intent documentation

### M-DOC-01 — Migration PR description doesn't enumerate moved files
**Severity:** P2
**Pattern:** PR body doesn't list (or link to a checklist of) moved files, consumer-side impact, test coverage status, baseline status.
**Why:** Migration PRs are expensive to review without an explicit map.
**Suggestion:** PR description should list at minimum: classes moved, Android consumer updates, iOS consumer updates, commonTest additions, baseline status.
**Source:** Team convention.

---

## When migration drift isn't here

Same rule as everywhere: Context7 → web_search of tier-1 sources. Don't fabricate migration rules — team-specific and hallucinating is worse than missing.
