# Figma Walk

Whenever a story contains a Figma link, `design-reviewer` (Wave 1 specialist) fetches the node, traverses any linked frames, captures a screenshot of every screen on the flow, and produces a screen catalog the lead embeds in the HTML doc. Without this, design questions are generated against text alone — leading to hallucinated UI assumptions and missed interaction edge cases.

## URL detection (runs in story-clarifier)

Match these patterns in the raw story text (case-insensitive, query string permitted):

| Pattern | Type | Notes |
|---|---|---|
| `figma.com/design/:fileKey/...?node-id=:nodeId` | Design file (preferred) | Convert `-` → `:` in `nodeId` |
| `figma.com/design/:fileKey/branch/:branchKey/...` | Branched file | Use `branchKey` as `fileKey` |
| `figma.com/file/:fileKey/...` | Legacy design file | Same as `design/` |
| `figma.com/proto/:fileKey/...?node-id=:nodeId` | Prototype | Used to derive flow ordering — see "Flow inference" |
| `figma.com/board/:fileKey/...?node-id=:nodeId` | FigJam | Reserved for `get_figjam` (rarely needed for Android feature analysis) |
| `figma.com/make/:makeFileKey/...` | Figma Make | Use `makeFileKey` |
| `figma.com/slides/:fileKey/...?node-id=:nodeId` | Figma Slides | Decks rarely contain product UI |

Story-clarifier extracts every match into `session.figma_targets[]`:

```json
{
  "figma_targets": [
    {
      "raw_url": "https://figma.com/design/abc123/Custom-TF?node-id=42-198",
      "kind": "design",
      "file_key": "abc123",
      "node_id": "42:198",
      "section_in_story": "Acceptance criteria (Android)"
    }
  ]
}
```

If no Figma URLs are present, `design-reviewer` is still spawned but emits `figma_unavailable: true` and skips this file. The lead does not treat absence of Figma as a Pre-flight failure — many feature stories have no design yet.

## design-reviewer walk protocol

Per Figma target, in order:

### 1. Resolve the starting node

Call `mcp__figma__get_design_context` with `{file_key, node_id}`. This is the primary tool — it returns:

- A React+Tailwind code reference (treat as *reference only*, never copy into Android code).
- A screenshot of the rendered node (base64 PNG).
- Contextual hints: linked Code Connect mappings, component docs, design annotations, design tokens.

If `get_design_context` fails (404, permission, deleted node), record `status: "unreachable"` with the failure reason and continue to the next target. Never abort the whole specialist.

### 2. Capture metadata + screenshot

Call `mcp__figma__get_metadata` once per file (cached for the session) to learn the document structure. Capture screenshots of every frame the specialist reports via `mcp__figma__get_screenshot` with `format: png` + `scale: 2` for clarity in the HTML doc.

### 3. Walk linked frames

Most stories link to a single frame, but real flows span 3-8 screens. Walk the frame's outgoing connections in this order:

1. **Prototype connections** — if a prototype exists (look at `metadata.prototype_starting_point` and per-frame `prototype_interactions`), traverse via Hover/Tap interactions in depth-first order. Maximum depth 8 frames per starting point. Track visited node IDs to avoid cycles.
2. **Section neighbours** — if no prototype, walk sibling frames inside the same Section (per `metadata.sections[]`). Cap at 8 frames.
3. **Named-flow groups** — if the file uses a `flow: <name>` annotation pattern, group frames by flow name.

Each visited frame produces:

```json
{
  "node_id": "42:215",
  "name": "Custom duration sheet - empty",
  "screenshot_path": "<workspace>/figma/abc123/42-215@2x.png",
  "annotations": ["..."],
  "linked_components": [{"name": "ChipRow", "kind": "instance"}],
  "outgoing_interactions": [
    {"trigger": "ON_TAP", "target_node_id": "42:240", "destination_label": "Configurator"}
  ]
}
```

### 4. Flow inference

Build a `flow_graph` keyed by start node:

```json
{
  "start_node": "42:198",
  "edges": [
    {"from": "42:198", "to": "42:215", "trigger": "ON_TAP", "label": "Add custom"},
    {"from": "42:215", "to": "42:240", "trigger": "ON_TAP", "label": "Save"}
  ],
  "node_index": {
    "42:198": {"name": "Duration sheet", "screenshot": "..."},
    "42:215": {"name": "Add custom config", "screenshot": "..."},
    "42:240": {"name": "Confirmation", "screenshot": "..."}
  }
}
```

