# HTML Output (Mode 1 default)

Mode 1 emits an HTML doc — not Markdown — because the audience is PM / Design / Backend, who consume the doc in a browser, not a terminal. Markdown in chat is unshareable; HTML is.

## Output path

`docs/feature-analysis/<feature-slug>-analysis.html`

Slug rule: kebab-case from the feature title (e.g. `Custom Time Frame` → `custom-time-frame`).

## Required components

The HTML doc has ten required components. All must be present even if a section ends up empty (render an empty-state hint instead of dropping the section).

1. **Sidebar nav (sticky, left rail)** — page-section links: Story · Scope · Existing flow · Code requirements · Blockers · Clarifications · Nice-to-have · Assumptions · Copy. One-click jumps; current section highlighted as you scroll.
2. **Header block** — feature name, one-line intent, date, run mode (Mode 1), session-id (small monospace).
3. **Tab strip + Original Story panel (MANDATORY, always visible)** — A two-tab strip sits at the top of `<main>` directly under the header: `Analysis` (default) and `Original Story`. The `Original Story` tab renders the raw story text the reviewer submitted, completely unmodified (no rewriting, no summarising, no question generation). Markdown is rendered with a minimal renderer; headings, lists, code, links preserved. The panel is required on every Mode 1 run, including greenfield and degraded-mode runs. See "Original Story panel" below.
4. **Progress bar** — "X / N answered" counter + fill bar. Tracks user interactions with radio groups. Starts at 0 (Recommended options are NOT pre-checked; the reviewer must actively select).
5. **Scope-report block** — populated by `scope-classifier.md`. Wide left column for Included; stacked right rail for Stripped + Conditional.
6. **Existing-flow trace** — collapsible panel. Populated by `existing-flow-trace.md`. If skipped (greenfield), render a 1-line "Flow trace skipped — story self-declares greenfield" note.
7. **Screen Catalog (Figma walk)** — collapsible panel. Populated by `design-reviewer`'s output per `figma-walk.md`. Renders thumbnails for each visited frame in a horizontal step strip, with per-frame name, annotations, linked Code Connect components, and a flow-graph showing prototype edges. If `figma_unavailable: true`, render a 1-line "No Figma URLs found in story — design questions are text-only" note. If Figma MCP failed, render a Pre-flight callout instead.
8. **Code requirements (diff block)** — collapsible panel. For every `delta` produced by `gap-analyzer`, render a unified diff with a per-block header showing the relative file path.
9. **Priority buckets** — collapsible panel per bucket: 🔴 Blockers · 🟡 Clarifications · 🟢 Nice-to-have. Each panel contains a question-card grid.
10. **Copy controls** — sticky toolbar with: select-all / select-none / blockers-only, **selective copy modal**.

## Design system — dark mode by default

The template uses a layered dark surface palette inspired by GitHub dark, Linear, and Vercel:

```css
:root {
  --base:       #0d1117;   /* page background */
  --surface:    #161b22;   /* sidebar, panels */
  --elevated:   #21262d;   /* cards, inputs, hover backgrounds */
  --hover:      #30363d;   /* hover state */
  --border:     #30363d;
  --border-sub: #21262d;
  --text:       #e6edf3;
  --text-muted: #8b949e;
  --text-dim:   #6e7681;

  --green:      #3fb950;   /* success / nice-to-have */
  --green-bg:   #0f2a1a;
  --green-dim:  #1a4a2a;
  --amber:      #d29922;   /* warning / clarification */
  --amber-bg:   #2a1f00;
  --amber-dim:  #3d2e00;
  --red:        #f85149;   /* danger / blocker */
  --red-bg:     #2a0f0f;
  --red-dim:    #4a1a1a;
  --blue:       #58a6ff;   /* links, file paths, badges */
  --blue-bg:    #0f1f3a;

  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;

  --sidebar-w: 260px;
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 10px;
}
```

## Sidebar nav

The sidebar is the navigation backbone. 260px fixed width; `position: sticky; top: 0; height: 100vh` so it stays visible while main scrolls. Scroll-spy updates the active link.

Role filter chips in the sidebar use colour-coded pill style with `active` state. Priority and pillar filter groups are stacked below role. Combined filters use AND logic. Filter state persists in `localStorage`.

