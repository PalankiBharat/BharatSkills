> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 10. Composables / Pages

> Path: `app/src/main/java/.../view/**/*Page.kt`
> Stack: **JVM-only.** Native UI strategy: Composables stay in
> `androidMain`, are not migration-bound, and **do not need
> baseline tests** for the KMM migration. Test as normal Android
> unit tests under `app/src/test/`.
> Notes: `androidx.compose.ui:ui-test-junit4` + Robolectric is wired, so Compose tests run as **JVM unit tests**, not instrumented.

### Why no baseline tests

Composables are pure UI. Under the native-UI KMM strategy
(Compose on Android, SwiftUI on iOS), they don't move to `:shared`.
The shared business logic (ViewModel/Presenter) carries the
behavioral contract; visual regressions are caught by
Paparazzi/Roborazzi golden images, not by `commonTest`.

If your project later adopts Compose Multiplatform, revisit — the
Compose test stack has KMP equivalents (`@OptIn(ExperimentalTestApi::class)`,
`runComposeUiTest { … }`), but that's deferred under the current
12–18 month strategy.

### Responsibility

Render a state to pixels and forward gestures to a callback /
ViewModel. Should be **stateless** — state hoisting is non-negotiable
(Constitution I).

### What to mock

- ✅ The state model (`SomeUiState`) — pass a real instance, not a mock.
- ✅ Callbacks — pass lambdas with `var captured: …` assertion variables.
- ❌ Don't mock `Modifier`, `MaterialTheme`, or anything in the Compose API.

### Coverage checklist

**Rendering**
- [ ] Each `UiState` branch (Loading / Loaded / Error / Empty) renders the right content.
- [ ] `testTag` (with `testTagsAsResourceId = true`) set on every element an Appium test or screenreader needs — assert via `onNodeWithTag(...)`.
- [ ] Content descriptions present on icons and clickable surfaces (Constitution VII).
- [ ] Dark mode + light mode previews don't crash.
- [ ] Edge-to-edge insets respected.

**Interaction**
- [ ] Tap on the primary CTA invokes the callback with the right payload, exactly once.
- [ ] Long-press / swipe gestures (where the spec defines them) fire.
- [ ] Disabled state actually blocks the click.

**Accessibility**
- [ ] All interactive elements have a content description or visible text.
- [ ] Touch targets ≥ 48dp.

### Template (JVM-only — JUnit 4 + Robolectric)

```kotlin
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MarketProtectionPageTest {

    @get:Rule val composeRule = createComposeRule()

    @Test fun `Loaded state shows protection toggle`() {
        composeRule.setContent {
            MaterialTheme {
                MarketProtectionPage(
                    state = MarketProtectionUiState.Loaded(isOn = true),
                    onToggle = {}
                )
            }
        }

        composeRule.onNodeWithTag("market_protection_toggle")
            .assertIsDisplayed()
            .assertIsOn()
    }

    @Test fun `tapping toggle invokes callback with new value`() {
        var captured: Boolean? = null
        composeRule.setContent {
            MarketProtectionPage(
                state = MarketProtectionUiState.Loaded(isOn = false),
                onToggle = { captured = it }
            )
        }

        composeRule.onNodeWithTag("market_protection_toggle").performClick()

        assertThat(captured).isTrue()
    }
}
```

### Anti-patterns

- Asserting on pixel positions or screen sizes.
- XPath-like node hierarchy assertions. Use `testTag`.
- Putting business logic inside the Composable to make it "self-contained for testing" — hoist the state.
- Using Espresso for Compose. Wire is `compose.ui.test`.
- Adding Composables to the migration baseline source set. Composables aren't migration-bound.

---

