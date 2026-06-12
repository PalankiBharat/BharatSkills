# Figma → Jetpack Compose mapping reference

Exhaustive field-by-field guide to translating a `screen.json` node (as produced by `figma-to-json.js`) into Compose code.

## Table of contents

- [Node types → composables](#node-types--composables)
- [Layout (auto-layout → Row/Column/Box)](#layout)
- [Sizing](#sizing)
- [Spacing, padding, alignment](#spacing-padding-alignment)
- [Backgrounds and fills](#backgrounds-and-fills)
- [Strokes](#strokes)
- [Corner radius](#corner-radius)
- [Shadows and effects](#shadows-and-effects)
- [Rotation and opacity](#rotation-and-opacity)
- [Text](#text)
- [Images and icons](#images-and-icons)
- [Instances (reusable components)](#instances)
- [Modifier chain ordering](#modifier-chain-ordering)

---

## Node types → composables

| Figma `type`              | Compose primitive                                                       |
|---------------------------|--------------------------------------------------------------------------|
| `FRAME`, `COMPONENT`      | `Column` / `Row` / `Box` depending on `layout.mode`                      |
| `GROUP`                   | `Box` (groups don't have their own layout mode in Figma)                 |
| `INSTANCE`                | Call to a shared `@Composable` function for that component               |
| `RECTANGLE`, `ELLIPSE`    | `Box` with `Modifier.background(...)` + `Modifier.clip(RoundedCornerShape(...))` or `CircleShape` |
| `TEXT`                    | `Text(...)`                                                              |
| `VECTOR`, `BOOLEAN_OPERATION` | `Icon(painter = painterResource(...), ...)` or `Image` |
| `LINE`                    | `Divider` (if horizontal/vertical) or `Box` with fixed height/width      |
| `SECTION`                 | Treat as a `FRAME` — it's just an organizational container               |
| `SLICE`                   | Skip — it's an export-only node, the exporter handles it                 |
| `CANVAS`                  | The page; treat as a plain `Box` around its children                     |

If a node has `asset` in its JSON, that takes precedence — render it as an `Image` or `Icon` with the referenced resource, ignoring its children (those have been rasterized into the asset).

---

## Layout

Figma's auto-layout fields live under `layout` in the JSON.

| JSON path                       | Meaning                         | Compose                                                  |
|---------------------------------|---------------------------------|----------------------------------------------------------|
| `layout.mode === "VERTICAL"`    | Auto-layout, vertical stack     | `Column { ... }`                                         |
| `layout.mode === "HORIZONTAL"`  | Auto-layout, horizontal stack   | `Row { ... }`                                            |
| `layout` missing / `mode == "NONE"` | No auto-layout              | `Box { ... }` with `Modifier.offset` on children         |

### Primary-axis alignment

| `layout.primary` value | `Row` arg                                    | `Column` arg                                 |
|------------------------|----------------------------------------------|----------------------------------------------|
| `MIN`                  | `horizontalArrangement = Arrangement.Start`  | `verticalArrangement = Arrangement.Top`      |
| `CENTER`               | `horizontalArrangement = Arrangement.Center` | `verticalArrangement = Arrangement.Center`   |
| `MAX`                  | `horizontalArrangement = Arrangement.End`    | `verticalArrangement = Arrangement.Bottom`   |
| `SPACE_BETWEEN`        | `horizontalArrangement = Arrangement.SpaceBetween` | `verticalArrangement = Arrangement.SpaceBetween` |

If `layout.gap` is set, prefer `Arrangement.spacedBy(<gap>.dp)` — this also handles `MIN`/`CENTER`/`MAX` when combined with alignment. For `SPACE_BETWEEN` + a gap, use `Arrangement.spacedBy(gap.dp, Alignment.CenterHorizontally)` or similar.

### Counter-axis alignment

| `layout.counter` value | `Row` arg                                    | `Column` arg                                 |
|------------------------|----------------------------------------------|----------------------------------------------|
| `MIN`                  | `verticalAlignment = Alignment.Top`          | `horizontalAlignment = Alignment.Start`      |
| `CENTER`               | `verticalAlignment = Alignment.CenterVertically` | `horizontalAlignment = Alignment.CenterHorizontally` |
| `MAX`                  | `verticalAlignment = Alignment.Bottom`       | `horizontalAlignment = Alignment.End`        |

### No auto-layout (absolute positioning)

When a parent has no `layout` block, its children are positioned absolutely in Figma. Use a `Box` and place children with `Modifier.offset`. Derive offsets from each child's `box` relative to the parent's `box`:

```kotlin
Box(modifier = Modifier.size(375.dp, 812.dp)) {
    Text(
        "Welcome",
        modifier = Modifier.offset(x = 20.dp, y = 80.dp)
    )
    // ...
}
```

Prefer converting to `Column`/`Row` when the children are visually stacked even if the designer didn't use auto-layout — the result is more flexible on different screen sizes.

---

## Sizing

From `box: {x, y, w, h}`, use `w` and `h` for sizing; `x`/`y` feed into `Modifier.offset` when absolute.

```kotlin
Modifier.size(width = 335.dp, height = 52.dp)
// or
Modifier.width(335.dp).height(52.dp)
```

When a Figma frame is set to "fill container" (harder to detect from the JSON alone — infer from the `box.w` matching the parent's), prefer `Modifier.fillMaxWidth()` or `Modifier.fillMaxHeight()`. When it's set to "hug contents" (box size matches children), omit the size modifier entirely — Compose wraps content by default.

---

## Spacing, padding, alignment

From `layout.padding: {t, r, b, l}`:

```kotlin
Modifier.padding(
    start = 16.dp,
    top = 24.dp,
    end = 16.dp,
    bottom = 24.dp,
)
```

If all four are equal, collapse to `Modifier.padding(16.dp)`. If symmetric, collapse to `Modifier.padding(horizontal = 16.dp, vertical = 24.dp)`.

From `layout.gap`:

```kotlin
Arrangement.spacedBy(12.dp)
```

---

## Backgrounds and fills

`fill` on a node is a CSS-style `rgba()` string. Convert to Compose `Color`:

- `rgba(0, 112, 243, 1)` → `Color(0xFF0070F3)`
- `rgba(255, 255, 255, 0.5)` → `Color(0x80FFFFFF)` — the alpha goes first in `AARRGGBB`

For `RECTANGLE` / `ELLIPSE` / `FRAME` with a fill, use `Modifier.background()`:

```kotlin
Modifier.background(Color(0xFF0070F3))
```

Combine with a shape for rounded/circular backgrounds:

```kotlin
Modifier.background(Color(0xFF0070F3), RoundedCornerShape(12.dp))
// or
Modifier.background(Color(0xFF0070F3), CircleShape) // for ellipses with equal w/h
```

The extracted `Color.kt` file contains reusable `val`s — prefer those over inline hex literals in generated code.

---

## Strokes

`stroke: {color, weight, align}` maps to `Modifier.border(...)`:

```kotlin
Modifier.border(
    width = 1.dp,
    color = Color(0xFFE6E6E6),
    shape = RoundedCornerShape(12.dp), // match the corner radius if any
)
```

Figma's `strokeAlign` values:
- `INSIDE`: matches Compose's `Modifier.border` default (the stroke is drawn inside the bounds).
- `CENTER`: Compose doesn't have a direct equivalent; approximate by reducing size by `strokeWeight / 2` on each side.
- `OUTSIDE`: wrap in a slightly larger `Box` with the border, or add padding equal to `strokeWeight` and place the filled content inside.

For most icon buttons and cards, `INSIDE` (default) is what you want.

---

## Corner radius

`radius` on a node → `RoundedCornerShape(<radius>.dp)`. Apply via `Modifier.clip(...)` (clips drawing) or pass as the `shape` argument to `background` / `border`.

```kotlin
Modifier
    .clip(RoundedCornerShape(12.dp))
    .background(Color(0xFF0070F3))
```

For a circle (common for avatars, icon buttons), if `box.w == box.h` and `radius >= w / 2`, use `CircleShape` instead.

Per-corner radii aren't currently exported; if the design has uneven corners, you'll see a single `radius` value that represents the uniform case. If you see the design uses different corners, edit to use `RoundedCornerShape(topStart = ..., topEnd = ..., bottomStart = ..., bottomEnd = ...)`.

---

## Shadows and effects

`effects: [{type, color, offset, blur, spread}]`:

| `type`         | Compose treatment                                                        |
|----------------|---------------------------------------------------------------------------|
| `DROP_SHADOW`  | `Modifier.shadow(elevation = <blur/2>.dp, shape = ..., ambientColor = color, spotColor = color)` |
| `INNER_SHADOW` | No direct Compose equivalent; approximate with a layered `Box` + gradient |
| `LAYER_BLUR`   | `Modifier.blur(<blur>.dp)`                                               |
| `BACKGROUND_BLUR` | `Modifier.blur(<blur>.dp)` applied to a sibling at lower z-order      |

Compose's `Modifier.shadow` elevation doesn't match Figma's `blur` one-to-one. A decent approximation: `elevation ≈ blur / 2`, clamped to a small value (most designs want 2–16dp elevations). Tune by eye.

---

## Rotation and opacity

- `rotation` (degrees) → `Modifier.rotate(<rotation>f)`
- `opacity` (0..1) → `Modifier.alpha(<opacity>f)`

Rotation and alpha don't change layout — the bounds in `box` are still the AABB of the rotated shape, so position/size first, then rotate.

---

## Text

For a `TEXT` node:

```kotlin
Text(
    text = "Welcome back",
    style = inter28Bold, // from Typography.kt
    color = titleTextColor, // from Color.kt
    modifier = Modifier.offset(x = 20.dp, y = 80.dp)
)
```

If `text.mixedStyles: true`, the single `text.style` captured only represents the dominant style. The real rendering has per-character overrides (different colors, weights, or sizes within one string). Options:
- Split into multiple `Text` composables laid out in a `Row` or `FlowRow`
- Use `AnnotatedString` with `SpanStyle` ranges — more accurate but requires inspecting the original Figma or re-exporting with the span boundaries preserved
- Flag this for the user to decide

---

## Images and icons

When a node has `asset: {kind, path}`:

### Icons (`kind == "icon"`)

```kotlin
// Compose Multiplatform (default)
import composeapp.generated.resources.Res
import composeapp.generated.resources.ic_search
import org.jetbrains.compose.resources.painterResource

Icon(
    painter = painterResource(Res.drawable.ic_search),
    contentDescription = null,   // or a meaningful label if the icon communicates state
    tint = Color(0xFF111111),    // applies Material tint
    modifier = Modifier.size(24.dp),
)
```

```kotlin
// Android-only projects
import androidx.compose.ui.res.painterResource

Icon(
    painter = painterResource(id = R.drawable.ic_search),
    contentDescription = null,
    tint = Color(0xFF111111),
    modifier = Modifier.size(24.dp),
)
```

`Icon` applies a tint by default. For multi-colour icons (a logo, a flag), either pass `tint = Color.Unspecified` to preserve the original colours, or switch to `Image` with `painterResource`.

### Images (`kind == "image"`)

```kotlin
// Compose Multiplatform
import composeapp.generated.resources.Res
import composeapp.generated.resources.hero
import org.jetbrains.compose.resources.painterResource

Image(
    painter = painterResource(Res.drawable.hero),
    contentDescription = null,
    contentScale = ContentScale.Crop,
    modifier = Modifier
        .size(width = 375.dp, height = 300.dp)
        .clip(RoundedCornerShape(12.dp)),
)
```

For Android-only projects, swap `Res.drawable.X` for `R.drawable.X` and adjust the `painterResource` import to `androidx.compose.ui.res.painterResource`.

The asset's relative `path` in JSON (e.g., `"assets/icons/ic-search.svg"`) tells you which file in the export corresponds to this node. The actual drawable name comes from the filename minus the extension, lowercased, with dashes → underscores, and (for icons via `svg-to-xml.js`) a `ic_` prefix:

| JSON `asset.path` | Conversion target | Resource reference |
|---|---|---|
| `assets/icons/union.svg` | KMP | `Res.drawable.ic_union` |
| `assets/icons/union.svg` | Android | `R.drawable.ic_union` |
| `assets/images/hero.png` | KMP (manual placement) | `Res.drawable.hero` |
| `assets/images/hero.png` | Android (manual placement) | `R.drawable.hero` |

Moving exported files into a project, and how `svg-to-xml.js` decides names, is covered in asset-pipeline.md (linked from SKILL.md, Step 8).

---

## Instances

A node with `type: "INSTANCE"` and a `componentId` field is a reuse of a Figma component. These should become calls to a shared `@Composable`:

```kotlin
// A single shared definition
@Composable
fun PrimaryButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(onClick = onClick, modifier = modifier) {
        Text(label)
    }
}

// Reused at each instance
PrimaryButton(
    label = "Sign in",
    onClick = { /* TODO */ },
    modifier = Modifier.fillMaxWidth(),
)
```

Run `scripts/detect-components.js` to get a grouped list of instances. Each group gets one composable; the name suggestion from the script (`suggestedComposableName`) is usually good enough.

For the composable body, look at the actual children under the first `INSTANCE` node in the group — those represent the component's visual structure.

---

## Modifier chain ordering

Modifier order in Compose is **meaningful**. Each modifier wraps the next, so ordering determines which operations happen inside vs outside the bounding box.

Recommended order for most cases:

```kotlin
Modifier
    .offset(x, y)          // 1. Position in parent
    .size(w, h)            // 2. Establish bounds
    .padding(...)          // 3. Outer padding (reduces content area)
    .clip(shape)           // 4. Clip to shape (affects everything drawn inside)
    .background(color)     // 5. Fill background inside the clip
    .border(width, color)  // 6. Draw border on the clip boundary
    .padding(...)          // 7. Inner padding (space between border and content)
    .clickable { ... }     // 8. Interaction area
```

Common gotchas:
- `padding` BEFORE `background` shrinks the background. `padding` AFTER `background` shrinks the content. Usually you want content padding, so: `background → padding`.
- `clip` after `background` has no effect on the background — always `clip` first.
- `clickable` should be near the end so the click area matches the visible bounds.