```html
<nav class="sidebar">
  <div class="sidebar-logo">
    <div class="label">Feature Analysis · Mode 1</div>
    <h2>{{feature_name}}</h2>
  </div>

  <ul>
    <li><a href="#scope"><span class="nav-icon">◫</span> Scope filter</a></li>
    <li><a href="#flow"><span class="nav-icon">⇢</span> Existing flow</a></li>
    <li><a href="#screens"><span class="nav-icon">▣</span> Screen catalog</a></li>
    <li><a href="#diff"><span class="nav-icon">±</span> Code requirements</a></li>
    <li><a href="#blockers"><span class="nav-icon">●</span> Blockers <span class="badge red">{{n_blockers}}</span></a></li>
    <li><a href="#clarifications"><span class="nav-icon">●</span> Clarifications <span class="badge amber">{{n_clarify}}</span></a></li>
    <li><a href="#nice"><span class="nav-icon">●</span> Nice-to-have <span class="badge green">{{n_nice}}</span></a></li>
    <li><a href="#assumptions"><span class="nav-icon">📌</span> Assumptions</a></li>
    <li><a href="#copy-toolbar"><span class="nav-icon">⧉</span> Copy answers</a></li>
  </ul>

  <hr class="sidebar-divider">
  <div class="sidebar-section-label">Filters</div>

  <div class="sidebar-filters">
    <div class="filter-group">
      <div class="filter-group-label">Role</div>
      <div class="chip-row" data-filter-group="role">
        <button class="chip active" data-filter-role="all">All</button>
        <button class="chip" data-filter-role="PM">PM</button>
        <button class="chip" data-filter-role="Backend">Backend</button>
        <button class="chip" data-filter-role="Design">Design</button>
        <button class="chip" data-filter-role="QA">QA</button>
        <button class="chip" data-filter-role="Compliance">Compliance</button>
        <button class="chip" data-filter-role="DevOps">DevOps</button>
      </div>
    </div>
    <div class="filter-group">
      <div class="filter-group-label">Priority</div>
      <div class="chip-row" data-filter-group="priority">
        <button class="chip active" data-filter-priority="all">All</button>
        <button class="chip red" data-filter-priority="red">Blockers</button>
        <button class="chip amber" data-filter-priority="yellow">Clarify</button>
        <button class="chip green" data-filter-priority="green">Nice</button>
      </div>
    </div>
    <div class="filter-group">
      <div class="filter-group-label">Pillar</div>
      <div class="chip-row" data-filter-group="pillar">
        <button class="chip active" data-filter-pillar="all">All</button>
        <button class="chip" data-filter-pillar="design">design</button>
        <button class="chip" data-filter-pillar="tech">tech</button>
        <button class="chip" data-filter-pillar="qa">qa</button>
        <button class="chip" data-filter-pillar="domain">domain</button>
      </div>
    </div>
  </div>
</nav>
```

## Page header + progress bar

```html
<div class="page-header">
  <div class="run-badge">{{session_id}} &nbsp;·&nbsp; {{date}}</div>
  <h1>{{feature_name}}</h1>
  <div class="intent">{{intent}}</div>
  <div class="page-meta">
    <span>Mode 1</span>
    <span>·</span>
    <span>{{n_total}} questions</span>
    <span>·</span>
    <span>{{n_diff_blocks}} diff blocks</span>
    <span>·</span>
    <span>{{scope_summary}}</span>
  </div>
  <div class="progress-bar-wrap">
    <div class="progress-label">
      <span>Progress</span>
      <strong><span id="answered-count">0</span> / {{n_total}} answered</strong>
    </div>
    <div class="progress-track">
      <div class="progress-fill" id="progress-fill"></div>
    </div>
  </div>
</div>
```

**Progress bar semantics:** "answered" means the reviewer has fired a `change` event on any radio in the card — i.e. they made an active choice. The Recommended option is NOT pre-checked; `input[type=radio]` elements carry no `checked` attribute in the HTML. The JS tracks answered qids in a `Set` keyed by `data-qid` and fires on every `change`. This avoids the bug where a pre-selected Recommended makes the bar start at 100%. The counter uses `aria-live="polite"` so screen readers announce progress changes.

## Tab strip + Original Story panel

The very first interactive element in `<main>` (under the header, above the progress bar) is a two-tab strip. The reviewer should ALWAYS be one click away from the source story — without it, every question card is unverifiable.

### Why this is mandatory

- Reviewers need to cross-check questions against the story that produced them. Without the story inline, they alt-tab to a Slack / Jira / Linear / Notion tab and break flow.
- Skill regression review needs the story to be embedded in the artifact — a `.feature-analyzer/<slug>/<session>/00-preflight.json` file is the source of truth, but the rendered HTML must be self-contained for sharing.
- Greenfield runs especially benefit — when there's no flow trace and no diff, the story IS the only context for the questions.

### Behaviour

- **Tabs**: `Analysis` (default, selected) and `Original Story`.
- **Persistence**: active tab persisted in `localStorage` key `fa-active-tab`. A returning reviewer lands on whichever tab they last viewed.
- **Keyboard**: arrow-left/right cycles tabs when the strip has focus; numeric `1` jumps to Analysis, `2` to Story (with `aria-keyshortcuts`).
- **Visibility**: switching tabs swaps `display: block` ↔ `display: none` on the two `<section>` panels. Both panels stay in the DOM so anchor links from the sidebar still work (the click handler activates the Analysis tab before scrolling).
- **No transformation**: the Story panel renders the raw text the reviewer submitted. No summarising, no re-styling, no inserting links to questions. The minimal markdown renderer handles headings, lists, code fences, blockquotes, inline code, and bold/italic. Anything more exotic falls back to a `<pre>` block so the text is never lost.
- **Diff against story**: each question card carries a "View source" affordance that opens the Story tab and scrolls to the first matching keyword (using `mark.js`-style highlighting). Out of scope for v1; tracked as iter-4 in the iteration plan.

