---
name: figma-to-compose
description: Generates Jetpack Compose Kotlin code from Figma designs — Compose Multiplatform by default, Android via a flag — including design tokens, drawable assets, and multi-screen batch export. Use the moment a Figma URL (figma.com/design, /file, /proto, or a link to a Section/page of screens) appears in any Kotlin, Android, KMP, or Compose context, even if the user never says "Compose" — phrases like "implement this design", "build the design", "create this design", "make it exactly like the Figma", "pixel-perfect", "build this screen", "build this flow", "extract this component". Re-trigger on every new Figma URL mid-conversation. Never hand-write the code instead — the skill enforces token and composable reuse, render verification, and a review checklist that prevent hallucinated elements and duplicated design systems. Not for SwiftUI, Flutter, React Native, or web output.
---

# Figma → Jetpack Compose

Take a Figma URL and produce working Jetpack Compose Kotlin code plus the drawable assets and design tokens that go with it. Each rule below appears exactly once, at the step where it applies — read the step before running it.

## Pipeline

| # | Step | Tool | Gate? |
|---|------|------|-------|
| 1 | Export design | `scripts/figma-to-json.js` | stops if export is shallow/broken |
| 2 | Extract tokens | `scripts/extract-tokens.js --match-existing` | |
| 3 | Detect Figma components | `scripts/detect-components.js` | |
| 4 | Detect variants | `scripts/detect-variants.js` | **STOPS** on non-zero exit |
| 5 | Analyze dimensions | `scripts/analyze-dimensions.js` | |
| 6 | Inventory existing composables | `scripts/find-composables.js` | |
| 7 | Generate code — Pass 1 then Pass 2 | Claude (no script) | |
| 8 | Convert icons | `scripts/svg-to-xml.js` | |
| 9 | Verify against the render | screenshot test or side-by-side | stops if mismatch unresolvable |
| 10 | Review checklist | Claude | **STOPS** on unresolvable issue |
| 11 | Clean up | `scripts/cleanup.js --confirm` | |

Run all steps in order, in one response, per screen. Don't ask "should I run the next step?" — the user asked for the end product. Only the gates pause for input. Skipping a step doesn't save time; it produces broken output that costs more to fix than the step would have taken. For multi-screen links, see **Batch mode** below. When in doubt at any step, ask the user — the cost of asking is one message; the cost of guessing wrong is the whole generation pass.

Copy this checklist into the response and check items off while working (one per screen):

```
<screen name>:
- [ ] 1 Exported — screen.json AND screen-render.png both present
- [ ] 2 Tokens — ran with --match-existing; read figma-token-reuse.json
- [ ] 3 Components detected (batch: all screen.json files in ONE run)
- [ ] 4 Variant gate passed
- [ ] 5 dimensions.json read
- [ ] 6 composable-inventory.json read
- [ ] 7 Pass 1 written, then Pass 2 replacement walked
- [ ] 8 Icons converted
- [ ] 9 Verified against the render
- [ ] 10 Review a–i walked
- [ ] 11 Cleaned up (only after final acceptance)
```

## Setup

```bash
export FIGMA_TOKEN=figd_xxxxxxxxxxxxx   # https://www.figma.com/developers/api#access-tokens (file_content:read scope)
```

Requires **Node 18+** (built-in `fetch`, no npm deps). If the token isn't set, ask for it before Step 1 — that's the only setup question.

## Step 1: Export

```bash
node scripts/figma-to-json.js "<figma-url>" --out ./figma-out
```

| URL shape | What gets exported |
|---|---|
| `...?node-id=` → a frame | That single screen |
| `...?node-id=` → a component (e.g. a button) | Just that component |
| `...?node-id=` → a **SECTION** or page | **Every frame inside, each to its own directory** (auto-split; see Batch mode) |
| No `node-id` | First frame on first page; prints a hint to use `--all-frames` if more exist |
| No `node-id` + `--all-frames` | Every top-level frame on the first page |

Handles `/file/`, `/design/`, `/proto/`, `/board/`, branch, and embed URLs.

Output per screen:

```
figma-out/<screen-name>/
├── screen.json         # layout tree + data values (compact)
├── screen-render.png   # the frame rendered @2x — the visual source of truth
└── assets/{icons/*.svg, images/*.png}
```

