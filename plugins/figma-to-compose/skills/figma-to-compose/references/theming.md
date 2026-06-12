# Theming

## Contents
- Option A — Use the extracted tokens directly
- Option B — Wire tokens into Material3 theme slots
- Material3 color roles — rough mapping guide
- Typography roles
- Shapes
- Using fonts
- Dark mode

The `extract-tokens.js` helper produces flat `Color.kt` and `Typography.kt` files. They work as-is — but folding them into a Material3 `ColorScheme` and `Typography` makes them play nice with Material components (`Button`, `Scaffold`, `TopAppBar`, etc.) that read theme values automatically.

This page shows both options. Pick one.

## Option A — Use the extracted tokens directly

Simpler for designs that aren't following Material. Just import and reference:

```kotlin
import com.example.ui.theme.blue0070F3
import com.example.ui.theme.titleTextColor
import com.example.ui.theme.inter28Bold

@Composable
fun LoginScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(20.dp),
    ) {
        Text(
            text = "Welcome back",
            style = inter28Bold,
            color = titleTextColor,
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = {},
            colors = ButtonDefaults.buttonColors(containerColor = blue0070F3),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Sign in")
        }
    }
}
```

Pros: no mapping step, names are self-documenting.

Cons: you have to pass `colors = ...` explicitly to every Material component that has a brand color.

## Option B — Wire tokens into Material3 theme slots

Material3 gives you `colorScheme`, `typography`, and `shapes`. When you wrap a screen in `MaterialTheme`, child components read these via `MaterialTheme.colorScheme.primary`, `MaterialTheme.typography.headlineMedium`, etc., with no extra wiring.

```kotlin
// Theme.kt
package com.example.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = blue0070F3,
    onPrimary = Color.White,
    background = Color.White,
    onBackground = titleTextColor,
    surface = Color.White,
    onSurface = titleTextColor,
    onSurfaceVariant = subtitleTextColor,
    outline = dividerFill,
)

private val DarkColors = darkColorScheme(
    primary = blue0070F3,
    // ...fill in dark values or leave Material defaults
)

private val AppTypography = Typography(
    headlineLarge = inter28Bold,
    bodyLarge = inter16Normal,
    // map each extracted style onto the closest Material3 role
)

@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}
```

Then in screens:

```kotlin
@Composable
fun LoginScreen() {
    Column(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
    ) {
        Text("Welcome back", style = MaterialTheme.typography.headlineLarge)
        Text("Sign in to continue", style = MaterialTheme.typography.bodyLarge)
        Button(onClick = {}) { Text("Sign in") }
    }
}
```

`Button` now uses `primary` / `onPrimary` automatically — no `colors = ...` needed.

Pros: works seamlessly with the Material3 component library, supports dark mode, reads intent clearly.

Cons: you have to decide how each extracted value maps to a Material role, and Material's roles don't always match a custom design 1:1.

## Material3 color roles — rough mapping guide

Material3 has ~30 color roles. The most common mappings from an extracted token to a role:

| Token in your design        | Likely Material role          |
|-----------------------------|-------------------------------|
| Main brand colour (buttons) | `primary`                     |
| Text on brand colour        | `onPrimary`                   |
| Page background             | `background`                  |
| Default text colour         | `onBackground`, `onSurface`   |
| Card background             | `surface`, `surfaceContainer` |
| Muted/secondary text        | `onSurfaceVariant`            |
| Dividers, thin borders      | `outline`, `outlineVariant`   |
| Destructive action          | `error`                       |
| Text on destructive         | `onError`                     |

Anything that doesn't fit a Material role cleanly — keep it as a direct `val` in `Color.kt` and reference it by name. It's fine to mix the two approaches.

## Typography roles

Material3's typography system:

| Role               | Common size range | Typical usage                      |
|--------------------|-------------------|-------------------------------------|
| `displayLarge/Medium/Small` | 36–57sp | Marketing heroes                   |
| `headlineLarge/Medium/Small` | 24–32sp | Screen titles                      |
| `titleLarge/Medium/Small`    | 14–22sp | Card titles, list headers          |
| `bodyLarge/Medium/Small`     | 12–16sp | Paragraphs                         |
| `labelLarge/Medium/Small`    | 11–14sp | Button text, metadata, chips       |