### HTML pattern

```html
<div class="tab-strip" role="tablist" aria-label="View">
  <button class="tab active" role="tab" aria-selected="true"
          aria-controls="tab-analysis" id="tab-btn-analysis"
          data-tab="analysis" aria-keyshortcuts="1">
    Analysis
  </button>
  <button class="tab" role="tab" aria-selected="false"
          aria-controls="tab-story" id="tab-btn-story"
          data-tab="story" aria-keyshortcuts="2">
    Original Story
    <span class="tab-hint">⌥2</span>
  </button>
</div>

<section id="tab-analysis" role="tabpanel"
         aria-labelledby="tab-btn-analysis" class="tab-panel active">
  <!-- progress bar, copy toolbar, scope, flow, diff, priority buckets, assumptions -->
</section>

<section id="tab-story" role="tabpanel"
         aria-labelledby="tab-btn-story" class="tab-panel" hidden>
  <div class="story-meta">
    <span>Source story · submitted at run start · not modified</span>
    <button class="toolbar-btn" id="copy-story">Copy story</button>
  </div>
  <article class="story-body">
    {{rendered_story_markdown}}
  </article>
</section>
```

### CSS pattern

```css
.tab-strip {
  display: flex; gap: 4px; padding: 0 24px;
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  position: sticky; top: 0; z-index: 30;
}
.tab {
  appearance: none; background: transparent; color: var(--text-muted);
  border: 0; border-bottom: 2px solid transparent;
  padding: 14px 18px; font: 500 13px/1 var(--sans);
  cursor: pointer; display: inline-flex; align-items: center; gap: 8px;
  transition: color 150ms ease, border-color 150ms ease;
}
.tab:hover { color: var(--text); }
.tab.active { color: var(--text); border-color: var(--blue); }
.tab:focus-visible { outline: 2px solid var(--blue); outline-offset: 2px; border-radius: 4px; }
.tab-hint { font: 400 11px/1 var(--mono); color: var(--text-dim);
            padding: 2px 6px; background: var(--elevated); border-radius: 4px; }
.tab-panel[hidden] { display: none; }
.story-meta { display: flex; justify-content: space-between; align-items: center;
              padding: 16px 24px; color: var(--text-muted); font-size: 13px; }
.story-body { padding: 8px 24px 48px; max-width: 80ch; font: 15px/1.7 var(--sans); }
.story-body h1, .story-body h2, .story-body h3 { color: var(--text); margin: 28px 0 8px; }
.story-body h1 { font-size: 22px; } .story-body h2 { font-size: 18px; }
.story-body h3 { font-size: 15px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); }
.story-body p, .story-body li { color: var(--text); }
.story-body code { font: 13px/1 var(--mono); background: var(--elevated); padding: 2px 6px;
                   border-radius: 4px; color: var(--blue); }
.story-body pre { background: var(--surface); padding: 14px 16px; border-radius: 6px;
                  overflow: auto; border: 1px solid var(--border); }
.story-body blockquote { border-left: 3px solid var(--border); padding: 4px 14px;
                         color: var(--text-muted); margin: 12px 0; }
```

### JS pattern

```js
const TAB_KEY = 'fa-active-tab';
function activateTab(name) {
  document.querySelectorAll('.tab').forEach(btn => {
    const isActive = btn.dataset.tab === name;
    btn.classList.toggle('active', isActive);
    btn.setAttribute('aria-selected', isActive);
  });
  document.querySelectorAll('.tab-panel').forEach(panel => {
    const isActive = panel.id === `tab-${name}`;
    panel.classList.toggle('active', isActive);
    panel.hidden = !isActive;
  });
  localStorage.setItem(TAB_KEY, name);
}
document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => activateTab(btn.dataset.tab));
});
window.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
  if (e.key === '1') activateTab('analysis');
  if (e.key === '2') activateTab('story');
});
// Sidebar anchor links: activate Analysis tab first, then scroll
document.querySelectorAll('nav.sidebar a[href^="#"]').forEach(a => {
  a.addEventListener('click', () => {
    if (a.getAttribute('href') !== '#tab-story') activateTab('analysis');
  });
});
// Hydrate
activateTab(localStorage.getItem(TAB_KEY) || 'analysis');
```

### Minimal markdown renderer

For the story panel only, a small markdown-to-HTML helper runs at render time (in the skill, not in the browser — the skill emits already-rendered HTML inside `<article class="story-body">`). The renderer covers:

| Source | Output |
|---|---|
| `# Heading` | `<h1>` |
| `## Heading` | `<h2>` |
| `### Heading` | `<h3>` |
| `- bullet` / `* bullet` | `<ul><li>` |
| `1. ordered` | `<ol><li>` |
| ` ```code``` ` (triple-backtick fenced) | `<pre><code>` |
| `` `inline` `` | `<code>` |
| `**bold**` | `<strong>` |
| `*italic*` / `_italic_` | `<em>` |
| `> quote` | `<blockquote>` |
| `[text](url)` | `<a href>` with `rel="noopener"` |
| blank-line-separated paragraph | `<p>` |
| anything else | passed through inside its block |

If the renderer encounters a construct it doesn't recognise (e.g. tables, footnotes, custom shortcodes), it wraps the entire offending block in a `<pre class="raw-block">` rather than silently dropping content. This guarantees the reviewer never loses information.

## Copy toolbar

Sticky below the header; stays visible as the user scrolls questions.

```html
<div class="copy-toolbar" id="copy-toolbar">
  <button class="toolbar-btn" id="select-all">Select all</button>
  <button class="toolbar-btn" id="select-none">Select none</button>
  <button class="toolbar-btn" id="select-blockers">Blockers only</button>
  <span class="toolbar-spacer"></span>
  <button class="toolbar-btn primary" id="open-copy-modal">⧉ Copy selected…</button>
</div>
```

## Scope-report block

Wide left column for Included (spans 2 rows); right rail stacks Stripped above Conditional. This avoids the equal-thirds layout that wastes space when Conditional has only 1 item.

```html
<div class="scope-grid" id="scope">
  <div class="scope-col included">
    <h4>Included</h4>
    <ul>{{included_items}}</ul>   <!-- each <li><span>…</span></li> -->
  </div>
  <div class="scope-col stripped">
    <h4>Stripped</h4>
    <ul>{{stripped_items}}</ul>
  </div>
  <div class="scope-col conditional">
    <h4>Conditional</h4>
    <ul>{{conditional_items}}</ul>
  </div>
</div>
```

Grid rule: `grid-template-columns: 1fr 280px; grid-template-rows: auto auto;` with `.included { grid-row: 1 / 3; }`.

## Existing-flow trace

Collapsible `<details class="panel">`. Summary line shows avg confidence. If `partial: true`, open with a prominent amber callout explaining degraded mode.

```html
<details class="panel" id="flow" open>
  <summary>
    Flow audit
    <span class="summary-label">avg confidence: {{avg_confidence}}</span>
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <!-- If partial: true -->
    <div class="partial-callout">
      <span class="icon">⚠</span>
      <div>Flow trace ran in <strong>degraded mode</strong> (<code>partial: true</code>).
      No <code>file:line</code> cites claimed. All auto-answer candidates surfaced.</div>
    </div>

    <!-- SDKs probed list -->
    <ul class="facts-list">
      <li><span class="conf-chip low">not_located</span> &nbsp;<code>{{sdk_name}}</code> — {{status_note}}</li>
    </ul>

    <!-- Inferred chain -->
    <ol class="flow-chain">
      <li><b>UI</b> — {{ui_component}} <span class="conf-chip {{confidence}}">{{confidence}}</span></li>
      <li><b>ViewModel</b> — {{viewmodel}} <span class="conf-chip {{confidence}}">{{confidence}}</span></li>
      <!-- … -->
    </ol>
  </div>
</details>
```

If the story is greenfield (no existing flow to trace), render a single callout:

```html
<div class="partial-callout">
  <span class="icon">ℹ</span>
  <div>Flow trace skipped — story self-declares greenfield. No existing component chain to audit.</div>
</div>
```

## Screen Catalog (Figma walk)

Renders the screens `design-reviewer` captured. For each Figma target, the panel contains a step strip (linear sequence of thumbnails representing the prototype flow), a flow-graph subhead if branches exist, and per-screen annotations.

