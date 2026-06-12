# Asset pipeline

## Contents
- SVGs — automated (svg-to-xml.js)
- SVGs — manual alternatives (Android Studio, Valkyrie)
- PNGs and density buckets
- Resource naming
- contentDescription — don't skip
- Asset references in generated Compose code
- Verification catches substitutions

The exporter produces two kinds of files:

```
figma-out/<screen>/assets/
├── icons/*.svg    # vector icons — single colour or multi-colour
└── images/*.png   # raster images — photos, complex illustrations, anything with image fills
```

Neither is directly usable by Android; both need a short conversion/placement step before Compose code can reference them. For SVGs, the skill includes an automated converter (`scripts/svg-to-xml.js`) that handles the common case. For PNGs and complex SVGs, you still need a manual step.

## SVGs — automated

Run `scripts/svg-to-xml.js` on the exporter output. It produces VectorDrawable XML in the right directory for either KMP or a standard Android project.

### Compose Multiplatform (KMP)

```bash
node scripts/svg-to-xml.js ./figma-out/<screen>/assets/icons \
    --target kmp \
    --project <path-to-your-kmp-project>
```

Output lands at `<project>/composeResources/drawable/ic_<n>.xml`. Reference in Compose:

```kotlin
import your_module.composeresources.Res
import your_module.composeresources.ic_union
import org.jetbrains.compose.resources.painterResource

Icon(
    painter = painterResource(Res.drawable.ic_union),
    contentDescription = null,
    modifier = Modifier.size(24.dp),
)
```

### Standard Android project

```bash
node scripts/svg-to-xml.js ./figma-out/<screen>/assets/icons \
    --target android \
    --project <path-to-app-module>
```

Output lands at `<app-module>/res/drawable/ic_<n>.xml`. Reference:

```kotlin
Icon(
    painter = painterResource(R.drawable.ic_union),
    contentDescription = null,
    modifier = Modifier.size(24.dp),
)
```

### What the converter handles

- Single and multi-path SVGs
- Solid fills (`#RRGGBB`, `#RGB`, `#RRGGBBAA`, named colours, `rgb()`, `rgba()`)
- `fill-opacity` (baked into the alpha channel)
- `fill-rule` (→ `android:fillType`)
- Strokes (colour + width)
- viewBox-only SVGs (width/height default to viewBox dimensions)

### What it rejects (with a clear fallback)

Unsupported features cause the specific file to be skipped, with a message:

- Linear/radial gradients
- `<clipPath>`, `<mask>`, `<filter>`
- `<text>`, `<use>`, `<image>`
- `transform=` on individual paths

For these, use [Valkyrie](https://github.com/ComposeGears/Valkyrie) (plugin or CLI) — it handles the full SVG feature set and produces Compose `ImageVector` code.

## SVGs — manual alternatives

If you prefer `ImageVector` output over `VectorDrawable` XML, or you want tighter IDE integration:

### Valkyrie

IntelliJ / Android Studio plugin + CLI. Right-click an SVG → "Convert to ImageVector". Produces:

```kotlin
val AppIcons.Union: ImageVector
    get() = /* lazy builder */

// Usage:
Icon(imageVector = AppIcons.Union, contentDescription = null)
```

Supports Compose Multiplatform. Actively maintained.

### svg-to-compose (Gradle plugin)

Integrates into the build — icons regenerate automatically when SVG sources change:

```kotlin
// build.gradle.kts
plugins {
    id("dev.tonholo.s2c") version "<latest>"
}
```

Drop SVGs into `src/main/svgs/`, run `./gradlew generateS2cIcons`, reference as `AppIcons.Union`.

### Android Studio Vector Asset tool

Built-in, no plugin. `File → New → Vector Asset → Local file (SVG, PSD)`. Produces `VectorDrawable` XML in `res/drawable/` — same format as this skill's auto-converter, just manual. Doesn't support gradients, text elements, or dashed paths.

## PNGs

These need manual placement. Exporter defaults to `--scale 2` (roughly `xhdpi`). For crisper assets on high-density devices, re-run with `--scale 3` or `--scale 4`.

| Exporter scale | Target folder (Android)           | Target folder (KMP)                    |
|----------------|-----------------------------------|-----------------------------------------|
| `--scale 1`    | `res/drawable-mdpi/`              | `composeResources/drawable-mdpi/`      |
| `--scale 2`    | `res/drawable-xhdpi/` (default)   | `composeResources/drawable-xhdpi/`     |
| `--scale 3`    | `res/drawable-xxhdpi/`            | `composeResources/drawable-xxhdpi/`    |
| `--scale 4`    | `res/drawable-xxxhdpi/`           | `composeResources/drawable-xxxhdpi/`   |

Rename each file so it's a valid Android resource name (lowercase, underscores):

```bash
cd figma-out/<screen>/assets/images
for f in *.png; do
    mv "$f" "$(echo "$f" | tr A-Z a-z | tr '-' '_')"
done
```

Reference from Compose:

```kotlin
Image(
    painter = painterResource(id = R.drawable.hero_banner),
    contentDescription = null,
    contentScale = ContentScale.Crop,
)
```

For KMP, use `Res.drawable.hero_banner`.

## Resource naming

The exporter uses kebab-case, Android wants snake_case, and resource names must start with a letter. `svg-to-xml.js` handles this automatically (adds `ic_` prefix by default). For PNGs, rename manually per the `tr` command above.

If two files sanitise to the same name, the exporter's collision suffix (`foo-2.svg`) carries through to `foo_2` — valid, just ugly.

## `contentDescription` — don't skip

Every `Image` / `Icon` needs a `contentDescription`. Decorative assets: `null`. Meaningful icons: a short string for the screen reader. When generating code, use the node's `name` in `screen.json` as a starting point:

```kotlin
Icon(
    painter = painterResource(Res.drawable.ic_search),
    contentDescription = "Search",
)
```

If the icon is inside a `Button` / `IconButton` with its own text label, pass `null` for the icon to avoid double-announcement.

## Asset references in generated Compose code

When emitting code from `screen.json`, an `asset` field like:

```json
"asset": { "kind": "icon", "path": "assets/icons/ic-search.svg" }
```

...translates to (after `svg-to-xml.js` with KMP target):

```kotlin
Icon(
    painter = painterResource(Res.drawable.ic_search),
    contentDescription = null,
    modifier = Modifier.size(24.dp),
)
```

...or (after `--target android`):

```kotlin
Icon(
    painter = painterResource(id = R.drawable.ic_search),
    contentDescription = null,
    modifier = Modifier.size(24.dp),
)
```

For `"kind": "image"`, use `Image(...)` instead of `Icon(...)` — `Icon` applies a tint by default which usually ruins a photo.

## Verification catches substitutions

`verify.js` errors out if the emitted Kotlin references a drawable name that wasn't in the export this run (catches invented references like `R.drawable.ic_profile` when only `union.svg` was exported), or if exported assets go unreferenced (catches silently skipping a Figma node). Always run it after generation.