Batch exports also write `figma-out/index.json` — a manifest of every screen exported.

**Both files are mandatory inputs to Step 7.** The PNG answers visual questions (Row vs Column, weights, chip vs button, what's prominent); the JSON answers data questions (exact strings, hexes, spacing, asset paths, hierarchy and child order). JSON-only generation produces "everything is a Box with offsets"; PNG-only loses exact values. If `screen-render.png` is missing, the export is incomplete — re-run Step 1, don't proceed.

`screen.json` compact format: colours are hex strings; designer style names surface as `styleRef` (the key signal for token reuse); text styles dedupe into a top-level `textStyles` map referenced by `styleKey`; defaults (zero padding/gap, weight 400, LEFT align) are omitted; single-child organisational frames are unwrapped; `x`/`y` are dropped on auto-layout children. `--verbose` and `--keep-ids` exist for debugging.

**Shallow-export trap:** if `screen.json` has a root with an `asset` field and **no `children`** on a screen-sized box (≥200×300), a designer's PNG `exportSettings` flattened the screen. STOP and re-run the exporter (current versions suppress this by default; `--emit-root-bitmap` is the deliberate opt-in for genuinely image-only frames). Never generate code from a flattened tree.

**Gotchas (facts that defy reasonable assumptions):** 401/403 = token problem. 404 = wrong URL *or* no access — Figma hides "no access" as 404, so have the user check both. 429 with a multi-hour Retry-After = file on a Free/Starter tier (Drafts count as Starter); it must move to a paid team workspace. Community URLs are rejected by the API entirely — the user must duplicate the file to their own workspace first.

## Batch mode (multiple screens from one link)

A link to a Figma SECTION or page auto-splits into per-screen export directories; `--all-frames` does the same for no-node-id URLs. **Never generate all screens in one shot** — N trees and N renders juggled at once is how every screen comes out mediocre. Instead:

1. Export once (one exporter run produces all directories + `index.json`).
2. Read `index.json`, tell the user the screen list and the order you'll take.
3. Run `detect-components.js` over **all** screen.json files in one invocation — cross-screen repeats are now known up front, so the first screen that needs a shared card creates the shared composable and later screens reuse it.
4. Process screens **sequentially, each through the full pipeline (Steps 2–10)**, completing one before starting the next. In Claude Code, dispatching one subagent per screen (still sequential) keeps each screen's context clean — give each subagent the screen directory, the repo path, and this SKILL.md.
5. **Between screens, refresh shared state:** re-run `find-composables.js` so screen N+1 sees the composables screen N just created, and rely on `--match-existing` picking up screen N's freshly written tokens. This is what turns ten screens into one design system instead of ten parallel ones.

Cleanup (Step 11) runs once, after the final screen's review passes.

## Step 2: Extract design tokens

```bash
node scripts/extract-tokens.js ./figma-out/<screen>/screen.json \
    --out ./kotlin-out --package com.example.ui.theme \
    --match-existing <repo-root-or-theme-dir>
```

**Always pass `--match-existing`** unless the user confirms they have no existing Kotlin theme — without it the script can't see existing tokens and silently emits parallel definitions of `SurfacePrimary` etc. Auto-detect the path: look for `*Colors*.kt`, `*Theme*.kt`, `Typography.kt`, or a `theme/` directory; when unsure pass the repo root (scanning is cheap, and it skips `build/`, `.gradle/`, `generated/`).

Produces `Color.kt` and `Typography.kt` (genuinely-new values only) and **`figma-token-reuse.json`** — read it before writing any composable. Matching is three-tier, no fuzz: (1) name match via `styleRef` (case/punctuation-insensitive: `surface-primary` ↔ `SurfacePrimary`), (2) exact hex / exact `(font, size, weight)` tuple, (3) new. Near-misses are emitted as new vals with a `// NOTE:` listing candidates — the user decides.

When generating code: `reason: name-match|hex-match|tuple-match` → reference `reusedName` with the import from the entry's `file` field (no new val exists). `reason: new` → reference `newName` from the generated `Color.kt`. `reason: ambiguous-*` → a new val exists but candidates overlap; surface it in your summary and let the user pick.

## Step 3: Detect Figma components

```bash
node scripts/detect-components.js ./figma-out/<screen>/screen.json          # single screen
node scripts/detect-components.js ./figma-out/*/screen.json                 # batch: ALL screens in one run
```

Two detectors run: (1) `INSTANCE` nodes sharing a `componentId` 2+ times become one `@Composable` each, not duplicated bodies — read the first instance's children for the structure. (2) Merkle subtree fingerprinting finds structurally identical subtrees the designer *didn't* componentize — including, when given every screen's JSON, repeats **across screens** (flagged `ACROSS SCREENS` in the report). Cross-screen repeats become shared composables created once by the first screen that needs them; extract within-screen repeats too unless the user wants a one-shot render.

## Step 4: Variant gate

```bash
node scripts/detect-variants.js ./figma-out/<screen>/screen.json
```

Non-zero exit = node names imply multi-state components (pressed/disabled/hover) but only one state was exported. **STOP. Do not generate.** Don't invent the missing states' colours even if you "know" the brand blue — it's been wrong before. Ask:

> The export contains a single state of a multi-state component: **`<name>`** — only `<state>` is present. Either (1) share "Copy link to selection" URLs for the other variants and I'll generate a stateful component, or (2) confirm only this state exists and I'll generate single-state.

## Step 5: Analyze dimensions

```bash
node scripts/analyze-dimensions.js ./figma-out/<screen>/screen.json \
    --out ./kotlin-out --package com.example.ui.screens.<screen>
```

Writes `Dimensions.kt` **only** for dp values used 2+ times (never an empty stub) and always writes `dimensions.json`: values under `extracted` are referenced by their named val; values under `inline` stay literal at the call site. Don't invent extra named dimensions and don't inline values that qualified — one-off constants like `LoginTopPadding` are noise, not rigor. Names come from Figma variable bindings first, shared node-name prefixes second, generic `Gap16`/`CornerRadius12` last. `--threshold <n>` raises the bar; `--json-out` previews without writing.

## Step 6: Inventory existing composables

```bash
node scripts/find-composables.js <repo-root> --out ./figma-out
```

Produces `composable-inventory.json`: every public `@Composable` in the repo, categorised (top-bar/bottom-sheet/dialog/button/card/...), with signatures and 30-line body excerpts. Categories are coarse hints, not authority — **names lie; bodies tell the truth.** When an excerpt isn't enough, open the file at the entry's `file` path.

## Step 7: Generate the Compose code — two passes, never merged

This is the only unguarded step: no script writes Compose for you, and merging the passes is what historically produced hallucinated elements, missed reuse, and stray hex literals. Re-read `references/compose-clean-code.md` before writing any `@Composable`; `references/figma-to-compose-mapping.md` has the full field-by-field translation; `references/example-screen.md` shows a complete post-Pass-2 file.

### 7a. Sketch the layout from the render

Open `screen-render.png` **first** and write the screen as plain pseudocode:

```
Screen = Column(fillMaxSize, padding 20):
  TopBar: title="Bookings" + back button
  ChipRow: Row(spacedBy 8) of [Chip("Active"), Chip("Past"), Chip("All")]
  CardList: Column(spacedBy 12) of BookingCard × N
    BookingCard = Row: [Avatar, Column(weight 1) of [Name, Service], Price]
```

This is where you decide three children are a weighted Row, not coordinate-positioned Boxes; that the price floats right via `weight(1f)`, not offsets; that chips need `Arrangement.spacedBy`. Those are second-long visual calls from the render and pages of coordinate inference from JSON. Emitted code with more than one or two `Modifier.offset(...)` calls means this step was skipped.

### 7b. Classify reuse candidates

For each thing the sketch needs, search `composable-inventory.json` by category and read bodies:

- **Exact match** → call it, using the import path the rest of the user's code uses.
- **Extendable** → default to a **feature-local wrapper** that composes the existing component plus the missing piece. Never modify `shared/designsystem/` from a feature workflow without asking — the user owns their design system. If a direct modification genuinely seems right (the missing slot is general-purpose), propose it and **wait for explicit confirmation**:

  > Your `AppTopBar` in `shared/designsystem/AppTopBar.kt` fits, but the design needs an end icon it doesn't support. I propose an optional `endIcon: (@Composable () -> Unit)? = null` param (existing calls unchanged). Make that edit, or prefer a feature-local wrapper?

- **Not a fit** → new feature-local composable. Prefer wrapping over modifying, and extending over parallel implementations — a wrapper around `AppDialog` beats a parallel `MyCustomDialog` almost always.

### 7c. Pass 1 — structure-faithful, styles inline

Translate the sketch into code where **every node from `screen.json` exists, in the right hierarchy and order**. Which input governs what: layout primitives, weights, alignment, and "is this a chip or a button" → the render and the sketch; exact strings, hexes, sizes, spacing, asset paths, child order → the JSON (never read pixel colours off the PNG).

Pass 1 styling is deliberately ugly: inline `Color(0xFF...)`, inline `TextStyle(...)`, inline `.dp`. Exact-match composables from 7b are called directly; everything else stays a placeholder `Box`/`Column` — don't invent `MyCustomThing` composables yet.

Node mapping (full version in the mapping reference): `layout.mode VERTICAL` → `Column`; `HORIZONTAL` → `Row`; other containers → `Box` (`.offset` only for genuine overlays); `TEXT` → `Text`; childless `RECTANGLE`/`ELLIPSE` → parent styling, `Spacer`, or `Divider`; `asset.kind icon` → `Icon(painterResource(...))`; `asset.kind image` → `Image(..., contentScale = ContentScale.Crop)`; `INSTANCE` → the shared/reused composable. Modifier order is meaningful — see the mapping reference. Names: PascalCase from frame names (`"Login Screen"` → `LoginScreen`).

### 7d. Pass 2 — systematic replacement, on the real file

Open the Pass 1 file from disk (not memory) and walk it top to bottom:

1. **Every `Color(0xFF...)`** → `reusedName` from `figma-token-reuse.json`, else the val in the fresh `Color.kt`, else add a properly named entry to `Color.kt` and reference it. Zero hex literals remain in screen code.
2. **Every inline `TextStyle(...)`** → same three tiers against `Typography.kt` + the reuse map. Zero inline constructors remain.
3. **Every `.dp` literal** → named val if `dimensions.json` lists it under `extracted`; untouched if `inline`. The file ends up matching `dimensions.json` exactly.
4. **Every placeholder `Box`/`Column`** → re-search the inventory now that you can see its real shape; replace with an existing composable (or the 7b handshake for extendables), else promote it into a properly named new feature-local composable with parameters. No unnamed structural blocks survive Pass 2.

## Step 8: Asset handoff

```bash
node scripts/svg-to-xml.js ./figma-out/<screen>/assets/icons --target kmp --project <kmp-project>      # → composeResources/drawable/, use Res.drawable.X
node scripts/svg-to-xml.js ./figma-out/<screen>/assets/icons --target android --project <app-module>   # → res/drawable/, use R.drawable.X
```

The converter handles typical Figma icons and lists what it skipped (gradients, clip paths, masks, `<use>`) with a pointer to [Valkyrie](https://github.com/ComposeGears/Valkyrie) for those. PNGs go into density buckets manually (`drawable-xhdpi/` for `--scale 2`) — see `references/asset-pipeline.md`.

## Step 9: Verify against the render

Generation is open-loop until something compares the *result* with the design — this step closes it. Pick the first available path:

**A. Maestro** (signal: a `.maestro/` directory in the repo, `maestro` on PATH, or the user says they use it): build and install the debug app, drive to the new screen, `takeScreenshot`, then open the captured PNG **next to** `figma-out/<screen>/screen-render.png` and compare: spacing rhythm, alignment, font sizes/weights, icon sizes, colours, anything cut off or overlapping. The device capture and the Figma @2x render differ in resolution — compare proportions and relationships, never pixel offsets. Fix discrepancies in the code, rebuild, re-capture. Cap at two fix iterations; if a mismatch survives, show the user both images and say what you couldn't reconcile. Flow template, debug-entry-point options, and batch tips: `references/maestro-verify.md`. If the user has their own Maestro-based parity pipeline, prefer running the screen through that — same loop, their harness.

**B. Paparazzi/Roborazzi** (grep gradle files): faster loop than Maestro (JVM render, no device, no app install) but doesn't exercise real app wiring. Write a throwaway test rendering the screen composable with preview-shaped fake data, run the record task (`./gradlew :<module>:recordPaparazziDebug` / `recordRoborazziDebug`), compare the snapshot against `screen-render.png` exactly as in path A. Delete the test afterwards unless the user wants it. Reasonable as the per-iteration loop even when Maestro exists, with a final Maestro pass at the end.

**C. Neither exists:** do the comparison with your eyes — open `screen-render.png` and walk the emitted code against it (directions, child order, weights vs hardcoded widths, anything hidden or stacked). Then tell the user the loop is open and offer to set up path A or B (touching build files or adding debug entry points needs their go-ahead).

Path C is materially weaker than A/B — code review predicts rendering imperfectly. If the user keeps reporting "doesn't match", getting them onto A or B is the fix, not more careful staring.

## Step 10: Review checklist — mandatory, after Pass 2

Open every emitted Kotlin file and walk these checks by reading in context. This step is independent of "I was careful while writing" — scripts catch surface bugs; these need judgment. An unresolvable finding stops the pipeline.

- **a. Completeness:** every child in `screen.json` (TEXT, INSTANCE, asset-bearing) has corresponding code. Missing → back to Pass 1.
- **b. No fabrication:** every code block traces to a `screen.json` node. A "PREMIUM chip" the design doesn't contain gets deleted, not justified — the Figma is the spec.
- **c. Assets, both directions:** every `Res.drawable.X`/`R.drawable.X` exists in this run's `assets/`; every exported asset is referenced. An unreferenced asset means a skipped node; a missing file means an invented name — fix or surface ("this node looked like an icon but wasn't exported — re-export?").
- **d. Colours, both directions:** no inline hex in screen code that a token covers; every distinct design colour appears in the code somewhere.
- **e. Reuse correctness:** every `name/hex/tuple-match` entry references `reusedName` with the right import, never a freshly minted val.
- **f. Composable reuse:** every *new* composable re-checked against the inventory — if an existing one does the job, wrap/reuse instead.
- **g. Dimensions:** `.dp` usage matches `dimensions.json` exactly.
- **h. Layout sanity:** with `screen-render.png` open — directions, child order, weights (`weight(1f)` where children share a Row evenly, not hardcoded widths), nothing hidden/cut off. (Step 9 path A largely covers this; do it explicitly on path C.)
- **i. Summary to the user:** which repo tokens and composables were reused (by name), what's new, and anything flagged-but-unresolved (ambiguous matches, missing assets). Not optional — it's how the user verifies their design system was respected without diffing files.

## Step 11: Clean up

```bash
node scripts/cleanup.js --confirm    # deletes figma-out/ and kotlin-out/ (--dry-run to preview)
```

Run without asking once ALL hold: review passed, the summary is delivered, no open follow-up question, no pending change request (changes are cheaper with intermediates around). Otherwise leave the artifacts; the user can run it themselves later. In batch mode, run once after the final screen.

## Known limitations

- **Step 7 is unguarded** — codegen is prose-driven; the sketch → inventory → classify → translate order helps, Step 9 catches the drift, but bugs originate here.
- **No semantic naming** — a frame named "Frame 47" becomes `Frame47Screen.kt`; rename in Figma before, or in code after.
- **Fingerprint matching is structural, not semantic** — two cards that are visually "the same component" but built differently in Figma (different nesting) won't group; only Step 10f's inventory review catches those.

## References

- `references/compose-clean-code.md` — rules every generated `.kt` must follow (state hoisting, recomposition, modifier discipline, previews). **Read before any codegen** (Step 7).
- `references/figma-to-compose-mapping.md` — every Figma field → Compose equivalent, incl. modifier ordering. **Read during Pass 1 whenever a field's translation is unclear.**
- `references/anti-patterns.md` — nine real failure modes with symptoms and fixes. **Read when output looks wrong, or before editing this skill.**
- `references/maestro-verify.md` — flow template, debug entry points, comparison checklist, batch tips. **Read when running Step 9 path A.**
- `references/example-screen.md` — complete worked example. **Open before the first Pass 2 of a session to calibrate the target shape.**
- `references/asset-pipeline.md` — SVG/PNG handling, density buckets, naming. **Read in Step 8 if the converter skips files or PNGs are involved.**
- `references/theming.md` — wiring tokens into Material3 vs direct use. **Read if the repo uses MaterialTheme or the user asks about theming.**
- `references/claude-code-hooks.md` — a user-side Claude Code hook that forces this skill to trigger on Figma URLs. **Read only if the user asks how to enforce triggering.**