```html
<details class="panel" id="screens" open>
  <summary>
    Screen catalog
    <span class="summary-label">{{n_screens}} screens · {{n_flows}} flow{{n_flows>1?'s':''}}</span>
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">

    <!-- Figma unavailable -->
    <div class="partial-callout">
      <span class="icon">ℹ</span>
      <div>No Figma URLs found in story. Design questions are text-only.</div>
    </div>

    <!-- Or: Figma MCP failure -->
    <div class="partial-callout warn">
      <span class="icon">⚠</span>
      <div>Figma MCP unreachable. <code>{{failure_reason}}</code></div>
    </div>

    <!-- Per flow-graph: horizontal step strip -->
    <div class="screen-strip">
      <div class="screen-tile" data-node-id="42:198">
        <img src="{{screenshot_path}}" alt="{{screen_name}}" loading="lazy">
        <div class="screen-meta">
          <div class="screen-name">Duration sheet — current state</div>
          <div class="screen-anno">{{designer_annotation_or_blank}}</div>
        </div>
      </div>
      <div class="screen-arrow" aria-hidden="true">→</div>
      <div class="screen-tile" data-node-id="42:215">
        <img src="{{screenshot_path}}" alt="Add custom configurator">
        <div class="screen-meta">
          <div class="screen-name">Add custom configurator</div>
          <div class="screen-anno">"Validate range 1s–24h"</div>
        </div>
      </div>
      <!-- repeat with arrows between -->
    </div>

    <!-- Design tokens referenced -->
    <div class="tokens-section">
      <h4>Design tokens referenced</h4>
      <table class="tokens-table">
        <thead><tr><th>Figma token</th><th>Value</th><th>Suggested app token</th></tr></thead>
        <tbody>
          <tr><td><code>color/surface/elevated</code></td><td>#1E293B</td><td>Surface.Elevated</td></tr>
        </tbody>
      </table>
    </div>

    <!-- Code Connect cross-reference -->
    <div class="cc-section">
      <h4>Linked Code Connect components</h4>
      <ul>
        <li><code>ChipRow</code> (from Figma) → <code>app/.../ChipRow.kt</code></li>
      </ul>
    </div>

  </div>
</details>
```

```css
.screen-strip { display: flex; flex-wrap: wrap; gap: 12px; align-items: stretch;
                padding: 12px 0; overflow-x: auto; }
.screen-tile { background: var(--surface); border: 1px solid var(--border);
               border-radius: var(--radius-md); overflow: hidden; flex: 0 0 240px;
               display: flex; flex-direction: column;
               transition: transform 150ms ease, border-color 150ms ease; }
.screen-tile:hover { transform: translateY(-2px); border-color: var(--hover); cursor: pointer; }
.screen-tile img { width: 100%; aspect-ratio: 9 / 16; object-fit: cover; background: var(--elevated); }
.screen-meta { padding: 10px 12px; }
.screen-name { font: 500 13px/1.3 var(--sans); color: var(--text); }
.screen-anno { font: 400 12px/1.4 var(--sans); color: var(--text-muted); margin-top: 4px;
               font-style: italic; }
.screen-arrow { align-self: center; color: var(--text-dim); font-size: 18px; }

.tokens-section, .cc-section { margin-top: 18px; }
.tokens-section h4, .cc-section h4 { font: 500 13px/1.3 var(--sans); color: var(--text-muted);
                                     margin: 12px 0 6px; }
.tokens-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.tokens-table th, .tokens-table td { padding: 6px 8px; text-align: left;
                                     border-bottom: 1px solid var(--border-sub); }
.tokens-table th { color: var(--text-muted); font-weight: 500; }
.tokens-table code { font: 12px/1 var(--mono); }
```

Clicking a `.screen-tile` opens the screenshot in a lightbox modal at full resolution (lightbox markup + JS minimal; reuses the copy-modal pattern with `display: flex` overlay). Right-click → "Open original" goes to the Figma URL in a new tab if `data-figma-url` is set on the tile.

## Code requirements — diff block

Each delta gets its own bordered card with a header showing the file path. The diff body uses a dark terminal look (`background: #010409`). Lines are `<span>` elements with class `diff-line add|del|meta|hunk`.

```html
<details class="panel" id="diff" open>
  <summary>
    Delta from existing flow
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <!-- Placeholder callout if no repo access -->
    <div class="partial-callout">…</div>

    <div class="delta">
      <div class="delta-header">
        <span class="delta-index">Δ1</span>
        <span class="delta-title">{{delta_title}}</span>
        <span class="delta-filepath">{{relative_file_path}}</span>
      </div>
      <div class="delta-desc"><p>{{current_state}} → {{target_state}}</p></div>
      <pre class="codediff"><code>
<span class="diff-line meta">--- a/{{file_path}}</span>
<span class="diff-line meta">+++ b/{{file_path}}</span>
<span class="diff-line hunk">@@ {{hunk_header}} @@</span>
<span class="diff-line"> {{context_line}}</span>
<span class="diff-line del">-{{removed_line}}</span>
<span class="diff-line add">+{{added_line}}</span>
      </code></pre>
      <div class="delta-evidence">Evidence: {{evidence_cite}}</div>
    </div>
    <!-- repeat .delta up to 5 times -->
  </div>
</details>
```

Rules:
- Only include diffs grounded in a `gap-analyzer.delta[]` entry whose evidence has `file:line` cites. No fabricated diffs.
- If gap-analyzer ran in degraded mode, render placeholder diffs with `// TODO: target shape — repo not accessible at trace time`.
- Maximum 5 diff blocks per doc. Overflow → bucket the rest under "Further deltas" with a one-line description each.

## Priority buckets

Each bucket is a `<details class="panel bucket-{color}">`. The left border color (3px) signals priority at a glance without needing to read the heading.

