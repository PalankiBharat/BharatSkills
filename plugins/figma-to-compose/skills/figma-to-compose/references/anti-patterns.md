# Anti-patterns: real failure modes this pipeline has produced

Each of these happened. The main SKILL.md steps prevent them; this file is the
"why" behind those rules. Read it when output looks wrong, or before editing
the skill — every rule you might be tempted to delete exists because of one of
these.

## 1. The flattened-screen silent miss
**Symptom:** `screen.json` has only a root node with an `asset` and no
`children`; the generated "screen" is one giant `Image(...)`.
**Cause:** a designer attached PNG `exportSettings` to the root frame; old
exporters treated it as "stop walking".
**Prevention:** Step 1's shallow-export trap — STOP and re-run the exporter.
Never generate against a flattened tree.

## 2. Reinventing tokens the repo already has
**Symptom:** repo has `SlotliColors.SurfacePrimary = Color(0xFFFDFDFD)`; the
output adds a parallel `val surfacePrimary` for the same hex.
**Cause:** `extract-tokens.js` ran without `--match-existing`, or codegen never
read `figma-token-reuse.json`.
**Prevention:** Step 2 — always `--match-existing`; reference `reusedName` for
every matched entry.

## 3. Invented drawable references
**Symptom:** code references `R.drawable.ic_profile`; no such file was
exported.
**Cause:** the node wasn't classified as an icon, so no SVG exists — the name
was pattern-matched from visual semantics.
**Prevention:** Step 10c — every drawable reference must exist in this run's
`assets/`; surface gaps instead of inventing.

## 4. Over-extracted Dimensions.kt
**Symptom:** a small screen yields twelve named constants used once each;
reading the screen requires a second file open per value.
**Cause:** "no magic numbers" applied without nuance.
**Prevention:** Step 5 — only `dimensions.json`-`extracted` values (2+ uses)
get names; one-offs stay inline by rule, not as a shortcut.

## 5. Inline hex where a token exists
**Symptom:** `Modifier.background(Color(0xFFFDFDFD))` next to a `Color.kt`
that has a val for that hex.
**Cause:** fluent-modifier momentum during codegen.
**Prevention:** Pass 2 sub-step 1 + Step 10d: zero hex literals in screen code.

## 6. Single-state component generated from a multi-state design
**Symptom:** a button with Default/Pressed/Disabled variants in Figma ships as
a stateless composable with one hardcoded background.
**Cause:** only one variant frame was exported; codegen matched what it saw.
**Prevention:** Step 4 gate — STOP on non-zero exit, ask the user, never invent
missing-state colours ("knowing" the brand blue has been wrong before).

## 7. Parallel composables
**Symptom:** repo has `AppBottomSheet`; output adds `BookingsBottomSheet`
doing the same thing with different parameters.
**Cause:** tokens were checked for reuse, composables weren't.
**Prevention:** Step 6 inventory + Step 7b classification + Step 10f re-check.
New composables are the last resort.

## 8. Modifying shared/designsystem to add a slot
**Symptom:** `AppTopBar` in `shared/designsystem/` gains an `endIcon` param for
one feature; every call site silently changes; a wrong contract ripples
through unrelated code.
**Cause:** the gap felt small enough that "just add a parameter" looked right.
**Prevention:** Step 7b — wrap in the feature module by default; modify shared
code only with the explicit-confirmation handshake. Promote a wrapper to
shared only when a second feature needs it.

## 9. Coordinates translated into Modifier.offset everywhere
**Symptom:** a chip row becomes three absolutely-positioned Boxes; the screen
renders at one width and breaks at every other.
**Cause:** JSON has `box.x/y` for non-auto-layout parents; walking the tree
literally produces offsets.
**Prevention:** Step 7a sketch from the render, every time. More than one or
two `.offset(...)` calls in output means the sketch was skipped.
