# Canonical sources

Every finding cites one of these URLs or a `references/rules/<file>.md#<rule-id>` reference (whose rule cites a URL below). No citation → drop the finding.

Source priority: tier 1 over tier 2 over anything else. JetBrains > Android > library when tier-1 sources conflict on KMP-specific points. For version-sensitive guidance (concurrency, memory manager, SKIE compatibility), verify current state via Context7 or fresh web search before citing — the canonical pages get updated.

## Tier 1 — JetBrains / Kotlin official

- KMP overview — https://kotlinlang.org/docs/multiplatform.html
- Project structure (commonMain, source sets, targets) — https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html
- Hierarchical project structure — https://kotlinlang.org/docs/multiplatform/multiplatform-hierarchy.html
- Expected and actual declarations — https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html
- Use platform-specific APIs (canonical: expect/actual vs interface+DI) — https://kotlinlang.org/docs/multiplatform/multiplatform-connect-to-apis.html
- Concurrency and coroutines on KMM — https://kotlinlang.org/docs/multiplatform/multiplatform-mobile-concurrency-and-coroutines.html
- Kotlin/Native memory management (post-1.7.20, freezing removed) — https://kotlinlang.org/docs/native-memory-manager.html
- Interop with Swift/Objective-C (canonical: type mapping, @Throws, singletons, generics erasure) — https://kotlinlang.org/docs/native-objc-interop.html
- Kotlin-Swift interopedia (official JetBrains-linked examples) — https://github.com/kotlin-hands-on/kotlin-swift-interopedia
- Kotlin coding conventions — https://kotlinlang.org/docs/coding-conventions.html
- KDoc — https://kotlinlang.org/docs/kotlin-doc.html
- Visibility modifiers — https://kotlinlang.org/docs/visibility-modifiers.html
- Sharing logic tutorial (suspend/Flow exposure) — https://kotlinlang.org/docs/multiplatform/multiplatform-upgrade-app.html
- KMP release notes — https://kotlinlang.org/docs/releases.html

## Tier 1 — Android official

- KMP on Android (Google's position, Jetpack KMP matrix) — https://developer.android.com/kotlin/multiplatform
- Migrating Room to KMP — https://developer.android.com/kotlin/multiplatform/migrate
- Lifecycle ViewModel — https://developer.android.com/topic/libraries/architecture/viewmodel
- Compose docs — https://developer.android.com/jetpack/compose
- Compose API guidelines — https://developer.android.com/jetpack/compose/api-guidelines
- Compose state & lifecycle — https://developer.android.com/jetpack/compose/state, https://developer.android.com/jetpack/compose/lifecycle, https://developer.android.com/jetpack/compose/side-effects
- Android Kotlin style guide — https://developer.android.com/kotlin/style-guide

## Tier 1 — SKIE official (Touchlab)

- SKIE intro — https://skie.touchlab.co/intro
- Features overview — https://skie.touchlab.co/features/
- Flow support — https://skie.touchlab.co/features/flows
- Suspend interop — https://skie.touchlab.co/features/suspend-interop
- Sealed class handling — https://skie.touchlab.co/features/sealed-classes
- Default arguments — https://skie.touchlab.co/features/default-arguments
- Configuration — https://skie.touchlab.co/configuration/
- Sealed configuration — https://skie.touchlab.co/configuration/sealed
- SKIE GitHub — https://github.com/touchlab/SKIE

## Tier 2 — Authoritative library docs (authoritative for that library only)

- Koin KMP — https://insert-koin.io/docs/reference/koin-mp/kmp/
- Koin ViewModel for KMP — https://insert-koin.io/docs/reference/koin-mp/kmp-viewmodel/
- kotlinx.coroutines API — https://kotlinlang.org/api/kotlinx.coroutines/
- kotlinx.coroutines repo — https://github.com/Kotlin/kotlinx.coroutines
- kotlinx.serialization — https://kotlinlang.org/docs/serialization.html
- Ktor client — https://ktor.io/docs/client.html
- SqlDelight — https://sqldelight.github.io/sqldelight/
- KMP-NativeCoroutines — https://github.com/rickclephas/KMP-NativeCoroutines
- Paparazzi — https://github.com/cashapp/paparazzi
- Roborazzi — https://github.com/takahirom/roborazzi
- kotlinx.atomicfu — https://github.com/Kotlin/kotlinx-atomicfu
- Turbine — https://github.com/cashapp/turbine
- Gradle version catalogs — https://docs.gradle.org/current/userguide/platforms.html

## Never cite

- Medium, dev.to, Stack Overflow, Reddit, Slack, forums. They are useful for context, not authority. If a blog repeats canonical guidance, cite canonical.