```html
<details class="panel bucket-red" id="blockers" open>
  <summary>
    <span class="summary-icon">🔴</span> Must answer before implementation starts
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{blocker_cards}}
    </div>
  </div>
</details>

<details class="panel bucket-yellow" id="clarifications" open>
  <summary>
    <span class="summary-icon">🟡</span> Should clarify before sprint ends
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{clarify_cards}}
    </div>
  </div>
</details>

<details class="panel bucket-green" id="nice">
  <summary>
    <span class="summary-icon">🟢</span> Address when bandwidth allows
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{nice_cards}}
    </div>
  </div>
</details>
```

The question grid is single-column by default; switches to 2-column above 1440px viewport (where each card has ≥560px — comfortable for radio-pill content). The breakpoint is set at 1440px viewport rather than 1100px because the 260px sidebar leaves only ~840px of main at 1100px, which is too narrow for two pill-option cards.

## Question card

Card layout clusters: meta-row (checkbox + role + pillar + confidence + per-card copy) at top; question + impact + reason-not-derivable in the body; radio pills below; card footer = override input + stable qid.

Radio pills are NOT pre-checked. The Recommended option is visually distinguished by a `★ Rec` badge inside the label, not by `checked`. The reviewer must click to register an answer.

```html
<section class="question-card priority-{{priority}}"
         data-qid="{{qid}}"
         data-role="{{role}}"
         data-pillar="{{pillar}}"
         data-priority="{{priority}}">

  <div class="card-meta-row">
    <input type="checkbox" class="card-select select-q" title="Include in copy">
    <span class="role-tag {{role}}">{{role}}</span>
    <span class="pillar-tag">{{pillar}}</span>
    <span class="conf-chip {{confidence}}">{{confidence}}</span>
    <button class="card-copy-btn copy-btn">Copy</button>
  </div>

  <div class="card-body">
    <h4>{{question}}</h4>
    <p class="card-impact"><strong>Decision affected:</strong> {{impact}}</p>
    <p class="card-reason">
      <strong>Not derivable because:</strong> {{reason_not_derivable}}
    </p>

    <div class="card-options">
      <!-- Recommended option — note: NO checked attribute -->
      <label class="pill recommended">
        <input type="radio" name="{{qid}}" value="{{rec_label}}">
        <span class="pill-rec-badge">★ Rec</span>
        <span class="pill-text">
          {{rec_label}}
          <span class="pill-reason">{{rec_reason}}</span>
        </span>
      </label>

      <!-- Other options -->
      <label class="pill">
        <input type="radio" name="{{qid}}" value="{{opt_b}}">
        <span class="pill-text">{{opt_b}}</span>
      </label>
      <label class="pill">
        <input type="radio" name="{{qid}}" value="{{opt_c}}">
        <span class="pill-text">{{opt_c}}</span>
      </label>
    </div>
  </div>

  <div class="card-footer">
    <input class="override-input override" placeholder="Other / override…">
    <span class="qid">{{qid}}</span>
  </div>
</section>
```

Per-card fields:

- **Header checkbox (`.select-q`)** — defaults checked (set by JS init). Drives selective copy.
- **Role tag** — colour-coded by role: PM (blue), Backend (purple), Design (orange), QA (green), Compliance (amber), DevOps (grey).
- **Pillar tag** — monospace badge (`design|tech|qa|domain`). Distinct from role.
- **Confidence chip** — `high` (green), `medium` (amber), `low` (grey). 10px monospace uppercase.
- **Per-card copy** — copies that Q+A as plain text.
- **Reason-not-derivable** — mandatory italic block. Reviewer sees *why* this couldn't be answered from code.
- **Override input** — supplements the radio options; dark input field.
- **Stable qid** — dim monospace at bottom-right.

## Copy controls (toolbar + selective copy modal)

```html
<div class="modal-backdrop" id="copy-modal">
  <div class="modal">
    <h3>Copy selected answers</h3>
    <p class="modal-sub">
      <span id="modal-count">0</span> of <span id="modal-total">{{n_total}}</span>
      questions selected. Review below, then click Copy.
    </p>
    <pre id="copy-preview">(no questions selected)</pre>
    <div class="modal-actions">
      <button class="toolbar-btn primary" id="copy-final">Copy to clipboard</button>
      <button class="toolbar-btn" id="modal-close">Close</button>
    </div>
  </div>
</div>
```

Output format (plain text, one block per question):

```
Q (Backend / blocker): Does the /history endpoint accept arbitrary duration values?
  → A: Accept arbitrary integer seconds via existing duration param

Q (Design / clarification): How should custom-duration chips be ordered?
  → A: Ascending by seconds, interleaved with built-ins
```

## Filter chips

Three filter groups in the sidebar: Role · Priority · Pillar. Each group has an "All" chip and per-value chips. Combined filters use AND logic. State persists in `localStorage`.