Map extracted `inter<size><weight>` styles to the closest role by size and usage. A 28sp bold title → `headlineMedium` or `headlineLarge`. A 14sp regular paragraph → `bodyMedium`.

## Shapes

Material3 also has a `Shapes` slot. If your design uses consistent corner radii across surfaces (e.g., always 12dp for cards, 8dp for buttons), define:

```kotlin
private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp),
)
```

...and pass it to `MaterialTheme(shapes = AppShapes, ...)`. Components will use the shape appropriate to their size without per-call overrides.

## Using fonts

Fonts are the one place where KMP and Android Compose genuinely differ. The extracted `Typography.kt` marks `fontFamily` as unset because it needs per-project wiring.

### Compose Multiplatform (default)

Drop font files into `composeApp/src/commonMain/composeResources/font/`. Names must be lowercase with underscores (e.g., `inter_regular.ttf`, `inter_medium.ttf`, `inter_bold.ttf`).

In KMP, the `Font()` constructor from `org.jetbrains.compose.resources` is `@Composable`-only — it must be called from inside a composable function, not at module level. That rules out the usual `val InterFontFamily = FontFamily(Font(...))` pattern.

The working pattern is a `@Composable` helper that builds the family, then a `@Composable` typography function that applies it:

```kotlin
// Typography.kt (commonMain)
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import composeapp.generated.resources.Res
import composeapp.generated.resources.inter_regular
import composeapp.generated.resources.inter_medium
import composeapp.generated.resources.inter_bold
import org.jetbrains.compose.resources.Font

@Composable
fun interFontFamily() = FontFamily(
    Font(Res.font.inter_regular, FontWeight.Normal),
    Font(Res.font.inter_medium, FontWeight.Medium),
    Font(Res.font.inter_bold, FontWeight.Bold),
)

// The TextStyle vals from extract-tokens.js have no fontFamily set —
// apply it here, in a composable context:
@Composable
fun appTypography(): Typography {
    val inter = interFontFamily()
    return Typography(
        headlineLarge = inter28Bold.copy(fontFamily = inter),
        bodyLarge = inter16Normal.copy(fontFamily = inter),
        // …map each extracted style to the Material3 slot that fits
    )
}
```

Then in your theme:

```kotlin
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = appTypography(),
        content = content,
    )
}
```

Because `appTypography()` is a composable function (not a val), it's reassembled on each composition — fine, since the `Font` resource lookup caches. If your app doesn't use Material3 `Typography` and you reference the extracted TextStyles directly at call sites, use the same `.copy(fontFamily = inter)` pattern inline, or make per-style composable wrappers (`@Composable fun inter28Bold() = inter28Bold.copy(fontFamily = interFontFamily())`).

### Android-only projects

The TTF/OTF files go in `app/src/main/res/font/` (same naming rule — lowercase, underscores). `Font()` is NOT `@Composable`-only on Android, so the classic module-level val pattern works:

```kotlin
// Type.kt
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

val InterFontFamily = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_bold, FontWeight.Bold),
)
```

Then uncomment and wire `fontFamily = InterFontFamily` inside each TextStyle in `Typography.kt` directly — no composable wrapper needed.

### Google Fonts

Both Android and KMP can use the `androidx.compose.ui.text.googlefonts` API, which downloads fonts at runtime. On KMP, it's available through `org.jetbrains.compose.ui:ui-text-google-fonts`. Works the same way as Android — define a `Font.ResourceProvider` and use `Font(googleFont = GoogleFont("Inter"), fontProvider = provider, ...)`.

## Dark mode

The exporter only reads one appearance from Figma. If the design has a dark-mode variant, export it separately (typically as a separate frame) and merge the two token sets into a single `darkColorScheme(...)` definition. The `detect-variants.js` gate won't flag light/dark on its own — it's driven by node naming, so if the dark variant isn't named with a state token, you'll need to run both exports and reconcile manually.