The lead renders this graph in the HTML doc as a horizontal step strip (see "Screen Catalog" in `html-output.md`).

### 5. Extract design tokens, annotations, components

For each visited frame:

- **Design tokens** — pull from `get_design_context` output (CSS variables). Surface in a "Design tokens used" table in the HTML doc so engineers know which app tokens to map to.
- **Annotations** — designer notes attached to layers. Quoted verbatim under the screenshot.
- **Linked Code Connect components** — if the team has Code Connect set up (`mcp__figma__get_code_connect_map`), surface "this frame uses <component name>" with a code path. Lets the questioner skip questions about already-implemented components.

## design-reviewer output schema

Adds these fields to the specialist envelope from `specialist-roster.md`:

```json
{
  "specialist": "design-reviewer",
  "figma_unavailable": false,
  "screens": [
    {
      "node_id": "42:198",
      "file_key": "abc123",
      "name": "Duration sheet — current state",
      "screenshot_path": "<workspace>/figma/abc123/42-198@2x.png",
      "annotations": [],
      "linked_components": [],
      "confidence": "high"
    }
  ],
  "flow_graphs": [
    { "start_node": "...", "edges": [...], "node_index": {...} }
  ],
  "design_tokens_referenced": [
    {"figma_token": "color/surface/elevated", "value": "#1E293B", "suggested_app_token": "Surface.Elevated"}
  ],
  "questions": [
    { /* Question schema from specialist-roster.md */ }
  ]
}
```

## Auto-answer rule (from design)

When the lead merges Wave 3 questions, every `design`-pillar question whose answer is visible in the screen catalog is dropped from the output. Examples of auto-answerable design questions:

- "What's the bottom-sheet behaviour on dismiss?" → answered by a frame named `Sheet — dismissed state`.
- "What's the chip-row scroll direction?" → answered by overflow markers in the frame.
- "What's the empty-state copy?" → answered by an `Empty` frame.

Dropped questions are logged in the scope report under "Auto-answered by Figma walk" so the developer can verify.

## Failure handling

| Failure | Detection | Lead behaviour |
|---|---|---|
| Figma MCP not connected | `mcp__figma__get_design_context` returns an MCP error before any node fetch | Surface a Pre-flight callout: "Figma MCP not configured — design questions will be text-only." Continue, design-reviewer runs in degraded mode. |
| File access denied | 403 on `get_design_context` | Record `status: "unreachable"` per target; surface in scope report. |
| Node deleted / moved | 404 | Same as above; suggest the reviewer paste a fresh link. |
| Prototype graph has cycles | Visited-set tracks node IDs | Stop at the cycle; record `truncated_by_cycle: true`. |
| Screenshot too large (>1 MB) | byte count check | Re-fetch with `scale: 1`; record `downscaled: true`. |
| Story has 10+ Figma URLs | URL count > 10 | Pre-flight warning; default to processing first 10, surface the rest in scope report with "consider grouping into one flow". |

## Privacy / security

- Screenshots are persisted under `.feature-analyzer/<slug>/<session-id>/figma/<file_key>/<node-id>@<scale>.png`. The replay log indexes them by relative path.
- If the file's title or annotations contain text patterns matching `email:`, `password`, `token`, `pii:`, or known account-id prefixes, the lead **does not embed those frames inline** in the HTML doc — it renders a placeholder and surfaces a "Sensitive content stripped (N screens)" callout. The replay log keeps the originals for audit.
- The skill never uploads screenshots elsewhere. Figma MCP fetches the screenshot via the user's authenticated Figma session; the bytes stay on disk.

## Why this matters

- **Cuts design question count by ~40% on stories with Figma.** Half the design questions in iter-2 were "what does X look like?" type — answerable from screenshots.
- **Catches interaction edge cases the story doesn't mention.** A prototype graph reveals secondary states (loading, error, empty, dismiss) that the story author forgot to enumerate.
- **Aligns engineering with design tokens up front.** Each frame's tokens map to app tokens during analysis, not during code review.
- **Provides reviewers a shared visual reference.** Stakeholders skim screenshots faster than they read AC bullets — and they correct mismatches earlier.