Chip visual states:
- Default: `border: 1px solid var(--border); color: var(--text-muted)`
- Hover: `background: var(--elevated); color: var(--text)`
- Active: `background: var(--elevated); border-color: var(--text-dim); color: var(--text)`
- Active + Priority: colour-tinted (red/amber/green bg + border-color match)

## Template skeleton

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Feature Analysis — {{feature_name}}</title>
  <style>
    :root {
      --base:#0d1117; --surface:#161b22; --elevated:#21262d; --hover:#30363d;
      --border:#30363d; --border-sub:#21262d;
      --text:#e6edf3; --text-muted:#8b949e; --text-dim:#6e7681;
      --green:#3fb950; --green-bg:#0f2a1a; --green-dim:#1a4a2a;
      --amber:#d29922; --amber-bg:#2a1f00; --amber-dim:#3d2e00;
      --red:#f85149; --red-bg:#2a0f0f; --red-dim:#4a1a1a;
      --blue:#58a6ff; --blue-bg:#0f1f3a;
      --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
      --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
      --sidebar-w:260px; --radius-sm:4px; --radius-md:6px; --radius-lg:10px;
    }
    *, *::before, *::after { box-sizing:border-box; margin:0; padding:0; }
    html { scroll-behavior:smooth; }
    body {
      font:14px/1.6 var(--sans); color:var(--text); background:var(--base);
      display:grid; grid-template-columns:var(--sidebar-w) 1fr; min-height:100vh;
    }
    /* … full CSS as in the preview file … */
  </style>
