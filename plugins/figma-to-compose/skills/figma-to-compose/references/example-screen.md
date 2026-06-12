# Example: a complete login screen (after Pass 2)

## Contents
- The generated files (LoginScreen.kt, PrimaryButton.kt, Dimensions.kt)
- Key clean-code rules enforced at generation time
- Full worked example with imports, previews, and modifier ordering

This is what the skill's output looks like for a small but realistic screen, AFTER the two-pass code generation has finished. Pass 1 produces a similar file but with inline literals instead of named tokens; Pass 2 produces this final shape.

Read this when you want to see how all the rules from SKILL.md actually compose into a finished file: the ordered modifier chain, the `@Preview` annotation pattern, the `composeapp.generated.resources` import path, the deliberate split between values that earned a named slot in `Dimensions.kt` (used 2+ times) versus values that stayed inline (one-offs).

The file structure mirrors the user's KMP project: the screen lives in `commonMain/kotlin/com/example/ui/screens/login/LoginScreen.kt`, the dimension constants in `Dimensions.kt` next to it, the colour and typography tokens already exist in `theme/Color.kt` and `theme/Typography.kt` (extracted in Step 2 of the pipeline).

---

### What a good output looks like

Every generated file must follow the clean-code rules in compose-clean-code.md (SKILL.md directs reading it before codegen). The key ones to enforce at generation time (the rest come up when iterating):

- **`modifier: Modifier = Modifier` is the first optional parameter.** Always. Required params first, then `modifier`, then everything else.
- **`Dimensions.kt` is for reused values only, not every dp in the design.** `analyze-dimensions.js` walks the screen and emits a `val` **only** for dp values used in 2+ places across the screen. One-off values stay inline at their call site. Many screens won't produce a `Dimensions.kt` at all, which is the correct outcome — a file of single-use constants is noisier than the inline values would be. See Step 4 below for the exact mechanism.
- **Extract tokens from `Color.kt` / `Typography.kt`.** Never inline `Color(0xFF...)` or `TextStyle(...)` in a composable body — reference the named token.
- **PascalCase noun-phrase names** for composables (`OrderCard`, not `renderOrderCard`).
- **`@Preview` for every non-trivial composable**, covering the meaningful states the design implies. Previews must compile without a real ViewModel.
- **No state, no side effects.** A Figma design is static. Don't emit `remember`, `mutableStateOf`, `LaunchedEffect`, or `ViewModel` references unless the user asked for interactivity. Screens take immutable data + event lambdas as parameters.
- **Parameters are state in, events out.** Callbacks are `() -> Unit` or `(T) -> Unit`. Never pass a ViewModel into a reusable composable.
- **KMP resource imports.** Icons and images come from `Res.drawable.X` (imported from `<your-module>.generated.resources.*`), not `R.drawable.X`. `painterResource` comes from `org.jetbrains.compose.resources`, not `androidx.compose.ui.res`. Use the user's actual module name — `composeapp`, `shared`, `composeApp`, or whatever they told you — lowercased, in the import path.

For a simple login screen — note that `Dimensions.kt` contains only the few values used more than once across the screen; one-offs are inline:

```kotlin
// Dimensions.kt — emitted only when the analyzer finds ≥ 2× reuse
package com.example.ui.screens.login

import androidx.compose.ui.unit.dp

// used 2×, derived from node names — both PrimaryButton instances
val PrimaryButtonHeight = 52.dp

// used 3×, generic name — shared by multiple cards in the design
val CardCornerRadius = 12.dp
```

```kotlin
// LoginScreen.kt — commonMain source set
package com.example.ui.screens.login

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview   // CMP 1.10+; old code may use org.jetbrains.compose.ui.tooling.preview.Preview
import com.example.ui.theme.*
import composeapp.generated.resources.Res            // adjust module name to match the user's project
import composeapp.generated.resources.ic_logo
import org.jetbrains.compose.resources.painterResource

@Composable
fun LoginScreen(
    modifier: Modifier = Modifier,
    onSignIn: () -> Unit = {},
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(loginScreenFill)
            .padding(horizontal = 20.dp, vertical = 80.dp),   // one-offs → inline
        verticalArrangement = Arrangement.spacedBy(16.dp),    // single gap → inline
    ) {
        Icon(
            painter = painterResource(Res.drawable.ic_logo),
            contentDescription = null,
            tint = Color.Unspecified,  // preserve original colours for a logo mark
            modifier = Modifier.size(48.dp),                  // single logo size → inline
        )
        Text(
            text = "Welcome back",
            style = inter28Bold,
            color = titleTextColor,
        )
        Text(
            text = "Sign in to continue",
            style = inter16Normal,
            color = subtitleTextColor,
        )
        Spacer(Modifier.weight(1f))
        PrimaryButton(
            label = "Sign in",
            onClick = onSignIn,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
fun PrimaryButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(PrimaryButtonHeight),     // extracted — used 2×
        colors = ButtonDefaults.buttonColors(containerColor = blue0070F3),
        shape = RoundedCornerShape(CardCornerRadius),        // extracted — used 3× across cards
    ) {
        Text(label, style = inter16Normal, color = Color.White)
    }
}

@Preview
@Composable
private fun LoginScreenPreview() {
    LoginScreen()
}

@Preview
@Composable
private fun LoginScreenLongTextPreview() {
    // Cover the long-text case since copy is usually the first thing to change.
    LoginScreen()
}
```

Points worth noting:
- `modifier` is the first optional parameter (required params, then `modifier`, then the rest).
- `Dimensions.kt` holds only `PrimaryButtonHeight` and `CardCornerRadius` because those are the only dp values reused across the screen. The 20.dp / 80.dp / 16.dp / 48.dp values stay inline because each appears once. This split comes from `dimensions.json`, not from your judgment.
- `PrimaryButton` is a separate composable because `detect-components.js` flagged it as reused — not because I arbitrarily split it.
- `@Preview` functions are `private`. Plain `@Preview` (no arguments) matches CMP 1.10's common annotation; `name = "..."` and `showBackground = true` parameters are Android-only.
- No state, no `remember`, no side effects — the design is static.
- Resource imports: `composeapp.generated.resources.Res` + one import per drawable. The `composeapp` prefix is the user's module name lowercased — `shared`, `composeApp`, `common-ui`, etc. Ask if you're unsure.

This shows the *final* shape after Pass 2 has done its replacements. **Pass 1's output looks different** — it has inline `Color(0xFF...)`, inline `TextStyle(...)`, inline dp values, no `loginScreenFill` references, no `Inter28Bold` references. Pass 1 produces compilable code that LOOKS like the design; Pass 2 polishes it into idiomatic code that USES the user's design system.