</head>
<body>
  <nav class="sidebar"> <!-- as above --> </nav>

  <main>
    <div class="page-header">
      <div class="run-badge">{{session_id}} · {{date}}</div>
      <h1>{{feature_name}}</h1>
      <div class="intent">{{intent}}</div>
      <div class="page-meta">…</div>
      <div class="progress-bar-wrap">…</div>
    </div>

    <div class="copy-toolbar" id="copy-toolbar">…</div>

    <div id="scope">
      <div class="section-header"><h2>Scope filter</h2></div>
      <hr class="section-divider">
      <div class="scope-grid">…</div>
    </div>

    <div class="section-header"><h2>Existing flow</h2></div>
    <hr class="section-divider">
    <details class="panel" id="flow" open>…</details>

    <div class="section-header"><h2>Code requirements</h2></div>
    <hr class="section-divider">
    <details class="panel" id="diff" open>…</details>

    <div class="section-header" id="blockers"><h2>🔴 Blockers</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-red" open>
      <div class="panel-body"><div class="question-grid">{{blocker_cards}}</div></div>
    </details>

    <div class="section-header" id="clarifications"><h2>🟡 Clarifications</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-yellow" open>
      <div class="panel-body"><div class="question-grid">{{clarify_cards}}</div></div>
    </details>

    <div class="section-header" id="nice"><h2>🟢 Nice-to-have</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-green">
      <div class="panel-body"><div class="question-grid">{{nice_cards}}</div></div>
    </details>

    <div class="section-header" id="assumptions"><h2>Assumptions</h2></div>
    <hr class="section-divider">
    <details class="panel" open>
      <summary>📌 {{n_assumptions}} assumptions <span class="summary-chevron">›</span></summary>
      <div class="panel-body">
        <ul class="assumptions-list">{{assumptions_items}}</ul>
      </div>
    </details>
  </main>

  <div class="modal-backdrop" id="copy-modal">…</div>

  <script>
    // Progress tracking — change events only, no pre-checked state
    const answeredQids = new Set();
    const totalQ = {{n_total}};
    function updateProgress() {
      const count = answeredQids.size;
      document.getElementById('answered-count').textContent = count;
      document.getElementById('progress-fill').style.width = `${(count / totalQ) * 100}%`;
    }
    document.querySelectorAll('.question-card input[type=radio]').forEach(radio => {
      radio.addEventListener('change', () => {
        answeredQids.add(radio.closest('.question-card').dataset.qid);
        updateProgress();
      });
    });

    // Bulk select
    document.getElementById('select-all').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = true);
    document.getElementById('select-none').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = false);
    document.getElementById('select-blockers').onclick = () =>
      document.querySelectorAll('.question-card').forEach(c => {
        c.querySelector('.select-q').checked = c.classList.contains('priority-red');
      });

    // Per-card copy
    document.querySelectorAll('.copy-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const card = btn.closest('.question-card');
        const sel = card.querySelector('input[type=radio]:checked');
        const override = card.querySelector('.override').value.trim();
        navigator.clipboard.writeText(
          `Q: ${card.querySelector('h4').innerText}\nA: ${sel ? sel.value : '(no selection)'}${override ? `\nOverride: ${override}` : ''}`
        ).catch(() => {});
      });
    });

    // Filter chips (AND logic)
    const filterState = { role:'all', priority:'all', pillar:'all' };
    function applyFilters() {
      document.querySelectorAll('.question-card').forEach(c => {
        const ok = (filterState.role === 'all' || c.dataset.role === filterState.role) &&
                   (filterState.priority === 'all' || c.dataset.priority === filterState.priority) &&
                   (filterState.pillar === 'all' || c.dataset.pillar === filterState.pillar);
        c.classList.toggle('hidden', !ok);
      });
    }
    function wireFilterGroup(groupName, stateKey, dataAttr) {
      const g = document.querySelector(`[data-filter-group="${groupName}"]`);
      if (!g) return;
      g.querySelectorAll('button').forEach(btn => {
        btn.addEventListener('click', () => {
          filterState[stateKey] = btn.dataset[dataAttr];
          g.querySelectorAll('button').forEach(b => b.classList.toggle('active', b === btn));
          applyFilters();
        });
      });
    }
    wireFilterGroup('role', 'role', 'filterRole');
    wireFilterGroup('priority', 'priority', 'filterPriority');
    wireFilterGroup('pillar', 'pillar', 'filterPillar');

    // Selective copy modal
    function buildCopyPreview() {
      const cards = [...document.querySelectorAll('.question-card')].filter(c =>
        c.querySelector('.select-q').checked && !c.classList.contains('hidden')
      );
      if (!cards.length) return '(no questions selected)';
      return cards.map(c => {
        const bucket = c.classList.contains('priority-red') ? 'blocker'
                     : c.classList.contains('priority-yellow') ? 'clarification' : 'nice';
        const sel = c.querySelector('input[type=radio]:checked');
        const override = c.querySelector('.override').value.trim();
        return `Q (${c.dataset.role} / ${bucket}): ${c.querySelector('h4').innerText}\n` +
               `  → A: ${sel ? sel.value : '(no selection)'}${override ? `\n  Override: ${override}` : ''}`;
      }).join('\n\n');
    }
    document.getElementById('open-copy-modal').addEventListener('click', () => {
      const selected = [...document.querySelectorAll('.select-q')].filter(c => c.checked).length;
      document.getElementById('modal-count').textContent = selected;
      document.getElementById('modal-total').textContent = totalQ;
      document.getElementById('copy-preview').textContent = buildCopyPreview();
      document.getElementById('copy-modal').classList.add('open');
    });
    document.getElementById('modal-close').addEventListener('click', () =>
      document.getElementById('copy-modal').classList.remove('open'));
    document.getElementById('copy-modal').addEventListener('click', e => {
      if (e.target === e.currentTarget) document.getElementById('copy-modal').classList.remove('open');
    });
    document.getElementById('copy-final').addEventListener('click', () => {
      navigator.clipboard.writeText(buildCopyPreview()).catch(() => {});
      document.getElementById('copy-modal').classList.remove('open');
    });

    // Scroll-spy
    const navLinks = [...document.querySelectorAll('nav.sidebar a[href^="#"]')];
    const anchorEls = navLinks.map(a => document.getElementById(a.getAttribute('href').slice(1))).filter(Boolean);
    function updateScrollSpy() {
      const y = window.scrollY + 100;
      let current = anchorEls[0];
      for (const el of anchorEls) { if (el.offsetTop <= y) current = el; }
      navLinks.forEach(a =>
        a.classList.toggle('active', a.getAttribute('href') === '#' + (current?.id ?? '')));
    }
    document.addEventListener('scroll', updateScrollSpy, { passive: true });
    updateScrollSpy();

    // Init: default checkboxes on
    document.querySelectorAll('.select-q').forEach(c => { c.checked = true; });
    updateProgress();
  </script>
</body>
</html>
```

## Markdown opt-in

Caller flag `--format md` falls back to the markdown layout in `SKILL.md` Mode 1 output block. Use only for terminal-only sessions or when HTML rendering is unavailable.

## Why these components

| Component | Reason |
|---|---|
| Sidebar | Doc can be 30+ questions; without nav, stakeholders scroll-lose. |
| Progress bar | Makes "0 of 14 answered" visible — accountability at a glance. Starts at 0 because Recommended is not pre-checked; reviewer must actively decide. |
| Diff block | Engineers don't want prose deltas. A real unified diff is the fastest way to convey "what changes in code". Per-block file-path header makes jumping to the right file instant. |
| Filter chips | A Backend engineer doesn't want to see 20 Design questions. One click filters. |
| Selective copy | Stakeholders rarely need the whole set. Per-question checkboxes + bucket presets = 1-click "blockers only". |
| Confidence chip | Reviewer sees at a glance which questions rest on `flow-tracer` cites vs UX heuristic vs speculation. |
| Reason-not-derivable line | Surfaces *why* the code couldn't answer this. Pushes back against questions that are lazily generated. |
| Dark surface palette | Consistent with developer tooling aesthetics (GitHub, Linear, Vercel). Reduces eye strain in low-light review sessions. High-contrast semantic colours (green/amber/red) communicate priority without colour-only dependency. |
